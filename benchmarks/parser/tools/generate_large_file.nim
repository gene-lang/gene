import random, strutils, times, os, strformat

# Gene Code Pattern Generator for Large File Testing
# Generates realistic Gene source files with various constructs

type
  CodePattern = enum
    cpFunctionDefinition
    cpVariableDeclaration
    cpDataStructures
    cpComments
    cpComplexExpressions
    cpClassDefinitions
    cpControlFlow
    cpModuleImports

  GeneratorConfig = object
    target_lines: int
    complexity_level: int  # 1-5, higher means more complex patterns
    output_file: string
    seed: int

  CodeGenerator = ref object
    config: GeneratorConfig
    current_lines: int
    output: File
    rng: Rand

proc initCodeGenerator(config: GeneratorConfig): CodeGenerator =
  result = CodeGenerator(
    config: config,
    current_lines: 0,
    rng: initRand(config.seed)
  )
  result.output = open(config.output_file, fmWrite)

proc addLine(gen: CodeGenerator, line: string) =
  gen.output.writeLine(line)
  inc(gen.current_lines)

proc addComment(gen: CodeGenerator, comment: string) =
  gen.addLine("# " & comment)

proc generateFunctionDefinition(gen: CodeGenerator) =
  let functions = [
    "calculate_sum",
    "process_data",
    "validate_input",
    "transform_value",
    "handle_result",
    "compute_metrics",
    "filter_results",
    "merge_collections",
    "parse_arguments",
    "format_output"
  ]

  let args = [
    "x y",
    "data options",
    "input validation_rules",
    "value transform_fn",
    "result handler",
    "metrics config",
    "items predicate",
    "left right",
    "args flags",
    "data format"
  ]

  let func_name = gen.rng.sample(functions)
  let func_args = gen.rng.sample(args)

  # Simple function body based on complexity
  let body = case gen.config.complexity_level:
    of 1: "  (+ x y)"
    of 2: "  (if (> x 0) (* x 2) (- y 1))"
    of 3: """
    (var temp x)
    (when (> y 0)
      (temp = (* temp y))
    )
    temp"""
    of 4: """
    (var result x)
    (var i 0)
    (while (< i y)
      (result = (+ result i))
      (i = (+ i 1)))
    result"""
    of 5: """
    (var result x)
    (var acc 1)
    (case y
      0 (result = 1)
      1 (acc = result)
      else
        (var i 2)
        (while (<= i y)
          (acc = (* acc i))
          (i = (+ i 1)))
        (result = acc))
    result"""
    else: "  (+ x y)"

  gen.addLine(fmt"(fn {func_name} [{func_args}]")
  for line in body.strip.splitLines:
    gen.addLine(line)
  gen.addLine(")")

proc generateVariableDeclaration(gen: CodeGenerator) =
  let var_names = [
    "count", "total", "result", "data", "items", "index", "value", "temp", "buffer", "cache"
  ]
  let var_name = gen.rng.sample(var_names)

  let values = case gen.config.complexity_level:
    of 1: "0"
    of 2: $gen.rng.rand(1..100)
    of 3: "[" & $gen.rng.rand(1..10) & " " & $gen.rng.rand(1..10) & " " & $gen.rng.rand(1..10) & "]"
    of 4: "^{:count " & $gen.rng.rand(1..10) & " :name \"test\"}"
    of 5: "(parse_data (get_input) ^{:mode \"strict\"})"
    else: $gen.rng.rand(1..100)

  gen.addLine(fmt"(var {var_name} {values})")

proc generateDataStructures(gen: CodeGenerator) =
  let structures = case gen.config.complexity_level:
    of 1:
      [ "[1 2 3 4 5]",
        "{\"a\" 1 \"b\" 2}",
        "(:simple :data)" ]
    of 2:
      [ "[10 20 30 40 50 60]",
        "{:count 100 :name \"test\" :active true}",
        "(:complex :data :structure)" ]
    of 3:
      [ "[1 2 3 [4 5 6] [7 8 9]]",
        "{:users [{{:name \"Alice\" :age 30}} {{:name \"Bob\" :age 25}}] :count 2}",
        "(:nested (:data (:with :multiple :levels)) )" ]
    of 4:
      [ "[{1 2 3} {4 5 6} {7 8 9}]",
        "{:config {{:database \"localhost\" :port 5432}} :cache {{:ttl 300 :size 100}}}",
        "(:level1 (:level2 (:level3 (:level4 \"deep\"))))" ]
    of 5:
      [ "[{:id 1 :data {:nested {:deep {:value \"complex\"}}}}]",
        "{:functions [(fn [x] (* x 2)) (fn [y] (+ y 3))] :metadata {:version \"1.0\"}}",
        "(:root (:branch (:leaf \"item\") (:leaf \"item2\")) (:branch (:leaf \"item3\")))" ]
    else: ["[1 2 3]", "{:a 1}", "(:simple)"]

  let structure = gen.rng.sample(structures)
  gen.addLine(fmt"(var data_{gen.current_lines} {structure})")

proc generateComments(gen: CodeGenerator) =
  let comments = [
    "Utility function for data processing",
    "TODO: Add error handling",
    "FIXME: Optimize this algorithm",
    "NOTE: This should be moved to a separate module",
    "WARNING: Experimental feature",
    "Performance critical section",
    "Temporary workaround for issue #123",
    "Legacy code - consider refactoring",
    "Generated code - do not modify manually",
    "Debug information - remove in production"
  ]

  let comment = gen.rng.sample(comments)
  gen.addComment(comment)

proc generateComplexExpressions(gen: CodeGenerator) =
  let expressions = case gen.config.complexity_level:
    of 1:
      [ "(+ 1 2)",
        "(* 3 4)",
        "(- 10 5)" ]
    of 2:
      [ "(+ (* 2 3) (/ 10 2))",
        "(if (> x 0) \"positive\" \"negative\")",
        "(concat \"hello\" \" world\")" ]
    of 3:
      [ "(reduce + (map (fn [x] (* x 2)) [1 2 3 4 5]))",
        "(filter (fn [x] (> x 5)) (range 1 20))",
        "(apply + (map (fn [x] (pow x 2)) [1 2 3 4]))" ]
    of 4:
      [ "(let [data (parse-json input)] (get data \"results\" 0))",
        "(pipe data (map transform) (filter valid) (reduce +))",
        "(match pattern {:success result} result {:error msg} (handle-error msg))" ]
    of 5:
      [ "(async (let [result (await (fetch-data))] (process result)))",
        "(comp (filter valid) (map transform) (sort-by :id) (take 10))",
        "(with-resource conn (db-connect) (query conn sql) (process-results))" ]
    else: ["(+ 1 1)", "(+ 2 2)", "(+ 3 3)"]

  let expr = gen.rng.sample(expressions)
  gen.addLine(expr)

proc generateClassDefinitions(gen: CodeGenerator) =
  let classes = [
    "Person",
    "Account",
    "Document",
    "Configuration",
    "EventHandler"
  ]

  let class_name = gen.rng.sample(classes)

  let methods = [
    "get_name", "set_value", "is_valid", "to_string",
    "clone", "equals", "serialize", "deserialize",
    "validate", "transform", "merge"
  ]
  let method_count = case gen.config.complexity_level:
    of 1: 2
    of 2: 4
    of 3: 6
    of 4: 8
    of 5: 11
    else: 2

  gen.output.writeLine(fmt"(class {class_name}")
  for i in 0..<method_count:
    let method_name = methods[i]
    gen.output.writeLine(fmt"  (def {method_name} [self] \"TODO: implement\")")
    inc(gen.current_lines)
  gen.output.writeLine(")")
  inc(gen.current_lines)

proc generateControlFlow(gen: CodeGenerator) =
  let patterns = case gen.config.complexity_level:
    of 1:
      [ """
(if (> x 0)
  "positive"
  "negative")""" ]
    of 2:
      [ """
(case type
  "string" (length value)
  "number" (round value)
  else (str value))""",
        """
(when (valid? input)
  (process input)
  (save result))""" ]
    of 3:
      [ """
(try
  (risky-operation data)
catch error
  (log-error error)
  (return nil))""",
        """
(loop [items data result []]
  (if (empty? items)
    result
    (recur (rest items) (conj result (process (first items))))))""" ]
    of 4:
      [ """
(cond
  (and (> x 0) (< x 10)) (small-number x)
  (>= x 10) (large-number x)
  (zero? x) 0
  else (error \"Invalid number\"))""",
        """
(when-let [data (fetch-data id)
           result (process data)]
  (save result)
  (notify-success result))""" ]
    of 5:
      [ """
(async (let [data (await (fetch-api url))
                processed (transform data)
                validated (validate processed)]
          (if (success? validated)
            (do (save validated) (notify-success))
            (throw (error \"Validation failed\")))))""",
        """
(with-transaction [tx (begin-transaction)]
  (try
    (save-data tx data1)
    (save-data tx data2)
    (commit tx)
  catch error
    (rollback tx)
    (throw error)))""" ]
    else: ["(if true \"yes\" \"no\")", "(+ 1 2)", "(println \"hello\")"]

  let pattern = gen.rng.sample(patterns)
  for line in pattern.strip.splitLines:
    gen.addLine(line)

proc generateModuleImports(gen: CodeGenerator) =
  let modules = [
    "utils/string",
    "utils/math",
    "data/collections",
    "io/file",
    "async/http",
    "database/sql"
  ]

  let module_name = gen.rng.sample(modules)
  let alias = module_name.split('/')[1]
  gen.addLine(fmt"(import {module_name} as {alias})")

proc generateRandomConstruct(gen: CodeGenerator) =
  let construct_type = gen.rng.rand(1..8)

  case construct_type
  of 1: gen.generateFunctionDefinition()
  of 2: gen.generateVariableDeclaration()
  of 3: gen.generateDataStructures()
  of 4: gen.generateComments()
  of 5: gen.generateComplexExpressions()
  of 6: gen.generateClassDefinitions()
  of 7: gen.generateControlFlow()
  of 8: gen.generateModuleImports()
  else: gen.generateVariableDeclaration()

proc generateFile(config: GeneratorConfig) =
  echo fmt"Generating {config.target_lines} lines of Gene code with complexity {config.complexity_level}..."

  let gen = initCodeGenerator(config)

  # Add header comment
  gen.addComment(fmt"Generated large Gene file for parsing benchmark")
  gen.addComment(fmt"Target lines: {config.target_lines}")
  gen.addComment(fmt"Complexity level: {config.complexity_level}")
  gen.addComment(fmt"Generated: {now()}")
  gen.addLine("")

  # Generate content
  while gen.current_lines < config.target_lines:
    gen.generateRandomConstruct()

    # Add occasional blank lines for readability
    if gen.rng.rand(10) == 0:
      gen.addLine("")

  gen.output.close()

  echo fmt"Generated {gen.current_lines} lines in {config.output_file}"
  echo fmt"File size: {getFileSize(config.output_file)} bytes"

proc main() =
  let args = commandLineParams()

  if args.len < 2:
    echo "Usage: generate_large_file <lines> <output_file> [complexity_level] [seed]"
    echo "Example: generate_large_file 50000 test_50k.gene 3 42"
    quit(1)

  let target_lines = parseInt(args[0])
  let output_file = args[1]
  let complexity_level = if args.len > 2: parseInt(args[2]) else: 3
  let seed = if args.len > 3: parseInt(args[3]) else: epochTime().int

  let config = GeneratorConfig(
    target_lines: target_lines,
    complexity_level: complexity_level.clamp(1, 5),
    output_file: output_file,
    seed: seed
  )

  generateFile(config)

when isMainModule:
  main()