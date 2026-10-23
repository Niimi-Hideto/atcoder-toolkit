import std/[monotimes, os, osproc, times]

import ./errors

type
  CommandResult* = object
    output*: string
    exitCode*: int

  CommandRunner* = proc(executable: string, args: seq[string]): CommandResult {.closure.}

  # 入出力をターミナルにつないだまま実行し、終了コードを返す
  InteractiveLauncher* = proc(executable: string): int {.closure.}

  WarmUpRunner* = proc(executable, inputPath: string, timeoutSeconds: float) {.closure.}

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

# 新しく作った実行ファイルは、初回起動時にmacOSの確認が入って1件目の計測が遅くなる。
# テスト前に一度起動して、その確認を計測の外で済ませる。結果と出力は使わない。
proc warmUpExecutable*(executable, inputPath: string, timeoutSeconds: float) =
  when defined(windows):
    # cmd.exe経由では制限時間で確実に止められず、Windowsでは未検証のため行わない
    discard
  else:
    # execでシェルをプログラム自身に置き換え、制限時間を過ぎたら確実に止められるようにする
    let command = "exec " & quoteShell(executable) & " < " & quoteShell(inputPath) &
      " > /dev/null 2>&1"
    try:
      let process = startProcess(command, options = {poEvalCommand})
      defer: process.close()
      let deadline = getMonoTime() + initDuration(milliseconds = int(timeoutSeconds * 1000))
      while process.running and getMonoTime() < deadline:
        sleep(5)
      if process.running:
        process.kill()
        discard process.waitForExit()
    except OSError:
      discard

