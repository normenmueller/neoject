#!/usr/bin/env bash
# neoject © 2025 nemron
set -euo pipefail
> neoject.log

VERSION="0.3.12"

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

# chunking controls
CHUNKED=false        # -f needs explicit opt-in
CHUNK_STMTS=0        # statements per chunk
CHUNK_BYTES=0        # bytes per chunk
BATCH_DELAY_MS=0     # delay between chunks (milliseconds)

# Defaults for -g (chunking always on)
DEFAULT_G_CHUNK_STMTS=1000               # 1000 Statements per default
DEFAULT_G_CHUNK_BYTES=$((8*1024*1024))   # 8 MiB
DEFAULT_G_DELAY_MS=0                     # 0 ms delay per default

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
  neoject -u <user> -p <password> -a <address> [-d <database>] <command> [args]

⚠️  Global options (-u/-p/-a/-d) must come **before** the subcommand.

Subcommands:
  inject
    Injects modular (-g) or monolithic (-f) Cypher-based graph initializations

  test-con
      Test Neo4j connectivity (no DB changes)

  clean-db
      Wipes all data from \$DBNAME

  reset-db
      Drops and recreates database \$DBNAME (requires system access!)

Base Options:
  -u|--user     <user>  Neo4j username (required)
  -p|--password <pass>  Neo4j password (required)
  -a|--address  <addr>  Bolt/Neo4j URI e.g. neo4j://localhost:7687 (required)
  -d|--database <db>    Database to use (default: neo4j)

ℹ️  Run 'neoject <command> --help' for details on a subcommand.
EOF
  exit ${1:-$EXIT_CLI_USAGE}
}

using() {
  case "$1" in
    test-con)
      cat <<EOF
🧬 Help: test-con

Usage:
  neoject test-con

Description:
  Verifies connectivity/authentication with given -u/-p/-a[-d] parameters.
EOF
      exit $EXIT_SUCCESS
      ;;
    inject)
      cat <<EOF
🧬 Help: inject

  Modular mode (-g):
    neoject inject -g <graph.cypher>
        [--ddl-pre <pre.cypher>] [--ddl-post <post.cypher>]
        [--clean-db] [--reset-db]
        [--chunk-stmts <N> | --chunk-bytes <M>] [--batch-delay <ms>]

    Description:
      Modular execution of DDL pre, the DML graph, and DDL post.

    Notes:
      - Chunking is always ON in -g mode (default: --chunk-stmts $DEFAULT_G_CHUNK_STMTS,
        --chunk-bytes $DEFAULT_G_CHUNK_BYTES, and --batch-delay=$DEFAULT_G_DELAY_MS ms)
      - --chunk-stmts and --chunk-bytes are mutually exclusive

  Monolithic mode (-f):
    neoject inject -f <mixed.cypher>
        [--clean-db] [--reset-db]
        [--chunked [--chunk-stmts <N> | --chunk-bytes <M>] [--batch-delay <ms>]]

    Description:
      Monolithic execution of a mixed Cypher file (DDL + DML) via
      'cypher-shell -f'. With --chunked, executes in explicit transactional
      chunks.

    Notes:
      - Chunking is OFF by default in -f mode; enable with --chunked
      - --chunk-stmts and --chunk-bytes are mutually exclusive
EOF
      exit $EXIT_SUCCESS
      ;;
    clean-db)
      cat <<EOF
🧬 Help: clean-db

Usage:
  neoject clean-db

Description:
  Removes all nodes, relationships, constraints, and indexes from the database.
  Internal metadata such as Labels, Property Keys, and Relationship Types remain.

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
  neoject reset-db

Description:
  Drops and recreates the database defined via -d (default: neo4j).
  ⚠️  This removes **all data, schema, and internal metadata**.

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

check_cli_stby() {
  if [[ $CHUNK_STMTS -gt 0 && $CHUNK_BYTES -gt 0 ]]; then
    log "❌ --chunk-stmts and --chunk-bytes are mutually exclusive"
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
# Utilities
# -----------------------------------------------------------------------------

sleepFor() {
  local ms="$1"
  [[ "$ms" -le 0 ]] && return 0
  # portable enough: awk for float seconds
  local sec
  sec=$(awk -v m="$ms" 'BEGIN{printf "%.3f", m/1000.0}')
  sleep "$sec"
}

fsize() {
  if stat --version >/dev/null 2>&1;
    then stat -c %s "$1";
    else stat -f %z "$1";
  fi
}

# -----------------------------------------------------------------------------
# Low level actions
# -----------------------------------------------------------------------------

# Create chunks according to size/bytes limits. Chunk flush occurs as soon as
# one of the two values is reached. Prints as output one chunk file path per
# line (in order).
chk() {
  local file="$1"
  local max_stmt="$2"     # statements per chunk (0 disables)
  local max_bytes="$3"    # bytes per chunk (0 disables)

  [[ ! -s "$file" ]] && { log "❌ Input missing for chk: $file"; exit $EXIT_CLI_FILE_UNREADABLE; }

  # Normalize CRLF -> LF so the state machine never sees '\r'
  local normfile
  normfile="$(mktemp)"
  tr -d '\r' <"$file" >"$normfile"
  file="$normfile"

  local tmpdir
  tmpdir="$(mktemp -d -t neoject-chunks-XXXXXX)"
  # NOTE: caller cleans up $tmpdir

  log "🧩 Chunking '$file' (max_stmt=${max_stmt:-0}, max_bytes=${max_bytes:-0})"
  log " → dir: $tmpdir "

  # State machine for semicolon-terminated statements; respects quotes/backticks
  local buf="" stmt_count=0 chunk_bytes=0 chunk_idx=0
  local in_sq=0 in_dq=0 in_bt=0 esc=0
  local at_boundary=0

  # Keep every byte, including '\n' — delimiter set to “never occurs”
  local IFS=                  # ← read raw, don't trim anything
  while IFS= read -r -n 1 -d '' ch; do
    buf+="$ch"

    # toggle states (quotes/backticks), respect escapes in double/single quotes
    if [[ $esc -eq 1 ]]; then
      esc=0
    else
      if [[ "$ch" == "\\" ]]; then
        esc=1
      elif [[ $in_sq -eq 1 ]]; then
        [[ "$ch" == "'" ]] && in_sq=0
      elif [[ $in_dq -eq 1 ]]; then
        [[ "$ch" == '"' ]] && in_dq=0
      elif [[ $in_bt -eq 1 ]]; then
        [[ "$ch" == '`' ]] && in_bt=0
      else
        case "$ch" in
          "'") in_sq=1 ;;
          '"') in_dq=1 ;;
          '`') in_bt=1 ;;
        esac
      fi
    fi

    # detect statement end (semicolon outside quotes/backticks)
    if [[ "$ch" == ";" && $in_sq -eq 0 && $in_dq -eq 0 && $in_bt -eq 0 ]]; then
      ((stmt_count++))
      at_boundary=1
    fi

    # update bytes AFTER adding char
    ((chunk_bytes++))

    local want_flush=0
    # statement-based boundary
    [[ $max_stmt  -gt 0 && $stmt_count  -ge $max_stmt  ]] && want_flush=1
    # byte-based boundary
    [[ $max_bytes -gt 0 && $chunk_bytes -ge $max_bytes ]] && want_flush=1

    if [[ $want_flush -eq 1 && $at_boundary -eq 1 ]]; then
      ((chunk_idx++))
      local chunk="$tmpdir/chunk.$(printf "%06d" "$chunk_idx").cypher"
      printf "%s" "$buf" >"$chunk"
      echo "$chunk"
      # reset counters/state for next chunk
      buf=""
      stmt_count=0
      chunk_bytes=0
      at_boundary=0
      in_sq=0; in_dq=0; in_bt=0; esc=0
    fi
  done <"$file"

  # last tail
  if [[ -n "$buf" ]]; then
    ((chunk_idx++))
    local chunk="$tmpdir/chunk.$(printf "%06d" "$chunk_idx").cypher"
    printf "%s" "$buf" >"$chunk"
    echo "$chunk"
  fi

  # cleanup normalized temp
  rm -f "$normfile"
}

# ⚠️  Currently not used
# Decision: we remain “lossy-free”, i.e. no trimming.
chk_trm() {
  local file="$1"
  local max_stmt="$2"     # statements per chunk (0 disables)
  local max_bytes="$3"    # bytes per chunk (0 disables)

  [[ ! -s "$file" ]] && { log "❌ Input missing for chk: $file"; exit $EXIT_CLI_FILE_UNREADABLE; }

  # Normalize CRLF -> LF so the state machine never sees '\r'
  local normfile
  normfile="$(mktemp)"
  tr -d '\r' <"$file" >"$normfile"
  file="$normfile"

  local tmpdir
  tmpdir="$(mktemp -d -t neoject-chunks-XXXXXX)"
  # NOTE: caller cleans up $tmpdir

  log "🧩 Chunking '$file' (max_stmt=${max_stmt:-0}, max_bytes=${max_bytes:-0})"
  log " → dir: $tmpdir "

  # State machine for semicolon-terminated statements; respects quotes/backticks
  local buf="" stmt_count=0 chunk_bytes=0 chunk_idx=0
  local in_sq=0 in_dq=0 in_bt=0 esc=0
  local new_chunk=1               # ✨ trim leading whitespace per chunk

  # Keep every byte, including '\n' — delimiter set to “never occurs”
  while IFS= read -r -n 1 -d '' ch; do
    # (Optional safety) ignore stray CR if any slipped through
    [[ "$ch" == $'\r' ]] && continue

    # ✨ Trim leading whitespace at the *beginning* of a chunk
    if [[ $new_chunk -eq 1 && "$ch" =~ [[:space:]] ]]; then
      continue
    fi

    # toggle states (quotes/backticks), respect escapes in double/single quotes
    if [[ $esc -eq 1 ]]; then
      esc=0
    else
      if [[ "$ch" == "\\" ]]; then
        esc=1
      elif [[ $in_sq -eq 1 ]]; then
        [[ "$ch" == "'" ]] && in_sq=0
      elif [[ $in_dq -eq 1 ]]; then
        [[ "$ch" == '"' ]] && in_dq=0
      elif [[ $in_bt -eq 1 ]]; then
        [[ "$ch" == '`' ]] && in_bt=0
      else
        case "$ch" in
          "'") in_sq=1 ;;
          '"') in_dq=1 ;;
          '`') in_bt=1 ;;
        esac
      fi
    fi

    # now we actually append the char
    buf+="$ch"
    ((chunk_bytes++))
    new_chunk=0                   # first non-trimmed char seen

    # detect statement end (semicolon outside quotes/backticks)
    if [[ "$ch" == ";" && $in_sq -eq 0 && $in_dq -eq 0 && $in_bt -eq 0 ]]; then
      ((stmt_count++))
    fi

    # flush conditions
    local flush=0
    [[ $max_stmt  -gt 0 && $stmt_count  -ge $max_stmt  ]] && flush=1
    [[ $max_bytes -gt 0 && $chunk_bytes -ge $max_bytes ]] && flush=1

    if [[ $flush -eq 1 ]]; then
      ((chunk_idx++))
      local chunk="$tmpdir/chunk.$(printf "%06d" "$chunk_idx").cypher"
      printf "%s" "$buf" >"$chunk"
      echo "$chunk"
      # reset for next chunk
      buf=""
      stmt_count=0
      chunk_bytes=0
      in_sq=0; in_dq=0; in_bt=0; esc=0
      new_chunk=1
    fi
  done <"$file"

  # ✨ Write the tail only if it contains non-whitespace
  if [[ -n "$buf" && "$buf" =~ [^[:space:]] ]]; then
    ((chunk_idx++))
    local chunk="$tmpdir/chunk.$(printf "%06d" "$chunk_idx").cypher"
    printf "%s" "$buf" >"$chunk"
    echo "$chunk"
  fi

  rm -f "$normfile"
}

# inject a single chunk into Neo4j inside an explicit transaction
injchk() {
  local chunk_file="$1"

  # Skip empty/whitespace-only Chunks (e.g., created by chunk boundaries)
  if [[ ! -s "$chunk_file" ]] || ! grep -q '[^[:space:]]' "$chunk_file"; then
    log "🪵 Skipping empty/whitespace chunk: $(basename "$chunk_file")"
    return 0
  fi

  log "🚚 Executing chunk: $(basename "$chunk_file") (size: $(wc -c <"$chunk_file") bytes)"

  {
    printf ':begin\n'
    cat "$chunk_file"
    printf '\n:commit\n'
  } | cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" \
                   --database "$DBNAME" --format verbose --fail-fast \
                   --non-interactive 2>&1 | tee -a neoject.log

  local rc=${PIPESTATUS[1]}
  if [[ $rc -ne 0 ]]; then
    log "❌ Chunk failed (exit code $rc): $chunk_file"
    exit $EXIT_DB_IMPORT_FAILED
  fi
}

# inject mixed file (no chunking)
injmxf() {
  local file="$1"
  cypher-shell \
    -u "$USER" \
    -p "$PASSWORD" \
    -a "$ADDRESS" \
    -d "$DBNAME" \
    --format verbose \
    --fail-fast \
    -f "$file" 2>&1 | tee -a neoject.log

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    log "❌ Inject failed (exit code $rc)"
    exit $EXIT_DB_IMPORT_FAILED
  fi
}

# combine components for -g (chunked by default)
cmbcmp() {
  if [[ -n "$DDL_PRE" ]]; then
    log "📄 Executing DDL PRE"
    if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" <"$DDL_PRE"; then
      log "❌ DDL-PRE failed"
      exit $EXIT_DB_IMPORT_FAILED
    fi
  fi

  # Determine effective chunking parameters for -g
  local eff_stmts="$CHUNK_STMTS"
  local eff_bytes="$CHUNK_BYTES"
  local eff_delay="$BATCH_DELAY_MS"

  if [[ $eff_stmts -eq 0 && $eff_bytes -eq 0 ]]; then
    eff_stmts="$DEFAULT_G_CHUNK_STMTS"
    eff_bytes="$DEFAULT_G_CHUNK_BYTES"
    eff_delay="$DEFAULT_G_DELAY_MS"
  fi

  log "📦 Importing DML graph in chunks (stmts=${eff_stmts:-0}, bytes=${eff_bytes:-0}, delay=${eff_delay}ms)"
  local chunklist
  local chunkdir=""
  chunklist="$(chk "$GRAPH" "$eff_stmts" "$eff_bytes")"
  local n=0
  while read -r chunk; do
    [[ -z "$chunk" ]] && continue
    [[ -z "$chunkdir" ]] && chunkdir="$(dirname "$chunk")"
    ((n++))
    log "➡️  Chunk $n"
    injchk "$chunk"
    sleepFor "$eff_delay"
  done <<<"$chunklist"
  [[ -n "$chunkdir" ]] && rm -rf "$chunkdir"
  log "✅ DML graph imported in $n chunk(s)"

  if [[ -n "$DDL_POST" ]]; then
    log "📄 Executing DDL POST"
    if ! cypher-shell -u "$USER" -p "$PASSWORD" -a "$ADDRESS" --database "$DBNAME" <"$DDL_POST"; then
      log "❌ DDL-POST failed"
      exit $EXIT_DB_IMPORT_FAILED
    fi
  fi
}

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
      log "ℹ️  Database '$DBNAME' is back online."
      return 0
    fi
    log "⏳ Waiting for '$DBNAME' to come online (status='$status')… ($i/30)"
    sleep 1
  done

  log "❌ Timeout waiting for database to become available."
  exit $EXIT_DB_TIMEOUT
}

clsdb() {
  check_db_apocext

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

test_con() {
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

inject_modu() {
  [[ ! -s "$GRAPH" ]]                      && { log "❌ Graph file missing: $GRAPH"; exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_PRE" && ! -s "$DDL_PRE" ]]   && { log "❌ DDL pre missing";  exit $EXIT_CLI_FILE_UNREADABLE; }
  [[ -n "$DDL_POST" && ! -s "$DDL_POST" ]] && { log "❌ DDL post missing"; exit $EXIT_CLI_FILE_UNREADABLE; }

  check_cli_clsrst
  check_cli_stby
  check_db_version

  if [[ "$CLEAN_DB" == "true" ]]; then
    log "🧹 Cleaning database '$DBNAME' before injection…"
    clsdb
  fi

  if [[ "$RESET_DB" == "true" ]]; then
    log "⚠️  Resetting database '$DBNAME' before injection…"
    rstdb
  fi

  log "📥 Merging DDL pre, DML graph (chunked), and DDL post"
  cmbcmp
  log "✅ Merge complete"
  exit $EXIT_SUCCESS
}

inject_mono() {
  if [[ ! -s "$MIXED_FILE" ]]; then
    log "❌ Mixed file missing: $MIXED_FILE"
    exit $EXIT_CLI_FILE_UNREADABLE
  fi

  check_cli_clsrst
  check_cli_stby
  check_db_version

  if [[ "$CLEAN_DB" == "true" ]]; then
    log "🧹 Cleaning database '$DBNAME' before injection…"
    clsdb
  fi

  if [[ "$RESET_DB" == "true" ]]; then
    log "⚠️  Resetting database '$DBNAME' before injection…"
    rstdb
  fi

  if [[ "$CHUNKED" == "true" ]]; then
    # For -f with chunking, if user gave none, choose a conservative default
    local eff_stmts="$CHUNK_STMTS"
    local eff_bytes="$CHUNK_BYTES"

    if [[ $eff_stmts -eq 0 && $eff_bytes -eq 0 ]]; then
      eff_bytes="$(fsize "$MIXED_FILE")"
    fi

    log "📥 Injecting mixed file in chunks (stmts=${eff_stmts:-0}, bytes=${eff_bytes:-0}, delay=${BATCH_DELAY_MS}ms): $MIXED_FILE"
    local chunklist
    local chunkdir=""
    chunklist="$(chk "$MIXED_FILE" "$eff_stmts" "$eff_bytes")"

    local n=0
    while read -r chunk; do
      [[ -z "$chunk" ]] && continue
      [[ -z "$chunkdir" ]] && chunkdir="$(dirname "$chunk")"
      ((n++))
      log "➡️  Chunk $n"
      injchk "$chunk"
      sleepFor "$BATCH_DELAY_MS"
    done <<<"$chunklist"
    [[ -n "$chunkdir" ]] && rm -rf "$chunkdir"
    log "✅ Injection complete in $n chunk(s)"
  else
    log "📥 Injecting mixed Cypher via file: $MIXED_FILE"
    injmxf "$MIXED_FILE"
    log "✅ Injection complete"
  fi

  exit $EXIT_SUCCESS
}

clean_db() {
  log "🧹 Cleaning database '$DBNAME'…"
  check_db_version
  clsdb
  log "✅ Database cleaning completed"
  exit $EXIT_SUCCESS
}

reset_db() {
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
      echo "👉 Run 'neoject --help' for usage." >&2
      exit $EXIT_CLI_INVALID_GLOBAL_FLAG
      ;;
    *)
      echo "❌ Invalid sub-command: $1";
      echo "👉 Run 'neoject --help' for usage." >&2
      exit $EXIT_CLI_INVALID_SUBCOMMAND
      ;;
  esac
done

# Base validation
if [[ -z "$USER" || -z "$PASSWORD" || -z "$ADDRESS" ]]; then
  echo "❌ Missing required global options: -u <user>, -p <password> and -a <address> must all be provided" >&2
  echo "👉 Run 'neoject --help' for usage." >&2
  exit $EXIT_CLI_MISSING_BASE_PARAMS
fi

# Phase 2: subcommand-specific flags
case "$CMD" in
  test-con)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help) using test-con ;;
        --clean-db|--reset-db)
          echo "❌ test-con does not accept --clean-db/--reset-db" >&2
          exit $EXIT_CLI_INVALID_DDL_USAGE
          ;;
        -*)
          echo "❌ Invalid test-con flag: $1" >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_FLAG
          ;;
        *)
          echo "❌ Invalid test-con sub-command: $1" >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD
          ;;
      esac
    done
    ;;
  inject)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -g)            GRAPH="$2";               shift 2 ;;
        --ddl-pre)     DDL_PRE="$2";             shift 2 ;;
        --ddl-post)    DDL_POST="$2";            shift 2 ;;
        -f)            MIXED_FILE="$2";          shift 2 ;;
        --chunked)     CHUNKED=true;             shift   ;;
        --chunk-stmts) CHUNK_STMTS="${2:-0}";    shift 2 ;;
        --chunk-bytes) CHUNK_BYTES="${2:-0}";    shift 2 ;;
        --batch-delay) BATCH_DELAY_MS="${2:-0}"; shift 2 ;;
        --clean-db)    CLEAN_DB=true;            shift   ;;
        --reset-db)    RESET_DB=true;            shift   ;;
        -h|--help)     using inject                      ;;
        -*)
          echo "❌ Invalid inject flag: $1" >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_FLAG
          ;;
        *)
          echo "❌ Invalid inject sub-command: $1" >&2
          exit $EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD
          ;;
      esac
    done

    # Validate mutual exclusivity -g / -f
    if [[ -n "$GRAPH" && -n "$MIXED_FILE" ]]; then
      echo "❌ Options -g and -f are mutually exclusive" >&2
      exit $EXIT_CLI_USAGE
    fi
    if [[ -z "$GRAPH" && -z "$MIXED_FILE" ]]; then
      echo "❌ Either -g or -f must be provided" >&2
      exit $EXIT_CLI_USAGE
    fi
    # Validate --ddl-pre and --ddl-post only valid with -g
    if [[ -n "$MIXED_FILE" && ( -n "$DDL_PRE" || -n "$DDL_POST" ) ]]; then
      echo "❌ --ddl-pre and --ddl-post can only be used with -g <graph.cypher>" >&2
      exit $EXIT_CLI_USAGE
    fi

    # Chunking rules per mode
    if [[ -n "$GRAPH" ]]; then
      # -g: chunking always on; defaults apply if user didn't specify
      :
    else
      # -f: only valid if --chunked is set
      if [[ "$CHUNKED" != "true" && ( $CHUNK_STMTS -gt 0 || $CHUNK_BYTES -gt 0 || $BATCH_DELAY_MS -gt 0 ) ]]; then
        echo "❌ --chunk-stmts/--chunk-bytes/--batch-delay require --chunked in -f mode" >&2
        exit $EXIT_CLI_USAGE
      fi
    fi
    ;;
  clean-db)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help) using clean-db ;;
        *)
          echo "❌ clean-db takes no arguments" >&2
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
          echo "❌ reset-db takes no arguments" >&2
          exit $EXIT_CLI_USAGE
          ;;
      esac
    done
    ;;
  *)
    echo "❌ Missing sub-command" >&2
    echo "👉 Run 'neoject --help' for usage." >&2
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
    test_con
    ;;
  inject)
    [[ -n "$GRAPH" ]] && inject_modu
    [[ -n "$MIXED_FILE" ]] && inject_mono
    ;;
  clean-db)
    clean_db
    ;;
  reset-db)
    reset_db
    ;;
esac

