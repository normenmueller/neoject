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

# --- CLI_MUTUAL_EXCLUSIVE_CLEAN_RESET=19

@test "[offline] fails with mutual exclusiveness of reset and clean (inject)" {
  setup_file="/tmp/neoject_test.cypher"
  echo "RETURN 1;" > "$setup_file"

  run ./src/neoject.sh \
    -u neo4j -p 12345678 -a neo4j://localhost:7687 \
    inject -f "$setup_file" \
    --reset-db --clean-db

  [ "$status" -eq 19 ]
  [[ "$output" == *"--reset-db and --clean-db are exclusive"* ]]
}

# --- DB_CONNECTION_FAILED=100

@test "[offline] fails with db connection failed (fake bolt address)" {
  run $neoject -u neo4j -p 12345678 -a bolt://invalid test-con
  [ "$status" -eq 100 ]
  [[ "$output" == *"Connection failed"* ]]
}

# --- EXIT_SUCCESS=0

@test "[online] succeeds with connection ok" {
  run $neoject -u neo4j -p 12345678 -a bolt://localhost:7687 test-con
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connection OK"* ]]
}

@test "[online] succeeds with injection complete (w/ --reset-db)" {
  # 1) inject
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --reset-db \
    -f "./tst/data/well-formed/valid/mixed/living.cypher"
  [ "$status" -eq 0 ]

  # 2) Person count must be 2
  person_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH (p:Person) RETURN count(p) AS c" \
    | tail -n +2 \
  )
  [ "$person_count" -eq 2 ]

  # 3) City count must be 2
  city_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH (c:City) RETURN count(c) AS c" \
    | tail -n +2 \
  )
  [ "$city_count" -eq 2 ]

  # 4) Relationship count must be 2
  rel_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH ()-[r:LIVES_IN]->() RETURN count(r) AS c" \
    | tail -n +2 \
  )
  [ "$rel_count" -eq 2 ]
}

@test "[online] succeeds with injection complete (w/ --clean-db)" {
  # 1) inject
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --clean-db \
    -f "./tst/data/well-formed/valid/mixed/living.cypher"
  [ "$status" -eq 0 ]

  # 2) Person count must be 2
  person_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH (p:Person) RETURN count(p) AS c" \
    | tail -n +2 \
  )
  [ "$person_count" -eq 2 ]

  # 3) City count must be 2
  city_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH (c:City) RETURN count(c) AS c" \
    | tail -n +2 \
  )
  [ "$city_count" -eq 2 ]

  # 4) Relationship count must be 2
  rel_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH ()-[r:LIVES_IN]->() RETURN count(r) AS c" \
    | tail -n +2 \
  )
  [ "$rel_count" -eq 2 ]
}

@test "[online] succeeds with combine complete (w/ --reset-db)" {
  # 1) combine
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    combine --reset-db \
    --ddl-pre "./tst/data/well-formed/valid/divided/living/living-pre.cql" \
    -g "./tst/data/well-formed/valid/divided/living/living-grp.cql"
  [ "$status" -eq 0 ]

  # 2) Person count must be 2
  person_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH (p:Person) RETURN count(p) AS c" \
    | tail -n +2 \
  )
  [ "$person_count" -eq 2 ]

  # 3) City count must be 2
  city_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH (c:City) RETURN count(c) AS c" \
    | tail -n +2 \
  )
  [ "$city_count" -eq 2 ]

  # 4) Relationship count must be 2
  rel_count=$( \
    cypher-shell \
      -u neo4j \
      -p 12345678 \
      -a neo4j://localhost:7687 \
      -d neo4j \
      --format plain \
      --non-interactive \
      "MATCH ()-[r:LIVES_IN]->() RETURN count(r) AS c" \
    | tail -n +2 \
  )
  [ "$rel_count" -eq 2 ]
}

