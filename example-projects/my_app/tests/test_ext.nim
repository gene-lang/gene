import dynlib

import ../src/my_app

type
  test_dynamic = proc(s: string)

proc test_plugin(path:string) =
  let lib = loadLib(path)
  if lib != nil:
    let test = lib.symAddr("test")
    if test != nil:
      let test_impl = cast[test_dynamic](test)
      test_impl("Dynamic")
    unloadLib(lib)

echo "Testing direct call:"
test("Direct")

echo "Testing dynamic call:"
test_plugin("./libtest_ext.dylib")
