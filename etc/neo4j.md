# Warum bleiben Labels und Property Keys erhalten, obwohl alle Knoten gelöscht wurden?

## Antwort

Das ist **erwartetes Verhalten in Neo4j.** Neo4j **behält Metadaten wie Labels und Property Keys**, selbst wenn keine Knoten oder Beziehungen mehr existieren, die sie verwenden.

## Details:

* **Labels**, **Relationship Types** und **Property Keys** sind Teil der **Schema-Metadaten**.
* Sie werden **nicht automatisch gelöscht**, wenn die letzten Knoten/Beziehungen verschwinden.
* Es gibt **keine Cypher-Anweisung**, um diese explizit zu löschen.
* Sie werden **intern erhalten**, z. B. für Performance oder Statistikzwecke.

> Sie "verschwinden“ erst, wenn du **die Datenbank komplett neu anlegst** oder das **Datenverzeichnis löschst**.

D.h. wenn du wirklich "alles" loswerden willst:

* **Datenbank komplett löschen** (`data/databases/neo4j/`)
* Oder: **Explizit neue Datenbank starten**, z. B. via `CREATE DATABASE <name>`

