#!/usr/bin/env bash

set -e

echo "========================================="
echo " Closing Claude Hybrid Stack"
echo "========================================="

# =====================================================
# KILL ALL CLAUDE PROCESSES
# =====================================================

echo ""
echo "Finding Claude processes..."

CLAUDE_PIDS="$(pgrep -f "[c]laude" || true)"

if [[ -z "$CLAUDE_PIDS" ]]; then

  echo "  No Claude processes found."

else

  echo "  Found Claude PIDs: $CLAUDE_PIDS"

  for PID in $CLAUDE_PIDS; do

    kill -9 "$PID" >/dev/null 2>&1 || true

    echo "  Killed PID $PID"

    sleep 0.5

  done

  echo "  All Claude processes stopped."
fi

# =====================================================
# KILL LITELLM GATEWAY
# =====================================================

echo ""
echo "Finding LiteLLM gateway (port 4001 only)..."

PORT_4001_PIDS="$(lsof -ti :4001 2>/dev/null || true)"

LITELLM_4001_PIDS="$(for pid in $PORT_4001_PIDS; do ps -p "$pid" -o comm= 2>/dev/null | grep -qi litellm && echo "$pid"; done || true)"

if [[ -z "$LITELLM_4001_PIDS" ]]; then

  echo "  No LiteLLM (port 4001) processes found."

else

  echo "  Found LiteLLM PIDs on port 4001: $LITELLM_4001_PIDS"

  for PID in $LITELLM_4001_PIDS; do

    kill -9 "$PID" >/dev/null 2>&1 || true

    echo "  Killed PID $PID"

    sleep 0.5

  done

  echo "  LiteLLM gateway (port 4001) stopped."
fi

# =====================================================
# FREE PORT 4001
# =====================================================

echo ""
echo "Checking port 4001..."

PORT_PIDS="$(lsof -ti :4001 2>/dev/null || true)"

if [[ -z "$PORT_PIDS" ]]; then

  echo "  Port 4001 is free."

else

  echo "  Port 4001 still held by PIDs: $PORT_PIDS"

  for PID in $PORT_PIDS; do

    kill -9 "$PID" >/dev/null 2>&1 || true

    echo "  Freed PID $PID from port 4001."

    sleep 0.5

  done

  sleep 1

  if lsof -ti :4001 >/dev/null 2>&1; then

    echo ""
    echo "  WARNING: port 4001 still in use."

  else

    echo "  Port 4001 is now free."

  fi
fi

# =====================================================
# VERIFY CLEAN
# =====================================================

echo ""
echo "Verifying cleanup..."

REMAINING_CLAUDE="$(pgrep -f "[c]laude" 2>/dev/null || true)"
REMAINING_LITELLM="$(pgrep -f "litellm" 2>/dev/null || true)"
REMAINING_PORT="$(lsof -ti :4001 2>/dev/null || true)"

if [[ -z "$REMAINING_CLAUDE" && -z "$REMAINING_LITELLM" && -z "$REMAINING_PORT" ]]; then

  echo ""
  echo "========================================="
  echo " All Sessions Closed  [OK]"
  echo "========================================="

else

  echo ""
  echo "========================================="
  echo " WARNING: Residual Processes Found"
  echo "========================================="

  [[ -n "$REMAINING_CLAUDE" ]] && echo "  Claude:   $REMAINING_CLAUDE"
  [[ -n "$REMAINING_LITELLM" ]] && echo "  LiteLLM:  $REMAINING_LITELLM"
  [[ -n "$REMAINING_PORT" ]] && echo "  Port 4001: $REMAINING_PORT"

  echo ""
  echo "  Run 'sudo ./close.sh' if processes refused to stop."

fi

echo ""
echo "Done."
