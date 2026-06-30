#!/usr/bin/env bash
set -euo pipefail

# storage.sh — manage a team's storage backend.
#
# Usage:
#   storage.sh use <driver> [team]        # set the backend (no data move)
#   storage.sh migrate <driver> [team]    # move the team's data to <driver>
#
# With no <team>, the operation applies to every registered team. Drivers:
# sqlite (default) | jsonl. "use" only flips the selection; "migrate" also
# carries the messages + read-state across (export -> import) and removes the
# source store afterward.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/storage.sh"

usage() { echo "Usage: storage.sh <use|migrate> <driver> [team]" >&2; }

# Every registered team (those with a teams/<team>/config.json).
_all_teams() {
  local d c; d="$(agmsg_teams_dir)"
  [ -d "$d" ] || return 0
  for c in "$d"/*/config.json; do
    [ -f "$c" ] || continue
    basename "$(dirname "$c")"
  done
}

_resolve_driver() {
  local team="$1" d
  d="$(agmsg_team_storage_driver "$team")"
  [ -n "$d" ] && [ "$d" != "null" ] || d="sqlite"
  printf '%s' "$d"
}

cmd_use() {
  local driver="$1" team="$2"
  agmsg_team_set_storage "$team" "$driver"
  echo "team '$team' storage -> $driver"
}

SUB="${1:-}"; [ -n "$SUB" ] || { usage; exit 1; }
shift
DRIVER="${1:-}"; [ -n "$DRIVER" ] || { usage; exit 1; }
TEAM="${2:-}"

case "$SUB" in
  use)
    if [ -n "$TEAM" ]; then
      cmd_use "$DRIVER" "$TEAM"
    else
      for t in $(_all_teams); do cmd_use "$DRIVER" "$t"; done
    fi
    ;;
  migrate)
    echo "storage.sh migrate: not yet implemented" >&2
    exit 1
    ;;
  *)
    usage; exit 1
    ;;
esac
