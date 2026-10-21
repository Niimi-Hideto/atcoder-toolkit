import std/[os, strutils, times, unittest]

import nimac/[errors, problem, processes, reporting, workflow]

suite "problem resolution":
  test "current ABC file convention is inferred":
    let problemInfo = inferProblem("ABC_C/C484.cpp")
    check problemInfo.contestId == "abc484"
    check problemInfo.taskId == "abc484_c"
    check problemInfo.url == "https://atcoder.jp/contests/abc484/tasks/abc484_c"

  test "explicit AtCoder URL is accepted":
    let problemInfo = validateAtCoderUrl(
      "https://atcoder.jp/contests/tessoku-book/tasks/tessoku_book_a"
    )
    check problemInfo.contestId == "tessoku-book"
    check problemInfo.taskId == "tessoku_book_a"

  test "non-AtCoder URL is rejected":
    expect NimacError:
      discard validateAtCoderUrl("https://example.com/contests/abc484/tasks/abc484_a")

suite "workflow":
  test "downloads once, then compiles and tests from cache":
    let tempRoot = getTempDir() / ("nimac-test-" & $getTime().toUnix())
    let sourceDir = tempRoot / "ABC_A"
    let sourcePath = sourceDir / "A999.cpp"
    createDir(tempRoot / ".git")
    createDir(sourceDir)
    writeFile(sourcePath, "int main() { return 0; }\n")

    var calls: seq[(string, seq[string])] = @[]
    let fakeRunner: CommandRunner = proc(executable: string, args: seq[string]): CommandResult =
      calls.add((executable, args))
      if executable == "fake-oj" and args.len > 0 and args[0] == "download":
        let directoryIndex = args.find("-d")
        check directoryIndex >= 0
        let testDir = args[directoryIndex + 1]
        createDir(testDir)
        writeFile(testDir / "sample-1.in", "1\n")
        writeFile(testDir / "sample-1.out", "1\n")
      elif executable == "fake-cxx":
        let outputIndex = args.find("-o")
        check outputIndex >= 0
        writeFile(args[outputIndex + 1], "fake executable")
      if executable == "fake-oj" and args.len > 0 and args[0] == "test":
        return CommandResult(
          output: "[INFO] sample-1\n[INFO] time: 0.006 sec\n[SUCCESS] AC\n",
          exitCode: 0
        )
      CommandResult(output: "", exitCode: 0)

    let config = WorkflowConfig(
      compiler: "fake-cxx",
      oj: "fake-oj",
      timeLimitSeconds: 2.0
    )
    check runWorkflow(sourcePath, config = config, runner = fakeRunner)
    check calls.len == 3
    check calls[0][0] == "fake-oj"
    check calls[0][1][0] == "download"
    check calls[1][0] == "fake-cxx"
    check calls[2][1][0] == "test"
    let expectedExecutable = tempRoot / ".nimac" / "build" / changeFileExt("A999", ExeExt)
    check fileExists(expectedExecutable)
    check fileExists(tempRoot / ".nimac" / "tests" / "abc999_a" / ".download-complete")

    calls.setLen(0)
    check runWorkflow(sourcePath, config = config, runner = fakeRunner)
    check calls.len == 2
    check calls[0][0] == "fake-cxx"
    check calls[1][1][0] == "test"

    removeDir(tempRoot)

suite "compact report":
  test "two-digit case counts align the current case number":
    var report = TestReport()
    for index in 1 .. 10:
      report.results.add(SampleResult(
        name: "sample-" & $index,
        verdict: verdictAc,
        seconds: 0.006
      ))
    let rendered = renderReport(report, 2.0)
    check "[ 1/10] AC" in rendered
    check "[10/10] AC" in rendered
    check "PASS  10/10  test time 60 ms" in rendered

  test "AC, WA, RE and TLE are parsed and rendered":
    let rawOutput = """
[INFO] online-judge-tools 11.5.1
[INFO] 4 cases found

[INFO] sample-1
[INFO] time: 0.006 sec
[SUCCESS] AC

[INFO] sample-2
[INFO] time: 0.007 sec
[FAILURE] WA
output:
Odd

expected:
Even

[INFO] sample-3
boom
[INFO] time: 0.012 sec
[FAILURE] RE: return code 3
output:
(empty)
expected:
42

[INFO] sample-4
[INFO] time: 2.013 sec
[FAILURE] TLE
output:
(empty)
expected:
42

[INFO] slowest: 2.013 sec  (for sample-4)
[FAILURE] test failed: 1 AC / 4 cases
"""
    let report = parseOjReport(rawOutput)
    check report.isComplete(4)
    check not report.allPassed()
    check report.results[0].verdict == verdictAc
    check report.results[1].verdict == verdictWa
    check report.results[2].verdict == verdictRe
    check report.results[3].verdict == verdictTle

    let rendered = renderReport(report, 2.0)
    check "[1/4] AC" in rendered
    check "[2/4] WA" in rendered
    check "expected: Even" in rendered
    check "got:      Odd" in rendered
    check "[3/4] RE" in rendered
    check "exit code: 3" in rendered
    check "stderr: boom" in rendered
    check "[4/4] TLE" in rendered
    check "FAIL  1/4 passed  (WA 1, RE 1, TLE 1)" in rendered

