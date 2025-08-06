CREATE CONSTRAINT unique_person_id IF NOT EXISTS
  FOR (p:Person)
  REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT unique_city_name IF NOT EXISTS
  FOR (c:City)
  REQUIRE c.name IS UNIQUE;

