#!/usr/bin/env bats

# Set the test script path once
setup() {
  neoject=./src/neoject.sh
}

# --- FILE_UNREADABLE=10

@test "fails with unreadable file" {
  run $neoject -u neo4j -p 12345678 -a neo4j://localhost:7687 apply -f ./tst/data/well-formed/valid/living.edge --import-dir /Users/normenmueller/Library/Application\ Support/neo4j-desktop/Application/Data/dbmss/dbms-823a39e0-cb6c-4dc4-a405-d2470a605346/import/
  [ "$status" -eq 7 ]
  [[ "$output" == *"Mixed file unreadable"* ]]
}

# --- MISSING_SUBCOMMAND=2

@test "rejects missing subcommand" {
  run $neoject
  [ "$status" -eq 2 ]
  [[ "$output" == *"Missing subcommand"* ]]
}

# --- INVALID_SUBCOMMAND=3

@test "rejects unknown subcommand" {
  run $neoject foo
  [ "$status" -eq 3 ]
  [[ "$output" == *"Unknown subcommand"* ]]
}

# --- MISSING_BASE_PARAMS=4

@test "fails without any base params" {
  run $neoject test-con
  [ "$status" -eq 4 ]
  [[ "$output" == *"Usage"* ]]
}

@test "fails with only user" {
  run $neoject -u neo4j test-con
  [ "$status" -eq 4 ]
  [[ "$output" == *"Usage"* ]]
}

@test "fails with user and password only" {
  run $neoject -u neo4j -p 12345678 test-con
  [ "$status" -eq 4 ]
  [[ "$output" == *"Usage"* ]]
}

# --- CONNECTION_FAILED=5

@test "succeeds with all base params (fake bold address)" {
  run $neoject -u neo4j -p 12345678 -a bolt://invalid test-con
  [ "$status" -eq 5 ]  # connection failure
  [[ "$output" == *"Connection failed"* ]]
}

@test "succeeds with all base params (fake neo4j address)" {
  run $neoject -u neo4j -p 12345678 -a neo4j://invalid test-con
  [ "$status" -eq 5 ]  # connection failure
  [[ "$output" == *"Connection failed"* ]]
}

# --- MUTUAL_EXCLUSIVE_CLEAN_RESET=11

@test "fails with mutual exclusiveness of reset and clean" {
  setup_file="/tmp/neoject_test.cypher"
  echo "RETURN 1;" > "$setup_file"

  run ./src/neoject.sh -u neo4j -p 12345678 -a neo4j://localhost:7687 apply -f "$setup_file" --reset-db --clean-db

  [ "$status" -eq 11 ]
  [[ "$output" == *"--reset-db and --clean-db are exclusive"* ]]
}

