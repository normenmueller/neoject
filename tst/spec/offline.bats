#!/usr/bin/env bats

load 'test_helper/bats-support' 2>/dev/null || true
load 'test_helper/bats-assert'  2>/dev/null || true

# Set the test script path once
setup() {
  tmpfiles=()
  neoject=./src/neoject.sh
}

teardown() {
  for f in "${tmpfiles[@]:-}"; do
    [ -e "$f" ] && rm -f "$f"
  done
}

# Helper to create a tiny temp cypher file and track it
mk_tmp_cypher() {
  local f
  f="$(mktemp /tmp/neoject-offline.XXXXXX.cypher)"
  printf 'RETURN 1;\n' > "$f"
  tmpfiles+=("$f")
  echo "$f"
}

# --- CLI_USAGE=10

@test "[offline] fails with mutual exclusiveness of reset and clean (inject)" {
  local setup_file; setup_file="$(mk_tmp_cypher)"

  run "$neoject" \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f "$setup_file" \
    --reset-db --clean-db

  [ "$status" -eq 10 ]
  [[ "$output" == *"--reset-db and --clean-db are exclusive"* ]]
}

@test "[offline] fails with --ddl-pre used alongside -f" {
  local dummy_file; dummy_file="$(mk_tmp_cypher)"
  local dummy_ddl;  dummy_ddl="$(mk_tmp_cypher)"
  echo "CREATE CONSTRAINT dummy IF NOT EXISTS FOR (n:Dummy) REQUIRE n.id IS UNIQUE;" > "$dummy_ddl"

  run "$neoject" \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject -f "$dummy_file" --ddl-pre "$dummy_ddl"

  [ "$status" -eq 10 ]
  [[ "$output" == *"--ddl-pre and --ddl-post can only be used with -g <graph.cypher>"* ]]
}

@test "[offline] fails with --ddl-post used alongside -f" {
  local dummy_file; dummy_file="$(mk_tmp_cypher)"
  local dummy_ddl;  dummy_ddl="$(mk_tmp_cypher)"
  echo "CREATE CONSTRAINT dummy IF NOT EXISTS FOR (n:Dummy) REQUIRE n.id IS UNIQUE;" > "$dummy_ddl"

  run "$neoject" \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject -f "$dummy_file" --ddl-post "$dummy_ddl"

  [ "$status" -eq 10 ]
  [[ "$output" == *"--ddl-pre and --ddl-post can only be used with -g <graph.cypher>"* ]]
}

# --chunk-stmts and --chunk-bytes are mutually exclusive (-g)
@test "[offline] -g fails when --chunk-stmts and --chunk-bytes are both set" {
  local gfile; gfile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -g "$gfile" --chunk-stmts 10 --chunk-bytes 1024
  [ "$status" -eq 10 ]
  [[ "$output" == *"--chunk-stmts and --chunk-bytes are mutually exclusive"* ]]
}

# --chunk-stmts and --chunk-bytes are mutually exclusive (-f with --chunked)
@test "[offline] -f fails when --chunk-stmts and --chunk-bytes are both set (with --chunked)" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -f "$ffile" --chunked --chunk-stmts 10 --chunk-bytes 1024
  [ "$status" -eq 10 ]
  [[ "$output" == *"--chunk-stmts and --chunk-bytes are mutually exclusive"* ]]
}

# -f: chunk flags without --chunked → error
@test "[offline] -f fails when --chunk-stmts is used without --chunked" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -f "$ffile" --chunk-stmts 10
  [ "$status" -eq 10 ]
  [[ "$output" == *"require --chunked in -f mode"* ]]
}

@test "[offline] -f fails when --chunk-bytes is used without --chunked" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -f "$ffile" --chunk-bytes 256
  [ "$status" -eq 10 ]
  [[ "$output" == *"require --chunked in -f mode"* ]]
}

@test "[offline] -f fails when --batch-delay is used without --chunked" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -f "$ffile" --batch-delay 5
  [ "$status" -eq 10 ]
  [[ "$output" == *"require --chunked in -f mode"* ]]
}

# -g and -f at the same time → error
@test "[offline] fails when -g and -f are both provided" {
  local gfile; gfile="$(mk_tmp_cypher)"
  local ffile; ffile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -g "$gfile" -f "$ffile"
  [ "$status" -eq 10 ]
  [[ "$output" == *"-g and -f are mutually exclusive"* ]]
}

# neither -g nor -f → error
@test "[offline] fails when neither -g nor -f is provided" {
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject
  [ "$status" -eq 10 ]
  [[ "$output" == *"Either -g or -f must be provided"* ]]
}

# --- CLI_INVALID_GLOBAL_FLAG=11

@test "[offline] fails with unknown global flag" {
  run "$neoject" -u user -p secret -a neo4j://localhost:7687 --foo test-con
  [ "$status" -eq 11 ]
  [[ "$output" == *"Invalid global flag"* ]]
}

# --- CLI_MISSING_BASE_PARAMS=12

@test "[offline] fails with missing base params (missing -u)" {
  run "$neoject" -p secret -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "[offline] fails with missing base params (missing -p)" {
  run "$neoject" -u user -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "[offline] fails with missing base params (missing -a)" {
  run "$neoject" -u user -p secret test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

# --- CLI_INVALID_SUBCOMMAND=13

@test "[offline] fails with invalid sub-command" {
  run "$neoject" -u user -p secret -a neo4j://localhost:7687 foo
  [ "$status" -eq 13 ]
  [[ "$output" == *"Invalid sub-command"* ]]
}

# --- CLI_MISSING_SUBCOMMAND=14

@test "[offline] fails with missing or invalid sub-command (missing)" {
  run "$neoject" -u user -p secret -a neo4j://localhost:7687
  [ "$status" -eq 14 ]
  [[ "$output" == *"Missing sub-command"* ]]
}

# --- CLI_INVALID_DDL_USAGE=15

@test "[offline] fails with invalid ddl usage" {
  run "$neoject" -u user -p secret -a neo4j://localhost:7687 test-con --reset-db --clean-db
  [ "$status" -eq 15 ]
  [[ "$output" == *"test-con does not accept --clean-db/--reset-db"* ]]
}

# --- EXIT_CLI_INVALID_SUBCOMMAND_FLAG=16

@test "[offline] fails with unknown test-con flag" {
  run "$neoject" -u user -p secret -a neo4j://localhost:7687 test-con --foo
  [ "$status" -eq 16 ]
  [[ "$output" == *"Invalid test-con flag: --foo"* ]]
}

@test "[offline] fails with unknown inject flag" {
  local ffile; ffile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -f "$ffile" --nope
  [ "$status" -eq 16 ]
  [[ "$output" == *"Invalid inject flag: --nope"* ]]
}

# --- EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD=17

@test "[offline] fails with unknown test-con sub-command" {
  run "$neoject" -u user -p secret -a neo4j://localhost:7687 test-con foo
  [ "$status" -eq 17 ]
  [[ "$output" == *"Invalid test-con sub-command: foo"* ]]
}

# --- CLI_FILE_UNREADABLE=18

@test "[offline] fails with unreadable file (inject)" {
  run "$neoject" \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f ./tst/neo.ject
  [ "$status" -eq 18 ]
  [[ "$output" == *"Mixed file missing"* ]]
}

# --ddl-pre / --ddl-post missing with -g → file unreadable
@test "[offline] -g fails when --ddl-pre file is missing" {
  local gfile; gfile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -g "$gfile" --ddl-pre /tmp/does-not-exist.cypher
  [ "$status" -eq 18 ]
  [[ "$output" == *"DDL pre missing"* ]]
}

@test "[offline] -g fails when --ddl-post file is missing" {
  local gfile; gfile="$(mk_tmp_cypher)"
  run "$neoject" -u u -p p -a neo4j://localhost:7687 inject -g "$gfile" --ddl-post /tmp/does-not-exist.cypher
  [ "$status" -eq 18 ]
  [[ "$output" == *"DDL post missing"* ]]
}

# --- DB_CONNECTION_FAILED=100

@test "[offline] fails with db connection failed (fake bolt address)" {
  run "$neoject" -u neo4j -p 12345678 -a neo4j://invalid test-con
  [ "$status" -eq 100 ]
  [[ "$output" == *"Connection failed"* ]]
}
