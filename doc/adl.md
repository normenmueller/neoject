---
title: Architecture Decision Log
...


# ADR-001: Use shell script with `cypher-shell` for data import

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

- Bash shellscript
- Haskell CLI
- Python script
- Makefile automation

## Decision

We use a shellscript wrapper (`neoject.sh`) that invokes the officially supported `cypher-shell` command-line client.

## Rationale

- `cypher-shell` is **officially maintained** and **cross-platform**
- Shellscripts are **widely available**, **zero-dependency**, and **CI-friendly**
- Easy to invoke from Makefiles, CI/CD pipelines or manually
- Full **transaction support** with precise error propagation
- Easy to extend or replace later

> This is the **most pragmatic and robust approach** for building a prototype or a first functional data pipeline.
> It gives immediate results with minimal setup, while keeping the door open for future refactoring.

## Consequences

- No need for external dependencies (e.g., Haskell toolchain)
- Simple setup via Homebrew or direct download
- Passwords are passed via command-line args for now (→ can be hardened later)
- Error handling is delegated to `cypher-shell` itself

## Alternatives Considered

- A fully typed Haskell CLI for richer UX (rejected due to overhead at this stage)
- Using Neo4j’s HTTP REST interface directly (less ergonomic)
- CSV-based import (requires custom mapping logic and multiple steps)

## Future Considerations

- Introduce a Haskell CLI once the system complexity grows
- Add `.env` file parsing or interactive password prompts
- Refactor into reusable CLI components (logging, output formatting, etc.)

# ADR-002: Let `neoject` wrap transactions — input files contain graph only

## Status

Accepted

## Context

Cypher input files like `fun.cypher` are meant to define the graph only. They contain `CREATE`, `MERGE`, `MATCH`, etc., but no transactional control commands such as `BEGIN`, `COMMIT`, or `ROLLBACK`.

However, when running Cypher scripts via `cypher-shell`, each statement is executed in isolation unless explicitly wrapped in a transaction. This leads to loss of scoped variables (like `f`, `b`, etc.) and can silently break multi-statement logic.

## Decision

`neoject.sh` will automatically wrap input files into an explicit transaction using `BEGIN ... COMMIT` before passing them to `cypher-shell`.

Input files must **not** contain any transaction statements. They are to remain clean and declarative — representing the intended graph structure only.

## Rationale

- **Separation of concerns**: Transaction handling is a runtime responsibility, not a property of static files.
- **Avoids silent failures** due to lost variables across isolated execution.
- **Ensures consistent behavior** across environments and tools.
- **Keeps Cypher files clean and focused** on graph semantics only.

## Technical Justification

The behavior originates from how **`cypher-shell`** processes input, as outlined in the official documentation:

1. **Cypher Shell processes each line individually by default** (i.e., scripting mode):
   - Each Cypher statement is executed in isolation and *not* as part of a shared transaction.
   - This means variable bindings (e.g., `f`, `b`) created in one line are not available in subsequent lines.
   - Multi-statement operations can therefore silently fail *without throwing an error*.
   [Neo4j Documentation](https://neo4j.com/docs/operations-manual/current/cypher-shell/)

2. The shell runs with **`--fail-fast`** by default, which causes it to abort on syntax or semantic errors *within a single statement*. However, if statements are *individually* valid (e.g., creating nodes), but **logically incomplete** (e.g., references to undefined variables like `f`), no failure is raised.

3. For example, the following will silently break:

   ```cypher
   CREATE (f:Function {id: 1});
   CREATE (b:Body {id: 2});
   CREATE (f)-[:CHILD]->(b);  // fails silently – f and b are undefined here
   ```

4. The only way to preserve variable bindings across statements is to wrap them in an **explicit transaction block** using:

   ```cypher
   BEGIN
   ...
   COMMIT
   ```

## Consequences

- `neoject.sh` needs to read the input file, prepend `BEGIN`, append `COMMIT`, and feed the composed string into `cypher-shell`.
- Input files are no longer directly usable with `cypher-shell -f`, but must go through the wrapper.

## Alternatives Considered

- Requiring explicit `BEGIN/COMMIT` in every input file (rejected: too error-prone and noisy).
- Accepting isolated Cypher statements without variable scoping (rejected: too fragile).

## Future Considerations

Introduce a `--raw` mode to bypass wrapping logic, allowing execution of pre-transactional scripts if needed.
