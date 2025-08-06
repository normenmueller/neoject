MERGE (p1:Person {id:1,name:"Alice"})-[:LIVES_IN]->(c1:City {name:"Berlin"});
MERGE (p2:Person {id:2,name:"Bob"})-[:LIVES_IN]->(c2:City {name:"Paris"});

