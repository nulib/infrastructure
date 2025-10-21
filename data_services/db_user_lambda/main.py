import json
import os
from contextlib import contextmanager
from typing import Dict

from pg8000.native import Connection


def handler(event, _context):
    username = event.get("username")
    password = event.get("password")
    database = event.get("database")

    if not username or not password:
        raise ValueError("event must include non-empty 'username' and 'password'")

    log("Starting user management", {"username": username, "database": database})

    with admin_connection() as conn:
        ensure_role(conn, username, password)

        if database:
            ensure_database(conn, database, username)
        conn.run(f"REVOKE {quote_ident(username)} FROM CURRENT_USER")

    log("User management complete", {"username": username, "database": database})
    return {"username": username, "database": database}


def ensure_role(conn: Connection, username: str, password: str) -> None:
    role_exists = bool(
        conn.run("SELECT 1 FROM pg_roles WHERE rolname = :name", name=username)
    )

    escaped_password = "'" + password.replace("'", "''").replace("\\", "\\\\") + "'"
    if role_exists:
        log("Updating existing role", {"role": username})
        conn.run(
            f"ALTER ROLE {quote_ident(username)} WITH LOGIN PASSWORD {escaped_password}"
        )
    else:
        log("Creating role", {"role": username})
        conn.run(
            f"CREATE ROLE {quote_ident(username)} WITH LOGIN PASSWORD {escaped_password}"
        )

    conn.run(f"GRANT {quote_ident(username)} TO CURRENT_USER")
    conn.run(f"ALTER ROLE {quote_ident(username)} WITH CREATEDB")


def ensure_database(conn: Connection, database: str, owner: str) -> None:
    database_exists = bool(
        conn.run("SELECT 1 FROM pg_database WHERE datname = :name", name=database)
    )

    if database_exists:
        log("Database exists; reassigning ownership", {"database": database})
        conn.run(
            f"ALTER DATABASE {quote_ident(database)} OWNER TO {quote_ident(owner)}"
        )
        reassign_database_ownership(database, owner)
    else:
        log("Creating database", {"database": database, "owner": owner})
        conn.run(
            f"CREATE DATABASE {quote_ident(database)} OWNER {quote_ident(owner)}"
        )


def reassign_database_ownership(database: str, owner: str) -> None:
    with admin_connection(database) as db_conn:
        reassign_schemas(db_conn, owner)
        reassign_relations(db_conn, owner)
        reassign_sequences(db_conn, owner)
        reassign_views(db_conn, owner)
        reassign_materialized_views(db_conn, owner)
        reassign_foreign_tables(db_conn, owner)
        reassign_types(db_conn, owner)
        reassign_functions(db_conn, owner)


def reassign_schemas(conn: Connection, owner: str) -> None:
    for (schema,) in conn.run(
        f"""
        SELECT nspname
        FROM pg_namespace
        WHERE {non_system_schema_predicate()}
        """
    ):
        conn.run(
            f"ALTER SCHEMA {quote_ident(schema)} OWNER TO {quote_ident(owner)}"
        )


def reassign_relations(conn: Connection, owner: str) -> None:
    for schema, name in conn.run(
        f"""
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {non_system_schema_predicate(alias="n.nspname")}
          AND c.relkind IN ('r', 'p')
        """
    ):
        conn.run(
            f"ALTER TABLE {qualify(schema, name)} OWNER TO {quote_ident(owner)}"
        )


def reassign_sequences(conn: Connection, owner: str) -> None:
    for schema, name in conn.run(
        f"""
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {non_system_schema_predicate(alias="n.nspname")}
          AND c.relkind = 'S'
        """
    ):
        conn.run(
            f"ALTER SEQUENCE {qualify(schema, name)} OWNER TO {quote_ident(owner)}"
        )


def reassign_views(conn: Connection, owner: str) -> None:
    for schema, name in conn.run(
        f"""
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {non_system_schema_predicate(alias="n.nspname")}
          AND c.relkind = 'v'
        """
    ):
        conn.run(
            f"ALTER VIEW {qualify(schema, name)} OWNER TO {quote_ident(owner)}"
        )


def reassign_materialized_views(conn: Connection, owner: str) -> None:
    for schema, name in conn.run(
        f"""
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {non_system_schema_predicate(alias="n.nspname")}
          AND c.relkind = 'm'
        """
    ):
        conn.run(
            f"ALTER MATERIALIZED VIEW {qualify(schema, name)} OWNER TO {quote_ident(owner)}"
        )


def reassign_foreign_tables(conn: Connection, owner: str) -> None:
    for schema, name in conn.run(
        f"""
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE {non_system_schema_predicate(alias="n.nspname")}
          AND c.relkind = 'f'
        """
    ):
        conn.run(
            f"ALTER FOREIGN TABLE {qualify(schema, name)} OWNER TO {quote_ident(owner)}"
        )


def reassign_types(conn: Connection, owner: str) -> None:
    for schema, name in conn.run(
        f"""
        SELECT n.nspname, t.typname
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        LEFT JOIN pg_class c ON t.typrelid = c.oid
        WHERE {non_system_schema_predicate(alias="n.nspname")}
          AND t.typtype IN ('c', 'd', 'e', 'r')
          AND c.relkind IS NULL
        """
    ):
        conn.run(
            f"ALTER TYPE {qualify(schema, name)} OWNER TO {quote_ident(owner)}"
        )


def reassign_functions(conn: Connection, owner: str) -> None:
    for schema, name, kind, args in conn.run(
        f"""
        SELECT n.nspname,
               p.proname,
               p.prokind,
               pg_get_function_identity_arguments(p.oid)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE {non_system_schema_predicate(alias="n.nspname")}
        """
    ):
        signature = f"{qualify(schema, name)}({args})"
        object_type = {
            "a": "AGGREGATE",
            "p": "PROCEDURE",
            "f": "FUNCTION",
            "w": "FUNCTION",
        }.get(kind, "FUNCTION")
        conn.run(
            f"ALTER {object_type} {signature} OWNER TO {quote_ident(owner)}"
        )


def admin_connection(database: str = None):
    params = connection_params(database)
    return connection_context(**params)


@contextmanager
def connection_context(**params):
    conn = Connection(**params)
    try:
        yield conn
    finally:
        conn.close()


def connection_params(database: str = None) -> Dict[str, object]:
    params = {
        "host": get_env("DB_HOST"),
        "port": int(get_env("DB_PORT", "5432")),
        "user": get_env("DB_SUPERUSER"),
        "password": get_env("DB_SUPERUSER_PASSWORD"),
        "database": database or get_env("DB_NAME", "postgres"),
    }
    return params


def get_env(key: str, default: str = None) -> str:
    value = os.getenv(key, default)
    if value is None:
        raise RuntimeError(f"Missing environment variable: {key}")
    return value

def escape_string(value: str) -> str:
    escaped = str.replace("'", "''").replace("\\", "\\\\")
    return f"'{escaped}'"

def quote_ident(identifier: str) -> str:
    quoted = identifier.replace('"', '""')
    return f'"{quoted}"'

def qualify(schema: str, name: str) -> str:
    return f"{quote_ident(schema)}.{quote_ident(name)}"


def non_system_schema_predicate(alias: str = "nspname") -> str:
    return (
        f"{alias} NOT IN ('pg_catalog', 'information_schema')"
        f" AND {alias} NOT LIKE 'pg_toast%%'"
        f" AND {alias} NOT LIKE 'pg_temp_%%'"
    )


def log(message: str, detail: Dict[str, object] = None) -> None:
    payload = {"message": message}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload))
