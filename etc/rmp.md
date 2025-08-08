---
title: Roadmap
...

# feature/cql-var

## Current topic

### Gültige Parameterkombinationen

| Modus | Pflicht für Chunking | Erlaubte Flags                                   | Ausschlüsse                      |
| ----- | -------------------- | ------------------------------------------------ | -------------------------------- |
| `-g`  | — (immer aktiv)      | `--chunk-size`, `--chunk-bytes`, `--batch-delay` | `--chunk-size` ⊕ `--chunk-bytes` |
| `-f`  | `--chunked`          | `--chunk-size`, `--chunk-bytes`, `--batch-delay` | `--chunk-size` ⊕ `--chunk-bytes` |

### Defaultwerte für -g

* `--chunk-size`: **1000 Statements**
* `--chunk-bytes`: **8 MiB**
* `--batch-delay`: **0 ms**
* **Exklusivregel**: Entweder `--chunk-size` **oder** `--chunk-bytes`.

### Neue Helferfunktionen

```bash
# create chunks from file/stdin according to size/bytes limits
chnk() {
  # Tokenizer + Batcher
}

# inject a single chunk into Neo4j inside an explicit transaction
injchk() {
  # :begin ... :commit piped to cypher-shell
}
```

`cmbcmp()` und `injmxf()` nutzen dann `chnk | injchk` in der gewünschten Reihenfolge mit Logging, Error-Stop, optionalem Delay.

## Pipeline

### README

- Align README

### Neo4j v5!

Auf Grund von `--clean-db`:

- SHOW INDEXES und SHOW CONSTRAINTS in der jetzigen Syntax nutzt
- `db.dropIndex(name)` oder `db.dropConstraint(name)`

### `neo4j.conf` pre-requisites

Damit `--clean-db` funktioniert:

````
dbms.security.procedures.unrestricted=apoc.*
dbms.security.procedures.allowlist=apoc.*
````

### APOC

#### Install `apoc-extended`

##### 🔽 1. **Download der richtigen JAR**

Gehe auf das [offizielle APOC GitHub-Release-Repository](https://github.com/neo4j/apoc/releases).
Wähle die **Version, die zu deiner Neo4j-Version passt** – in deinem Fall also vermutlich:

🔗 [https://github.com/neo4j/apoc/releases/tag/2025.07.0](https://github.com/neo4j/apoc/releases/tag/2025.07.0)

XXX URL stimmen nicht! Dort ist kein "all" apoc. Go to https://github.com/neo4j-contrib/neo4j-apoc-procedures

Dort findest du:

```
apoc-2025.07.0-all.jar ✅
```

Lade genau **diese** Datei herunter.

##### 📦 2. **Ins Plugin-Verzeichnis kopieren**

Angenommen dein Neo4j-Home ist `/var/lib/neo4j` oder `/usr/local/neo4j`, dann:

```bash
cp apoc-2025.07.0-all.jar /path/to/neo4j/plugins/
```

⚠️ Entferne ggf. die alte `apoc-core`-Version:

```bash
rm /path/to/neo4j/plugins/apoc-2025.07.0-core.jar
```

##### ⚙️ 3. **`apoc.conf` prüfen**

Die Datei `apoc.conf` muss im Konfig-Verzeichnis (z. B. `/conf` oder `/etc/neo4j`) liegen und **mindestens** enthalten:

```properties
apoc.export.file.enabled=true
apoc.import.file.enabled=true
apoc.import.file.use_neo4j_config=true
apoc.cypher.runfile.enabled=true
```

##### 🛡️ 4. **`neo4j.conf` prüfen**

Füge (falls noch nicht geschehen) hinzu:

```properties
dbms.security.procedures.unrestricted=apoc.*
dbms.security.procedures.allowlist=apoc.*
```

##### 🔄 5. **Neo4j neu starten**

```bash
neo4j restart
```

Oder – je nach Installation:

```bash
sudo systemctl restart neo4j
```

##### 🧪 6. **Verifizieren**

```bash
echo 'RETURN apoc.version()' \
  | cypher-shell -u neo4j -p <your-pass> -a neo4j://localhost:7687
```

und:

```bash
echo 'SHOW PROCEDURES YIELD name WHERE name CONTAINS("runFile") RETURN name;' \
  | cypher-shell -u neo4j -p <your-pass> -a neo4j://localhost:7687
```

Wenn du dort `apoc.cypher.runFile` siehst → ✔️

##### 🧠 Warum ist das so kompliziert?

Seit Neo4j 4.x ist **APOC modularisiert**:

* `apoc-core`: nur „sichere“ Funktionen, wird standardmäßig verteilt
* `apoc-extended`: mächtigere Features, aber mit potenziellen Sicherheitsimplikationen

Darum musst du diese gezielt freischalten (inkl. JAR & Konfiguration).

#### `apoc.conf` XXX

````
apoc.export.file.enabled=true
apoc.import.file.enabled=true
apoc.import.file.use_neo4j_config=true
apoc.cypher.runfile.enabled=true
````

#### CLI parameters

Hinweis: Base-Parameter (-u, -p, -a) müssen vor dem Subcommand stehen.

#### Überblick: Cypher-Konstrukte & Einlesemodi

| Kategorie                            | Typ                                                                         | Beschreibung                                                     | In `apply` (APOC)             | In `slurp` (Tx via cypher-shell)   |
| ------------------------------------ | --------------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------------- | ---------------------------------- |
| **DDL (Data Definition Language)**   | `CREATE/DROP CONSTRAINT`<br>`CREATE/DROP INDEX`<br>`CREATE/DROP DATABASE`   | Definiert strukturelle Metadaten (Constraints, Indexes, DBs).    | ✅ (wenn semikolon-terminiert) | ⚠️ nur via `--ddl-pre/--ddl-post` |
| **DML (Data Manipulation Language)** | `MERGE`, `CREATE`, `MATCH`, `SET`, `REMOVE`, `DELETE` etc.                  | Standard-Graphoperationen auf Knoten, Kanten, Labels, Properties | ✅                             | ✅                                |
| **Transactions**                     | `:begin`, `:commit`, `:rollback`                                            | Steuerung von Transaktionsrahmen bei Batch-Importen              | ❌ **(verboten)**              | ✅ **(Pflicht bei slurp)**        |
| **CALL-Prozeduren**                  | `CALL apoc.*`, `CALL db.*`, `CALL gds.*`                                    | Prozeduren für Erweiterungen oder Low-Level-Systemzugriffe       | ✅ (sofern APOC etc. erlaubt)  | ✅                                |
| **Cypher-Syntax-Erweiterungen**      | `FOREACH`, `UNWIND`, `WITH`, `RETURN`, `CASE`, `EXISTS`, `LIST`, `MAP` usw. | Kontrollfluss, Abfragen, Bedingungen, Aggregationen, Datenfluss  | ✅                             | ✅                                |
| **Kommentare**                       | `// einzeilig`, `/* mehrzeilig */`                                          | Werden ignoriert, auch von APOC                                  | ✅                             | ✅                                |

##### Wichtigste Unterschiede: apply vs. slurp

| Aspekt                                 | `apply` (`apoc.cypher.runFile`)                    | `slurp` (via `cypher-shell` with `:begin/:commit`)       |
| -------------------------------------- | -------------------------------------------------- | -------------------------------------------------------- |
| Transaktional                          | ❌ *non-transactional per default (`useTx:false`)* | ✅ vollständige Einzeltransaktion                        |
| Fehlerverhalten                        | ✅ Robust gegenüber einzelnen Query-Fehlern        | ❌ jeder Fehler rollt gesamte Tx zurück                  |
| Unterstützung für `:begin` / `:commit` | ❌ nicht erlaubt                                   | ✅ explizit erforderlich                                 |
| Unterstützung für DDL                  | ✅ Ja (wenn `useTx:false` und semikolonterminiert) | ❌ muss ausgelagert werden in `--ddl-pre` / `--ddl-post` |
| Empfohlene Dateiform                   | `.cql` oder `.cypher`, mehrere Statements mit `;`  | Nur genau ein Statementblock mit \:begin/\:commit        |
| Batch-Verarbeitung                     | 🟡 möglich durch APOC-Prozeduren                   | ❌ nicht ohne manuelles Chunking                         |

XXX Moment. Das heißt aber doch, das wir mit `useTx:true` auch mit APOC transaktional sein können. ABER dann dürfen keine DDL in der Datei vorkommen. Richtig?

> Ja, apoc.cypher.runFile(..., {useTx:true}) macht die gesamte Datei zu einer Transaktion – aber:
> 	•	Sobald DDL-Anweisungen (z. B. CREATE CONSTRAINT, DROP INDEX) darin vorkommen, schlägt useTx:true fehl, da DDL nicht in aktiven Transaktionen erlaubt ist.
> 	•	Für DDL gilt (wie bei JDBC / RDBMS): sie sind implizit autocommitted und nicht rollbackfähig.
>
> 👉 Fazit:
> 	•	useTx:true → nur für DML
> 	•	useTx:false → für DDL + DML gemischt

##### Validierung – Was muss gelten?

Für apply (APOC):

- ✔ alle Statements enden mit ;
- ✔ kein :begin oder :commit
- ✔ APOC installiert & `apoc.cypher.runFile` freigegeben
- ✔ Datei im import-Pfad & freigegeben in `apoc.conf`
- ✔ keine Transaktionslogik (Cypher intern ist okay)

Für slurp:

- ✔ Datei beginnt mit :begin und endet mit :commit
- ✔ enthält nur pure Cypher (DML, Prozeduren)
- ✔ kein DROP/CREATE DATABASE
- ✔ keine APOC/DDL? → in --ddl-pre oder --ddl-post auslagern
- ✔ syntaktisch korrekt – Slurp ist **fail-fast**

XXX "Datei beginnt mit :begin und endet mit :commit" NEIN! `:begin` und `:commit` werden durch `neoject` hinzugefügt! In `-g` darf nur der pure Graph stehen --- wie nennt man das in "Cypher-Sprech"? Also keine DDL Konstrukute, aber wie heißen diese "nicht-DDL-Konstrukte"? DML? Für was steht das? --- in `--ddl-pre` bzw `-post` dürfen dann DDL Konstrukte stehen. D.h. sogesehen ist `:begin` und `:commit` in slurp erlaubt, aber eben nicht explizit; das wird von `neoject` erledigt. OK?

> 2. :begin / :commit in slurp
>
> Exakt richtig!
> Die Datei, die über -g an slurp übergeben wird, enthält keine expliziten :begin/:commit.
>
> Diese werden von neoject automatisch um den Inhalt der Datei gelegt:
>
> ````
> :begin
> $(cat "$GRAPH")
> :commit
> ````
> 👉 Daher gilt:
> •	Inhalt der -g Datei = ausschließlich pure Cypher DML
> •	DDL (CREATE/DROP CONSTRAINT/INDEX/…) → nur in --ddl-pre oder --ddl-post
> •	:begin/:commit sind in -g verboten (würde sonst doppelt eingefügt)

> 3. Wie nennt man “nicht-DDL-Konstrukte”?
> Der richtige Begriff ist:
>
> 🔹 DML – Data Manipulation Language
>
> Das umfasst:
> 	•	MERGE, CREATE, MATCH, SET, REMOVE, DELETE, UNWIND, FOREACH, WITH, RETURN, CALL ... usw.
> 	•	Also alle Cypher-Statements, die Graphdaten manipulieren, erzeugen oder abfragen
>
> 👉 Damit ist die Datei für -g eine reine DML-Datei (kein DDL, kein Tx-Control)

> Zusammengefasst
> | Konstrukt | APOC (apply)        | slurp -g         | --ddl-pre/post    |
> | --------- | ------------------- | ---------------- | ----------------- |
> | DDL       | ✅ mit `useTx:false` | ❌ verboten       | ✅ erlaubt         |
> | DML       | ✅                   | ✅                | 🟡 (nicht üblich) |
> | `:begin`  | ❌ verboten          | 🔄 auto-injected | ❌ verboten        |

#### Fazit & Empfehlungen

| Situation                       | Empfehlung                                        |
| ------------------------------- | ------------------------------------------------- |
| Full import inkl. DDL           | `apply -f <mixed.cql>` via APOC                   |
| Transaktionales Graph-only      | `slurp -g <graph.cql>` + `--ddl-pre` optional     |
| Sicherheit & Reproduzierbarkeit | `slurp` bevorzugen                                |
| Massive Datenmengen (Batch)     | in Zukunft: Chunking oder `apoc.periodic.iterate` |

n/a

