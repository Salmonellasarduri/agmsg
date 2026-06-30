#!/usr/bin/env bash
set -euo pipefail

# Usage: send.sh <team> <from> <to> <message>

TEAM="${1:?Usage: send.sh <team> <from> <to> <message>}"
FROM="${2:?Missing from agent}"
TO="${3:?Missing to agent}"
BODY="${4:?Missing message body}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
# Persist through the team's storage backend (sqlite by default; a per-team
# backend writes to that team's own store). The driver owns schema init,
# SQL-literal escaping, and the concurrent first-write retry (#114).
agmsg_storage_load "$TEAM"
storage_send "$TEAM" "$FROM" "$TO" "$BODY"

echo "Sent to $TO in team $TEAM"
