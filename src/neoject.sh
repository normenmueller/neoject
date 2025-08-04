#!/usr/bin/env bash
set -euo pipefail
> neoject.log

VERSION="0.2.3"

# -----------------------------------------------------------------------------
# Exit Codes
# -----------------------------------------------------------------------------

readonly EXIT_SUCCESS=0
readonly EXIT_USAGE=1
readonly EXIT_INVALID_SUBCOMMAND=2
readonly EXIT_MISSING_BASE_PARAMS=3
readonly EXIT_UNSUPPORTED_NEO4J_VERSION=4
readonly EXIT_CONNECTION_FAILED=5
readonly EXIT_FILE_UNREADABLE=6
readonly EXIT_APOC_NOT_INSTALLED=7
readonly EXIT_DB_TIMEOUT=8
readonly EXIT_IMPORT_FAILED=9
readonly EXIT_MUTUAL_EXCLUSIVE_CLEAN_RESET=10
readonly EXIT_INVALID_DDL_USAGE=11

# -----------------------------------------------------------------------------
# Global State
# -----------------------------------------------------------------------------

USER=""
PASSWORD=""
ADDRESS=""

CLEAN_DB=false
RESET_DB=false

CMD=""
GRAPH=""
DDL_PRE=""
DDL_POST=""
MIXED_FILE=""

EXTRA_ARGS=()

# -----------------------------------------------------------------------------
# Logging & Help
# -----------------------------------------------------------------------------

log() {
  echo "[$(date +'%F %T')] $*" | tee -a neoject.log >&2
}

usage() {
  cat <<EOF
🧬 neoject v$VERSION
© 2025 nemron

Usage:
  neoject.sh -u <user> -p <password> -a <address> [cypher-shell options] <subcommand> [args]

Subcommands:
  test-con                       Test Neo4j connectivity (no DB changes)
  slurp     -g <graph> [--ddl-pre <pre>] [--ddl-post <post>]
                                 Import graph with optional DDL pre/post
  apply     -f <file>            Execute mixed Cypher file (DDL + data)
  help [<cmd>]                   Show general or subcommand-specific help

Base Options:
  -u|--user <user>               Neo4j username (required)
  -p|--password <password>       Neo4j password (required)
  -a|--address <addr>            e.g. bolt://localhost:7687 (required)

Import Options (for slurp/apply only):
  --clean-db                     Remove all nodes, indexes, constraints
  --reset-db                     Drop and recreate database (system access)

Notes:
  - Exactly one of: test-con | slurp | apply must be provided
  - --clean-db and --reset-db are mutually exclusive
  - --ddl-pre and --ddl-post are valid only with slurp
  - All extra args passed after -a ... are forwarded to cypher-shell
EOF
  exit ${1:-$EXIT_USAGE}
}

sub_help() {
  case "$1" in
    slurp) cat <<EOF
🧬 Help: slurp
Usage:
  neoject slurp -g <graph.cypher> [--ddl-pre <pre.cypher>] [--ddl-post <post.cypher>]
Options:
  --clean-db     Clean current database (nodes, constraints, indexes)
  --reset-db     Drop and recreate the database
Notes:
  - All files must be readable
  - DDL files are executed outside of the transaction
EOF
      ;;
    apply) cat <<EOF
🧬 Help: apply
Usage:
  neoject apply -f <mixed.cypher>
Options:
  --clean-db     Clean current database (nodes, constraints, indexes)
  --reset-db     Drop and recreate the database
Notes:
  - File must contain semicolon-terminated Cypher statements
  - No :begin/:commit must appear in the file
  - APOC must be installed (uses apoc.cypher.runFile)
EOF
      ;;
    test-con) cat <<EOF
🧬 Help: test-con
Usage:
  neoject test-con
Description:
  Verifies connection/authentication with given -u/-p/-a parameters.
EOF
      ;;
    *) usage ;;
  esac
  exit 0
}

# -----------------------------------------------------------------------------
# Validation & Environment
# -----------------------------------------------------------------------------

check_version() {
  local version
  version=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< \
    "CALL dbms.components() YIELD versions RETURN versions[0];" | tail -n 1)
  version=${version//\"/}
  log "ℹ️  Connected to Neo4j version $version"
  [[ "$version" != 5* ]] && {
    log "❌ Neoject requires Neo4j v5.x – detected: $version"
    exit $EXIT_UNSUPPORTED_NEO4J_VERSION
  }
}

resetdb() {
  local dbname="neo4j"
  log "⚠️  Resetting database '$dbname'..."
  {
    echo "DROP DATABASE $dbname IF EXISTS;"
    echo "CREATE DATABASE $dbname;"
  } | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database system --format verbose "${EXTRA_ARGS[@]}" | tee -a neoject.log

  for i in {1..30}; do
    status=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database system --format plain <<< \
      "SHOW DATABASES YIELD name, currentStatus WHERE name = '$dbname' RETURN currentStatus;" | tail -n 1 | tr -d '"')
    [[ "$status" == "online" ]] && { log "✅ Database is online."; return 0; }
    sleep 1
  done
  log "❌ Timeout waiting for database to become available."
  exit $EXIT_DB_TIMEOUT
}

cleandb() {
  log "🧹 Cleaning database..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "RETURN apoc.version()" &>/dev/null \
    || { log "❌ APOC not available"; exit $EXIT_APOC_NOT_INSTALLED; }

  log "  ➤ Deleting nodes..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< \
    'CALL apoc.periodic.iterate("MATCH (n) RETURN n", "DETACH DELETE n", {batchSize:10000}) YIELD batches RETURN batches;' \
    | tee -a neoject.log

  log "  ➤ Dropping constraints..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW CONSTRAINTS YIELD name RETURN name;" \
    | tail -n +2 | while read -r c; do
      [[ -n "$c" ]] && cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" <<< "CALL db.dropConstraint('${c//\"/}');"
    done

  log "  ➤ Dropping indexes..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW INDEXES YIELD name RETURN name;" \
    | tail -n +2 | while read -r i; do
      [[ -n "$i" ]] && cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" <<< "CALL db.dropIndex('${i//\"/}');"
    done

  log "✅ Database cleaned"
}

# -----------------------------------------------------------------------------
# Core Commands
# -----------------------------------------------------------------------------

import_file_apoc() {
  local file="$1"
  local abs_path
  abs_path=$(realpath "$file")
  local target="/tmp/$(basename "$abs_path")"
  cp "$abs_path" "$target"
  log "📥 Importing mixed Cypher via APOC: $target"
  echo "CALL apoc.cypher.runFile(\"file://$target\", {useTx:false});" \
    | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]}" \
    | tee -a neoject.log
}

run_slurp() {
  [[ ! -s "$GRAPH" ]] && { log "❌ Graph file missing: $GRAPH"; exit $EXIT_FILE_UNREADABLE; }
  [[ -n "$DDL_PRE" && ! -s "$DDL_PRE" ]] && { log "❌ DDL pre missing"; exit $EXIT_FILE_UNREADABLE; }
  [[ -n "$DDL_POST" && ! -s "$DDL_POST" ]] && { log "❌ DDL post missing"; exit $EXIT_FILE_UNREADABLE; }
  [[ "$RESET_DB" == true && "$CLEAN_DB" == true ]] && { log "❌ --reset-db and --clean-db are exclusive"; exit $EXIT_MUTUAL_EXCLUSIVE_CLEAN_RESET; }

  [[ "$RESET_DB" == true ]] && resetdb
  [[ "$CLEAN_DB" == true ]] && cleandb
  [[ -n "$DDL_PRE" ]] && { log "📄 Executing DDL pre..."; cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]}" < "$DDL_PRE"; }

  log "📦 Importing graph as transaction"
  tee -a neoject.log <<EOF | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose --fail-fast "${EXTRA_ARGS[@]}"
:begin
$(cat "$GRAPH")
:commit
EOF

  [[ $? -eq 0 ]] || { log "❌ Import failed"; exit $EXIT_IMPORT_FAILED; }

  [[ -n "$DDL_POST" ]] && { log "📄 Executing DDL post..."; cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]}" < "$DDL_POST"; }
  log "✅ Slurp complete"
}

run_apply() {
  [[ ! -s "$MIXED_FILE" ]] && { log "❌ Mixed file unreadable"; exit $EXIT_FILE_UNREADABLE; }
  [[ "$RESET_DB" == true ]] && resetdb
  [[ "$CLEAN_DB" == true ]] && cleandb
  import_file_apoc "$MIXED_FILE"
  log "✅ Apply complete"
}

run_testcon() {
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]}" \
    && log "✅ Connection OK" && exit $EXIT_SUCCESS \
    || { log "❌ Connection failed"; exit $EXIT_CONNECTION_FAILED; }
}

# -----------------------------------------------------------------------------
# Arg Parsing
# -----------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then usage; fi

# Phase 1: global flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user) USER="$2"; shift 2 ;;
    -p|--password) PASSWORD="$2"; shift 2 ;;
    -a|--address) ADDRESS="$2"; shift 2 ;;
    --clean-db) CLEAN_DB=true; shift ;;
    --reset-db) RESET_DB=true; shift ;;
    help|-h|--help) [[ $# -gt 1 ]] && sub_help "$2" || usage ;;
    test-con|slurp|apply) CMD="$1"; shift; break ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

# Phase 2: subcommand args and passthrough
while [[ $# -gt 0 ]]; do
  case "$CMD:$1" in
    slurp:-g) GRAPH="$2"; shift 2 ;;
    slurp:--ddl-pre) DDL_PRE="$2"; shift 2 ;;
    slurp:--ddl-post) DDL_POST="$2"; shift 2 ;;
    apply:-f) MIXED_FILE="$2"; shift 2 ;;
    *) EXTRA_ARGS+=("$1"); shift ;;  # passthrough to cypher-shell
  esac
done

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

[[ -z "$CMD" ]] && usage
[[ -z "$USER" || -z "$PASSWORD" || -z "$ADDRESS" ]] && usage $EXIT_MISSING_BASE_PARAMS

check_version

case "$CMD" in
  test-con) [[ "$CLEAN_DB" == true || "$RESET_DB" == true ]] && usage $EXIT_INVALID_DDL_USAGE; run_testcon ;;
  slurp) run_slurp ;;
  apply) run_apply ;;
  *) log "❌ Unknown subcommand: $CMD"; usage $EXIT_INVALID_SUBCOMMAND ;;
esac
