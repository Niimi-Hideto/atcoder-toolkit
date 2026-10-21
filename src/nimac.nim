import std/[os, strutils]

import nimac/[errors, workflow]

const Usage = """
nimac - AtCoder sample runner

Usage:
  nimac test <solution.cpp> [--url <AtCoder problem URL>] [--verbose]

Examples:
  nimac test ABC_A/A484.cpp
  nimac test main.cpp --url https://atcoder.jp/contests/abc484/tasks/abc484_a
"""

type
  CliOptions = object
    sourcePath: string
    url: string
    verbose: bool

proc parseOptions(args: seq[string]): CliOptions =
  if args.len == 0 or args[0] in ["-h", "--help", "help"]:
    echo Usage
    quit(0)
  if args[0] != "test":
    raise newException(NimacError, "未対応のコマンドです: " & args[0] & "\n\n" & Usage)
  if args.len < 2:
    raise newException(NimacError, "C++ファイルを指定してください\n\n" & Usage)

  result.sourcePath = args[1]
  var index = 2
  while index < args.len:
    let argument = args[index]
    if argument == "--url":
      if index + 1 >= args.len:
        raise newException(NimacError, "--url の後に問題URLを指定してください")
      result.url = args[index + 1]
      inc index, 2
    elif argument.startsWith("--url="):
      result.url = argument[6 .. ^1]
      inc index
    elif argument == "--verbose":
      result.verbose = true
      inc index
    else:
      raise newException(NimacError, "不明な引数です: " & argument)

proc main() =
  try:
    let options = parseOptions(commandLineParams())
    if not runWorkflow(options.sourcePath, options.url, verbose = options.verbose):
      quit(1)
  except NimacError as error:
    stderr.writeLine("[error] " & error.msg)
    quit(1)
  except CatchableError as error:
    stderr.writeLine("[error] 予期しないエラー: " & error.msg)
    quit(1)

when isMainModule:
  main()

