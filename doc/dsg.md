---
title: Neoject design
...

# Entscheidungsmatrix: Format-Optionen

| Formatoption                            | Beschreibung                                                 | Bewertung                                                      |
| --------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------- |
| **Raw-Cypher**                          | Du erzeugst direkt `.cypher`-Dateien mit `CREATE` Statements | ✅ **Einfach, direkt importierbar**                            |
| **CSV für `LOAD CSV`**                  | Du exportierst Knoten + Kanten als CSV-Dateien               | 🟡 **Effizienter bei großen Daten, aber komplexer in Mapping** |
| **GraphML / GML / JSON**                | Neo4j kann manche Formate via Plugins importieren            | 🔴 **Overhead / weniger direkt / Plugin-abhängig**             |
| **APOC `apoc.import.graphml/json/csv`** | über APOC-Skripte                                            | 🟡 **Leistungsstark, aber zusätzliche Konfiguration nötig**    |

