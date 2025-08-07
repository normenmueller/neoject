#!/usr/bin/env bash
set -euo pipefail
> neoject.log

VERSION="0.2.0"

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
  inject
    ( -g <graph.cypher> [--ddl-pre <pre.cypher>] [--ddl-post <post.cypher>]
    | -f <mixed.cypher>
    ) [--clean-db] [--reset-db]

  test-con
      Test Neo4j connectivity (no DB changes)

  clean-db
      Wipes all data from $DBNAME

  reset-db
      Drops and recreates database $DBNAME
      (requires system access!)

Base Options:
  -u|--user     <user>  Neo4j username (required)
  -p|--password <pass>  Neo4j password (required)
  -a|--address  <addr>  Bolt URI e.g. {bolt, neo4j}://localhost:7687 (required)
  -d|--database <db>    Database to use (default: neo4j)

Notes:
  - Exactly one sub-command must be provided
  - --clean-db and --reset-db are mutually exclusive
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
    inject)
      cat <<EOF
🧬 Help: inject

# Monolithic

Usage:
  neoject.sh inject -f <mixed.cypher> [--clean-db] [--reset-db]

Description:
  Monolithic execution of a mixed Cypher file (DDL + DML) via cypher-shell -f.
  Each statement runs in its own implicit transaction. Supports optional
  database reset/clean before import.

# Modular

Usage:
  neoject.sh inject -g <graph.cypher> [--ddl-pre <pre.cypher>]
    [--ddl-post <post.cypher>] [--clean-db] [--reset-db]

Description:
  Modular exection of DDL pre-statements (if provided), the DML graph
  (executed inside *one* explicit transaction), and DDL post-statements
  (if provided). Supports optional database reset/clean before import.
EOF
      exit $EXIT_SUCCESS
      ;;
    clean-db)
      cat <<EOF
🧬 Help: clean-db

Usage:
  neoject.sh clean-db

Description:
  Removes all nodes, relationships, constraints, and indexes from the database.
  Internal metadata such as Labels, Property Keys, and Relationship Types remain.

  Use this if you want to clear data but retain schema metadata.

Requires:
  - ⚠️ APOC plugin installed
  - WRITE permissions
EOF
      exit $EXIT_SUCCESS
      ;;
    reset-db)
      cat <<EOF
🧬 Help: reset-db

Usage:
  neoject.sh reset-db

Description:
  Drops and recreates the database defined via -d (default: neo4j).
  ⚠️  This removes **all data, schema, and internal metadata** —
     including Labels, Property Keys, and Relationship Types.

Requires:
  - SYSTEM database access
  - Will interrupt availability of the database
EOF
      exit $EXIT_SUCCESS
      ;;
    *)
      usage $EXIT_SUCCESS
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

check_cli_clsrst() {
  if [[ "$RESET_DB" == "true" && "$CLEAN_DB" == "true" ]]; then
    log "❌ --reset-db and --clean-db are exclusive"
    exit $EXIT_CLI_USAGE
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

check_db_apocext() {
  if cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<<"RETURN apoc.version();" &>/dev/null; then
    log "ℹ️  APOC detected"
  else
    log "❌ APOC not available"
    exit $EXIT_ENV_APOC_NOT_INSTALLED
  fi
}

# -----------------------------------------------------------------------------
# Low level actions
# -----------------------------------------------------------------------------

# inject mixed file
injmxf() {
  local file="$1"

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
}

# combine components
cmbcmp() {
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
}

# reset db
rstdb() {
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
      log "ℹ️  Database '$DBNAME' is online."
      return 0
    fi
    log "⏳ Waiting for '$DBNAME' to come online (status='$status')… ($i/30)"
    return 0
    sleep 1
  done

  log "❌ Timeout waiting for database to become available."
  exit $EXIT_DB_TIMEOUT
}

# clean db
clsdb() {
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
}

# -----------------------------------------------------------------------------
# Top level commands
# -----------------------------------------------------------------------------

test-con() {
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

inject-modu() {
  [[ ! -s "$GRAPH" ]]                      && { log "❌ Graph file missing: $GRAPH"; exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_PRE" && ! -s "$DDL_PRE" ]]   && { log "❌ DDL pre missing";  exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_POST" && ! -s "$DDL_POST" ]] && { log "❌ DDL post missing"; exit $EXIT_CLI_FILE_UNREADABLE; }

  log "📥 Merging DDL pre, DML graph, and DDL post"

  check_cli_clsrst
  check_db_version
  check_db_apocext

  $RESET_DB && rstdb
  $CLEAN_DB && clsdb

  cmbcmp

  log "✅ Merge complete"
  exit $EXIT_SUCCESS
}

inject_mono() {
  if [[ ! -s "$MIXED_FILE" ]]; then
    log "❌ Mixed file missing: $MIXED_FILE"
    exit $EXIT_CLI_FILE_UNREADABLE
  fi

  log "📥 Injecting mixed Cypher via file: $MIXED_FILE"

  check_cli_clsrst
  check_db_version
  check_db_apocext

  $RESET_DB && rstdb
  $CLEAN_DB && clsdb

  injmxf "$MIXED_FILE"

  log "✅ Injection complete"
  exit $EXIT_SUCCESS
}

clean-db() {
  log "🧹 Cleaning database '$DBNAME'…"
  check_db_version; clsdb
  log "✅ Database cleaning completed"
  exit $EXIT_SUCCESS
}

reset-db() {
  log "⚠️  Resetting database '$DBNAME'…"
  check_db_version; rstdb
  log "✅ Database reset completed"
  exit $EXIT_SUCCESS
}

# -----------------------------------------------------------------------------
# Arg Parsing
# -----------------------------------------------------------------------------

# Phase 1: global flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)      USER="$2";     shift 2 ;;
    -p|--password)  PASSWORD="$2"; shift 2 ;;
    -a|--address)   ADDRESS="$2";  shift 2 ;;
    -d|--database)  DBNAME="$2";   shift 2 ;;
    test-con|inject|clean-db|reset-db)
      CMD="$1"; shift; break ;;
    -h|--help)
      usage
      ;;
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

# Base validation
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
  inject)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -g)           GRAPH="$2";      shift 2 ;;
        --ddl-pre)    DDL_PRE="$2";    shift 2 ;;
        --ddl-post)   DDL_POST="$2";   shift 2 ;;
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
    # Validate mutual exclusivity
    if [[ -n "$GRAPH" && -n "$MIXED_FILE" ]]; then
      echo "❌ Options -g and -f are mutually exclusive"
      exit $EXIT_CLI_USAGE
    fi
    if [[ -z "$GRAPH" && -z "$MIXED_FILE" ]]; then
      echo "❌ Either -g or -f must be provided"
      exit $EXIT_CLI_USAGE
    fi
    # Validate --ddl-pre and --ddl-post only valid with -g
    if [[ -n "$MIXED_FILE" && ( -n "$DDL_PRE" || -n "$DDL_POST" ) ]]; then
      echo "❌ --ddl-pre and --ddl-post can only be used with -g <graph.cypher>"
      exit $EXIT_CLI_USAGE
    fi
    ;;
  clean-db)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help) using clean-db ;;
        *)
          echo "❌ clean-db takes no arguments"
          echo "👉 Run 'neoject help reset-db' for usage." >&2
          exit $EXIT_CLI_USAGE
          ;;
      esac
    done
    ;;
  reset-db)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help) using reset-db ;;
        *)
          echo "❌ reset-db takes no arguments"
          echo "👉 Run 'neoject help reset-db' for usage." >&2
          exit $EXIT_CLI_USAGE
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
    $RESET_DB && usage $EXIT_CLI_INVALID_DDL_USAGE
    $CLEAN_DB && usage $EXIT_CLI_INVALID_DDL_USAGE
    test-con
    ;;
  inject)
    [[ -n "$GRAPH" ]] && inject-modu
    [[ -n "$MIXED_FILE" ]] && inject_mono
    ;;
  clean-db)
    clean-db
    ;;
  reset-db)
    reset-db
    ;;
esac

