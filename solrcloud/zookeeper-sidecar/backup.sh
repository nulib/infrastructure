# Sidecar for a zookeeper task: decide whether to restore this node's S3 backup before
# ZooKeeper starts, then back its data up to S3 until the task stops.
#
# Runs as a non-essential container on the stock aws-cli image (bash -c "<this file>").
# The zookeeper container waits for this container to be HEALTHY, which happens once
# $GATE_DIR/ready exists, so ZooKeeper never starts before the restore decision.
#
# Restore decision:
#   - Another ensemble member is serving (`srvr` reports leader or follower): join it.
#     Start empty and let the leader sync us. Mode "joined".
#   - No member is serving and S3 has a backup: restore it. Mode "restored".
#   - No member is serving and S3 has nothing: a brand-new ensemble. Mode "fresh".
# The mode goes to $GATE_DIR/mode; the zookeeper health check uses it to decide whether
# to require or create the /nul/ensemble-initialized semaphore znode.
#
# Env: S3_BUCKET (required), S3_PREFIX (default zk), ZOO_MY_ID, ZOO_SERVERS,
#      BACKUP_INTERVAL (seconds, default 360), ZK_ADMIN_AUTH (optional, for the forced
#      pre-backup snapshot), DATA_DIR, DATALOG_DIR, GATE_DIR.

set -u

: "${S3_PREFIX:=zk}"
: "${BACKUP_INTERVAL:=360}"
: "${ZK_ADMIN_URL:=http://127.0.0.1:8080/commands}"
: "${ZK_ADMIN_AUTH:=}"
: "${DATA_DIR:=/data}"
: "${DATALOG_DIR:=/datalog}"
: "${GATE_DIR:=/gate}"
: "${ZK_CLIENT_PORT:=2181}"
: "${PROBE_TIMEOUT:=3}"

MYID="${ZOO_MY_ID:-1}"
DATA_V2="$DATA_DIR/version-2"
LOG_V2="$DATALOG_DIR/version-2"
S3_SNAP="s3://${S3_BUCKET}/${S3_PREFIX}/${MYID}/data/"
S3_LOG="s3://${S3_BUCKET}/${S3_PREFIX}/${MYID}/datalog/"

log() { echo "[zk-backup] $*"; }

# Print a server's `srvr` Mode (leader, follower, standalone), or nothing if it isn't
# answering or isn't serving.
zk_mode() {
  timeout "$PROBE_TIMEOUT" bash -c \
    "exec 3<>/dev/tcp/$1/$ZK_CLIENT_PORT && echo srvr >&3 && cat <&3" 2>/dev/null \
    | sed -n 's/^Mode: //p'
}

# Hostnames of the other ensemble members, from ZOO_SERVERS
# ("server.1=host:2888:3888;2181 server.2=...").
peers() {
  local server id host
  for server in ${ZOO_SERVERS:-}; do
    id="${server%%=*}"; id="${id#server.}"
    host="${server#*=}"; host="${host%%:*}"
    [[ "$id" != "$MYID" ]] && echo "$host"
  done
}

serving_peer() {
  local peer mode
  for peer in $(peers); do
    mode="$(zk_mode "$peer")"
    if [[ "$mode" == leader || "$mode" == follower ]]; then
      echo "$peer ($mode)"
      return 0
    fi
  done
  return 1
}

s3_has() { [[ -n "$(aws s3 ls "$1" 2>/dev/null)" ]]; }

decide_and_restore() {
  local peer
  if peer="$(serving_peer)"; then
    log "ensemble is serving ($peer); joining without restoring"
    echo joined > "$GATE_DIR/mode"
  elif s3_has "$S3_SNAP"; then
    log "no ensemble member is serving; restoring from $S3_SNAP and $S3_LOG"
    mkdir -p "$DATA_V2" "$LOG_V2"
    aws s3 sync "$S3_SNAP" "$DATA_V2/" --only-show-errors || { log "snapshot restore failed"; return 1; }
    aws s3 sync "$S3_LOG"  "$LOG_V2/"  --only-show-errors || { log "log restore failed"; return 1; }
    echo restored > "$GATE_DIR/mode"
  else
    log "no ensemble member is serving and no backup at $S3_SNAP; starting a fresh ensemble"
    echo fresh > "$GATE_DIR/mode"
  fi
}

# Force a current on-disk snapshot so a restore replays minimal transaction log.
force_snapshot() {
  [[ -n "$ZK_ADMIN_AUTH" ]] || return 0
  if curl -fsS -H "Authorization: $ZK_ADMIN_AUTH" "$ZK_ADMIN_URL/snapshot" -o /dev/null 2>/dev/null; then
    log "forced admin snapshot"
  else
    log "admin snapshot unavailable (rate limit/auth); syncing existing state"
  fi
}

# Only back up a node that is serving, so a node still syncing from the leader never
# uploads a partial copy over a good backup. `final` skips that check: ZooKeeper has
# already stopped cleanly by then (it depends on this container, so ECS stops it first).
backup() {
  [[ -d "$DATA_V2" ]] || return 0
  if [[ "${1:-}" != final ]]; then
    case "$(zk_mode 127.0.0.1)" in
      leader|follower) force_snapshot ;;
      *) log "not serving; skipping backup"; return 0 ;;
    esac
  fi
  aws s3 sync "$DATA_V2/" "$S3_SNAP" --only-show-errors || log "snapshot backup had errors"
  aws s3 sync "$LOG_V2/"  "$S3_LOG"  --only-show-errors || log "log backup had errors"
}

SLEEP_PID=""
on_term() {
  log "shutdown signal: final backup"
  [[ -n "$SLEEP_PID" ]] && kill "$SLEEP_PID" 2>/dev/null
  backup final || log "final backup failed"
  exit 0
}

main() {
  [[ -n "${S3_BUCKET:-}" ]] || { log "S3_BUCKET is not set"; exit 1; }
  mkdir -p "$GATE_DIR"
  rm -f "$GATE_DIR/ready" "$GATE_DIR/mode"

  decide_and_restore || exit 1
  touch "$GATE_DIR/ready"

  trap on_term TERM INT
  [[ "$BACKUP_INTERVAL" -gt 0 ]] || BACKUP_INTERVAL=360
  while true; do
    sleep "$BACKUP_INTERVAL" & SLEEP_PID=$!
    wait "$SLEEP_PID"
    log "periodic backup"
    backup || true
  done
}

main
