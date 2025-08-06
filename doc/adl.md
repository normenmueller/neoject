---
title: Architecture Decision Log
...

# ADR-001: Use shell script with `cypher-shell` for data import
<a name="adr-wrp-cshl"></a>

## Status

Accepted

## Context

To import `.cypher` files into Neo4j, multiple technical options were considered:

- `cypher-shell` (official Neo4j CLI)
- CSV + `LOAD CSV`
- APOC imports
- REST/HTTP APIs
- Custom clients (e.g., Haskell, Python, JavaScript)

Additionally, the orchestration could have been done via:

- Bash shell script
- Haskell CLI
- Python script
- Makefile automation

## Decision

We use a shell script wrapper (`neoject`) that invokes the officially supported `cypher-shell` command-line client.

## Rationale

- `cypher-shell` is **officially maintained**, **cross-platform**, and battle-tested
- Shell scripts are **widely available**, **zero-dependency**, and **CI-friendly**
- Easy to invoke from Makefiles, CI/CD pipelines or manually
- Full **transaction support** with precise error propagation
- Ideal for small-scale orchestration and first functional prototypes
- Simple to migrate to more structured tooling in the future

> This is the **most pragmatic and robust approach** for early-stage data import pipelines.

## Consequences

- No need for external dependencies (e.g., Python, Haskell, etc.)
- Passwords are passed via command-line args (→ can be hardened later)
- Error handling is delegated to `cypher-shell`
- Logging and testability are limited compared to fully typed languages

## Alternatives Considered

- ✅ **Why Bash works well for now**:

  | Argument                         | Justification                                                   |
  |--------------------------------- | --------------------------------------------------------------- |
  | Near the OS                      | Directly invokes `cypher-shell`, manipulates files, uses pipes  |
  | Fast & portable                  | No interpreter or runtime needed beyond Bash                    |
  | Simple data model                | No need for complex in-memory structures                        |
  | DevOps-friendly                  | Shell scripts are easy to distribute and CI-integrate           |

- 🛑 **Why Bash will eventually hit limits**:

  | Problem                          | Symptoms                                                 |
  |--------------------------------- | -------------------------------------------------------- |
  | Complex CLI flags & validation   | Nested, typed, or interdependent options become painful  |
  | Poor error handling              | Weak typing of exit codes, hard to mock or unit-test     |
  | Debugging/logging limitations    | No structured logs, poor traceability                    |
  | Growing maintenance burden       | Refactors get risky, readability suffers at >500 LOC     |

- 🔄 **Migration paths & options**:

  | Option                              | When to switch |
  |-------------------------------------|----------------------------------------------------- |
  | 🐍 Python + `argparse`              | When config parsing, retry logic, or file I/O grows  |
  | 🦀 Rust (`clap`)                    | When performance or static analysis becomes critical |
  | 🔤 Haskell (`optparse-applicative`) | When you want type-safe pipelines with rich CLI UX   |

## Future Considerations

- Introduce a Haskell CLI once the complexity grows
- Add `.env` support or interactive password input
- Refactor the logic into modular, testable units

# ADR-002: neoject owns transaction boundaries in modular DML mode
<a name="adr-own-trx"></a>

## Status

Accepted

## Context

Graph input files provided to `neoject` via `-g` are intended to be **declarative** and must **not** contain transaction statements such as `BEGIN`, `COMMIT`, or `ROLLBACK`.

These files define only the **DML** layer of the graph, i.e.:

- Node and relationship creation (`CREATE`, `MERGE`)
- Property assignments (`SET`)
- Pattern-based modifications (`MATCH`, `UNWIND`)
- No schema, no side-effects, no procedural logic

However, `cypher-shell` by default executes one statement at a time — meaning variable bindings and scoped graph construction will fail silently without transactional boundaries.

## Decision

`neoject` takes full responsibility for **wrapping modular graph files** in an explicit transaction block (`:begin` ... `:commit`) before feeding them to `cypher-shell`.

This applies **only** in modular mode (`-g`). In monolithic mode (`-f`), the file is considered fully specified and no automatic wrapping occurs.

## Rationale

- Prevents **loss of variable scope**
- Guarantees **atomic graph construction**
- Encourages **clean, declarative DML** files
- Delegates transaction orchestration to the runtime (`neoject`)

## Technical Justification

By design:

- `cypher-shell` executes input statements independently unless wrapped
- Variables like `(p)` or `(c)` created in one line are not retained in the next
- Wrapping is required for correct multi-statement DML logic

**Bad Example (fails silently):**

```cypher
CREATE (p:Person {name: 'Alice'});
CREATE (c:City {name: 'Paris'});
CREATE (p)-[:LIVES_IN]->(c);
```

**Correct Execution:**

```cypher
:begin
CREATE (p:Person {name: 'Alice'});
CREATE (c:City {name: 'Paris'});
CREATE (p)-[:LIVES_IN]->(c);
:commit
```

XXX Re-assess

## Consequences

- Users must **not** include transaction markers in `-g` files
- The modular `inject -g` logic will always wrap the input
- Mixed files (`-f`) are treated as-is (e.g., for DDL + DML together)

## Alternatives Considered

- Requiring users to write their own `:begin`/`:commit` markers (too error-prone)
- Allowing unwrapped execution (risk of broken variable bindings)

## Future Considerations

- A `--raw` mode could bypass transaction wrapping for advanced use cases
- See ADR-003 for how the wrapping is applied structurally

# ADR-003: Execute modular DML graph in one atomic transaction
<a name="adr-sgl-trx"></a>

## Status

Accepted

## Context

Modular graph imports (`inject -g`) allow splitting a Cypher specification into:

- DDL pre-statements (`--ddl-pre`)
- Core DML graph (`-g`)
- DDL post-statements (`--ddl-post`)

For correctness and safety, **neoject executes the DML section as one single transaction**.

This is **not** applied in monolithic mode (`-f`), which executes as-is without wrapping.

## Decision

The core graph section (`-g`) is **wrapped in a single transaction block** before execution:

```cypher
:begin
... contents of graph.cypher ...
:commit
```

This transaction is piped directly into `cypher-shell`.

## Rationale

- Avoids **partial writes** on failure
- Preserves **variable bindings**
- Makes DML graph application **atomic, deterministic, and CI-safe**

## Technical Justification

- Neo4j guarantees **ACID behavior** for wrapped transactions
- A failed Cypher line will rollback the entire block
- DML-only files are often multi-statement and require execution as a unit

## Consequences

- `neoject` reads and wraps the DML input
- All graph logic must be syntactically and semantically valid as a whole
- Partial application of a broken graph is prevented

## Alternatives Considered

- Streaming statements line by line (rejected: too fragile)
- Wrapping each line (rejected: breaks variable scope)
- Requiring pre-wrapped files (rejected: burdens the user)

## Future Considerations

- **Batching** very large DML inputs (e.g., N statements per transaction)
- **Chunked execution** to avoid memory/timeouts
- Consider using `LOAD CSV` or `neo4j-admin import` for massive datasets

