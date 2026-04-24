import std/[os, strutils, tables, tempfiles, unittest]

import gene/types except Exception
import gene/vm/module
import gene/vm/package_manifest

proc write_manifest(path: string, content: string) =
  createDir(parentDir(path))
  writeFile(path, content)

suite "Package manifest":
  test "flat package manifest parses MVP fields":
    let root = createTempDir("gene_manifest_flat_", "")
    defer:
      if dirExists(root):
        removeDir(root)

    write_manifest(root / "package.gene", """
^name "x/app"
^version "1.2.3"
^license "MIT"
^homepage "https://example.invalid/app"
^source-dir "lib"
^main-module "boot"
^test-dir "spec"
^globals ["cache"]
^singleton true
^native true
^native-build ["make"]
^dependencies []
""")

    let manifest = parse_package_manifest(root / "package.gene", root)
    check manifest.package_root == root
    check manifest.name == "x/app"
    check manifest.version == "1.2.3"
    check manifest.license == "MIT"
    check manifest.homepage == "https://example.invalid/app"
    check manifest.source_dir == "lib"
    check manifest.main_module == "boot"
    check manifest.test_dir == "spec"
    check manifest.globals == @["cache"]
    check manifest.singleton
    check manifest.native
    check manifest.native_build == @["make"]
    check manifest.props.hasKey("source-dir".to_key())
    check manifest.props.hasKey("main-module".to_key())

  test "map package manifest parses MVP fields":
    let root = createTempDir("gene_manifest_map_", "")
    defer:
      if dirExists(root):
        removeDir(root)

    write_manifest(root / "package.gene", """
{
  ^name "x/map"
  ^version "2.0.0"
  ^license "Apache-2.0"
  ^homepage "https://example.invalid/map"
  ^source-dir "source"
  ^main-module "entry"
  ^test-dir "checks"
  ^dependencies []
}
""")

    let manifest = parse_package_manifest(root / "package.gene", root)
    check manifest.name == "x/map"
    check manifest.version == "2.0.0"
    check manifest.license == "Apache-2.0"
    check manifest.homepage == "https://example.invalid/map"
    check manifest.source_dir == "source"
    check manifest.main_module == "entry"
    check manifest.test_dir == "checks"

  test "dependency declaration parses path source":
    let root = createTempDir("gene_manifest_dep_", "")
    defer:
      if dirExists(root):
        removeDir(root)

    write_manifest(root / "package.gene", """
^name "x/app"
^dependencies [
  ($dep "x/lib" "^1.0" ^path "./vendor/lib")
]
""")

    let manifest = parse_package_manifest(root / "package.gene", root)
    check manifest.dependencies.len == 1
    let dep = manifest.dependencies[0]
    check dep.name == "x/lib"
    check dep.version_expr == "^1.0"
    check dep.path == "./vendor/lib"

  test "malformed dependency declaration fails deterministically":
    let root = createTempDir("gene_manifest_bad_dep_", "")
    defer:
      if dirExists(root):
        removeDir(root)

    write_manifest(root / "package.gene", """
^name "x/app"
^dependencies [
  ($dep)
]
""")

    var failed = false
    try:
      discard parse_package_manifest(root / "package.gene", root)
    except PackageManifestError as e:
      failed = true
      check e.msg.contains("$dep requires package name")
    check failed

  test "package value uses manifest fields":
    let root = createTempDir("gene_manifest_pkg_value_", "")
    defer:
      if dirExists(root):
        removeDir(root)

    write_manifest(root / "package.gene", """
^name "x/runtime"
^version "0.5.0"
^license "BSD-2-Clause"
^homepage "https://example.invalid/runtime"
^source-dir "lib"
^main-module "main"
^test-dir "spec"
^dependencies []
""")

    let pkg_value = package_value_for_module(root / "lib" / "main.gene")
    check pkg_value.kind == VkPackage
    check pkg_value.ref.pkg.name == "x/runtime"
    check pkg_value.ref.pkg.version.kind == VkString
    check pkg_value.ref.pkg.version.str == "0.5.0"
    check pkg_value.ref.pkg.license.kind == VkString
    check pkg_value.ref.pkg.license.str == "BSD-2-Clause"
    check pkg_value.ref.pkg.homepage == "https://example.invalid/runtime"
    check pkg_value.ref.pkg.src_path == "lib"
    check pkg_value.ref.pkg.test_path == "spec"
    check pkg_value.ref.pkg.props["main-module".to_key()].str == "main"
