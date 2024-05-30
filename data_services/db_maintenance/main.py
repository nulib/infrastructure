from pg8000.native import Connection
import json

def handler(event, _context):
  max_age = event.get('max_age', '1 WEEK')
  config = event.get('connection', {})
  database = config['database']

  log('Beginning database maintenance', { 'database': database })
  conn = Connection(**config)

  for table in event.get('tables', []):
    log('Deleting stale entries', { 'database': database, 'max_age': max_age, 'table': table })
    conn.run(f"DELETE FROM {table} WHERE updated_at < NOW() - interval '{max_age}'")
    log('Deleted', { 'database': database, 'table': table, 'rows': conn.row_count })

    log('Size before vacuuming', { 'database': database, 'table': table, 'bytes': table_size(conn, table) })
    conn.run(f"VACUUM FULL {table}")
    log('Size after vacuuming', { 'database': database, 'table': table, 'bytes': table_size(conn, table) })

    log('Maintenance complete', { 'database': database })

def log(message, detail = {}):
  print(json.dumps({ 'message': message, 'detail': detail }))

def table_size(conn, table):
  return conn.run(f"SELECT pg_total_relation_size('{table}')")[0][0];