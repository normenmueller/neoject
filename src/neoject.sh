#!/usr/bin/env bash
set -euo pipefail
> neoject.log

VERSION=0.1

TEST_CON=false

CLEAN_DB=false
RESET_DB=false

declare -a EXTRA_ARGS=()

usage() {
  echo "🧬 neoject, v$VERSION"
  echo "Usage: neoject.sh [-h | --help]"
  echo "                  (-f <cypher file> | --test-con)"
  echo "                  [--clean-db | --reset-db]"
  echo "                  -u <user> -p <password>"
  echo "                  -a <neo4j://host:port>"
  echo "© 2025 nemron"
}

# ----------------------------------------------------------------------------
# Argument parsing & validation
# ----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -f|--file) FILE="$2"; shift 2 ;;
    -u|--user) USER="$2"; shift 2 ;;
    -p|--password) PASSWORD="$2"; shift 2 ;;
    -a|--address) ADDRESS="$2"; shift 2 ;;
    --test-con) TEST_CON=true; shift ;;
    --clean-db) CLEAN_DB=true; shift ;;
    --reset-db) RESET_DB=true; shift ;;
    *) # passthrough unknown args
      EXTRA_ARGS+=("$1"); shift ;;
  esac
done

# Enforce mutual exclusivity
if [[ "$TEST_CON" == true && -n "${FILE:-}" ]]; then
  log "❌ Options --test-con and -f are mutually exclusive."
  usage
  exit 2
fi

# Enforce mutual exclusivity
if [[ "$CLEAN_DB" == true && "$RESET_DB" == true ]]; then
  log "❌ Options --clean-db and --reset-db are mutually exclusive."
  usage
  exit 3
fi

# Base parameters
if [[ -z "${USER:-}" || -z "${PASSWORD:-}" || -z "${ADDRESS:-}" ]]; then
  usage
  exit 4
fi

# Version check
check_version

# Connection test
if [[ "$TEST_CON" == true ]]; then
  if cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]:-}"; then
    log "✅ Connection successful"
    exit 0
  else
    log "❌ Connection failed"
    exit 5
  fi
fi

# Validate input file
if [[ -z "${FILE:-}" ]]; then
  log "Missing -f argument. Use --test-con for connection test."
  exit 6
fi
if [[ ! -s "$FILE" ]]; then
  log "⚠️  Cypher file '$FILE' is empty or not readable."
  exit 7
fi

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------

echo "🧬 neoject, v$VERSION"

# Optional: clean the database first
if [[ "$CLEAN_DB" == true ]]; then
  log "🧹 Cleaning database: nodes, constraints, indexes..."
  delnds
  drpcst
  drpidx
  log "🧹 Database cleaned."
fi

# Now import the AST as a single transaction
tee -a neoject.log <<EOF | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose --fail-fast 2>&1
:begin
$(cat "$FILE")
:commit
EOF

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  log "✅ Import completed: '$FILE' executed as single transaction."
  exit 0
else
  log "❌ Import failed for file '$FILE' (exit code $EXIT_CODE)"
  exit $EXIT_CODE
fi

# ----------------------------------------------------------------------------
# Utility Functions
# ----------------------------------------------------------------------------

log() {
  echo "[$(date +'%F %T')] $*" | tee -a neoject.log >&2
}

check_version() {
  local version
  version=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain \
    <<< "CALL dbms.components() YIELD versions RETURN versions[0];" | tail -n 1)

  version=${version//\"/}  # Entfernt doppelte Anführungszeichen

  log "ℹ️  Connected to Neo4j version $version"

  if [[ "$version" != 5* ]]; then
    log "❌ Unsupported Neo4j version: $version. This script requires Neo4j v5.x."
    exit 1
  fi
}

# ⚠️  Access to the system database required
resetdb() {
  local dbname="${1:-neo4j}"  # Default: 'neo4j'
  log "------------------------------"
  log "⚠️  Resetting database '$dbname'..."
  {
    echo "DROP DATABASE $dbname IF EXISTS;"
    echo "CREATE DATABASE $dbname;"
  } | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database system --format verbose 2>&1 \
    | tee -a neoject.log
  log "✅ Database '$dbname' dropped and recreated."
  log "⏳ Waiting for database to come online..."
  sleep 5
}

delnds() {
  log "------------------------------"

  #local apoc_version
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "RETURN apoc.version()" &>/dev/null \
    || { log "❌ APOC not available – cannot clean nodes"; exit 1; }
  # or:
  #apoc_version=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "RETURN apoc.version()" 2>/dev/null | tail -n 1)
  #
  #if [[ -z "$apoc_version" ]]; then
  #  log "❌ APOC not available – cannot clean nodes"
  #  exit 1
  #fi

  log "⚠️  Deleting all nodes using APOC (batchSize=10000)..."
  {
    echo 'CALL apoc.periodic.iterate('
    echo '  "MATCH (n) RETURN n",'
    echo '  "DETACH DELETE n",'
    echo '  {batchSize:10000, parallel:false}'
    echo ')'
    echo 'YIELD timeTaken, batches, total'
    echo 'RETURN timeTaken, batches, total;'
  } | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain 2>&1 \
    | tee -a neoject.log
  log "✅ APOC-based node deletion completed."
}

drpcst() {
  log "⚠️  Dropping all constraints (Neo4j 5)..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW CONSTRAINTS YIELD name RETURN name;" \
    | tail -n +2 | while read -r cname; do
        cname=${cname//\"/}
        [[ -n "$cname" ]] && {
          log "    ➤ Dropping constraint: $cname"
          echo "CALL db.dropConstraint('$cname');" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1 \
            | tee -a neoject.log
        }
      done

  log "✅ Constraints dropped."
}

drpcst4() {
  log "------------------------------"
  log "⚠️  Dropping all constraints..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW CONSTRAINTS YIELD name RETURN name;" \
    | tail -n +2 | while read -r cname; do
        # Entferne doppelte Anführungszeichen (") aus dem Constraint-Namen
        cname=${cname//\"/}
        [[ -n "$cname" ]] && {
          log "    ➤ Dropping constraint: $cname"
          echo "DROP CONSTRAINT \`$cname\`;" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" \
              --format verbose 2>&1 | tee -a neoject.log
        }
      done
  log "✅ Constraints dropped."
}

drpidx() {
  log "⚠️  Dropping all indexes (Neo4j 5)..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW INDEXES YIELD name RETURN name;" \
    | tail -n +2 | while read -r iname; do
        iname=${iname//\"/}
        [[ -n "$iname" ]] && {
          log "    ➤ Dropping index: $iname"
          echo "CALL db.dropIndex('$iname');" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1 \
            | tee -a neoject.log
        }
      done
  log "✅ Indexes dropped."
}

drpidx4() {
  log "------------------------------"
  log "⚠️  Dropping all indexes..."

  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW INDEXES YIELD name RETURN name;" \
    | tail -n +2 | while read -r iname; do
        iname=${iname//\"/}  # Entferne doppelte Anführungszeichen
        [[ -n "$iname" ]] && {
          log "    ➤ Dropping index: $iname"
          echo "DROP INDEX \`$iname\`;" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1 \
            | tee -a neoject.log
        }
      done

  log "✅ Indexes dropped."
}

