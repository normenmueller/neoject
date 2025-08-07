// Nodes
CREATE (f:Function {id: 1, name: "main"});
CREATE (b:Body {id: 2, name: "body"});

// Relations
MATCH (f:Function {id:1}), (b:Body {id:2}) CREATE (f)-[:HAS]->(b);

