#!/usr/bin/env bash
set -euo pipefail
> neoject.log

VERSION="0.2.30"

# -----------------------------------------------------------------------------
# Exit Codes
# -----------------------------------------------------------------------------

readonly EXIT_SUCCESS=0

readonly EXIT_CLI_USAGE=10
readonly EXIT_CLI_INVALID_GLOBAL_FLAG=11
readonly EXIT_CLI_MISSING_BASE_PARAMS=12
readonly EXIT_CLI_INVALID_SUBCOMMAND=13
readonly EXIT_CLI_MISSING_SUBCOMMAND=14
readonly EXIT_CLI_INVALID_DDL_USAGE=15
readonly EXIT_CLI_INVALID_SUBCOMMAND_FLAG=16
readonly EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD=17
readonly EXIT_CLI_FILE_UNREADABLE=18
readonly EXIT_CLI_MUTUAL_EXCLUSIVE_CLEAN_RESET=19

readonly EXIT_ENV_UNSUPPORTED_NEO4J_VERSION=1000
readonly EXIT_ENV_APOC_NOT_INSTALLED=1001

readonly EXIT_DB_CONNECTION_FAILED=100
readonly EXIT_DB_TIMEOUT=101
readonly EXIT_DB_RESET_FAILED=102
readonly EXIT_DB_IMPORT_FAILED=103

# -----------------------------------------------------------------------------
# Global State
# -----------------------------------------------------------------------------

USER=""
PASSWORD=""
ADDRESS=""
DBNAME="neo4j"

CLEAN_DB=false
RESET_DB=false

CMD=""
GRAPH=""
DDL_PRE=""
DDL_POST=""
MIXED_FILE=""

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
  neoject.sh -u <user> -p <password> -a <address> [-d <database>] <command> [args]

⚠️  Note: Global options (-u/-p/-a/-d) must come **before** the subcommand.
         Subcommand-specific options come **after** the subcommand.

Subcommands:
  test-con
      Test Neo4j connectivity (no DB changes)

  combine -g <graph.cypher> [--ddl-pre <pre.cypher>] [--ddl-post <post.cypher>] [--clean-db] [--reset-db]
      Execute:
        1) optional RESET or CLEAN on $DBNAME
        2) optional DDL-PRE
        3) GRAPH (as DML only) in one transaction
        4) optional DDL-POST

  inject -f <mixed.cypher> [--clean-db] [--reset-db]
      Execute:
        1) optional RESET or CLEAN on $DBNAME
        2) execute mixed Cypher file (DDL + DML) via cypher-shell -f

Base Options:
  -u|--user     <user>     Neo4j username (required)
  -p|--password <pass>     Neo4j password (required)
  -a|--address  <addr>     Bolt URI e.g. neo4j://localhost:7687 (required)
  -d|--database <db>       Database to use (default: neo4j)

Notes:
  - Exactly one of test-con | combine | inject must be provided
  - combine requires -g <graph.cypher>
  - inject requires -f <mixed.cypher>
  - combine/inject allow for cleaning/resetting DB in advance,
    --clean-db and --reset-db are mutually exclusive
EOF
  exit ${1:-$EXIT_CLI_USAGE}
}

using() {
  case "$1" in
    test-con)
      cat <<EOF
🧬 Help: test-con
Usage:
  neoject.sh test-con
Description:
  Verifies connectivity/authentication with given -u/-p/-a[-d] parameters.
EOF
      exit $EXIT_SUCCESS
      ;;
    combine)
      cat <<EOF
🧬 Help: combine
Usage:
  neoject.sh combine -g <graph.cypher> [--ddl-pre <pre.cypher>] [--ddl-post <post.cypher>] [--clean-db] [--reset-db]
Description:
  Builds and runs:
    [DDL-PRE]      (if provided)
    [DML GRAPH]    (inside one explicit transaction)
    [DDL-POST]     (if provided)
  Supports optional database reset/clean before import.
EOF
      exit $EXIT_SUCCESS
      ;;
    inject)
      cat <<EOF
🧬 Help: inject
Usage:
  neoject.sh inject -f <mixed.cypher> [--clean-db] [--reset-db]
Description:
  Executes a mixed Cypher file (DDL + DML) via cypher-shell -f.
  Each statement runs in its own implicit transaction.
  Supports optional database reset/clean before import.
EOF
      exit $EXIT_SUCCESS
      ;;
    *)
      usage
      ;;
  esac
  exit $EXIT_SUCCESS
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

check_cli_clsrst() {
  if [[ "$RESET_DB" == "true" && "$CLEAN_DB" == "true" ]]; then
    log "❌ --reset-db and --clean-db are exclusive"
    exit $EXIT_CLI_MUTUAL_EXCLUSIVE_CLEAN_RESET
  fi
}

check_db_apocext() {
  if cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<<"RETURN apoc.version();" &>/dev/null; then
    log "ℹ️  APOC detected"
  else
    log "❌ APOC not available"
    exit $EXIT_ENV_APOC_NOT_INSTALLED
  fi
}

check_db_version() {
  local version
  version=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<<'CALL dbms.components() YIELD versions RETURN versions[0];' \
    | tail -n1 | tr -d '"')
  if [[ "$version" == 5* ]]; then
    log "ℹ️  Neo4j v5.x detected: $version"
  else
    log "❌ Neoject requires Neo4j v5.x – detected: $version"
    exit $EXIT_ENV_UNSUPPORTED_NEO4J_VERSION
  fi
}

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

# import mixed file
inject() {
  local file="$1"
  log "📥 Injecting mixed Cypher via file: $file"

  cypher-shell \
    -u "$USER" \
    -p "$PASSWORD" \
    -a "$ADDRESS" \
    -d "$DBNAME" \
    --format verbose \
    -f "$file" 2>&1 | tee -a neoject.log

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    log "❌ Inject failed (exit code $rc)"
    exit $EXIT_DB_IMPORT_FAILED
  fi

  log "✅ Inject complete"
}

# Environment
# -----------------------------------------------------------------------------

resetdb() {
  log "⚠️  Resetting database '$DBNAME'…"
  local script
  script=$(mktemp)
  cat >"$script" <<EOF
DROP DATABASE $DBNAME IF EXISTS;
CREATE DATABASE $DBNAME;
EOF

  if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database system -f "$script" --format verbose \
       | tee -a neoject.log; then
    log "❌ Failed to reset database via script"
    rm -f "$script"
    exit $EXIT_DB_RESET_FAILED
  fi
  rm -f "$script"

  for i in {1..30}; do
    local status
    status=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database system --format plain \
               <<<"SHOW DATABASE $DBNAME YIELD currentStatus;" \
             | tail -n+2 | tr -d '"' | xargs)
    if [[ "$status" == "online" ]]; then
      log "✅ Database '$DBNAME' is online."
      return 0
    fi
    log "⏳ Waiting for '$DBNAME' to come online (status='$status')… ($i/30)"
    sleep 1
  done

  log "❌ Timeout waiting for database to become available."
  exit $EXIT_DB_TIMEOUT
}

cleandb() {
  log "🧹 Cleaning database '$DBNAME'…"

  log "  ➤ Deleting nodes via APOC"
  if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" --format plain <<<'CALL apoc.periodic.iterate("MATCH (n) RETURN n", "DETACH DELETE n", {batchSize:10000}) YIELD batches RETURN batches;' \
        | tee -a neoject.log; then
    log "❌ Failed to delete nodes via APOC"
    exit $EXIT_DB_IMPORT_FAILED
  fi

  log "  ➤ Dropping constraints"
  if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" --format plain <<<"SHOW CONSTRAINTS YIELD name RETURN name;" \
        | tail -n+2 \
        | while read -r c; do
            [[ -n "$c" ]] && cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" <<<"DROP CONSTRAINT \`${c//\"/}\` IF EXISTS;"
          done \
        | tee -a neoject.log; then
    log "❌ Failed to drop constraints"
    exit $EXIT_DB_IMPORT_FAILED
  fi

  log "  ➤ Dropping indexes"
  if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" --format plain <<<"SHOW INDEXES YIELD name RETURN name;" \
        | tail -n+2 \
        | while read -r i; do
            [[ -n "$i" ]] && cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" <<<"DROP INDEX \`${i//\"/}\` IF EXISTS;"
          done \
        | tee -a neoject.log; then
    log "❌ Failed to drop indexes"
    exit $EXIT_DB_IMPORT_FAILED
  fi

  log "✅ Database cleaned"
}

# -----------------------------------------------------------------------------
# Core Commands
# -----------------------------------------------------------------------------

run_testcon() {
  if cypher-shell \
       -u "$USER" \
       -p "$PASSWORD" \
       -a "$ADDRESS" \
       -d "$DBNAME" \
       --format plain \
       --non-interactive \
       "RETURN 1" \
       &>/dev/null
  then
    log "✅ Connection OK"
    exit $EXIT_SUCCESS
  else
    log "❌ Connection failed"
    exit $EXIT_DB_CONNECTION_FAILED
  fi
}

run_combine() {
  [[ ! -s "$GRAPH" ]]                      && { log "❌ Graph file missing: $GRAPH"; exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_PRE" && ! -s "$DDL_PRE" ]]   && { log "❌ DDL pre missing";  exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_POST" && ! -s "$DDL_POST" ]] && { log "❌ DDL post missing"; exit $EXIT_CLI_FILE_UNREADABLE; }

  check_cli_clsrst
  check_db_version
  check_db_apocext

  $RESET_DB && resetdb
  $CLEAN_DB && cleandb

  if [[ -n "$DDL_PRE" ]]; then
    log "📄 Executing DDL PRE"
    if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" <"$DDL_PRE"; then
      log "❌ DDL-PRE failed"
      exit $EXIT_DB_IMPORT_FAILED
    fi
  fi

  log "📦 Importing DML graph as one transaction"
  tee -a neoject.log <<EOF | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" --format verbose --fail-fast 2>&1
:begin
$(cat "$GRAPH")
:commit
EOF

  if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
    log "❌ Graph import failed"
    exit $EXIT_DB_IMPORT_FAILED
  fi

  if [[ -n "$DDL_POST" ]]; then
    log "📄 Executing DDL POST"
    if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" <"$DDL_POST"; then
      log "❌ DDL-POST failed"
      exit $EXIT_DB_IMPORT_FAILED
    fi
  fi

  log "✅ Combine complete"
}

run_inject() {
  if [[ ! -s "$MIXED_FILE" ]]; then
    log "❌ Mixed file missing: $MIXED_FILE"
    exit $EXIT_CLI_FILE_UNREADABLE
  fi

  check_cli_clsrst
  check_db_version
  check_db_apocext

  $RESET_DB && resetdb
  $CLEAN_DB && cleandb

  inject "$MIXED_FILE"

  exit $EXIT_SUCCESS
}

# -----------------------------------------------------------------------------
# Arg Parsing
# -----------------------------------------------------------------------------

# Phase 1: global flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)               USER="$2";     shift 2 ;;
    -p|--password)           PASSWORD="$2"; shift 2 ;;
    -a|--address)            ADDRESS="$2";  shift 2 ;;
    -d|--database)           DBNAME="$2";   shift 2 ;;
    test-con|combine|inject) CMD="$1"; shift; break ;;
    -h|--help)               usage ;;
    -*)
      echo "❌ Invalid global flag: $1";
      echo "👉 Run 'neoject help' for usage." >&2
      exit $EXIT_CLI_INVALID_GLOBAL_FLAG
      ;;
    *)
      echo "❌ Invalid sub-command: $1";
      echo "👉 Run 'neoject help' for usage." >&2
      exit $EXIT_CLI_INVALID_SUBCOMMAND
      ;;
  esac
done

# Check for base params
if [[ -z "$USER" || -z "$PASSWORD" || -z "$ADDRESS" ]]; then
  echo "❌ Missing required global options: -u <user>, -p <password> and -a <address> must all be provided" >&2
  echo "👉 Run 'neoject help' for usage." >&2
  exit $EXIT_CLI_MISSING_BASE_PARAMS
fi

# Phase 2: subcommand-specific flags
case "$CMD" in
  test-con)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help)
          using test-con
          ;;
        --clean-db|--reset-db)
          echo "❌ test-con does not accept --clean-db/--reset-db"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_DDL_USAGE
          ;;
        -*)
          echo "❌ Invalid test-con flag: $1"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_FLAG
          ;;
        *)
          echo "❌ Invalid test-con sub-command: $1"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD
          ;;
      esac
    done
    ;;
  combine)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -g)           GRAPH="$2";    shift 2 ;;
        --ddl-pre)    DDL_PRE="$2";  shift 2 ;;
        --ddl-post)   DDL_POST="$2"; shift 2 ;;
        --clean-db)   CLEAN_DB=true; shift   ;;
        --reset-db)   RESET_DB=true; shift   ;;
        -h|--help)    using combine  ;;
        -*)
          echo "❌ Invalid combine flag: $1"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_FLAG
          ;;
        *)
          echo "❌ Invalid combine sub-command: $1"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD
          ;;
      esac
    done
    ;;
  inject)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f)           MIXED_FILE="$2"; shift 2 ;;
        --clean-db)   CLEAN_DB=true;   shift   ;;
        --reset-db)   RESET_DB=true;   shift   ;;
        -h|--help)    using inject             ;;
        -*)
          echo "❌ Invalid inject flag: $1"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_FLAG
          ;;
        *)
          echo "❌ Invalid inject sub-command: $1"
          echo "👉 Run 'neoject help' for usage." >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD
          ;;
      esac
    done
    ;;
  *)
    echo "❌ Missing sub-command"
    echo "👉 Run 'neoject help' for usage." >&2
    exit $EXIT_CLI_MISSING_SUBCOMMAND
    ;;
esac

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

case "$CMD" in
  test-con)
    #$RESET_DB && usage $EXIT_CLI_INVALID_DDL_USAGE
    #$CLEAN_DB && usage $EXIT_CLI_INVALID_DDL_USAGE
    run_testcon
    ;;
  combine) run_combine ;;
  inject)  run_inject  ;;
esac

