import std/[os, tables]

import ../parser
import ../types except Exception

type
  PackageManifestError* = object of CatchableError

  PackageDependencySpec* = object
    name*: string
    version_expr*: string
    path*: string
    git*: string
    commit*: string
    tag*: string
    branch*: string
    subdir*: string

  PackageManifest* = object
    package_root*: string
    name*: string
    version*: string
    license*: string
    homepage*: string
    source_dir*: string
    main_module*: string
    test_dir*: string
    globals*: seq[string]
    singleton*: bool
    native*: bool
    native_build*: seq[string]
    dependencies*: seq[PackageDependencySpec]
    props*: Table[Key, Value]

proc package_manifest_error(msg: string) {.noreturn.} =
  raise newException(PackageManifestError, msg)

proc key_to_symbol_name*(k: Key): string =
  get_symbol(symbol_index(k))

proc normalize_manifest_key(raw: string): string =
  if raw.len > 0 and raw[0] == '^':
    raw[1 .. ^1]
  else:
    raw

proc value_as_string*(v: Value, context: string): string =
  case v.kind
  of VkString, VkSymbol:
    v.str
  else:
    package_manifest_error(context & ": expected string/symbol, got " & $v.kind)

proc value_as_bool*(v: Value): bool =
  case v.kind
  of VkBool:
    v == TRUE
  of VkInt:
    v.to_int() != 0
  else:
    false

proc value_as_string_array*(v: Value, context: string): seq[string] =
  if v.kind != VkArray:
    package_manifest_error(context & ": expected array, got " & $v.kind)
  for item in array_data(v):
    result.add(value_as_string(item, context))

proc init_package_manifest*(package_root: string): PackageManifest =
  PackageManifest(
    package_root: package_root,
    source_dir: "src",
    main_module: "index",
    test_dir: "tests",
    props: initTable[Key, Value]()
  )

proc parse_dependency(item: Value, context: string): PackageDependencySpec =
  if item.kind != VkGene or item.gene.type.kind != VkSymbol or item.gene.type.str != "$dep":
    package_manifest_error(context & " ^dependencies: expected ($dep ...), got " & $item)
  if item.gene.children.len < 1:
    package_manifest_error(context & " ^dependencies: $dep requires package name")

  result.name = value_as_string(item.gene.children[0], context & " dependency name")
  if item.gene.children.len >= 2:
    result.version_expr = value_as_string(item.gene.children[1], context & " dependency version")

  for k, v in item.gene.props:
    let prop = normalize_manifest_key(key_to_symbol_name(k))
    case prop
    of "path":
      result.path = value_as_string(v, context & " dependency ^path")
    of "git":
      result.git = value_as_string(v, context & " dependency ^git")
    of "commit":
      result.commit = value_as_string(v, context & " dependency ^commit")
    of "tag":
      result.tag = value_as_string(v, context & " dependency ^tag")
    of "branch":
      result.branch = value_as_string(v, context & " dependency ^branch")
    of "subdir":
      result.subdir = value_as_string(v, context & " dependency ^subdir")
    else:
      discard

proc apply_manifest_pair(manifest: var PackageManifest, raw_key: string, value: Value, context: string) =
  let key = normalize_manifest_key(raw_key)
  manifest.props[key.to_key()] = value

  case key
  of "name":
    manifest.name = value_as_string(value, context & " ^name")
  of "version":
    manifest.version = value_as_string(value, context & " ^version")
  of "license":
    manifest.license = value_as_string(value, context & " ^license")
  of "homepage":
    manifest.homepage = value_as_string(value, context & " ^homepage")
  of "source-dir", "src-path":
    manifest.source_dir = value_as_string(value, context & " ^source-dir")
  of "main-module":
    manifest.main_module = value_as_string(value, context & " ^main-module")
  of "test-dir", "test-path":
    manifest.test_dir = value_as_string(value, context & " ^test-dir")
  of "globals":
    manifest.globals = value_as_string_array(value, context & " ^globals")
  of "singleton":
    manifest.singleton = value_as_bool(value)
  of "native":
    manifest.native = value_as_bool(value)
  of "native-build":
    manifest.native_build = value_as_string_array(value, context & " ^native-build")
  of "dependencies":
    if value.kind != VkArray:
      package_manifest_error(context & " ^dependencies: expected array, got " & $value.kind)
    for item in array_data(value):
      manifest.dependencies.add(parse_dependency(item, context))
  else:
    discard

proc parse_package_manifest*(path: string, package_root: string): PackageManifest =
  if not fileExists(path):
    package_manifest_error("Manifest not found: " & path)

  result = init_package_manifest(package_root)
  let nodes = read_all(readFile(path))
  if nodes.len == 0:
    return

  if nodes.len == 1 and nodes[0].kind == VkMap:
    for k, v in map_data(nodes[0]):
      apply_manifest_pair(result, key_to_symbol_name(k), v, path)
    return

  var i = 0
  while i < nodes.len:
    let key_node = nodes[i]
    if key_node.kind == VkSymbol:
      if i + 1 >= nodes.len:
        package_manifest_error(path & ": missing value for key " & key_node.str)
      apply_manifest_pair(result, key_node.str, nodes[i + 1], path)
      i += 2
    else:
      inc(i)

proc try_parse_package_manifest*(path: string, package_root: string): tuple[ok: bool, manifest: PackageManifest, error: string] =
  try:
    result = (true, parse_package_manifest(path, package_root), "")
  except CatchableError as e:
    result = (false, init_package_manifest(package_root), e.msg)

proc find_package_root*(start: string): string =
  var dir = absolutePath(start)
  if fileExists(dir):
    dir = parentDir(dir)
  while dir.len > 0:
    if fileExists(joinPath(dir, "package.gene")):
      return dir
    let parent = parentDir(dir)
    if parent.len == 0 or parent == dir:
      break
    dir = parent
  return ""
