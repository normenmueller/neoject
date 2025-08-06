#!/usr/bin/env bats

# Set the test script path once
setup() {
  neoject=./src/neoject.sh
}

# --- CLI_INVALID_GLOBAL_FLAG=11

@test "[offline] fails with unknown global flag" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 --foo test-con
  [ "$status" -eq 11 ]
  [[ "$output" == *"Invalid global flag"* ]]
}

# --- CLI_MISSING_BASE_PARAMS=12

@test "[offline] fails with missing base params (missing -u)" {
  run $neoject -p secret -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "[offline] fails with missing base params (missing -p)" {
  run $neoject -u user -a neo4j://localhost:7687 test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

@test "[offline] fails with missing base params (missing -a)" {
  run $neoject -u user -p secret test-con
  [ "$status" -eq 12 ]
  [[ "$output" == *"Missing required global options"* ]]
}

# --- CLI_INVALID_SUBCOMMAND=13

@test "[offline] fails with invalid sub-command" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 foo
  [ "$status" -eq 13 ]
  [[ "$output" == *"Invalid sub-command"* ]]
}

# --- CLI_MISSING_SUBCOMMAND=14

@test "[offline] fails with missing or invalid sub-command (missing)" {
  run $neoject -u user -p secret -a neo4j://localhost:7687
  [ "$status" -eq 14 ]
  [[ "$output" == *"Missing sub-command"* ]]
}

# --- CLI_INVALID_DDL_USAGE=15

@test "[offline] fails with invalid ddl usage" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 test-con --reset-db --clean-db
  [ "$status" -eq 15 ]
  [[ "$output" == *"test-con does not accept --clean-db/--reset-db"* ]]
}

# --- EXIT_CLI_INVALID_SUBCOMMAND_FLAG=16

@test "[offline] fails with unknown test-con flag" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 test-con --foo
  [ "$status" -eq 16 ]
  [[ "$output" == *"Invalid test-con flag: --foo"* ]]
}

# --- EXIT_CLI_INVALID_SUBCOMMAND_SUBCMD=17

@test "[offline] fails with unknown test-con sub-command" {
  run $neoject -u user -p secret -a neo4j://localhost:7687 test-con foo
  [ "$status" -eq 17 ]
  [[ "$output" == *"Invalid test-con sub-command: foo"* ]]
}

# --- CLI_FILE_UNREADABLE=18

@test "[offline] fails with unreadable file (inject)" {
  run $neoject \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f ./tst/neo.ject
  [ "$status" -eq 18 ]
  [[ "$output" == *"Mixed file missing"* ]]
}

# --- CLI_USAGE=10

@test "[offline] fails with mutual exclusiveness of reset and clean (inject)" {
  setup_file="/tmp/neoject_test.cypher"
  echo "RETURN 1;" > "$setup_file"

  run $neoject \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f "$setup_file" \
    --reset-db --clean-db

  [ "$status" -eq 10 ]
  [[ "$output" == *"--reset-db and --clean-db are exclusive"* ]]
}

@test "[offline] fails with --ddl-pre used alongside -f" {
  dummy_file="/tmp/neoject_test.cypher"
  echo "RETURN 1;" > "$dummy_file"
  dummy_ddl="/tmp/neoject_pre.cypher"
  echo "CREATE CONSTRAINT dummy IF NOT EXISTS FOR (n:Dummy) REQUIRE n.id IS UNIQUE;" > "$dummy_ddl"

  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a bolt://localhost:7687 \
    inject -f "$dummy_file" --ddl-pre "$dummy_ddl"

  [ "$status" -eq 10 ]
  [[ "$output" == *"--ddl-pre and --ddl-post can only be used with -g <graph.cypher>"* ]]
}

@test "[offline] fails with --ddl-post used alongside -f" {
  dummy_file="/tmp/neoject_test.cypher"
  echo "RETURN 1;" > "$dummy_file"
  dummy_ddl="/tmp/neoject_post.cypher"
  echo "CREATE CONSTRAINT dummy IF NOT EXISTS FOR (n:Dummy) REQUIRE n.id IS UNIQUE;" > "$dummy_ddl"

  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a bolt://localhost:7687 \
    inject -f "$dummy_file" --ddl-post "$dummy_ddl"

  [ "$status" -eq 10 ]
  [[ "$output" == *"--ddl-pre and --ddl-post can only be used with -g <graph.cypher>"* ]]
}

# --- DB_CONNECTION_FAILED=100

@test "[offline] fails with db connection failed (fake bolt address)" {
  run $neoject -u neo4j -p 12345678 -a bolt://invalid test-con
  [ "$status" -eq 100 ]
  [[ "$output" == *"Connection failed"* ]]
}

