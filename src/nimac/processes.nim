import std/[os, osproc]

import ./errors

type
  CommandResult* = object
    output*: string
    exitCode*: int

  CommandRunner* = proc(executable: string, args: seq[string]): CommandResult {.closure.}

proc runCommand*(executable: string, args: seq[string]): CommandResult =
  try:
    let command = quoteShellCommand(@[executable] & args)
    let response = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    result = CommandResult(output: response.output, exitCode: response.exitCode)
  except OSError as error:
    raise newException(
      NimacError,
      "コマンドを起動できません: " & executable & "\n" & error.msg
    )

