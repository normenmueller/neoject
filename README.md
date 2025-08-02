# Neoject

> **Neoject** — A pragmatic CLI to inject `.cypher` graph descriptions into a running Neo4j database.

## What is Neoject?

**Neoject** is a simple command-line tool that injects pre-generated Cypher files into a running Neo4j database instance. It is intended for use in data analytics pipelines where graph data is already exported as Cypher and now needs to be loaded into Neo4j — reliably, repeatedly, and with minimal tooling.

XXX Hier einen Hinweis bzgl. "pre-generated" bzw. "exported" hinzu [Pangrm](https://github.com/normenmueller/pangrm) einfügen!

## Why Neoject?

Typical Neo4j import pipelines rely on heavy tooling, custom drivers, or multi-step formats such as CSV or GraphML. Neoject simplifies this process by assuming the data is already serialized as raw Cypher (i.e., `CREATE` statements), and focuses solely on the **import task**.

**Neoject provides:**

- CLI-based, scriptable access to `cypher-shell`
- Zero dependencies beyond Neo4j tooling
- A robust and testable path for local or CI/CD integration
- Clear separation of [conversion](https://github.com/normenmueller/pangrm) (AST → Cypher) and ingestion (Cypher → Neo4j)

## How It Works

Neoject is a thin wrapper around [`cypher-shell`](https://neo4j.com/docs/operations-manual/current/tools/cypher-shell/), Neo4j’s official command-line interface.

You provide:

- A `.cypher` file with graph data (usually `CREATE` statements)
- Credentials for the running Neo4j database
- A valid Bolt address to connect to the database instance

Neoject connects to the database and executes the given file in a single transaction.

## Installation

### Introduction

Neoject requires two components:

1. **Neo4j Desktop** – a GUI tool for managing local Neo4j database instances
2. **`cypher-shell`** – a command-line tool for executing `.cypher` files into Neo4j over Bolt

> Note: **Neo4j Desktop does *not* include `cypher-shell`**. It must be installed separately (e.g., via Homebrew or manual download).

Neo4j Desktop and `cypher-shell` operate independently and communicate solely via the Bolt protocol (`bolt://localhost:7687`).
There are no version conflicts as long as you don’t attempt to run multiple server instances simultaneously.

### Install Neo4j Desktop

Download and install [Neo4j Desktop](https://neo4j.com/download/) for your platform.

Neo4j Desktop is a graphical user interface that lets you manage Neo4j databases locally: create, start, stop, and inspect databases.

> Notes:
>
> - Available for macOS, Windows, and Linux
> - Requires a free Neo4j account on first launch
> - Does **not** include `cypher-shell` (see below)

After installation, you can create projects and local databases via the UI.

### Install `cypher-shell`

`cypher-shell` is used to import `.cypher` files into a running Neo4j instance. It must be installed separately.

#### macOS

Install via [Homebrew](https://brew.sh/):

```bash
brew install cypher-shell
```

Verify installation:

```bash
which cypher-shell
cypher-shell --version
```

If the command is not found, check your `PATH`:

```bash
echo $PATH
```

By default, `cypher-shell` is installed here:

```bash
/opt/homebrew/bin/cypher-shell
```

You may need to add it to your shell config (`~/.zshrc` or `~/.bashrc`):

```bash
export PATH="/opt/homebrew/bin:$PATH"
```

#### Linux

On Linux, install using your package manager:

```bash
# Debian/Ubuntu
sudo apt install cypher-shell

# Fedora/RHEL
sudo dnf install cypher-shell
```

Or download manually from: [Neo4j CLI Tools](https://neo4j.com/deployment-center/)

#### Windows

On Windows, `cypher-shell.bat` is part of the Neo4j CLI tools. You may need to download and extract it:

- [Download Neo4j Cypher Shell (ZIP)](https://neo4j.com/download-center/#command-line-tools)
- Extract and add `bin` to your `PATH`:

```cmd
set PATH=C:\neo4j-cli\bin;%PATH%
```

After installation, you should be able to run `cypher-shell` from any terminal.

## Setup

### Create a Graph Database in Neo4j Desktop

#### Create Project and Instance

1. Launch Neo4j Desktop.
2. (Optional) Create a new **Project** for organization.
3. Click **"Add" → "Local DB"** to create a new local database instance.
4. Choose a name and database version (e.g., 5.x).

#### Start Database and Set Password

1. Click the newly created instance in your project.
2. Click the **Start** button.
3. On first launch, you’ll be prompted to set a password.

> The username is always `neo4j` (this cannot be changed).
> You’ll need the password later when running `neoject`.

Write it down:

```text
Username: neo4j
Password: (your chosen password)
```

*Note:* The database must be running before using `neoject` or `cypher-shell`.
You will connect via the *Bolt* protocol, typically:

```text
bolt://localhost:7687
```

Details on how to assemble this URL follow below.

### Clone Repository & Prepare Neoject

#### Clone the Repo

```bash
git clone https://github.com/normenmueller/neoject.git
cd neoject
```

#### Determine Connection Details

To connect `neoject` or `cypher-shell` to your database, you need the **Bolt URL**.

In Neo4j Desktop:

1. Open your running database instance.
2. Click **“Connection Details”** (chain icon).
3. Note:
   - **IP address** (typically `localhost`)
   - **Bolt port** (typically `7687`)

Then assemble the Bolt URL:

```text
bolt://<IP address>:<Bolt port>
```

Standard case:

```text
bolt://localhost:7687
```

You will pass this value to `neoject` using the `-a` flag.

## Connection Test

Before importing data, test your connection setup.

Run `neoject` without a file:

```bash
./neoject -u neo4j -p <your-password> -a bolt://localhost:7687
```

This opens `cypher-shell` with no input, validating your credentials and connection.

### Expected Output

If successful, no errors will appear. You may see something like:

```text
Connected to Neo4j at bolt://localhost:7687 as user neo4j.
Type :help for a list of available commands or :exit to exit the shell.
```

Press `Ctrl+D` or type `:exit` to close the shell.

### Common Issues

- Wrong Bolt URL (wrong port or IP)
- Database not started
- Incorrect password
- Firewall/VPN blocks Bolt access

You can also test directly using `cypher-shell`:

```bash
cypher-shell -u neo4j -p <your-password> -a bolt://localhost:7687
```

## Usage

### Prepare a Cypher File

Create a file named `fun.cypher`:

```cypher
CREATE (f:Function {id: 1, name: "main"});
CREATE (b:Block {id: 2});
CREATE (f)-[:CHILD]->(b);
```

This file contains a small example AST fragment with two nodes and one relationship.

### Run the Import

Use `neoject` to execute the file:

```bash
./neoject -f fun.cypher -u neo4j -p <your-password> -a bolt://localhost:7687
```

### Expected Result

- The script runs without errors
- If the file is empty or invalid, `cypher-shell` returns an error
- Open Neo4j Desktop and run a query to verify:

```cypher
MATCH (n) RETURN n;
```

You should see two nodes and one relationship.

### Notes

- **Transactions:** The file is executed in a single transaction. If one statement fails, nothing is committed.
- **Security:** Never store passwords in version control.
  Consider using `.env` files or interactive prompts (to be added later).

## Contributing

We welcome contributions!

### Guidelines

- Keep CLI interface minimal
- Avoid hard dependencies
- Submit ADRs for design changes

## FAQ

...


## License

See [LICENSE](./LICENSE)
© 2025 [nemron](https://github.com/normenmueller)

