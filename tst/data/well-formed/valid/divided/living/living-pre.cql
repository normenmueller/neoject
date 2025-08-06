// --- DDL (you can also put these in --ddl-pre)
CREATE CONSTRAINT unique_person_id IF NOT EXISTS
  FOR (p:Person)
  REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT unique_city_name IF NOT EXISTS
  FOR (c:City)
  REQUIRE c.name IS UNIQUE;

// --- Data (all in one statement per logical unit) ---
MERGE (p1:Person {id:1,name:"Alice"})-[:LIVES_IN]->(c1:City {name:"Berlin"});
MERGE (p2:Person {id:2,name:"Bob"})-[:LIVES_IN]->(c2:City {name:"Paris"});

