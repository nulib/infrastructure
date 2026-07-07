#!/bin/bash

set -e

# Allow the container to be started with `--user`
if [[ "$1" = 'zkServer.sh' && "$(id -u)" = '0' ]]; then
    chown -R zookeeper "$ZOO_DATA_DIR" "$ZOO_DATA_LOG_DIR" "$ZOO_LOG_DIR"
    exec gosu zookeeper "$0" "$@"
fi

# Generate the config only if it doesn't exist
if [[ ! -f "$ZOO_CONF_DIR/zoo.cfg" ]]; then
    CONFIG="$ZOO_CONF_DIR/zoo.cfg"
    {
        echo "dataDir=$ZOO_DATA_DIR"
        echo "dataLogDir=$ZOO_DATA_LOG_DIR"

        echo "tickTime=$ZOO_TICK_TIME"
        echo "initLimit=$ZOO_INIT_LIMIT"
        echo "syncLimit=$ZOO_SYNC_LIMIT"

        echo "autopurge.snapRetainCount=$ZOO_AUTOPURGE_SNAPRETAINCOUNT"
        echo "autopurge.purgeInterval=$ZOO_AUTOPURGE_PURGEINTERVAL"
        echo "maxClientCnxns=$ZOO_MAX_CLIENT_CNXNS"
        echo "standaloneEnabled=$ZOO_STANDALONE_ENABLED"
        echo "admin.enableServer=$ZOO_ADMINSERVER_ENABLED"
    } >> "$CONFIG"
    if [[ -z $ZOO_SERVERS ]]; then
      ZOO_SERVERS="server.1=localhost:2888:3888;2181"
    fi

    for server in $ZOO_SERVERS; do
        echo "$server" >> "$CONFIG"
    done

    if [[ -n $ZOO_4LW_COMMANDS_WHITELIST ]]; then
        echo "4lw.commands.whitelist=$ZOO_4LW_COMMANDS_WHITELIST" >> "$CONFIG"
    fi

    for cfg_extra_entry in $ZOO_CFG_EXTRA; do
        echo "$cfg_extra_entry" >> "$CONFIG"
    done
fi

# Write myid only if it doesn't exist
if [[ ! -f "$ZOO_DATA_DIR/myid" ]]; then
    echo "${ZOO_MY_ID:-1}" > "$ZOO_DATA_DIR/myid"
fi

# =========================================================================
# S3 backup / restore (added).
# Entirely inert unless S3_BUCKET is set, so default behavior is unchanged.
#
# Config (env):
#   S3_BUCKET        required to enable; e.g. my-zk-backups
#   S3_PREFIX        key prefix (default: zk)  ->  s3://$S3_BUCKET/$S3_PREFIX/<myid>/
#   BACKUP_INTERVAL  seconds between backups (default: 360; keep >=300, admin
#                    snapshot is rate-limited to once / 5 min by default)
#   ZK_ADMIN_URL     admin server commands base (default: http://127.0.0.1:8080/commands)
#   ZK_ADMIN_AUTH    Authorization header value for a clean pre-backup snapshot,
#                    e.g. "digest super:PASSWORD". If empty, the forced snapshot
#                    is skipped and we sync ZK's own periodic snapshots + logs.
#
# Requires `aws` (awscli) and `curl` in the image, and a task role with
# s3:GetObject/PutObject/ListBucket on the prefix. Uses 127.0.0.1 (never
# localhost) so the admin Host header is an IP literal.
# =========================================================================
: "${S3_PREFIX:=zk}"
: "${BACKUP_INTERVAL:=360}"
: "${ZK_ADMIN_URL:=http://127.0.0.1:8080/commands}"
: "${ZK_ADMIN_AUTH:=""}"

ZK_MYID_VAL="${ZOO_MY_ID:-1}"
DATA_V2="$ZOO_DATA_DIR/version-2"
LOG_V2="$ZOO_DATA_LOG_DIR/version-2"
S3_SNAP="s3://${S3_BUCKET:-}/${S3_PREFIX}/${ZK_MYID_VAL}/data/"
S3_LOG="s3://${S3_BUCKET:-}/${S3_PREFIX}/${ZK_MYID_VAL}/datalog/"

blog() { echo "[backup] $*"; }

s3_has() { [[ -n "$(aws s3 ls "$1" 2>/dev/null)" ]]; }

# Restore only when there is no local snapshot AND S3 has data. A node
# rejoining a live ensemble re-syncs from the leader; this path matters for
# whole-ensemble loss (all ephemeral storage gone at once).
restore() {
    if compgen -G "$DATA_V2/snapshot.*" > /dev/null 2>&1; then
        blog "local snapshot present; skipping restore"
        return 0
    fi
    if s3_has "$S3_SNAP"; then
        blog "restoring from $S3_SNAP and $S3_LOG"
        mkdir -p "$DATA_V2" "$LOG_V2"
        aws s3 sync "$S3_SNAP" "$DATA_V2/" --only-show-errors || blog "snapshot restore had errors"
        aws s3 sync "$S3_LOG"  "$LOG_V2/"  --only-show-errors || blog "log restore had errors"
    else
        blog "no backup at $S3_SNAP; starting fresh"
    fi
}

# Force a current on-disk snapshot via the admin server before syncing, so
# restore replays minimal transaction log. Best-effort.
force_snapshot() {
    [[ -n "$ZK_ADMIN_AUTH" ]] || return 0
    if curl -fsS -H "Authorization: $ZK_ADMIN_AUTH" "$ZK_ADMIN_URL/snapshot" -o /dev/null 2>/dev/null; then
        blog "forced admin snapshot"
    else
        blog "admin snapshot unavailable (rate limit/auth); syncing existing state"
    fi
}

# Sync whole version-2 dirs (captures snapshot.*, log.*, and the
# acceptedEpoch/currentEpoch files needed for a full restore).
backup() {
    [[ -d "$DATA_V2" ]] || return 0
    force_snapshot
    aws s3 sync "$DATA_V2/" "$S3_SNAP" --only-show-errors || blog "snapshot backup had errors"
    aws s3 sync "$LOG_V2/"  "$S3_LOG"  --only-show-errors || blog "log backup had errors"
}

backup_loop() {
    [[ "$BACKUP_INTERVAL" -gt 0 ]] || return 0
    while true; do
        sleep "$BACKUP_INTERVAL"
        blog "periodic backup"
        backup || true
    done
}

# If S3 isn't configured, or this isn't a server start (e.g. zkCli), keep the
# original exec-based behavior untouched.
if [[ -z "${S3_BUCKET:-}" || "$1" != 'zkServer.sh' ]]; then
    exec "$@"
fi

# --- Supervised start: restore, run ZK, periodic + shutdown backups ---------
# NOTE: with backups enabled the wrapper (not ZK) is PID 1, and forwards
# SIGTERM to ZK after a final backup. Bump the Fargate task stopTimeout if a
# large final sync might exceed the default 30s.
restore

ZK_PID=""
BK_PID=""

term() {
    blog "shutdown signal: final backup"
    backup || blog "final backup failed"
    [[ -n "$ZK_PID" ]] && kill -TERM "$ZK_PID" 2>/dev/null || true
    wait "$ZK_PID" 2>/dev/null || true
    [[ -n "$BK_PID" ]] && kill "$BK_PID" 2>/dev/null || true
    exit 0
}
trap term SIGTERM SIGINT

backup_loop &
BK_PID=$!

"$@" &
ZK_PID=$!
# zkCli.sh addauth ${ZK_ADMIN_AUTH}
wait "$ZK_PID" || true

# ZK exited on its own (crash/restart) — take a final backup before leaving.
blog "zookeeper process exited; final backup"
backup || blog "final backup failed"
[[ -n "$BK_PID" ]] && kill "$BK_PID" 2>/dev/null || true