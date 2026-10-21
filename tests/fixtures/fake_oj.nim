import std/[cmdline, os, osproc, strutils]

proc optionValue(args: seq[string], optionName: string): string =
  let index = args.find(optionName)
  if index < 0 or index + 1 >= args.len:
    stderr.writeLine("missing " & optionName)
    quit(2)
  args[index + 1]

let args = commandLineParams()
if args.len == 0:
  stderr.writeLine("missing command")
  quit(2)

let logPath = getEnv("NIMAC_FAKE_OJ_LOG")
if logPath.len > 0:
  var logFile = open(logPath, fmAppend)
  defer: logFile.close()
  logFile.writeLine(args.join("\t"))

case args[0]
of "download":
  let testDir = optionValue(args, "-d")
  createDir(testDir)
  writeFile(testDir / "sample-1.in", "41\n")
  writeFile(testDir / "sample-1.out", "42\n")
  echo "fake download: 1 sample"
of "test":
  let testDir = optionValue(args, "-d")
  let command = optionValue(args, "-c")
  let inputText = readFile(testDir / "sample-1.in")
  let expected = readFile(testDir / "sample-1.out").strip()
  let processResult = execCmdEx(command, input = inputText)
  let actual = processResult.output.strip()
  if processResult.exitCode != 0:
    stderr.writeLine("solution exited with " & $processResult.exitCode)
    quit(3)
  if actual != expected:
    stderr.writeLine("expected: " & expected)
    stderr.writeLine("actual: " & actual)
    quit(1)
  echo "fake test: 1/1 passed"
else:
  stderr.writeLine("unsupported command: " & args[0])
  quit(2)

