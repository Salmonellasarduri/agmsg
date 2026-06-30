#!/usr/bin/env bash
set -euo pipefail

# Usage: history.sh <team> [agent_id] [limit]
# Shows message history. If agent_id given, shows only that agent's messages.

TEAM="${1:?Usage: history.sh <team> [agent_id] [limit]}"
AGENT="${2:-}"
LIMIT="${3:-20}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
DB="$(agmsg_team_db_path "$TEAM")"

if [ ! -f "$DB" ]; then
  echo "No messages (DB not initialized)"
  exit 0
fi

# Read history through the team's storage backend (sqlite default). The driver
# returns newest-first records: from <US> to <US> body <US> ts <US> status.
agmsg_storage_load "$TEAM"
RESULT=$(storage_history "$TEAM" "$AGENT" "$LIMIT")

if [ -z "$RESULT" ]; then
  echo "No message history."
  exit 0
fi

# Reverse order (oldest first) and display
REVERSED=$(echo "$RESULT" | tail -r 2>/dev/null || echo "$RESULT" | tac 2>/dev/null || echo "$RESULT" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')
while IFS=$'\x1f' read -r from to body ts status; do
  echo "  $status [$ts] $from → $to: $body"
done <<< "$REVERSED"
