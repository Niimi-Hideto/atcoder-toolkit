import std/[cmdline, os]

let args = commandLineParams()
let outputIndex = args.find("-o")
if outputIndex < 0 or outputIndex + 1 >= args.len:
  stderr.writeLine("missing -o")
  quit(2)

let fakeSolution = getEnv("ACKT_FAKE_SOLUTION")
if fakeSolution.len == 0 or not fileExists(fakeSolution):
  stderr.writeLine("ACKT_FAKE_SOLUTION is missing")
  quit(3)

copyFile(fakeSolution, args[outputIndex + 1])
echo "fake compile: OK"

