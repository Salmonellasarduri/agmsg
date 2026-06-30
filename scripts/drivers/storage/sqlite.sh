#!/usr/bin/env bash
# sqlite storage driver — the default backend.
#
# Wraps the message store in the storage_* contract so message call sites can be
# backend-agnostic. SCHEMA IS UNCHANGED from the non-driver path: message
# CONTENT lives in the `messages` table; read-state is the append-only `events`
# log (dual-written with messages.read_at during the transition). This driver
# is a faithful wrap of the existing SQL — same records, same ordering.
#
# Sourced by agmsg_storage_load(); assumes lib/storage.sh helpers (agmsg_sqlite,
# agmsg_team_db_path, agmsg_sqlesc, agmsg_skill_dir) are already in scope. Each
# function takes the <team> and resolves that team's store, so a per-team
# backend and the shared global store are handled identically.

# storage_exists <team> — has this team's store been initialized?
storage_exists() { [ -f "$(agmsg_team_db_path "$1")" ]; }

# storage_send <team> <from> <to> <body>
storage_send() {
  local team="$1" from="$2" to="$3" body="$4" db init insert
  db="$(agmsg_team_db_path "$team")"
  init="$(agmsg_skill_dir)/scripts/internal/init-db.sh"
  [ -f "$db" ] || bash "$init" "$team" >/dev/null
  insert="INSERT INTO messages (team, from_agent, to_agent, body) VALUES ('$(agmsg_sqlesc "$team")', '$(agmsg_sqlesc "$from")', '$(agmsg_sqlesc "$to")', '$(agmsg_sqlesc "$body")');"
  # Retry once after ensuring the schema (the #114 concurrent first-write race).
  # Pipe via stdin so a large body cannot overflow the OS command-line limit.
  if ! printf '%s\n' "$insert" | agmsg_sqlite "$db" 2>/dev/null; then
    bash "$init" "$team" >/dev/null
    printf '%s\n' "$insert" | agmsg_sqlite "$db"
  fi
}

# storage_list_unread <team> <agent>
# Emits one record per unread message: from <US> body <US> created_at  (oldest first).
storage_list_unread() {
  local team="$1" agent="$2" db tl al
  db="$(agmsg_team_db_path "$team")"
  [ -f "$db" ] || return 0
  tl="$(agmsg_sqlesc "$team")"; al="$(agmsg_sqlesc "$agent")"
  agmsg_sqlite "$db" "
    SELECT from_agent || char(31) || replace(replace(body, char(10), '\n'), char(9), '\t') || char(31) || created_at
    FROM messages WHERE team='$tl' AND to_agent='$al' AND read_at IS NULL
    ORDER BY created_at ASC;
  "
}

# storage_mark_read <team> <agent>
# Dual-write: append message_read events (append-only read-state) for the unread
# set, AND set read_at for back-compat. The events INSERT runs before the UPDATE
# so read_at IS NULL still selects the just-read set.
storage_mark_read() {
  local team="$1" agent="$2" db tl al
  db="$(agmsg_team_db_path "$team")"
  [ -f "$db" ] || return 0
  tl="$(agmsg_sqlesc "$team")"; al="$(agmsg_sqlesc "$agent")"
  agmsg_sqlite "$db" "
INSERT INTO events (type, team, agent, msg_id)
  SELECT 'message_read', team, to_agent, id FROM messages
  WHERE team='$tl' AND to_agent='$al' AND read_at IS NULL;
UPDATE messages SET read_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
  WHERE team='$tl' AND to_agent='$al' AND read_at IS NULL;
" 2>/dev/null || true
}

# storage_history <team> <agent-or-empty> <limit>
# Emits one record per message: from <US> to <US> body <US> created_at <US> status
# (newest first; ● = unread, ○ = read). <limit> must be a validated integer.
storage_history() {
  local team="$1" agent="$2" limit="$3" db tl where
  db="$(agmsg_team_db_path "$team")"
  [ -f "$db" ] || return 0
  tl="$(agmsg_sqlesc "$team")"
  if [ -n "$agent" ]; then
    local al; al="$(agmsg_sqlesc "$agent")"
    where="WHERE team='$tl' AND (from_agent='$al' OR to_agent='$al')"
  else
    where="WHERE team='$tl'"
  fi
  agmsg_sqlite "$db" "
    SELECT from_agent || char(31) || to_agent || char(31) || replace(replace(body, char(10), '\n'), char(9), '\t') || char(31) || created_at || char(31) || CASE WHEN read_at IS NULL THEN '●' ELSE '○' END
    FROM messages $where ORDER BY created_at DESC LIMIT $limit;
  "
}
