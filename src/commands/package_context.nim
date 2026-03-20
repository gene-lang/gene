import os, strutils

import ../gene/types
import ../gene/vm/module

type
  CliPackageContext* = object
    enabled*: bool
    explicit*: bool
    root*: string
    name*: string

proc disabled_cli_package_context*(): CliPackageContext =
  CliPackageContext(enabled: false, explicit: false, root: "", name: "")

proc discover_cli_package_context*(anchor_path = "", importer_dir = ""): CliPackageContext =
  let anchor =
    if anchor_path.len > 0:
      anchor_path
    elif importer_dir.len > 0:
      importer_dir
    else:
      getCurrentDir()
  let root = find_package_root(anchor)
  if root.len == 0:
    return disabled_cli_package_context()

  let probe_module = absolutePath(joinPath(root, "src", "__gene_cli_autodiscover.gene"))
  let pkg_value = package_value_for_module(probe_module, "", root)
  let name =
    if pkg_value.kind == VkPackage and pkg_value.ref.pkg != nil:
      pkg_value.ref.pkg.name
    else:
      ""
  CliPackageContext(
    enabled: true,
    explicit: false,
    root: absolutePath(root),
    name: name,
  )

proc resolve_cli_package_context*(package_spec: string, importer_dir = "", importer_module = "",
                                  discovery_path = ""): CliPackageContext =
  if package_spec.len == 0:
    return discover_cli_package_context(discovery_path, importer_dir)

  let resolved = resolve_package_reference(package_spec, importer_dir, importer_module)
  CliPackageContext(
    enabled: true,
    explicit: true,
    root: resolved.root,
    name: resolved.name,
  )

proc resolve_package_path*(ctx: CliPackageContext, path: string): string =
  if not ctx.explicit or path.len == 0 or path.isAbsolute:
    return path
  absolutePath(joinPath(ctx.root, path))

proc virtual_module_name*(ctx: CliPackageContext, command_name: string, fallback_name: string): string =
  if not ctx.enabled:
    return fallback_name
  let safe_name = command_name.multiReplace(("-", "_"), (" ", "_"), ("/", "_"))
  absolutePath(joinPath(ctx.root, "src", "__gene_cli_" & safe_name & ".gene"))

proc configure_main_namespace*(ns: Namespace, module_name: string, ctx: CliPackageContext) =
  ns["__module_name__".to_key()] = module_name.to_value()
  ns["__is_main__".to_key()] = TRUE
  ns["gene".to_key()] = App.app.gene_ns
  ns["genex".to_key()] = App.app.genex_ns
  let package_name = if ctx.enabled: ctx.name else: ""
  let package_root = if ctx.enabled: ctx.root else: ""
  bind_module_package_context(ns, module_name, package_name, package_root)
  let pkg_value = package_value_for_module(module_name, package_name, package_root)
  if pkg_value.kind == VkPackage and pkg_value.ref.pkg != nil:
    App.app.pkg = pkg_value.ref.pkg
  App.app.gene_ns.ref.ns["main_module".to_key()] = module_name.to_value()
