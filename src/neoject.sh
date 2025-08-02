#!/usr/bin/env bash
set -euo pipefail
> neoject.log

TEST_MODE=false
declare -a EXTRA_ARGS=()

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      FILE="$2"
      shift 2
      ;;
    -u|--user)
      USER="$2"
      shift 2
      ;;
    -p|--password)
      PASSWORD="$2"
      shift 2
      ;;
    -a|--address)
      ADDRESS="$2"
      shift 2
      ;;
    --test-con)
      TEST_MODE=true
      shift
      ;;
    *) # passthrough unknown args
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

# Enforce mutual exclusivity
if [[ "$TEST_MODE" == true && -n "${FILE:-}" ]]; then
  echo "❌ Options --test-con and -f are mutually exclusive."
  exit 1
fi

# Base parameters
if [[ -z "${USER:-}" || -z "${PASSWORD:-}" || -z "${ADDRESS:-}" ]]; then
  echo "Usage: neoject.sh (-f in.cypher | --test-con) -u <user> -p <password> -a <bolt://host:port> [-- additional cypher-shell args]"
  echo "© 2025 nemron"
  exit 1
fi

# Connection test
if [[ "$TEST_MODE" == true ]]; then
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

tee neoject.log <<EOF | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --format verbose 2>&1
:begin
$(cat "$FILE")
:commit
EOF

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ Import completed: '$FILE' executed as single transaction."
else
  echo "❌ Import failed for file '$FILE'"
  exit $EXIT_CODE
fi

