#!/usr/bin/env bats

# bats-support
if [ -f test_helper/bats-support/load.bash ]; then
  load 'test_helper/bats-support/load'
fi
# bats-assert
if [ -f test_helper/bats-assert/load.bash ]; then
  load 'test_helper/bats-assert/load'
fi

# -------------------------------------------------------------------
# Setup / Teardown / Helpers
# -------------------------------------------------------------------
setup() {
  tmpfiles=()
  neoject=./src/neoject.sh

  user="u"
  pass="p"
  neo4j_url="neo4j://invalid:7687"
}

teardown() {
  if [ "${#tmpfiles[@]}" -gt 0 ]; then
    for f in "${tmpfiles[@]}"; do
      [ -n "$f" ] && [ -e "$f" ] && rm -f "$f"
    done
  fi
}

mk_tmp_cypher() {
  local f
  if mktemp --version >/dev/null 2>&1; then
    # GNU mktemp: suffix allowed
    f="$(mktemp /tmp/neoject-offline.XXXXXX.cypher)"
  else
    # BSD mktemp (macOS): use -t and no suffix
    f="$(mktemp -t neoject-offline.XXXXXX)"
  fi
  printf 'RETURN 1;\n' > "$f"
  tmpfiles+=("$f")
  echo "$f"
}

# Neoject mit fixen "global" Parametern starten
run_neoject() {
  run "$neoject" -u "$user" -p "$pass" -a "$neo4j_url" "$@"
}

# -------------------------------------------------------------------
# CLI_USAGE=10
# -------------------------------------------------------------------

@test "[offline] inject: --reset-db and --clean-db are exclusive" {
  local setup_file; setup_file="$(mk_tmp_cypher)"
  run_neoject inject -f "$setup_file" --reset-db --clean-db
  [ "$status" -eq 10 ]
  [[ "$output" == *"--reset-db and --clean-db are exclusive"* ]]
}

@test "[offline] -f denied --ddl-pre" {
  local dummy_file; dummy_file="$(mk_tmp_cypher)"
  local dummy_ddl;  dummy_ddl="$(mk_tmp_cypher)"
  echo "CREATE CONSTRAINT dummy IF NOT EXISTS FOR (n:Dummy) REQUIRE n.id IS UNIQUE;" > "$dummy_ddl"
  run_neoject inject -f "$dummy_file" --ddl-pre "$dummy_ddl"
  [ "$status" -eq 10 ]
  [[ "$output" == *"--ddl-pre and --ddl-post can only be used with -g <graph.cypher>"* ]]
}

@test "[offline] -f denied --ddl-post" {
  local dummy_file; dummy_file="$(mk_tmp_cypher)"
  local dummy_ddl;  dummy_ddl="$(mk_tmp_cypher)"
  echo "CREATE CONSTRAINT dummy IF NOT EXISTS FOR (n:Dummy) REQUIRE n.id IS UNIQUE;" > "$dummy_ddl"
  run_neoject inject -f "$dummy_file" --ddl-post "$dummy_ddl"
  [ "$status" -eq 10 ]
  [[ "$output" == *"--ddl-pre and --ddl-post can only be used with -g <graph.cypher>"* ]]
}

@test "[offline] -g: --chunk-stmts and --chunk-bytes are exclusive" {
  local gfile; gfile="$(mk_tmp_cypher)"
  run_neoject inject -g "$gfile" --chunk-stmts 10 --chunk-bytes 1024
  [ "$status" -eq 10 ]
  [[ "$output" == *"--chunk-stmts and --chunk-bytes are mutually exclusive"* ]]
}

@test "[offline] -f(--chunked): --chunk-stmts and --chunk-bytes are exclusive" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run_neoject inject -f "$ffile" --chunked --chunk-stmts 10 --chunk-bytes 1024
  [ "$status" -eq 10 ]
  [[ "$output" == *"--chunk-stmts and --chunk-bytes are mutually exclusive"* ]]
}

@test "[offline] -f: --chunk-stmts without --chunked → Error" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run_neoject inject -f "$ffile" --chunk-stmts 10
  [ "$status" -eq 10 ]
  [[ "$output" == *"require --chunked in -f mode"* ]]
}

@test "[offline] -f: --chunk-bytes without --chunked → Error" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run_neoject inject -f "$ffile" --chunk-bytes 256
  [ "$status" -eq 10 ]
  [[ "$output" == *"require --chunked in -f mode"* ]]
}

@test "[offline] -f: --batch-delay without --chunked → Error" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run_neoject inject -f "$ffile" --batch-delay 5
  [ "$status" -eq 10 ]
  [[ "$output" == *"require --chunked in -f mode"* ]]
}

@test "[offline] -g and -f simultaneously → Error" {
  local gfile; gfile="$(mk_tmp_cypher)"
  local ffile; ffile="$(mk_tmp_cypher)"
  run_neoject inject -g "$gfile" -f "$ffile"
  [ "$status" -eq 10 ]
  [[ "$output" == *"-g and -f are mutually exclusive"* ]]
}

@test "[offline] neither -g nor -f specified → Error" {
  run_neoject inject
  [ "$status" -eq 10 ]
  [[ "$output" == *"Either -g or -f must be provided"* ]]
}

# -------------------------------------------------------------------
# CLI_INVALID_GLOBAL_FLAG=11
# -------------------------------------------------------------------

@test "[offline] unknown global option" {
  run_neoject --foo test-con
  [ "$status" -eq 11 ]
  [[ "$output" == *"Invalid global flag"* ]]
}

# -------------------------------------------------------------------
# CLI_MISSING_BASE_PARAMS=12
# -------------------------------------------------------------------

@test "[offline] missing basic parameters (-u missing)" {
  run "$neoject" -p secret -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "[offline] missing basic parameters (-p missing)" {
  run "$neoject" -u user -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "[offline] missing basic parameters (-a missing)" {
  run "$neoject" -u user -p secret test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

# -------------------------------------------------------------------
# CLI_INVALID_SUBCOMMAND=13
# -------------------------------------------------------------------

@test "[offline] invalid sub-command" {
  run_neoject foo
  [ "$status" -eq 13 ]
  [[ "$output" == *"Invalid sub-command"* ]]
}

# -------------------------------------------------------------------
# CLI_MISSING_SUBCOMMAND=14
# -------------------------------------------------------------------

@test "[offline] missing sub-command" {
  run_neoject
  [ "$status" -eq 14 ]
  [[ "$output" == *"Missing sub-command"* ]]
}

# -------------------------------------------------------------------
# CLI_INVALID_DDL_USAGE=15
# -------------------------------------------------------------------

@test "[offline] test-con does not accept --clean/--reset flags" {
  run_neoject test-con --reset-db --clean-db
  [ "$status" -eq 15 ]
  [[ "$output" == *"test-con does not accept --clean-db/--reset-db"* ]]
}

# -------------------------------------------------------------------
# EXIT_CLI_INVALID_SUBCOMMAND_FLAG=16
# -------------------------------------------------------------------

@test "[offline] invalid test-con flag" {
  run_neoject test-con --foo
  [ "$status" -eq 16 ]
  [[ "$output" == *"Invalid test-con flag: --foo"* ]]
}

@test "[offline] invalid inject flag" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run_neoject inject -f "$ffile" --nope
  [ "$status" -eq 16 ]
  [[ "$output" == *"Invalid inject flag: --nope"* ]]
}

# -------------------------------------------------------------------
# EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD=17
# -------------------------------------------------------------------

@test "[offline] invalid test-con sub-command" {
  run_neoject test-con foo
  [ "$status" -eq 17 ]
  [[ "$output" == *"Invalid test-con sub-command: foo"* ]]
}

# -------------------------------------------------------------------
# CLI_FILE_UNREADABLE=18
# -------------------------------------------------------------------

@test "[offline] -f with missing file → Error" {
  run_neoject inject -f ./tst/neo.ject
  [ "$status" -eq 18 ]
  [[ "$output" == *"Mixed file missing"* ]]
}

@test "[offline] -g: --ddl-pre file missing" {
  local gfile; gfile="$(mk_tmp_cypher)"
  run_neoject inject -g "$gfile" --ddl-pre /tmp/does-not-exist.cypher
  [ "$status" -eq 18 ]
  [[ "$output" == *"DDL pre missing"* ]]
}

@test "[offline] -g: --ddl-post file missing" {
  local gfile; gfile="$(mk_tmp_cypher)"
  run_neoject inject -g "$gfile" --ddl-post /tmp/does-not-exist.cypher
  [ "$status" -eq 18 ]
  [[ "$output" == *"DDL post missing"* ]]
}

# -------------------------------------------------------------------
# DB_CONNECTION_FAILED=100
# -------------------------------------------------------------------

@test "[offline] test-con against fake host → connection failed" {
  # Overwrite URL to encounter the intended error message
  neo4j_url=neo4j://invalid
  run_neoject test-con
  [ "$status" -eq 100 ]
  [[ "$output" == *"Connection failed"* ]]
}

