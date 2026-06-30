#!/usr/bin/env bash
set -euo pipefail

# Usage: inbox.sh <team> <agent_id> [--quiet]
# Shows unread messages and marks them as read.
# --quiet: only output if there are unread messages (for hooks)

TEAM="${1:?Usage: inbox.sh <team> <agent_id> [--quiet]}"
AGENT="${2:?Missing agent_id}"
QUIET=false
if [ "${3:-}" = "--quiet" ]; then
  QUIET=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
# Read + mark through the team's storage backend (sqlite default).
agmsg_storage_load "$TEAM"

if ! storage_exists "$TEAM"; then
  if [ "$QUIET" = true ]; then exit 0; fi
  echo "No messages (DB not initialized)"
  exit 0
fi

UNREAD=$(storage_list_unread "$TEAM" "$AGENT")

if [ -z "$UNREAD" ]; then
  if [ "$QUIET" = true ]; then exit 0; fi
  echo "No new messages."
  exit 0
fi

# Display
COUNT=$(echo "$UNREAD" | wc -l | tr -d ' ')
echo "$COUNT new message(s):"
echo ""
while IFS=$'\x1f' read -r from body ts; do
  echo "  [$ts] $from: $body"
done <<< "$UNREAD"
echo ""

# Mark as read (non-fatal — may fail in sandboxed environments). The driver
# dual-writes: append-only message_read events + read_at for back-compat.
storage_mark_read "$TEAM" "$AGENT"
