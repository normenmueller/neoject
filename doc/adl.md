---
title: Architecture Decision Log (ADL)
version: 0.1.4
...

# Overview

This ADL documents major design decisions for the `neoject` data import CLI tool. Neoject wraps Cypher-based graph data manipulations into structured execution pipelines and distinguishes **modular** (`-g`) from **monolithic** (`-f`) modes.

## Modes Summary

| Mode           | Command-line Flag | Input File(s)        | Transaction Wrapping | Intended Content       |
| -------------- | ----------------- | -------------------- | -------------------- | ---------------------- |
| **Modular**    | `-g`              | DML (+ optional DDL) | ✅ (DML only)        | Pure DML (graph logic) |
| **Monolithic** | `-f`              | Mixed DDL + DML      | ❌                   | Fully specified import |

## Allowed Statements by File Type

| File Type         | Cypher Statements Allowed                                     | Notes                                     |
| ----------------- | ------------------------------------------------------------- | ----------------------------------------- |
| `--ddl-pre/post`  | `CREATE CONSTRAINT`, `DROP INDEX`, etc.                       | DDL only; read/write discouraged          |
| `-g` (graph)      | `CREATE`, `MERGE`, `MATCH`, `UNWIND`, `SET`, `WITH`, `DELETE` | DML only; no DDL or transactions allowed  |
| `-f` (monolithic) | Any valid Cypher (DDL + DML + transactions)                   | Treated as-is                             |

📌 *See also: [Neo4j Cypher Cheat Sheet](https://neo4j.com/docs/cypher-cheat-sheet/5/all/)*

- **DML** = Read, Write, Procedure, etc.
- **DDL** = Schema, Performance, Administration blocks

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

Additionally, orchestration could have been done via:

- Bash shell script
- Haskell CLI
- Python script
- Makefile automation

## Decision

We use a Bash shell script (`neoject`) that invokes the officially supported `cypher-shell` command-line client.

## Rationale

- `cypher-shell` is officially maintained and cross-platform
- Bash is widely available, zero-dependency, and CI-friendly
- Easy integration into Makefiles, pipelines, or manual runs
- No external dependencies (e.g., Python, Haskell)

## Consequences

- Fast setup and simple distribution
- Passwords passed via CLI (→ can be hardened later)
- Error handling delegated to `cypher-shell`
- Script complexity may grow over time

## Alternatives Considered

- ✅ **Why Bash works now**:

  | Reason                    | Justification                                       |
  | ------------------------- | --------------------------------------------------- |
  | OS proximity              | Can invoke binaries, manage files and logs easily   |
  | Lightweight               | No virtualenvs or builds required                   |
  | Minimal data modeling     | No complex in-memory objects needed                 |
  | DevOps-native             | Familiar to infra/CI engineers                      |

- 🛑 **Why Bash may fail later**:

  | Limitation               | Symptoms                               |
  | ------------------------ | -------------------------------------- |
  | CLI parsing complexity   | Option validation becomes brittle      |
  | No structured logging    | Difficult to trace or log with levels  |
  | Hard to unit-test        | No dependency injection or mocks       |
  | Fragile error handling   | Exit code reliance without granularity |

- 🔄 **Migration paths**:

  | Language  | When to switch                                         |
  | --------- | ------------------------------------------------------ |
  | Python    | Rich CLI and data handling needed                      |
  | Rust      | Performance and static typing required                 |
  | Haskell   | Full type-safe orchestration and declarative pipelines |

## Future Considerations

- Migrate to Python or Haskell as complexity grows
- Extract reusable modules for schema or logging
- Support `.env` or password prompts for better security

# ADR-002: neoject owns transaction boundaries in modular mode
<a name="adr-own-trx"></a>

## Status

Accepted

## Context

Graph DML files (`-g`) **must** contain only **declarative, transaction-free** Cypher statements:

- No Cypher shell statements (e.g., `:begin`, `:commit`, `:rollback`)
- No DDL statements (e.g., `CREATE CONSTRAINT`, `DROP INDEX`)

These files are treated as graph data manipulations only. Transactional orchestration is the responsibility of the runtime (`neoject`).

## Decision

Neoject **automatically wraps graph DML files** in an explicit transaction:

```cypher
:begin
<contents of -g file>
:commit
```

> 🚨 _Clarification_: `:begin`/`:commit` do **not** affect Cypher variable scoping. They **only** guarantee atomicity. Variables like `f` or `b` are still scoped **per statement**, unless explicitly passed via `WITH`.

This happens only in `inject -g`. Monolithic mode (`inject -f`) bypasses this behavior.

## Rationale

- Prevents partial writes on failure
- Ensures atomic graph import
- Encourages clean, modular DML separation
- Avoids fragile manual transaction markup

## Technical Justification

Even if a graph DML file contains 10+ statements, Neo4j will apply them **one-by-one** unless wrapped. A single syntax error mid-file would otherwise result in partial application.

XXX Was heißt "unless wrapped"? Ich denke `:begin` o.ä. ist in `inject -g` nicht erlaubt. Das verwirrt mich jetzt :-/

Wrapping via `:begin ... :commit` ensures:

- All statements succeed or none do
- Cypher shell returns a consistent exit code
- CI/CD pipelines remain deterministic

## Consequences

- Users must not include transaction boundaries in modular DML files
- Variable bindings still require `WITH` or `MATCH` – wrapping does not change that

  XXX Hier evtl. noch mal explizit erwähnen, dass diese Verhalten per-design von Cypher so ist!

- Monolithic files may include their own transactional or imperative logic

## Alternatives Considered

- Trusting user to wrap input (error-prone)
- Wrapping each line separately (breaks graph semantics)
- Allowing unwrapped graph files (fragile, non-atomic)

XXX Was ist ein "unwarpped graph file"?

## Future Considerations

- Introduce `--raw` to allow unwrapped execution (for advanced cases)
- Add validation logic to ensure modular files don’t contain transactions

# ADR-003: Execute modular DML graph in one atomic transaction
<a name="adr-atomic-dml"></a>

## Status

Accepted

## Context

Modular imports via `inject -g` allow decomposition into:

1. `--ddl-pre`: constraints, indexes, etc.
2. `-g`: pure DML graph logic
3. `--ddl-post`: cleanup, post-indexing, etc.

XXX Hier ggf. den Begriff 'modular graph initialization' als Bezeichner für ein Tripple `(--ddl-pre, -g, --ddl-post)` einführen?

Only the graph file (`-g`) is wrapped in a transaction. The DDL parts run in implicit separate transactions.

## Decision

Neoject wraps the core DML graph file in:

XXX Anpasse zu: Neoject wraps a modular graph initialization in:

```plaintext
cypher-shell <"$DDL_PRE"
cypher-shell < :begin
               CREATE (f:Function {id: 1});
               CREATE (b:Body {id: 2});
               MATCH (f:Function {id:1}), (b:Body {id:2}) CREATE (f)-[:HAS]->(b);
               :commit
cypher-shell <"$DDL_POST"
```

This ensures that if anything fails, **none** of the graph changes are applied.

XXX Abschlusssatz anpassen und sollten wir hier nicht ADR-002 referenzieren!?

XXX Die folgenden Kapitel "Rationale", "Technical Justification" (wenn noch nötig), "Consequences", "Alternatives Considered", "Future Considered" entsprechend anpassen wenn notwendig

## Rationale

- DDL changes can stand alone
- DML must succeed as a **single atomic unit**
- Failure in DML should not leave partial graph state

## Technical Justification

Cypher shell runs each statement in isolation by default. This means:

- Errors mid-file are not recoverable
- ACID guarantees are only effective if user controls transactions
- Rolling back changes requires explicit boundaries

## Consequences

- Modular files are read, wrapped, piped into shell as a unit
- DDL and DML are kept orthogonal
- Full rollback of graph logic is ensured

## Alternatives Considered

- Letting Neo4j auto-batch (no rollback guarantee)
- Wrapping the entire import (including DDL) – rejected due to coupling
- Manual control by user – error-prone

## Future Considerations

- Batch wrapping large graphs (>10K statements)
- Partial checkpointing of batches
- Optional retries for transient failures

# ADR-004: `clean-db` preserves schema metadata; `reset-db` purges everything
<a name="adr-cls-vs-rst"></a>

## Status

Accepted

## Context

Neoject offers two options to clear the database:

- `clean-db`: removes all nodes, relationships, indexes, constraints
- `reset-db`: drops and recreates the database completely

## Decision

| Operation     | Deletes Data | Deletes Schema | Deletes Metadata |
| ------------- | ------------ | -------------- | ---------------- |
| `clean-db`    | ✅           | ✅             | ❌               |
| `reset-db`    | ✅           | ✅             | ✅               |

Neo4j **retains schema metadata** (labels, keys, rel types) unless the DB is dropped.

## Rationale

- Cleaning is sufficient for dev/test cycles
- Reset is required for truly fresh DB (e.g. CI/CD or introspection)
- Metadata like labels remain visible unless purged

## Technical Justification

Neo4j stores metadata in internal system stores. Only:

```cypher
DROP DATABASE <name>;
```

removes these entries.

## Consequences

- Tools like Neo4j Desktop may show labels/types after `clean-db`
- `reset-db` requires SYSTEM access
- Script must wait until recreated DB becomes ONLINE

## Alternatives Considered

- Using APOC to delete metadata (not possible)
- Resetting via file deletion (unportable)

## Future Considerations

- Add `--hard-clean` flag as alias to `reset-db`
- Provide metadata inspection command (`SHOW LABELS`, etc.)
- Warn user if SYSTEM access is missing

---

# ADR-005: Cypher modular style must avoid cross-statement variable references
<a name="adr-modular-style"></a>

## Status

Accepted

## Context

Cypher variables are **statement-local** unless passed via `WITH`.

This applies regardless of transaction wrapping. Many `.cypher` files fail silently by assuming that:

```cypher
CREATE (f:Function {id: 1});
CREATE (b:Body {id: 2});
CREATE (f)-[:HAS]->(b);  // 🚫 f/b are not defined here
```

This creates _4 nodes_ and _no relationship_.

## Decision

Modular DML files **must** follow one of these valid patterns:

- **Pattern-matching**:

  ```cypher
  CREATE (f:Function {id: 1});
  CREATE (b:Body {id: 2});
  MATCH (f:Function {id:1}), (b:Body {id:2}) CREATE (f)-[:HAS]->(b);
  ```

- **WITH chaining**:

  ```cypher
  CREATE (f:Function {id: 1});
  CREATE (b:Body {id: 2});
  WITH f, b
  CREATE (f)-[:HAS]->(b);
  ```

- **Single statement**:

  ```cypher
  CREATE (f:Function {id: 1}), (b:Body {id: 2}), (f)-[:HAS]->(b);
  ```

## Rationale

- Prevents duplicate nodes and missing relationships
- Works in browser, CLI, CI/CD alike
- Avoids confusion from implicit Cypher behavior

## Technical Justification

Neo4j does **not** preserve variables across statements.

Wrapping in `:begin/:commit` ensures atomicity, but **not** variable visibility.

## Consequences

- All `.cypher` authors must use `WITH` or `MATCH`
- `neoject` does not validate this (yet)
- Failures may be silent unless tested manually

## Alternatives Considered

- Auto-rewriting Cypher (rejected: dangerous)
- Pre-validating for cross-scope variables (not implemented yet)

## Future Considerations

- Add `neoject lint` to statically check modular files
- Provide examples and tooling to verify graph shape post-import

