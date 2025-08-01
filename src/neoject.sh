#!/usr/bin/env bash
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case $1 in
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
    *)
      echo "Unbekannter Parameter: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${FILE:-}" || -z "${USER:-}" || -z "${PASSWORD:-}" || -z "${ADDRESS:-}" ]]; then
  echo "Usage: neoject.sh -f in.cypher -u neo4j -p geheim -a bolt://localhost:7687"
  exit 1
fi

cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" -f "$FILE"

