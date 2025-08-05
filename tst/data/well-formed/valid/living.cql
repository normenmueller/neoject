// --- DDL ---
CREATE CONSTRAINT unique_person_id IF NOT EXISTS
FOR (p:Person)
REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT unique_city_name IF NOT EXISTS
FOR (c:City)
REQUIRE c.name IS UNIQUE;

// --- Data ---
MERGE (p1:Person {id: 1, name: "Alice"});
MERGE (c1:City {name: "Berlin"});
MERGE (p1:Person {id: 1})-[:LIVES_IN]->(c1:City {name: "Berlin"});

MERGE (p2:Person {id: 2, name: "Bob"});
MERGE (c2:City {name: "Paris"});
MERGE (p2:Person {id: 2})-[:LIVES_IN]->(c2:City {name: "Paris"});

