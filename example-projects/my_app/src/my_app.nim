{.push dynlib exportc.}

proc test*(s: string) =
  echo "test_app/src/test_ext.nim:"
  echo s
  echo "Done."

{.pop.}
