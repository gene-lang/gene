import std/[os, strutils, tables, unittest]

import ../helpers
import gene/types except Exception
import gene/vm
import gene/vm/extension

proc extension_suffix(): string =
  when defined(macosx):
    ".dylib"
  elif defined(windows):
    ".dll"
  else:
    ".so"

proc gene_string_literal(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc mysql_smoke_enabled(): bool =
  getEnv("GENE_TEST_MYSQL") == "1"

suite "MySQL extension":
  test "build produces a MySQL extension artifact":
    init_all_with_extensions()
    check fileExists("build/libmysql" & extension_suffix())

  test "optional live smoke test":
    init_all_with_extensions()

    if mysql_smoke_enabled():
      let host = getEnv("GENE_TEST_MYSQL_HOST", "127.0.0.1")
      let port = parseInt(getEnv("GENE_TEST_MYSQL_PORT", "3306"))
      let user = getEnv("GENE_TEST_MYSQL_USER")
      let password = getEnv("GENE_TEST_MYSQL_PASSWORD")
      let database = getEnv("GENE_TEST_MYSQL_DATABASE")

      if user.len == 0 or database.len == 0:
        fail()
      else:
        let ns = load_extension(VM, "build/libmysql")
        check ns.name == "mysql"
        check ns.members.hasKey("open".to_key())

        let code =
          "(var db (genex/mysql/open " & gene_string_literal(host) & " " &
            gene_string_literal(user) & " " & gene_string_literal(password) & " " &
            gene_string_literal(database) & " ^port " & $port & "))\n" &
          """
          (db .exec "create temporary table gene_mysql_ext_test (id int, name varchar(32))")
          (db .exec "insert into gene_mysql_ext_test (id, name) values (?, ?)" 1 "Alice")
          (var rows (db .query "select name from gene_mysql_ext_test where id = ?" 1))
          (db .close)
          rows
          """
        let result = VM.exec(code, "genex_mysql_live.gene")
        check result.kind == VkArray
        check array_data(result).len == 1
        check array_data(array_data(result)[0])[0].str == "Alice"
    else:
      check true
