#!/usr/bin/env bats

load 'test_helper/bats-support' 2>/dev/null || true
load 'test_helper/bats-assert'  2>/dev/null || true

# -------------------------------------------------------------------
# Setup / Helpers
# -------------------------------------------------------------------

setup() {
  neoject=./src/neoject.sh
  user=neo4j
  pass=12345678
  db=neo4j
  neo4j_url=neo4j://localhost:7687

  mixed="./tst/data/well-formed/valid/mixed/living.cypher"
  grp="./tst/data/well-formed/valid/divided/living/living-grp.cql"
  ddl_pre="./tst/data/well-formed/valid/divided/living/living-pre.cql"
}

# Run a Cypher query and print the single scalar result (plain output)
cypher_val() {
  local q="$1"
  cypher-shell \
    -u "$user" -p "$pass" -a "$neo4j_url" -d "$db" \
    --format plain --non-interactive "$q" \
  | tail -n +2
}

# Assert label/rel counts: Person 2 City 2 LIVES_IN 2
assert_counts() {
  local label1="$1" exp1="$2"
  local label2="$3" exp2="$4"
  local reltype="$5" expr="$6"

  local c1; c1="$(cypher_val "MATCH (n:$label1) RETURN count(n) AS c")"
  local c2; c2="$(cypher_val "MATCH (n:$label2) RETURN count(n) AS c")"
  local cr; cr="$(cypher_val "MATCH ()-[r:$reltype]->() RETURN count(r) AS c")"

  [ "$c1" -eq "$exp1" ]
  [ "$c2" -eq "$exp2" ]
  [ "$cr" -eq "$expr" ]
}

# A tiny wrapper to run neoject with fixed globals
run_neoject() {
  run "$neoject" -u "$user" -p "$pass" -a "$neo4j_url" "$@"
}

# -------------------------------------------------------------------
# Smoke: connectivity
# -------------------------------------------------------------------

@test "[online] test-con succeeds against running DB" {
  run_neoject test-con
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connection OK"* ]]
}

# -------------------------------------------------------------------
# Monolithic (-f): baseline flows (reset/clean)
# -------------------------------------------------------------------

@test "[online/-f] monolithic import with --reset-db" {
  run_neoject inject --reset-db -f "$mixed"
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-f] monolithic import with --clean-db" {
  run_neoject inject --clean-db -f "$mixed"
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

# -------------------------------------------------------------------
# Modular (-g): baseline flows (reset) + quick sanity
# -------------------------------------------------------------------

@test "[online/-g] modular import (fun) with --reset-db" {
  run_neoject inject --reset-db -g "./tst/data/well-formed/valid/divided/fun/fun-grp.cql"
  [ "$status" -eq 0 ]
  local node_count; node_count="$(cypher_val 'MATCH (n) RETURN count(n) AS c')"
  [ "$node_count" -ge 2 ]
}

@test "[online/-g] modular import (living) with --reset-db + --ddl-pre" {
  run_neoject inject --reset-db --ddl-pre "$ddl_pre" -g "$grp"
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-g] modular import (living) with --clean-db + --ddl-pre" {
  run_neoject inject --clean-db --ddl-pre "$ddl_pre" -g "$grp"
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

# -------------------------------------------------------------------
# Admin commands: clean-db / reset-db
# -------------------------------------------------------------------

@test "[online] clean-db wipes graph contents" {
  # seed
  run_neoject inject --clean-db -f "$mixed"
  [ "$status" -eq 0 ]
  local seeded; seeded="$(cypher_val 'MATCH (n) RETURN count(n) AS c')"
  [ "$seeded" -gt 0 ]

  # clean
  run_neoject clean-db
  [ "$status" -eq 0 ]
  [[ "$output" == *"Database cleaning completed"* ]]
  local after; after="$(cypher_val 'MATCH (n) RETURN count(n) AS c')"
  [ "$after" -eq 0 ]
}

@test "[online] reset-db drops & recreates DB" {
  # seed
  run_neoject inject --reset-db -f "$mixed"
  [ "$status" -eq 0 ]
  local seeded; seeded="$(cypher_val 'MATCH (n) RETURN count(n) AS c')"
  [ "$seeded" -gt 0 ]

  # reset
  run_neoject reset-db
  [ "$status" -eq 0 ]
  [[ "$output" == *"Database reset completed"* ]]
  local after; after="$(cypher_val 'MATCH (n) RETURN count(n) AS c')"
  [ "$after" -eq 0 ]
}

# -------------------------------------------------------------------
# --------- -g Mode (Chunking always ON) ----------------------------
# -------------------------------------------------------------------

@test "[online/-g] --chunk-stmts 1 + --reset-db" {
  run_neoject inject --reset-db -g "$grp" --chunk-stmts 1
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-g] --chunk-bytes 64 (very small byte chunks)" {
  run_neoject inject --reset-db -g "$grp" --chunk-bytes 64
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-g] --chunk-stmts 2 + --batch-delay 5ms + --ddl-pre" {
  run_neoject inject --reset-db --ddl-pre "$ddl_pre" -g "$grp" --chunk-stmts 2 --batch-delay 5
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

# -------------------------------------------------------------------
# --------- -f Mode (Chunking optional) -----------------------------
# -------------------------------------------------------------------

@test "[online/-f] --chunked (no size args) → 1 chunk (whole file)" {
  run_neoject inject --reset-db -f "$mixed" --chunked
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-f] --chunked --chunk-stmts 1" {
  run_neoject inject --reset-db -f "$mixed" --chunked --chunk-stmts 1
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-f] --chunked --chunk-bytes 64" {
  run_neoject inject --reset-db -f "$mixed" --chunked --chunk-bytes 64
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

@test "[online/-f] --chunked --chunk-stmts 2 --batch-delay 5ms" {
  run_neoject inject --reset-db -f "$mixed" --chunked --chunk-stmts 2 --batch-delay 5
  [ "$status" -eq 0 ]
  assert_counts Person 2 City 2 LIVES_IN 2
}

