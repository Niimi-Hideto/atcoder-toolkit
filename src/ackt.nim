import std/[os, strutils]

import atcoder_toolkit/[errors, initializer, workflow]

const Usage = """
ackt - AtCoder Toolkit

Usage:
  ackt init <ABC contest number>
  ackt test <solution.cpp> [--url <AtCoder problem URL>] [--verbose]

Examples:
  ackt init 484
  ackt test ABC_A/A484.cpp
  ackt test main.cpp --url https://atcoder.jp/contests/abc484/tasks/abc484_a
"""

type
  CommandKind = enum
    commandInit,
    commandTest

  CliOptions = object
    command: CommandKind
    contest: string
    sourcePath: string
    url: string
    verbose: bool

proc parseOptions(args: seq[string]): CliOptions =
  if args.len == 0 or args[0] in ["-h", "--help", "help"]:
    echo Usage
    quit(0)

  if args[0] == "init":
    if args.len < 2:
      raise newException(AcktError, "ABCのコンテスト番号を指定してください\n\n" & Usage)
    if args.len > 2:
      raise newException(AcktError, "initに不明な引数があります: " & args[2])
    result.command = commandInit
    result.contest = args[1]
    return

  if args[0] != "test":
    raise newException(AcktError, "未対応のコマンドです: " & args[0] & "\n\n" & Usage)
  if args.len < 2:
    raise newException(AcktError, "C++ファイルを指定してください\n\n" & Usage)

  result.command = commandTest
  result.sourcePath = args[1]
  var index = 2
  while index < args.len:
    let argument = args[index]
    if argument == "--url":
      if index + 1 >= args.len:
        raise newException(AcktError, "--url の後に問題URLを指定してください")
      result.url = args[index + 1]
      inc index, 2
    elif argument.startsWith("--url="):
      result.url = argument[6 .. ^1]
      inc index
    elif argument == "--verbose":
      result.verbose = true
      inc index
    else:
      raise newException(AcktError, "不明な引数です: " & argument)

proc main() =
  try:
    let options = parseOptions(commandLineParams())
    case options.command
    of commandInit:
      let initResult = initializeContest(options.contest)
      echo "contest  " & initResult.contestId
      for path in initResult.created:
        echo "created  " & path
      for path in initResult.skipped:
        echo "skipped  " & path & "  (already exists)"
      echo ""
      echo "READY  " & $initResult.created.len & " created, " &
        $initResult.skipped.len & " skipped"
    of commandTest:
      if not runWorkflow(options.sourcePath, options.url, verbose = options.verbose):
        quit(1)
  except AcktError as error:
    stderr.writeLine("[error] " & error.msg)
    quit(1)
  except CatchableError as error:
    stderr.writeLine("[error] 予期しないエラー: " & error.msg)
    quit(1)

when isMainModule:
  main()

