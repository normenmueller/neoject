#!/usr/bin/env bats

# Set the test script path once
setup() {
  neoject=./src/neoject.sh
}

# --- CLI_INVALID_GLOBAL_FLAG=11

@test "fails with unknown global flag" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 --foo test-con
  [ "$status" -eq 11 ]
  [[ "$output" == *"Invalid global flag"* ]]
}

# --- CLI_MISSING_BASE_PARAMS=12

@test "fails with missing base params (missing -u)" {
  run $neoject -p secret -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "fails with missing base params (missing -p)" {
  run $neoject -u user -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "fails with missing base params (missing -a)" {
  run $neoject -u user -p secret test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

# --- CLI_INVALID_SUBCOMMAND=13

@test "fails with invalid sub-command" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 foo
  [ "$status" -eq 13 ]
  [[ "$output" == *"Invalid sub-command"* ]]
}

# --- CLI_MISSING_SUBCOMMAND=14

@test "fails with missing or invalid sub-command (missing)" {
  run $neoject -u user -p secret -a neo4j://localhost:7687
  [ "$status" -eq 14 ]
  [[ "$output" == *"Missing sub-command"* ]]
}

# --- CLI_INVALID_DDL_USAGE=15

@test "fails with invalid ddl usage" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 test-con --reset-db --clean-db
  [ "$status" -eq 15 ]
  [[ "$output" == *"test-con does not accept --clean-db/--reset-db"* ]]
}

# --- EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD=16

@test "fails with unknown test-con flag" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 test-con foo
  [ "$status" -eq 16 ]
  [[ "$output" == *"Invalid test-con sub-command: foo"* ]]
}

# --- CLI_FILE_UNREADABLE=17

@test "fails with unreadable file (inject)" {
  run $neoject \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f ./tst/data/well-formed/valid/living.edge
  [ "$status" -eq 17 ]
  [[ "$output" == *"Mixed file missing"* ]]
}

# --- CLI_MUTUAL_EXCLUSIVE_CLEAN_RESET=18

@test "fails with mutual exclusiveness of reset and clean (inject)" {
  setup_file="/tmp/neoject_test.cypher"
  echo "RETURN 1;" > "$setup_file"

  run ./src/neoject.sh \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f "$setup_file" \
    --reset-db --clean-db

  [ "$status" -eq 18 ]
  [[ "$output" == *"--reset-db and --clean-db are exclusive"* ]]
}

# --- DB_CONNECTION_FAILED=100

@test "fails with db connection failed (fake bolt address)" {
  run $neoject -u neo4j -p 12345678 -a bolt://invalid test-con
  [ "$status" -eq 100 ]
  [[ "$output" == *"Connection failed"* ]]
}

# --- EXIT_SUCCESS=0

@test "succeeds with connection ok" {
  run $neoject -u neo4j -p 12345678 -a bolt://localhost:7687 test-con
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connection OK"* ]]
}

