import ./types
import ./stdlib/core as stdlib_core
import ./stdlib/classes
import ./stdlib/strings
import ./stdlib/regex
import ./stdlib/json
import ./stdlib/collections
import ./stdlib/dates
import ./stdlib/selectors
import ./stdlib/gene_meta
import ./stdlib/aspects

proc init_gene_namespace*() =
  stdlib_core.init_gene_namespace()

proc init_stdlib*() =
  stdlib_core.init_stdlib()
