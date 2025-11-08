import ./helpers

test_vm """
  (gene/Class .name)
""", "Class"

test_vm """
  ((gene/Class .parent) .name)
""", "Object"

test_vm """
  ((gene/String .parent) .name)
""", "Object"
