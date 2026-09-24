# Health check for the zookeeper container (stock image; run as bash -c "<this file>").
#
# Healthy means this node is part of a serving quorum -- or no quorum exists anywhere,
# which is the cold start of a whole ensemble (nobody can serve until 2 of 3 are up, so
# requiring it would deadlock a sequential rollout). A node that isn't serving while a
# peer is serving is still syncing, or has been refused, and is not healthy.
#
# Once serving, check the /nul/ensemble-initialized semaphore once, based on what the
# zk-backup sidecar decided at startup ($GATE_DIR/mode):
#   joined           the ensemble must already have it; a live ensemble without it formed
#                    from empty nodes, and this node won't vouch for it
#   restored, fresh  create it if missing
# then write $READY_FILE so later checks skip zkCli. Each zkCli run starts a JVM, which is
# slow on a quarter vCPU, so each path makes exactly one zkCli call (commands on stdin).

: "${GATE_DIR:=/gate}"
: "${READY_FILE:=/tmp/zk-verified}"
: "${ZK_CLIENT_PORT:=2181}"
: "${PROBE_TIMEOUT:=2}"
: "${ZK_CLI:=zkCli.sh}"
SEMAPHORE=/nul/ensemble-initialized
MYID="${ZOO_MY_ID:-1}"

srvr() {
  timeout "$PROBE_TIMEOUT" bash -c \
    "exec 3<>/dev/tcp/$1/$ZK_CLIENT_PORT && echo srvr >&3 && cat <&3" 2>/dev/null
}
mode() { srvr "$1" | sed -n 's/^Mode: //p'; }
serving() { case "$1" in leader|follower) return 0 ;; *) return 1 ;; esac; }

# Run zkCli commands from stdin in one session (one JVM start)
zkcli() { timeout 15 "$ZK_CLI" -server "127.0.0.1:$ZK_CLIENT_PORT" 2>&1; }

local_out="$(srvr 127.0.0.1)"
[ -n "$local_out" ] || { echo "zookeeper not answering"; exit 1; }
local_mode="$(printf '%s\n' "$local_out" | sed -n 's/^Mode: //p')"

if ! serving "$local_mode"; then
  for server in ${ZOO_SERVERS:-}; do
    id="${server%%=*}"; id="${id#server.}"
    host="${server#*=}"; host="${host%%:*}"
    [ "$id" = "$MYID" ] && continue
    if serving "$(mode "$host")"; then
      echo "not serving, but $host is: still syncing or refused"
      exit 1
    fi
  done
  echo "no quorum anywhere (cold start); healthy on liveness"
  exit 0
fi

[ -f "$READY_FILE" ] && exit 0

case "$(cat "$GATE_DIR/mode" 2>/dev/null)" in
  joined)
    if ! printf 'stat %s\nquit\n' "$SEMAPHORE" | zkcli | grep -q '^ctime'; then
      echo "joined a live ensemble without $SEMAPHORE; refusing to vouch for it"
      exit 1
    fi
    ;;
  restored|fresh)
    # `create` of an existing znode just reports "already exists"
    if ! printf 'create /nul\ncreate %s "%s node %s"\nstat %s\nquit\n' \
        "$SEMAPHORE" "$(date -u +%FT%TZ)" "$MYID" "$SEMAPHORE" | zkcli | grep -q '^ctime'; then
      echo "could not create $SEMAPHORE"
      exit 1
    fi
    ;;
  *)
    echo "no startup mode from the zk-backup sidecar"
    exit 1
    ;;
esac

touch "$READY_FILE"
echo "serving as $local_mode; semaphore verified"
