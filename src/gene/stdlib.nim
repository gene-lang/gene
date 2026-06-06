import tables

import ./types
import ./stdlib/core as stdlib_core
import ./stdlib/classes
import ./stdlib/strings
import ./stdlib/regex
import ./stdlib/json
import ./stdlib/collections
import ./stdlib/dates
import ./stdlib/selectors
import ./stdlib/gdat
import ./stdlib/gene_meta
import ./stdlib/interception
import ./serdes

const StdlibTypeRetrofits = [
  (path: "src/gene/stdlib/types/collections.gene",
   source: staticRead("stdlib/types/collections.gene")),
]

proc run_stdlib_type_retrofits() =
  if App == NIL or App.kind != VkApplication or App.app.gene_ns.kind != VkNamespace:
    return

  let gene_ns = App.app.gene_ns.ns
  let applied_key = "__stdlib_type_retrofits_applied__".to_key()
  if gene_ns.members.has_key(applied_key):
    return

  let main_module_key = "main_module".to_key()
  let had_main_module = gene_ns.members.has_key(main_module_key)
  let previous_main_module =
    if had_main_module: gene_ns.members[main_module_key]
    else: NIL
  let previous_frame = VM.frame
  let previous_cu = VM.cu
  let previous_pc = VM.pc

  try:
    for retrofit in StdlibTypeRetrofits:
      if retrofit.source.len > 0:
        discard VM.exec(retrofit.source, retrofit.path)
  finally:
    VM.frame = previous_frame
    VM.cu = previous_cu
    VM.pc = previous_pc
    if had_main_module:
      gene_ns[main_module_key] = previous_main_module
    elif gene_ns.members.has_key(main_module_key):
      gene_ns.members.del(main_module_key)
      gene_ns.version.inc()

  gene_ns[applied_key] = TRUE

proc init_gene_namespace*() =
  stdlib_core.init_gene_namespace()

proc init_stdlib*() =
  stdlib_core.init_stdlib()
  init_serdes()
  run_stdlib_type_retrofits()
  freeze_bootstrap_publication()
