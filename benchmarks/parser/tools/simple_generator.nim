import random, strutils, times, os, strformat

# Simple Gene file generator for benchmarking

proc generateGeneFile(lines: int, output: string) =
  let file = open(output, fmWrite)

  # Header
  file.writeLine("# Generated Gene file for parsing benchmark")
  file.writeLine(fmt"# Target lines: {lines}")
  file.writeLine(fmt"# Generated: {now()}")
  file.writeLine("")

  var current_lines = 4

  let patterns = [
    "(var count 0)",
    "(var data [1 2 3 4 5])",
    "(fn add [x y] (+ x y))",
    "(if (> count 0) \"positive\" \"negative\")",
    "(println \"Hello, Gene!\")",
    "(var config {:name \"test\" :enabled true})",
    "(class Person)",
    "(def get_name [self] \"default\")",
    "(map (fn [x] (* x 2)) [1 2 3 4 5])",
    "(filter (fn [x] (> x 5)) [1 2 3 4 5 6 7 8 9 10])"
  ]

  var rng = initRand(42)

  while current_lines < lines:
    let pattern = rng.sample(patterns)
    file.writeLine(pattern)
    inc(current_lines)

    # Add occasional comments
    if rng.rand(20) == 0:
      file.writeLine("# Random comment")
      inc(current_lines)

  file.close()
  echo fmt"Generated {current_lines} lines in {output}"
  echo fmt"File size: {getFileSize(output)} bytes"

proc main() =
  let args = commandLineParams()

  if args.len != 2:
    echo "Usage: simple_generator <lines> <output_file>"
    echo "Example: simple_generator 10000 test.gene"
    quit(1)

  let lines = parseInt(args[0])
  let output = args[1]

  generateGeneFile(lines, output)

when isMainModule:
  main()