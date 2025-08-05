#!/usr/bin/env bash
set -uo pipefail
> neoject.log

VERSION="0.2.20"

# -----------------------------------------------------------------------------
# Exit Codes
# -----------------------------------------------------------------------------

readonly EXIT_SUCCESS=0

readonly EXIT_CLI_USAGE=10
readonly EXIT_CLI_FILE_UNREADABLE=11
readonly EXIT_CLI_INVALID_DDL_USAGE=12
readonly EXIT_CLI_MISSING_SUBCOMMAND=13
readonly EXIT_CLI_INVALID_SUBCOMMAND=14
readonly EXIT_CLI_MISSING_BASE_PARAMS=15
readonly EXIT_CLI_MUTUAL_EXCLUSIVE_CLEAN_RESET=16

readonly EXIT_ENV_UNSUPPORTED_NEO4J_VERSION=100
readonly EXIT_ENV_APOC_NOT_INSTALLED=101

readonly EXIT_DB_TIMEOUT=1000
readonly EXIT_DB_RESET_FAILED=1001
readonly EXIT_DB_IMPORT_FAILED=1002
readonly EXIT_DB_CONNECTION_FAILED=10003

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
DBMS_IMPORT_DIR=""

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
  neoject.sh -u <user> -p <password> -a <address> <command> [args]

⚠️  Note: All *global options* (-u/-p/-a etc.) must appear **before** the subcommand.
         All *subcommand-specific options* must follow **after** the subcommand.

Subcommands:
  test-con                       Test Neo4j connectivity (no DB changes)
  slurp     -g <graph> [--ddl-pre <pre>] [--ddl-post <post>]
                                 Import graph with optional DDL pre/post
  apply     -f <file> --import-dir <dir> [--clean-db|--reset-db]
                                 Execute mixed Cypher file (DDL + data)
  help [<cmd>]                   Show general or subcommand-specific help

Base Options:
  -u|--user <user>               Neo4j username (required)
  -p|--password <password>       Neo4j password (required)
  -a|--address <addr>            e.g. neo4j://localhost:7687 (required)

Import Options (for slurp/apply only):
  --clean-db                     Remove all nodes, indexes, constraints
  --reset-db                     Drop and recreate database (system access)

Notes:
  - Exactly one of: test-con | slurp | apply must be provided
  - --clean-db and --reset-db are mutually exclusive
  - --ddl-pre and --ddl-post are valid only with slurp
EOF
  exit ${1:-$EXIT_USAGE}
}

using() {
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
  --import-dir <dir> ???
  --clean-db         Clean current database (nodes, constraints, indexes)
  --reset-db         Drop and recreate the database

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
# Validation
# -----------------------------------------------------------------------------

check_version() {
  local version
  version=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< \
    "CALL dbms.components() YIELD versions RETURN versions[0];" | tail -n 1)
  version=${version//\"/}

  if [[ "$version" == 5* ]]; then
    log "ℹ️  Adequate Neo4j version detected: $version"
  else
    log "❌ Neoject requires Neo4j v5.x – detected: $version"
    exit $EXIT_ENV_UNSUPPORTED_NEO4J_VERSION
  fi
}

check_apoc() {
  if cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "RETURN apoc.version()" &>/dev/null; then
    log "ℹ️  APOC detected"
  else
    log "❌ APOC not available"
    exit $EXIT_ENV_APOC_NOT_INSTALLED
  fi
}

check_apoc_conformity() {
  local file="$1"
  local violations=0

  log "🔍 Validating APOC conformity of file: $file"

  # --- Rule 1: No :begin/:commit ---
  if grep -iE '^\s*:begin|^\s*:commit' "$file" >/dev/null; then
    log "❌ Rule violation: File must not contain :begin or :commit – Neoject wraps transaction automatically"
    ((violations++))
  fi

  # --- Rule 2: Forbidden transaction control ---
  if grep -iE '\bROLLBACK\b|\bCOMMIT\b' "$file" >/dev/null; then
    log "❌ Rule violation: Detected transaction control (ROLLBACK/COMMIT) – not allowed with apply"
    ((violations++))
  fi

  if [[ "$violations" -gt 0 ]]; then
    log "❌ Aborting due to $violations Cypher conformity violation(s)"
    exit $EXIT_DB_IMPORT_FAILED
  fi
}

check_mutually_exclusive_clean_reset() {
  if [[ "$RESET_DB" == "true" && "$CLEAN_DB" == "true" ]]; then
    log "❌ --reset-db and --clean-db are exclusive"
    exit $EXIT_CLI_MUTUAL_EXCLUSIVE_CLEAN_RESET
  fi
}

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------

# XXX User `-d` for `dbname`
resetdb() {
  local dbname="neo4j"
  log "⚠️  Resetting database '$dbname'…"

  # write the reset script
  local script
  script=$(mktemp)
  cat > "$script" <<EOF
DROP DATABASE $dbname IF EXISTS;
CREATE DATABASE $dbname;
EOF

  # run it on the system database
  if ! cypher-shell \
       -u "$USER" -p "$PASSWORD" \
       -a "$ADDRESS" \
       --database system \
       -f "$script" \
       --format verbose \
       | tee -a neoject.log
  then
    log "❌ Failed to reset database via script"
    rm -f "$script"
    exit $EXIT_DB_RESET_FAILED
  fi
  rm -f "$script"

  # wait up to 30s for it to report ONLINE
  for i in {1..30}; do
    # Query for currentStatus, strip header line and quotes/whitespace
    status=$(cypher-shell \
               -u "$USER" -p "$PASSWORD" \
               -a "$ADDRESS" \
               --database system \
               --format plain \
             <<< "SHOW DATABASE $dbname YIELD currentStatus;" \
             | tail -n +2 \
             | tr -d '"' \
             | xargs)

    if [[ "$status" == "online" ]]; then
      log "✅ Database '$dbname' is online."
      return 0
    fi

    log "⏳ Waiting for '$dbname' to come online (status='$status')… ($i/30)"
    sleep 1
  done

  log "❌ Timeout waiting for database to become available."
  exit $EXIT_DB_TIMEOUT
}

# XXX error handling!
cleandb() {
  log "🧹 Cleaning database..."
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
  if [[ -z "$DBMS_IMPORT_DIR" ]]; then
    log "❌ Missing --import-dir for apply"
    echo "👉 Provide the path to Neo4j's import directory via --import-dir"
    echo "🔧 For Neo4j Desktop, this must be set explicitly."
    exit $EXIT_CLI_USAGE
  fi

  if [[ ! -d "$DBMS_IMPORT_DIR" || ! -w "$DBMS_IMPORT_DIR" ]]; then
    log "❌ Invalid or unwritable --import-dir: $DBMS_IMPORT_DIR"
    exit $EXIT_CLI_FILE_UNREADABLE
  fi

  local file="$1"
  local abs_path
  abs_path=$(realpath "$file")
  local filename
  filename=$(basename "$abs_path")
  local target="$DBMS_IMPORT_DIR/$filename"

  cp "$abs_path" "$target" || {
    log "❌ Failed to copy file to import directory: $target"
    exit $EXIT_DB_IMPORT_FAILED
  }

  log "📥 Importing via APOC: file://$filename"

  echo "CALL apoc.cypher.runFile(\"file://$filename\", {useTx:false});" \
    | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" 2>&1 \
    | tee -a neoject.log

  local rc=${PIPESTATUS[1]}
  if [[ $rc -ne 0 ]]; then
    log "❌ APOC import failed (exit code $rc)"
    exit $EXIT_DB_IMPORT_FAILED
  fi

  log "✅ Apply complete"
  exit $EXIT_SUCCESS
}

import_file_shell() {
  local file="$1"
  log "📥 Importing Cypher via direct file: $file"

  cypher-shell \
    -u "$USER" -p "$PASSWORD" \
    -a "$ADDRESS" \
    -f "$file" \
    --format verbose \
    "${EXTRA_ARGS[@]:-}" 2>&1 \
    | tee -a neoject.log

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    log "❌ Direct file import failed (exit code $rc)"
    exit $EXIT_IMPORT_FAILED
  fi

  log "✅ Apply complete"
}

run_slurp() {
  [[ ! -s "$GRAPH" ]] && { log "❌ Graph file missing: $GRAPH"; exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_PRE" && ! -s "$DDL_PRE" ]] && { log "❌ DDL pre missing"; exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_POST" && ! -s "$DDL_POST" ]] && { log "❌ DDL post missing"; exit $EXIT_CLI_FILE_UNREADABLE; }
  check_mutually_exclusive_clean_reset

  [[ "$RESET_DB" == true ]] && resetdb
  [[ "$CLEAN_DB" == true ]] && cleandb
  [[ -n "$DDL_PRE" ]] && { log "📄 Executing DDL pre..."; cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]:-}" < "$DDL_PRE"; }

  log "📦 Importing graph as transaction"
  tee -a neoject.log <<EOF | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose --fail-fast "${EXTRA_ARGS[@]:-}"
:begin
$(cat "$GRAPH")
:commit
EOF

  [[ $? -eq 0 ]] || { log "❌ Import failed"; exit $EXIT_DB_IMPORT_FAILED; }

  [[ -n "$DDL_POST" ]] && { log "📄 Executing DDL post..."; cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]:-}" < "$DDL_POST"; }
  log "✅ Slurp complete"
}

run_apply() {
  [[ ! -s "$MIXED_FILE" ]] && { log "❌ Mixed file unreadable"; exit $EXIT_CLI_FILE_UNREADABLE; }

  check_apoc_conformity "$MIXED_FILE"
  check_mutually_exclusive_clean_reset

  [[ "$RESET_DB" == true ]] && resetdb
  [[ "$CLEAN_DB" == true ]] && cleandb

  import_file_apoc "$MIXED_FILE"
  #import_file_shell "$MIXED_FILE"
}

run_testcon() {
  if out=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]:-}" 2>&1); then
    log "✅ Connection OK"
    exit $EXIT_SUCCESS
  else
    echo "$out" >&2
    log "❌ Connection failed"
    exit $EXIT_DB_CONNECTION_FAILED
  fi
}

# -----------------------------------------------------------------------------
# Arg Parsing
# -----------------------------------------------------------------------------

# Phase 1: global flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user) USER="$2"; shift 2 ;;
    -p|--password) PASSWORD="$2"; shift 2 ;;
    -a|--address) ADDRESS="$2"; shift 2 ;;
    --clean-db) CLEAN_DB=true; shift ;;
    --reset-db) RESET_DB=true; shift ;;
    help|-h|--help) [[ $# -gt 1 ]] && using "$2" || usage ;;
    test-con|slurp|apply)
      CMD="$1"; shift; break ;;
    help|-h|--help)
      [[ $# -gt 1 ]] && using "$2" || usage ;;
    -*)
      EXTRA_ARGS+=("$1"); shift ;;  # passthrough for cypher-shell
    *)
      log "❌ Unknown subcommand: $1"
      echo "👉 Run 'neoject help' for usage." >&2
      exit $EXIT_CLI_INVALID_SUBCOMMAND
  esac
done

# Phase 2: subcommand-specific flags
while [[ $# -gt 0 ]]; do
  case "$CMD:$1" in
    apply:-f) MIXED_FILE="$2"; shift 2 ;;
    apply:--import-dir) DBMS_IMPORT_DIR="$2"; shift 2 ;;
    apply:help|apply:--help|apply:-h) using apply ;;

    slurp:-g) GRAPH="$2"; shift 2 ;;
    slurp:--ddl-pre) DDL_PRE="$2"; shift 2 ;;
    slurp:--ddl-post) DDL_POST="$2"; shift 2 ;;
    slurp:help|slurp:--help|slurp:-h) using slurp ;;

    slurp:--clean-db|apply:--clean-db) CLEAN_DB=true; shift ;;
    slurp:--reset-db|apply:--reset-db) RESET_DB=true; shift ;;

    test-con:help|test-con:--help|test-con:-h) using test-con ;;
    -*)
      EXTRA_ARGS+=("$1"); shift ;;
    *)
      log "❌ Fatal error: unknown argument for $CMD: $1"
      echo "👉 Run 'neoject help' for usage." >&2
      exit $EXIT_CLI_USAGE ;;
  esac
done

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

if [[ -z "$CMD" ]]; then
  log "❌ Missing subcommand"
  echo "👉 Run 'neoject help' for usage." >&2
  exit $EXIT_CLI_MISSING_SUBCOMMAND
fi

[[ -z "$USER" || -z "$PASSWORD" || -z "$ADDRESS" ]] && usage $EXIT_CLI_MISSING_BASE_PARAMS

case "$CMD" in
  test-con)
    [[ "$CLEAN_DB" == true || "$RESET_DB" == true ]] && usage $EXIT_CLI_INVALID_DDL_USAGE
    run_testcon
    ;;
  slurp)
    check_version
    check_apoc
    run_slurp
    ;;
  apply)
    check_version
    check_apoc
    run_apply
    ;;
  *)
    log "❌ Unhandled subcommand: $CMD"
    echo "👉 Run 'neoject help' for usage." >&2
    exit $EXIT_CLI_INVALID_SUBCOMMAND
    ;;
esac

