CREATE (f:Function {id: 1, name: "main"});
CREATE (b:Body {id: 2});
CREATE (f)-[:CHILD]->(b);

