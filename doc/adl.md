---
title: Architecture Decision Log
...

# ADR-001: Format-Optionen

Entscheidungsmatrix:

| Formatoption                            | Beschreibung                                                 | Bewertung                                                      |
| --------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------- |
| **Raw-Cypher**                          | Du erzeugst direkt `.cypher`-Dateien mit `CREATE` Statements | ✅ **Einfach, direkt importierbar**                            |
| **CSV für `LOAD CSV`**                  | Du exportierst Knoten + Kanten als CSV-Dateien               | 🟡 **Effizienter bei großen Daten, aber komplexer in Mapping** |
| **GraphML / GML / JSON**                | Neo4j kann manche Formate via Plugins importieren            | 🔴 **Overhead / weniger direkt / Plugin-abhängig**             |
| **APOC `apoc.import.graphml/json/csv`** | über APOC-Skripte                                            | 🟡 **Leistungsstark, aber zusätzliche Konfiguration nötig**    |

# ADR-002: Technische Optionen zum Import

## Mit `cypher-shell` *(offiziell empfohlen)*

**Voraussetzung:** Neo4j installiert (lokal oder remote), `cypher-shell` verfügbar (Teil von Neo4j oder Neo4j Desktop).

### Beispiel-Aufruf

```bash
cypher-shell -u neo4j -p geheim -a bolt://localhost:7687 -f ast.cypher
```

**Parameter:**

* `-u`: Benutzername
* `-p`: Passwort
* `-a`: Adresse (URL, z. B. `bolt://host:port`)
* `-f`: Pfad zur Cypher-Datei

### Vorteile

- direkt, stabil, offiziell unterstützt
- Skriptbar
- gute Fehlermeldungen
- transaktional

### CLI-Wrapper: Shellscript oder Haskell?

| Kriterium        | Shellscript (`bash`, `sh`)           | Haskell-CLI                        |
| ---------------- | ------------------------------------ | ---------------------------------- |
| Komplexität      | Niedrig                              | Hoch                               |
| Portabilität     | Hoch (jede Unix-Shell)               | Geringer (nur mit Build/Install)   |
| Parametrisierung | Einfach (mit `getopts`)              | Sehr flexibel, typsicher           |
| Testbarkeit      | Eingeschränkt                        | Sehr gut, wenn modular aufgebaut   |
| Wartbarkeit      | Schwierig bei wachsender Komplexität | Besser bei komplexen Anforderungen |

## Mit XXX

TODO

## Empfehlung:

* **Für schnelles Arbeiten + CI/CD**: Shellscript mit `cypher-shell`
* **Für robuste Distribution + Tooling**: Haskell-CLI mit Argumenten-Parsing + Logging

## Fazit

> Shellscript mit `cypher-shell` als *Backend*.



