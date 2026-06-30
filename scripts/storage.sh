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

# Move a team's messages + read-state to <target>. Order is chosen so the
# export file is always a usable backup if anything later fails:
#   export(current) -> purge(current) -> flip mapping -> import(target)
cmd_migrate() {
  local team="$1" target="$2" current backup
  current="$(_resolve_driver "$team")"
  if [ "$current" = "$target" ]; then
    echo "team '$team' already on $target"
    return 0
  fi

  agmsg_storage_load "$team"                      # current backend
  backup="$(agmsg_team_storage_dir "$team")/migrate-${current}-to-${target}.jsonl"
  mkdir -p "$(dirname "$backup")"
  storage_export "$team" > "$backup"

  storage_purge "$team"                           # config still = current
  agmsg_team_set_storage "$team" "$target"        # flip mapping (seam)

  _AGMSG_LOADED_DRIVER=""                          # force reload of the target
  agmsg_storage_load "$team"
  storage_import "$team" < "$backup"

  echo "team '$team' migrated $current -> $target (backup: $backup)"
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
    if [ -n "$TEAM" ]; then
      cmd_migrate "$TEAM" "$DRIVER"
    else
      for t in $(_all_teams); do cmd_migrate "$t" "$DRIVER"; done
    fi
    ;;
  *)
    usage; exit 1
    ;;
esac
