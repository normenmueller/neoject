// https://github.com/neo4j-graph-examples/movies/blob/main/scripts/movies.cypher

CREATE CONSTRAINT IF NOT EXISTS FOR (p:Person) REQUIRE (p.name) IS UNIQUE;
CREATE INDEX IF NOT EXISTS FOR (p:Person) ON (p.born);
CREATE CONSTRAINT IF NOT EXISTS FOR (m:Movie) REQUIRE (m.title) IS UNIQUE;
CREATE INDEX IF NOT EXISTS FOR (m:Movie) ON (m.released);

