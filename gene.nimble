# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "Gene - a general purpose language"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
installExt    = @["nim"]
bin           = @["gene"]

# Dependencies
requires "nim >= 1.4.0"
requires "db_connector"

task speedy, "Optimized build for maximum performance":
  exec "nim c -d:release --mm:orc --opt:speed --passC:\"-march=native -O3\" -o:gene src/gene.nim"

task bench, "Build and run benchmarks":
  exec "nim c -d:release --mm:orc --opt:speed --passC:\"-march=native\" -r bench/run_benchmarks.nim"

task buildext, "Build extension modules":
  exec "mkdir -p build"
  exec "nim c --app:lib -d:release --mm:orc -o:build/libhttp.dylib src/genex/http.nim"
  exec "nim c --app:lib -d:release --mm:orc -o:build/libsqlite.dylib src/genex/sqlite.nim"

task testcore, "Runs the test suite":
  exec "nim c -r tests/test_types.nim"
  exec "nim c -r tests/test_parser.nim"
  exec "nim c -r tests/test_parser_interpolation.nim"

task test, "Runs the test suite":
  exec "nim c -r tests/test_basic.nim"
  exec "nim c -r tests/test_scope.nim"
  exec "nim c -r tests/test_symbol.nim"
  exec "nim c -r tests/test_repeat.nim"
  exec "nim c -r tests/test_for.nim"
  # exec "nim c -r tests/test_case.nim"
  exec "nim c -r tests/test_enum.nim"
  exec "nim c -r tests/test_arithmetic.nim"
  exec "nim c -r tests/test_exception.nim"
  exec "nim c -r tests/test_fp.nim"
  exec "nim c -r tests/test_block.nim"
  exec "nim c -r tests/test_function_optimization.nim"
  exec "nim c -r tests/test_namespace.nim"
  exec "nim c -r tests/test_oop.nim"
  # exec "nim c -r tests/test_cast.nim"
  exec "nim c -r tests/test_pattern_matching.nim"
  exec "nim c -r tests/test_macro.nim"
  exec "nim c -r tests/test_async.nim"
  exec "nim c -r tests/test_module.nim"
  # exec "nim c -r tests/test_package.nim"
  exec "nim c -r tests/test_selector.nim"
  exec "nim c -r tests/test_template.nim"
  # exec "nim c -r tests/test_serdes.nim"
  exec "nim c -r tests/test_native.nim"
  exec "nim c -r tests/test_ext.nim"
  # exec "nim c -r tests/test_metaprogramming.nim"
  # exec "nim c -r tests/test_array_like.nim"
  # exec "nim c -r tests/test_map_like.nim"
  exec "nim c -r tests/test_stdlib.nim"
  exec "nim c -r tests/test_stdlib_class.nim"
  exec "nim c -r tests/test_stdlib_string.nim"
  exec "nim c -r tests/test_stdlib_array.nim"
  exec "nim c -r tests/test_stdlib_map.nim"
  exec "nim c -r tests/test_stdlib_gene.nim"
  exec "nim c -r tests/test_stdlib_regex.nim"
  exec "nim c -r tests/test_stdlib_json.nim"
  # exec "nim c -r tests/test_stdlib_os.nim"
  # exec "nim c -r tests/test_custom_compiler.nim"
  # exec "nim c -r tests/test_ffi.nim"
