#!/usr/bin/env bash
set -euo pipefail
> neoject.log

TEST_CON=false
CLEAN_DB=false
declare -a EXTRA_ARGS=()

log() {
  echo "[$(date +'%F %T')] $*" | tee -a neoject.log >&2
}
#log() {
#  echo "[$(date +'%F %T')] $*"  | tee -a neoject.log
#}

check_version() {
  local version
  version=$(cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain \
    <<< "CALL dbms.components() YIELD versions RETURN versions[0];" | tail -n 1)

  log "ℹ️  Connected to Neo4j version $version"

  if [[ "$version" != 5* ]]; then
    log "❌ Unsupported Neo4j version: $version. This script requires Neo4j v5.x."
    exit 1
  fi
}

# ⚠️  Access to the system database required
resetdb() {
  local dbname="${1:-neo4j}"  # Default: 'neo4j'
  echo "------------------------------"
  echo "⚠️  Resetting database '$dbname'..."
  {
    echo "DROP DATABASE $dbname IF EXISTS;"
    echo "CREATE DATABASE $dbname;"
  } | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database system --format verbose 2>&1 \
    | tee -a neoject.log
  echo "✅ Database '$dbname' dropped and recreated."
  echo "⏳ Waiting for database to come online..."
  sleep 5
}

delnds() {
  echo "------------------------------"

  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "RETURN apoc.version()" 2>/dev/null \
    || { echo "❌ APOC not available – cannot clean nodes"; exit 1; }

  echo "⚠️  Deleting all nodes using APOC (batchSize=10000)..."
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
  echo "✅ APOC-based node deletion completed."
}

drpcst() {
  echo "⚠️  Dropping all constraints (Neo4j 5)..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW CONSTRAINTS YIELD name RETURN name;" \
    | tail -n +2 | while read -r cname; do
        cname=${cname//\"/}
        [[ -n "$cname" ]] && {
          echo "    ➤ Dropping constraint: $cname"
          echo "CALL db.dropConstraint('$cname');" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1 \
            | tee -a neoject.log
        }
      done

  echo "✅ Constraints dropped."
}

drpcst4() {
  echo "------------------------------"
  echo "⚠️  Dropping all constraints..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW CONSTRAINTS YIELD name RETURN name;" \
    | tail -n +2 | while read -r cname; do
        # Entferne doppelte Anführungszeichen (") aus dem Constraint-Namen
        cname=${cname//\"/}
        [[ -n "$cname" ]] && {
          echo "    ➤ Dropping constraint: $cname"
          echo "DROP CONSTRAINT \`$cname\`;" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" \
              --format verbose 2>&1 | tee -a neoject.log
        }
      done
  echo "✅ Constraints dropped."
}

drpidx() {
  echo "⚠️  Dropping all indexes (Neo4j 5)..."
  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW INDEXES YIELD name RETURN name;" \
    | tail -n +2 | while read -r iname; do
        iname=${iname//\"/}
        [[ -n "$iname" ]] && {
          echo "    ➤ Dropping index: $iname"
          echo "CALL db.dropIndex('$iname');" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1 \
            | tee -a neoject.log
        }
      done
  echo "✅ Indexes dropped."
}

drpidx4() {
  echo "------------------------------"
  echo "⚠️  Dropping all indexes..."

  cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format plain <<< "SHOW INDEXES YIELD name RETURN name;" \
    | tail -n +2 | while read -r iname; do
        iname=${iname//\"/}  # Entferne doppelte Anführungszeichen
        [[ -n "$iname" ]] && {
          echo "    ➤ Dropping index: $iname"
          echo "DROP INDEX \`$iname\`;" \
            | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1 \
            | tee -a neoject.log
        }
      done

  echo "✅ Indexes dropped."
}

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) FILE="$2"; shift 2 ;;
    -u|--user) USER="$2"; shift 2 ;;
    -p|--password) PASSWORD="$2"; shift 2 ;;
    -a|--address) ADDRESS="$2"; shift 2 ;;
    --test-con) TEST_CON=true; shift ;;
    --clean-db) CLEAN_DB=true; shift ;;
    *) # passthrough unknown args
      EXTRA_ARGS+=("$1"); shift ;;
  esac
done

# Enforce mutual exclusivity
if [[ "$TEST_CON" == true && -n "${FILE:-}" ]]; then
  echo "❌ Options --test-con and -f are mutually exclusive."
  exit 1
fi

# Base parameters
if [[ -z "${USER:-}" || -z "${PASSWORD:-}" || -z "${ADDRESS:-}" ]]; then
  echo "Usage: neoject.sh (-f <cypher file> | --test-con) [--clean-db] -u <user> -p <password> -a <bolt://host:port>"
  exit 1
fi

# Version check
check_version

# Connection test
if [[ "$TEST_CON" == true ]]; then
  if cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" "${EXTRA_ARGS[@]:-}"; then
    echo "✅ Connection successful"
    exit 0
  else
    echo "❌ Connection failed"
    exit 1
  fi
fi

# Validate input file
if [[ -z "${FILE:-}" ]]; then
  echo "Missing -f argument. Use --test-con for connection test."
  exit 1
fi
if [[ ! -s "$FILE" ]]; then
  echo "⚠️  Cypher file '$FILE' is empty or not readable."
  exit 1
fi

# Optional: clean the database first
if [[ "$CLEAN_DB" == true ]]; then
  echo "🧹 Cleaning database: nodes, constraints, indexes..."
  delnds
  drpcst
  drpidx
  echo "🧹 Database cleaned."
fi

# Now import the AST as a single transaction
tee -a neoject.log <<EOF | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose --fail-fast 2>&1
:begin
$(cat "$FILE")
:commit
EOF

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ Import completed: '$FILE' executed as single transaction."
else
  echo "❌ Import failed for file '$FILE' (exit code $EXIT_CODE)"
  exit $EXIT_CODE
fi

