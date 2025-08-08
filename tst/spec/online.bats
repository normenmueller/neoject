#!/usr/bin/env bats

# Set the test script path once
setup() {
  neoject=./src/neoject.sh
}

# >>> ONLINE TESTS <<<
# --- EXIT_SUCCESS=0

@test "[online] succeeds with connection ok" {
  run $neoject -u neo4j -p 12345678 -a bolt://localhost:7687 test-con
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connection OK"* ]]
}

@test "[online] 'mixed/living.cypher' succeeds with monolithic injection w/ --reset-db" {
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

@test "[online] 'mixed/living.cypher' succeeds with monolithic injection w/ --clean-db" {
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

@test "[online] 'divided/fun/fun-grp.cql' succeeds with modular injection w/ --reset-db" {
  # 1) inject
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --reset-db \
    -g "./tst/data/well-formed/valid/divided/fun/fun-grp.cql"
  [ "$status" -eq 0 ]

  node_count=$(cypher-shell -u neo4j -p 12345678 -a neo4j://localhost:7687 -d neo4j --format plain --non-interactive "MATCH (n) RETURN count(n) AS c" | tail -n +2)
  [ "$node_count" -ge 2 ]
}

@test "[online] 'divided/living/living-*.cql' succeeds with modular injection w/ --reset-db" {
  # 1) inject
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --reset-db \
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

@test "[online] 'divided/living/living-*.cql' succeeds with modular injection w/ --clean-db" {
  # 1) inject
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --clean-db \
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

@test "[online] succeeds with clean-db" {
  # 1) Inject graph
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --clean-db \
    -f "./tst/data/well-formed/valid/mixed/living.cypher"
  [ "$status" -eq 0 ]

  # 2) Ensure we now have data
  node_count=$(cypher-shell -u neo4j -p 12345678 -a neo4j://localhost:7687 -d neo4j --format plain --non-interactive "MATCH (n) RETURN count(n) AS c" | tail -n +2)
  [ "$node_count" -gt 0 ]

  # 3) Run clean-db
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    clean-db
  [ "$status" -eq 0 ]
  [[ "$output" == *"Database cleaning completed"* ]]

  # 4) Ensure database is empty again
  node_count=$(cypher-shell -u neo4j -p 12345678 -a neo4j://localhost:7687 -d neo4j --format plain --non-interactive "MATCH (n) RETURN count(n) AS c" | tail -n +2)
  [ "$node_count" -eq 0 ]
}

@test "[online] succeeds with reset-db" {
  # 1) Inject graph
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    inject --reset-db \
    -f "./tst/data/well-formed/valid/mixed/living.cypher"
  [ "$status" -eq 0 ]

  # 2) Ensure we now have data
  node_count=$(cypher-shell -u neo4j -p 12345678 -a neo4j://localhost:7687 -d neo4j --format plain --non-interactive "MATCH (n) RETURN count(n) AS c" | tail -n +2)
  [ "$node_count" -gt 0 ]

  # 3) Run reset-db
  run $neoject \
    -u neo4j \
    -p 12345678 \
    -a neo4j://localhost:7687 \
    reset-db
  [ "$status" -eq 0 ]
  [[ "$output" == *"Database reset completed"* ]]

  # 4) Ensure database is empty again
  node_count=$(cypher-shell -u neo4j -p 12345678 -a neo4j://localhost:7687 -d neo4j --format plain --non-interactive "MATCH (n) RETURN count(n) AS c" | tail -n +2)
  [ "$node_count" -eq 0 ]
}

