#!/bin/bash
set -euo pipefail

DOCKER_COMPOSE="docker-compose.yml"
SSH_HOST="root@194.163.164.110"
SSH_PASS="Olddelicate@1"

if [ ! -f "$DOCKER_COMPOSE" ]; then
  echo "Error: $DOCKER_COMPOSE not found in current directory"
  exit 1
fi

PORTS=$(grep -E '^\s+-\s*"[0-9]+:[0-9]+"' "$DOCKER_COMPOSE" | grep -oE '"[0-9]+:[0-9]+"' | sed 's/"//g' | cut -d: -f1 | sort -u)

LOG_DIR="./ssh-tunnel-logs"
mkdir -p "$LOG_DIR"
rm -f "${LOG_DIR}"/*.log
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

pkill -f "sshpass.*${SSH_HOST}" 2>/dev/null || true

echo "Starting SSH tunnels for $(echo "$PORTS" | wc -l | tr -d ' ') ports..."

for PORT in $PORTS; do
  LOG_FILE="$LOG_DIR/tunnel-${PORT}-${TIMESTAMP}.log"

  if lsof -ti tcp:"$PORT" > /dev/null 2>&1; then
    PIDS=$(lsof -ti tcp:"$PORT")
    echo "  -> Port ${PORT} in use by PID(s) ${PIDS}, killing..."
    kill -9 $PIDS 2>/dev/null || true
    sleep 0.5
  fi

  nohup sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -N \
    -L "${PORT}:127.0.0.1:${PORT}" "${SSH_HOST}" \
    > "$LOG_FILE" 2>&1 &
  echo "  -> Port ${PORT} (PID: $!) -> $LOG_FILE"
  sleep 0.2
done

echo ""
echo "Verify: tail -f ${LOG_DIR}/tunnel-*-${TIMESTAMP}.log"
echo "Stop:   pkill -f 'sshpass.*${SSH_HOST}'"
