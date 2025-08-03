---
title: Export a Neo4j DB
...

Neo4j bietet über **APOC** die Möglichkeit, einen eingespielten Graphen als reines Cypher‑Skript zu exportieren. Dieses Skript kannst Du anschließend als `.cypher` bzw. `.cql` Datei nutzen und mit `neoject.sh` importieren.

# Voraussetzungen

- **APOC Plugin installiert und aktiv**
- In `apoc.conf` aktiviert:

  ```properties
  apoc.export.file.enabled=true
  apoc.import.file.use_neo4j_config=true
  ```

*Hinweis*: Der Pfad erhält man u.a. in Neo4j Desktop. Er steht unter `Path` in der jeweiligen Instanz.

# Export-Befehl im Neo4j Browser oder `cypher-shell`:

```cypher
CALL apoc.export.cypher.all(null, {format: 'plain', stream: true})
YIELD cypherStatements
RETURN cypherStatements;
```

Dieser Befehl liefert den vollständigen Datenbank‑Graph als Cypher-Statements zurück – als ein großer Textblock, den Du kopieren kannst. ([Stack Overflow][1])

# Speichere das als Datei:

```bash
echo "<kopierter cypherStatements‑Text>" > export.cql
```

# Import via `neoject.sh`:

```bash
./src/neoject.sh --clean-db -u neo4j -p <password> -a bolt://localhost:7687 -f export.cql
```

Damit wird der gesamte Graph in einem einzelnen, atomaren Import in Neo4j eingespielt.

[1]: https://stackoverflow.com/questions/65298867/export-data-from-neo4j-sandbox "Export data from Neo4j Sandbox - cypher"

