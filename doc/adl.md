---
title: Architecture Decision Log (ADL)
version: 0.1.8
...

# Overview

This ADL documents major design decisions for the `neoject` data import CLI tool. Neoject wraps Cypher-based graph initializations into structured execution pipelines and distinguishes **modular** (`-g`) from **monolithic** (`-f`) modes.

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

<!-- The All-or-Nothing ADR ;-) -->

## Status

Accepted

## Context

Graph DML files (`-g`) **must** contain only **declarative, transaction-free** Cypher statements:

- No Cypher shell meta-commands (e.g., `:begin`, `:commit`, `:rollback`)
- No DDL statements (e.g., `CREATE CONSTRAINT`, `DROP INDEX`)

These files are treated as graph data manipulations only. Transactional orchestration is the responsibility of the runtime (`neoject`).

## Decision

Neoject **automatically wraps** the contents of a modular graph DML file in a single transaction:

```cypher
:begin
<contents of -g file>
:commit
```

> 🚨 _Clarification_:
> `:begin`/`:commit` do **not** change Cypher variable scoping — variables remain **per statement** unless explicitly passed via `WITH`. The wrapping **only** provides all-or-nothing execution (atomicity). User-supplied transaction markers in modular mode are **forbidden**; wrapping is always performed by `neoject`.

This happens only in `inject -g`. Monolithic mode (`inject -f`) executes the file exactly as given.

## Rationale

- Prevents partial writes if any statement fails
- Ensures atomic DML execution in modular imports
- Centralizes transaction control in one place (`neoject`)
- Avoids fragile and inconsistent manual transaction markup

## Technical Justification

Without wrapping, Neo4j (via `cypher-shell`) will execute each statement independently; a failure mid-file leaves earlier statements committed and later ones skipped.

Wrapping via `:begin ... :commit` ensures:

- All statements succeed or none do
- The Cypher shell returns a clear non-zero exit code on failure
- CI/CD runs are deterministic

The need for `WITH`/`MATCH` to carry variables across statements is a separate Cypher design rule — wrapping does not bypass it.

> **Risk of large single transactions (OOM / transaction limits)**
>
> Executing all DML in one `:begin ... :commit` block means Neo4j holds the entire transaction in memory until commit. With large datasets, this can cause:
>
> - OOM (Out Of Memory) errors due to heap exhaustion
> - Transaction timeouts if the commit phase is too long
>
> This is especially risky when:
>
> - Importing via large UNWIND lists
> - Executing thousands of CREATE or MERGE statements in one go
> - Combining complex constraints or index builds with heavy data writes
>
> Mitigation: In such cases, batching or chunking of DML should be considered instead of one atomic transaction.

## Consequences

- Modular DML files must not contain transaction boundaries
- Cypher variables must be propagated explicitly if reused
  (_This is by design of the Cypher language itself_)
- Monolithic files may include their own transactions and are executed as-is

## Alternatives Considered

- **Unwrapped graph file** = modular file executed statement-by-statement without `:begin/:commit` → rejected as fragile and non-atomic
- Letting users wrap their own transactions → rejected, too error-prone
- Wrapping each line separately → breaks graph semantics and is inefficient

## Future Considerations

- `--raw` flag to bypass wrapping for expert scenarios
- Static validation to detect forbidden DDL or transaction markers in modular mode

# ADR-003: Execute modular graph initialization in two non-transactional and one transactional step
<a name="adr-atomic-dml"></a>

## Status

Accepted

## Context

A **modular graph initialization** is the triplet:

1. `--ddl-pre`: constraints, indexes, or other schema setup (runs non-transactionally)
2. `-g`: pure DML graph logic (runs **within a single explicit transaction**)
3. `--ddl-post`: optional schema updates or cleanup (runs non-transactionally)

Only the `-g` part is wrapped in `:begin ... :commit`. This separation allows schema changes to be applied before and after the DML, while keeping the data import atomic.

## Decision

Neoject executes a modular graph initialization as:

```plaintext
cypher-shell <"$DDL_PRE"
cypher-shell <<'EOF'
:begin
<contents of -g file>
:commit
EOF
cypher-shell <"$DDL_POST"
```

If any statement inside the `-g` transaction fails, **none** of its changes are committed, but the surrounding DDL parts remain applied.

(See [ADR-002](#adr-own-trx) for details on why wrapping is enforced in modular mode.)

## Rationale

- Schema changes (`--ddl-pre`/`--ddl-post`) can stand alone
- DML graph logic (`-g`) must succeed entirely or not at all
- Clean separation reduces coupling and improves maintainability

## Technical Justification

- Neo4j ACID guarantees apply only to statements within the same explicit transaction
- By isolating `-g` into one transaction, any failure causes a rollback of all graph data manipulations
- Schema changes remain in place, which is often desired (e.g., indexes for debugging a failed import)

## Consequences

- Modular imports run in exactly **three** distinct execution units:

  1) DDL pre (non-transactional)
  2) DML graph (atomic transaction)
  3) DDL post (non-transactional)

- Users can rely on `-g` being all-or-nothing, without worrying about partial graph writes

## Alternatives Considered

- Wrapping the entire triplet (`--ddl-pre`, `-g`, `--ddl-post`) in one transaction → rejected because many DDL statements in Neo4j cannot be executed inside an explicit transaction, and separating schema operations from DML improves clarity and error recovery.
- Leaving `-g` unwrapped → rejected as it allows partial data loads
- Forcing all imports to be monolithic → rejected; modular mode is more flexible

## Future Considerations

- Optional batch execution for huge `-g` files (>10k statements)
- Allow configurable transaction size for modular graph initializations
- Retry logic for transient errors in the `-g` phase

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

# ADR-006 (DRAFT): Prefer `cypher-shell` as primary import path; use APOC only as auxiliary tooling
<a name="adr-no-apoc-runfile-primary"></a>

## Status

DRAFT

- Übersetzen auf Englisch
- Als Entscheidung und nicht als Empfehlung formulieren! Es muss klar ersichtlich sein, warum wir uns für den Import gegen APOC entschieden haben (denn komplett gegen APOC sind wir ja nicht - cf. `clsdb`)

## Context

`neoject` must reliably ingest **very large graph initializations** (≫100 MB) in Neo4j. Es gibt zwei naheliegende Pfade:

1. **Clientseitig** via `cypher-shell` (offizielles CLI), Dateien per `-f` oder über STDIN einspeisen, Transaktionen im Client steuern.
2. **Serverseitig** via **APOC** (z. B. `CALL apoc.cypher.runFile("file:///...")`), das Dateien aus dem **Server‑Import‑Pfad** liest und innerhalb der DB ausführt.

Wir nutzen APOC bereits zielgerichtet in `clean-db` (`apoc.periodic.iterate`) zum **batchweisen Löschen**. Es stellt sich die Frage, ob wir APOC auch als **primären Importpfad** verwenden sollten.

## Decision

`neoject` verwendet **`cypher-shell` als primären Importpfad**.
**APOC bleibt optionales Hilfsmittel** (z. B. für Cleanup/Batching), wird **nicht** für den allgemeinen Import vorausgesetzt.

## Rationale

**1) Portability & Operations**
- `cypher-shell` ist **offiziell**, überall verfügbar, **ohne Plugin‑Pflicht**.
- APOC erfordert Installation, passende `apoc.*`‑Konfiguration, Import‑Pfad, ggf. Neustart und Security‑Freigaben — in vielen Umgebungen (Prod/Cloud) unerwünscht.

**2) Security Surface**
- `apoc.cypher.runFile` öffnet **serverseitigen** Dateizugriff (Import‑Verzeichnis). Viele Teams schließen das aus Sicherheitsgründen aus.
- `cypher-shell` liest Dateien **clientseitig** und sendet nur Cypher — geringere Angriffsoberfläche.

**3) Path/Deployment Friction**
- APOC erwartet Files **auf dem Server** (Import‑Pfad). CI/CD muss Volumes mounten, Rechte setzen, Pfade abbilden.
- `cypher-shell` funktioniert out‑of‑the‑box aus dem Runner: Datei lokal/aus der Pipeline → CLI/STDIN.

**4) Error Handling & DX (Developer Experience)**
- `cypher-shell` bietet klares Exit‑Code‑Verhalten, `--fail-fast`, sauberes Stdout/Stderr → **perfekt für BATS/CI**.
- `apoc.cypher.runFile` parst per Semikolon; Mischfälle (Kommentare, leere Zeilen, Meta‑Kommandos) können fragile Fehlerbilder erzeugen. Zeilen‑Zuordnung/Logs sind oft schlechter.

**5) Transaction Model & Memory**
- APOC läuft **serverseitig**; große Transaktionen können **ebenfalls** zu OOM/Timeouts führen.
- „Zeile‑für‑Zeile“ ist **nicht automatisch**; ohne explicites Batching (z. B. `apoc.periodic.iterate`) werden nicht automatisch kleine, getrennte Commits erzeugt.
- Mit `cypher-shell` behalten wir die **volle Kontrolle über Transaktionsgrenzen** – heute: 1 TX für `-g`; morgen: **clientseitiges Chunking** (geplant) mit eindeutigem Logging pro Batch.

**6) Modulare Semantik (DDL vs. DML)**
- Unser Modell trennt DDL (non‑transactional) und DML (`-g` → eine explizite TX).
- `runFile` verwischt diese Grenze leicht, wenn DDL und DML semikolon‑getrennt in einem Server‑Call landen.

## Technical Justification

- **Primärer Pfad** bleibt leichtgewichtig, reproduzierbar und **Plugin‑frei**.
- Logging/Fehlercodes von `cypher-shell` verbessern **Determinismus und Testbarkeit** (BATS, CI/CD).
- Das Risiko großer Transaktionen (OOM/Timeout) adressieren wir nicht mit einem Wechsel auf APOC, sondern mit **geplantem clientseitigem Chunking** (siehe Future Considerations und ADR‑003).

## Consequences

- **Keine APOC‑Pflicht** für Standard‑Imports; geringere Hürde für Nutzer.
- APOC bleibt **gezielt** im Einsatz (z. B. `clean-db` via `apoc.periodic.iterate`).
- Für extrem große Datenmengen wird `neoject` mittelfristig **clientseitiges Batching** anbieten (ohne APOC‑Zwang).

## Alternatives Considered

- **APOC `runFile` als Standard:** abgelehnt wegen Plugin‑Pflicht, Security-/Ops‑Reibung, Import‑Pfad‑Kopplung, schwächerer DX/Fehlerdiagnostik.
- **Gemischter Default (APOC bei großen Files):** abgelehnt; wechselnde Codepfade erschweren Debugging/Support. Ein klarer Default ist vorzuziehen.
- **Nur APOC (kein cypher-shell):** abgelehnt; verschlechtert Portabilität und CI‑Eignung.

## Future Considerations

- **Clientseitiges Chunking** für `-g` (z. B. N Statements/UNWIND‑Größe pro TX) zur Vermeidung von OOM/Timeouts.
- Optionales **Experten‑Flag** (z. B. `--apoc-run-file`) mit klaren Hinweisen: APOC‑Installation, Import‑Pfad, Security‑Implikationen — **kein** Default.
- Leitfäden/Modi für **Massendaten**: `LOAD CSV`, `neo4j-admin import` als empfohlene Wege für *very large* initial loads.


