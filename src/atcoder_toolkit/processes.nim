import std/[os, osproc]

import ./errors

type
  CommandResult* = object
    output*: string
    exitCode*: int

  CommandRunner* = proc(executable: string, args: seq[string]): CommandResult {.closure.}

  # 入出力をターミナルにつないだまま実行し、終了コードを返す
  InteractiveLauncher* = proc(executable: string): int {.closure.}

proc runCommand*(executable: string, args: seq[string]): CommandResult =
  try:
    let command = quoteShellCommand(@[executable] & args)
    let response = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    result = CommandResult(output: response.output, exitCode: response.exitCode)
  except OSError as error:
    raise newException(
      ActkError,
      "コマンドを起動できません: " & executable & "\n" & error.msg
    )

proc launchInteractive*(executable: string): int =
  try:
    let process = startProcess(executable, options = {poParentStreams})
    defer: process.close()
    result = process.waitForExit()
  except OSError as error:
    raise newException(
      ActkError,
      "実行ファイルを起動できません: " & executable & "\n" & error.msg
    )

