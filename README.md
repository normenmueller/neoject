# Einarbeiten

- Bzgl. dem Design: "pragmatischter und robuster Weg für einen Prototyp bzw. eine erste funktionale Pipeline"

---

# Neoject

> **Neoject** — A ..

## What is Neoject?

...

## Why Neoject?


**Neoject provides:**

- ...

## How It Works

...

## Installation

XXX Hier oder weiter unten, eine Erklärung warum man beides installieren muss. UND wie das Zusammenspiel zw. "Neo4j Desktop" und `neo4j` via Homebrew ist. Verwendet Neo4j Desktop etwas aus `neo4j`? Muss da auf Versionen achten? Also... einfach dem Leser erklären WARUM man das beides installieren muss. Bspw. was genau ist in `/opt/homebrew/opt/neo4j` installiert? Wie spielt das mit Neo4j Desktop zusammen? Kann es da Konflikte geben?

### Install Neo4j Desktop

Installiere [Neo4j Desktop](https://neo4j.com/download/) auf Deinem System. Die Anwendung bietet eine lokale Entwicklungsumgebung mit grafischer Benutzeroberfläche, in der Du Datenbanken erstellen, starten und verwalten kannst.

> Hinweis: Für macOS, Windows und Linux verfügbar. Kein Login notwendig, aber ein kostenloses Konto ist erforderlich, um die Installation abzuschließen.

### Install `cypher-shell`

> Wichtig: `cypher-shell` ist **nicht automatisch** über Neo4j Desktop verfügbar.

Um `.cypher`-Dateien via Shell auszuführen, benötigst Du das Tool `cypher-shell`.

#### macOS (empfohlen)

Installiere es mit [Homebrew](https://brew.sh/):

```bash
brew install neo4j
```

Danach solltest Du `cypher-shell` direkt verwenden können:

```bash
cypher-shell --version
```

XXX NEIN! Das funktioniert nicht. Man muss wohl auch im Falle von Homebrew die Pfade in `$PATH` aufnehmen. ABER wie bekommt man die Pfade raus?

Falls Du Neo4j **nicht über Homebrew** installiert hast, kannst Du das CLI-Tool auch manuell herunterladen:

- [Download Neo4j Cypher Shell](https://neo4j.com/deployment-center/#tools-tab)

#### Windows/Linux

Unter Windows ist `cypher-shell.bat` oft im Projektverzeichnis von Neo4j Desktop zu finden. Unter Linux kann es analog per Paketmanager (`apt`, `brew`, `dnf`) installiert werden.

#### Pfad setzen

Wenn Du `cypher-shell` manuell heruntergeladen hast, füge den Pfad zur Binärdatei in Deine Shell-Konfiguration (`.bashrc`, `.zshrc`) ein:

```bash
export PATH="$HOME/neo4j-cli/bin:$PATH"
```

XXX Dieses Kapitle passt so nicht mehr. Denn in beiden Fällen muss man `$PATH` ergänzen.

### Erstelle Graph Datenbank in Neo4j Desktop

#### Instanz (Projekt) anlegen

- Öffne Neo4j Desktop.
- Erstelle ein neues **Projekt** (optional).
- Erstelle eine **neue Datenbankinstanz** (lokal) oder nutze eine bestehende.

> Achte darauf: Die Instanz **muss laufen**, bevor Du per CLI darauf zugreifen kannst.

#### Datenbank starten

- Starte Deine gewünschte Datenbank über den "Start"-Button.
- Beim ersten Start wirst Du aufgefordert, ein Passwort zu setzen. Der Benutzername ist *standardmäßig* `neo4j` und kann nicht geändert werden.
- Merke Dir also:

  - Benutzer: `neo4j`
  - Passwort: (selbst gewähltes Passwort beim ersten Start)

### Clone Neoject Repository

XXX Hier kurz und knapp erklären wie man das neoject Repo clone-d

### Setup Neoject

#### ...

XXX ggf. `ln -s neoject.sh neoject` UND `chmod u+x neoject` oder so etwas Ähnliches

#### Zugriffsadresse (Bolt-Port) ermitteln

In den **Instanz-Details** (rechter Seitenbereich) findest Du:

- `IP address`: z. B. `localhost`
- `Bolt port`: z. B. `7687`

Daraus setzt sich die **Bolt-URL** wie folgt zusammen:

```text
bolt://<IP address>:<Bolt port>
```

Beispiel:
```text
bolt://localhost:7687
```

Diese URL wird als Argument bei `-a` bzw. `--address` im Shellskript verwendet.

#### Test

````bash
> neoject -u neo4j -p geheim -a bolt://localhost:7687
````

XXX Was ist die erwartete Ausgabe für diesen Test?

## Usage

### Daten vorbereiten

```cypher
// fun.cypher
CREATE (f:Function {id: 1, name: "main"});
CREATE (b:Block {id: 2});
CREATE (f)-[:CHILD]->(b);
```

### Shellskript ausführen

```bash
neoject -f fun.cypher -u neo4j -p geheim -a bolt://localhost:7687
```

Ergebnis:

- Keine Fehlermeldung
- Kontrolliere in Neo4j Desktop über "Query":

```cypher
MATCH (n) RETURN n;
```

### Wichtig

* **Transaktionen**: `cypher-shell` führt die Datei **in einer Sitzung** aus – wenn ein Fehler auftritt, schlägt die gesamte Ausführung fehl (gut!).
* **Passwort speichern**: Niemals Klartext im Repo – besser: `.env` oder Prompt-Lösung, wenn gewünscht.

## Contributing

We welcome contributions!

### Guidelines

- ...

## FAQ

...

## License

See [LICENSE](./LICENSE)
© 2025 [nemron](https://github.com/normenmueller)

