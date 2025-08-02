---
title: Architecture Decision Log
...


# ADR-001: Use Shellscript with `cypher-shell` for Data Import

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

