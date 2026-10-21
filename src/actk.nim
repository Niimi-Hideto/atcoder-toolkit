import std/[os, strutils]

import atcoder_toolkit/[errors, initializer, workflow]

const Usage = """
AtCoderToolKit

Usage:
  actk init <ABC contest number>
  actk test <solution.cpp> [--url <AtCoder problem URL>] [--tl <seconds>]
                           [--error <tolerance>] [--verbose]
  actk run <solution.cpp> [--verbose]

Examples:
  actk init 484
  actk test ABC_A/A484.cpp
  actk run ABC_A/A484.cpp
  actk test ABC_C/C484.cpp --tl 3
  actk test ABC_B/B484.cpp --error 1e-6
  actk test main.cpp --url https://atcoder.jp/contests/abc484/tasks/abc484_a
"""

type
  CommandKind = enum
    commandInit,
    commandTest,
    commandRun

  CliOptions = object
    command: CommandKind
    contest: string
    sourcePath: string
    url: string
    timeLimitSeconds: float
    errorTolerance: float
    verbose: bool

proc isOption(argument, name: string): bool =
  argument == name or argument.startsWith(name & "=")

proc takeOptionValue(args: seq[string], index: var int, name, hint: string): string =
  let argument = args[index]
  if argument == name:
    if index + 1 >= args.len:
      raise newException(ActkError, name & " の後に" & hint & "を指定してください")
    result = args[index + 1]
    inc index, 2
  else:
    result = argument[name.len + 1 .. ^1]
    inc index

proc parsePositiveFloat(value, name: string): float =
  try:
    result = parseFloat(value)
  except ValueError:
    raise newException(ActkError, name & " には数値を指定してください: " & value)
  if result <= 0.0:
    raise newException(ActkError, name & " には0より大きい値を指定してください: " & value)

proc parseOptions(args: seq[string]): CliOptions =
  if args.len == 0 or args[0] in ["-h", "--help", "help"]:
    echo Usage
    quit(0)

  if args[0] == "init":
    if args.len < 2:
      raise newException(ActkError, "ABCのコンテスト番号を指定してください\n\n" & Usage)
    if args.len > 2:
      raise newException(ActkError, "initに不明な引数があります: " & args[2])
    result.command = commandInit
    result.contest = args[1]
    return

  case args[0]
  of "test": result.command = commandTest
  of "run": result.command = commandRun
  else:
    raise newException(ActkError, "未対応のコマンドです: " & args[0] & "\n\n" & Usage)
  if args.len < 2:
    raise newException(ActkError, "C++ファイルを指定してください\n\n" & Usage)
  if args[1].startsWith("--"):
    raise newException(
      ActkError,
      "オプションはC++ファイルの後ろに書いてください。例: actk " & args[0] & " ABC_A/A484.cpp " & args[1]
    )

  result.sourcePath = args[1]
  var index = 2
  while index < args.len:
    let argument = args[index]
    if result.command == commandRun and argument != "--verbose":
      raise newException(ActkError, "runで使えるオプションは --verbose だけです: " & argument)
    if argument.isOption("--url"):
      result.url = takeOptionValue(args, index, "--url", "問題URL")
    elif argument.isOption("--tl"):
      let value = takeOptionValue(args, index, "--tl", "制限時間（秒）")
      result.timeLimitSeconds = parsePositiveFloat(value, "--tl")
    elif argument.isOption("--error"):
      let value = takeOptionValue(args, index, "--error", "許容誤差")
      result.errorTolerance = parsePositiveFloat(value, "--error")
    elif argument == "--verbose":
      result.verbose = true
      inc index
    else:
      raise newException(ActkError, "不明な引数です: " & argument)

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
      var config = defaultWorkflowConfig()
      if options.timeLimitSeconds > 0.0:
        config.timeLimitSeconds = options.timeLimitSeconds
      config.errorTolerance = options.errorTolerance
      if not runWorkflow(options.sourcePath, options.url, config, verbose = options.verbose):
        quit(1)
    of commandRun:
      if not runInteractive(options.sourcePath, verbose = options.verbose):
        quit(1)
  except ActkError as error:
    stderr.writeLine("[error] " & error.msg)
    quit(1)
  except CatchableError as error:
    stderr.writeLine("[error] 予期しないエラー: " & error.msg)
    quit(1)

when isMainModule:
  main()

