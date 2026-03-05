import os, strutils
import std/json as nim_json

import ../types
import ./json

const GdatHeader = "#< gdat 1.0 >#\n"

proc init_gdat_namespace*() =
  proc gdat_save_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 2:
      not_allowed("gdat/save expects value and path")

    let data = get_positional_arg(args, 0, has_keyword_args)
    let path_val = get_positional_arg(args, 1, has_keyword_args)
    if path_val.kind != VkString:
      not_allowed("gdat/save path must be a string")

    let path = path_val.str
    let dir = splitFile(path).dir
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)

    let payload = value_to_json(data)
    writeFile(path, GdatHeader & payload)
    path_val

  proc gdat_load_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      not_allowed("gdat/load expects a path")

    let path_val = get_positional_arg(args, 0, has_keyword_args)
    if path_val.kind != VkString:
      not_allowed("gdat/load path must be a string")

    let content = readFile(path_val.str)
    if not content.startsWith(GdatHeader):
      not_allowed("Invalid .gdat file header (expected #< gdat 1.0 >#)")

    let payload = content[GdatHeader.len .. ^1]
    try:
      {.cast(gcsafe).}:
        parse_json_string(payload)
    except nim_json.JsonParsingError as e:
      raise new_exception(types.Exception, "Invalid gdat payload: " & e.msg)

  let gdat_ns = new_namespace("gdat")
  gdat_ns["save".to_key()] = NativeFn(gdat_save_native).to_value()
  gdat_ns["load".to_key()] = NativeFn(gdat_load_native).to_value()
  App.app.gene_ns.ns["gdat".to_key()] = gdat_ns.to_value()
  App.app.global_ns.ns["gdat".to_key()] = gdat_ns.to_value()
