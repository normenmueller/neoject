CREATE (n1:ASTNode {id: 1, type: "FunctionDef", name: "foo"});
CREATE (n2:ASTNode {id: 2, type: "Arguments"});
CREATE (n1)-[:CHILD]->(n2);

