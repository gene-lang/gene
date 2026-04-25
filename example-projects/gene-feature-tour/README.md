# Gene Feature Tour

```
# Run source
bin/gene run src/index.gene

# Parse and inspect AST
bin/gene parse src/index.gene

# Compile to a readable or cached representation
bin/gene compile -f pretty src/index.gene
bin/gene compile -f gir src/index.gene

# Inline eval / REPL
bin/gene eval '(println "hello")'
bin/gene repl
```
