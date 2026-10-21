import std/[os, strutils, times, unittest]

import atcoder_toolkit/[errors, initializer, problem, processes, reporting, workflow]

suite "contest initialization":
  test "creates A through D from template without overwriting existing files":
    let tempRoot = getTempDir() / ("actk-init-create-" & $getTime().toUnix())
    createDir(tempRoot)
    defer:
      if dirExists(tempRoot):
        removeDir(tempRoot)

    let templateText = "#include <bits/stdc++.h>\nint main() {}\n"
    writeFile(tempRoot / "template.cpp", templateText)

    let firstResult = initializeContest("484", tempRoot)
    check firstResult.contestId == "abc484"
    check firstResult.created == @[
      "ABC_A/A484.cpp",
      "ABC_B/B484.cpp",
      "ABC_C/C484.cpp",
      "ABC_D/D484.cpp"
    ]
    check firstResult.skipped.len == 0
    for relativePath in firstResult.created:
      check readFile(tempRoot / relativePath) == templateText

    writeFile(tempRoot / "ABC_A" / "A484.cpp", "keep this answer\n")
    let secondResult = initializeContest("abc484", tempRoot)
    check secondResult.created.len == 0
    check secondResult.skipped == firstResult.created
    check readFile(tempRoot / "ABC_A" / "A484.cpp") == "keep this answer\n"

  test "short contest numbers are padded to three digits":
    check normalizeContestNumber("86") == "086"
    check normalizeContestNumber("ABC086") == "086"
    check normalizeContestNumber("abc484") == "484"

  test "invalid contest numbers and missing templates are rejected":
    expect ActkError:
      discard normalizeContestNumber("arc484")
    expect ActkError:
      discard normalizeContestNumber("abc")
    expect ActkError:
      discard normalizeContestNumber("000")

    let tempRoot = getTempDir() / ("actk-init-missing-" & $getTime().toUnix())
    createDir(tempRoot)
    defer:
      if dirExists(tempRoot):
        removeDir(tempRoot)
    expect ActkError:
      discard initializeContest("484", tempRoot)

suite "problem resolution":
  test "current ABC file convention is inferred":
    let problemInfo = inferProblem("ABC_C/C484.cpp")
    check problemInfo.contestId == "abc484"
    check problemInfo.taskId == "abc484_c"
    check problemInfo.url == "https://atcoder.jp/contests/abc484/tasks/abc484_c"

  test "three-digit ABC numbers remain ABC problems":
    let problemInfo = inferProblem("ABC_A/A086.cpp")
    check problemInfo.contestId == "abc086"
    check problemInfo.taskId == "abc086_a"

  test "numbered review files use the original ABC problem":
    let secondAttempt = inferProblem("ABC_Re_B/B474_2.cpp")
    check secondAttempt.contestId == "abc474"
    check secondAttempt.taskId == "abc474_b"

    let anotherReview = inferProblem("ABC_Re_C/C437_2.cpp")
    check anotherReview.taskId == "abc437_c"

  test "tessoku A and B file names are inferred":
    let a01 = inferProblem("tessoku/A01.cpp")
    check a01.contestId == "tessoku-book"
    check a01.taskId == "tessoku_book_a"
    check a01.url == "https://atcoder.jp/contests/tessoku-book/tasks/tessoku_book_a"

    let b01 = inferProblem("tessoku/B01.cpp")
    check b01.taskId == "tessoku_book_bz"

    let b06 = inferProblem("tessoku/B06.cpp")
    check b06.taskId == "tessoku_book_ce"

  test "tessoku tasks borrowed from other contests use their real task IDs":
    check inferProblem("tessoku/A77.cpp").taskId == "typical90_a"
    check inferProblem("tessoku/C18.cpp").taskId == "typical90_s"
    check inferProblem("tessoku/A06.cpp").taskId == "math_and_algorithm_ai"
    check inferProblem("tessoku/A50.cpp").taskId == "future_contest_2018_qual_a"
    check inferProblem("tessoku/B16.cpp").taskId == "dp_a"
    check inferProblem("tessoku/B63.cpp").taskId == "abc007_3"
    check inferProblem("tessoku/C09.cpp").taskId == "math_and_algorithm_ac"

    let a62 = inferProblem("競技プログラミングの鉄則/09_グラフアルゴリズム/A62_2.cpp")
    check a62.contestId == "tessoku-book"
    check a62.url == "https://atcoder.jp/contests/tessoku-book/tasks/math_and_algorithm_am"

  test "regular tessoku numbers around borrowed ones stay sequential":
    check inferProblem("tessoku/A05.cpp").taskId == "tessoku_book_e"
    check inferProblem("tessoku/A07.cpp").taskId == "tessoku_book_g"
    check inferProblem("tessoku/C10.cpp").taskId == "tessoku_book_fh"

  test "numbered review files also work for tessoku problems":
    check inferProblem("競技プログラミングの鉄則/01_アルゴリズムと計算量/A04_2.cpp").taskId == "tessoku_book_d"
    check inferProblem("競技プログラミングの鉄則/03_二分探索/A12_3.cpp").taskId == "tessoku_book_l"

  test "missing tessoku problem numbers are rejected":
    expect ActkError:
      discard inferProblem("tessoku/A47.cpp")
    expect ActkError:
      discard inferProblem("tessoku/B05.cpp")

  test "explicit AtCoder URL is accepted":
    let problemInfo = validateAtCoderUrl(
      "https://atcoder.jp/contests/tessoku-book/tasks/tessoku_book_a"
    )
    check problemInfo.contestId == "tessoku-book"
    check problemInfo.taskId == "tessoku_book_a"

  test "non-AtCoder URL is rejected":
    expect ActkError:
      discard validateAtCoderUrl("https://example.com/contests/abc484/tasks/abc484_a")

suite "workflow":
  test "downloads once, then compiles and tests from cache":
    let tempRoot = getTempDir() / ("actk-test-" & $getTime().toUnix())
    let sourceDir = tempRoot / "ABC_A"
    let sourcePath = sourceDir / "A999.cpp"
    createDir(tempRoot / ".git")
    createDir(sourceDir)
    writeFile(sourcePath, "int main() { return 0; }\n")
    defer:
      if dirExists(tempRoot):
        removeDir(tempRoot)

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
    let expectedExecutable = tempRoot / ".actk" / "build" / changeFileExt("A999", ExeExt)
    check fileExists(expectedExecutable)
    check fileExists(tempRoot / ".actk" / "tests" / "abc999_a" / ".download-complete")

    calls.setLen(0)
    check runWorkflow(sourcePath, config = config, runner = fakeRunner)
    check calls.len == 2
    check calls[0][0] == "fake-cxx"
    check calls[1][1][0] == "test"

  test "samples left by an interrupted download are fetched again":
    let tempRoot = getTempDir() / ("actk-test-retry-" & $getTime().toUnix())
    let sourcePath = tempRoot / "ABC_A" / "A998.cpp"
    let testDir = tempRoot / ".actk" / "tests" / "abc998_a"
    createDir(tempRoot / ".git")
    createDir(sourcePath.parentDir)
    createDir(testDir)
    writeFile(sourcePath, "int main() { return 0; }\n")
    writeFile(testDir / "sample-1.in", "stale\n")
    writeFile(testDir / "sample-1.out", "stale\n")
    defer:
      if dirExists(tempRoot):
        removeDir(tempRoot)

    # 本物のoj downloadと同じく、既存ファイルがあれば失敗する
    let fakeRunner: CommandRunner = proc(executable: string, args: seq[string]): CommandResult =
      if args.len > 0 and args[0] == "download":
        let downloadDir = args[args.find("-d") + 1]
        if fileExists(downloadDir / "sample-1.in"):
          return CommandResult(output: "[ERROR] file already exists", exitCode: 1)
        writeFile(downloadDir / "sample-1.in", "1\n")
        writeFile(downloadDir / "sample-1.out", "1\n")
      elif executable == "fake-cxx":
        writeFile(args[args.find("-o") + 1], "fake executable")
      elif args.len > 0 and args[0] == "test":
        return CommandResult(
          output: "[INFO] sample-1\n[INFO] time: 0.006 sec\n[SUCCESS] AC\n",
          exitCode: 0
        )
      CommandResult(output: "", exitCode: 0)

    let config = WorkflowConfig(compiler: "fake-cxx", oj: "fake-oj", timeLimitSeconds: 2.0)
    check runWorkflow(sourcePath, config = config, runner = fakeRunner)
    check readFile(testDir / "sample-1.in") == "1\n"
    check fileExists(testDir / ".download-complete")

  test "time limit and error tolerance are passed to oj test":
    let tempRoot = getTempDir() / ("actk-test-options-" & $getTime().toUnix())
    let sourcePath = tempRoot / "ABC_B" / "B999.cpp"
    createDir(tempRoot / ".git")
    createDir(sourcePath.parentDir)
    writeFile(sourcePath, "int main() { return 0; }\n")
    defer:
      if dirExists(tempRoot):
        removeDir(tempRoot)

    var testArgs: seq[string] = @[]
    let fakeRunner: CommandRunner = proc(executable: string, args: seq[string]): CommandResult =
      if args.len > 0 and args[0] == "download":
        let testDir = args[args.find("-d") + 1]
        writeFile(testDir / "sample-1.in", "1\n")
        writeFile(testDir / "sample-1.out", "0.5\n")
      elif executable == "fake-cxx":
        writeFile(args[args.find("-o") + 1], "fake executable")
      elif args.len > 0 and args[0] == "test":
        testArgs = args
        return CommandResult(
          output: "[INFO] sample-1\n[INFO] time: 0.006 sec\n[SUCCESS] AC\n",
          exitCode: 0
        )
      CommandResult(output: "", exitCode: 0)

    let config = WorkflowConfig(
      compiler: "fake-cxx",
      oj: "fake-oj",
      timeLimitSeconds: 3.0,
      errorTolerance: 1e-6
    )
    check runWorkflow(sourcePath, config = config, runner = fakeRunner)
    check testArgs[testArgs.find("-t") + 1] == "3.000"
    let errorIndex = testArgs.find("-e")
    check errorIndex >= 0
    check parseFloat(testArgs[errorIndex + 1]) == 1e-6

suite "interactive run":
  setup:
    let tempRoot = getTempDir() / ("actk-run-" & $getTime().toUnix())
    let sourcePath = tempRoot / "ABC_A" / "A997.cpp"
    createDir(tempRoot / ".git")
    createDir(sourcePath.parentDir)
    writeFile(sourcePath, "int main() { return 0; }\n")

  teardown:
    if dirExists(tempRoot):
      removeDir(tempRoot)

  test "compiles every time and runs the fresh executable without oj":
    var executables: seq[string] = @[]
    let fakeRunner: CommandRunner = proc(executable: string, args: seq[string]): CommandResult =
      executables.add(executable)
      if executable == "fake-cxx":
        writeFile(args[args.find("-o") + 1], "fake executable")
      CommandResult(output: "", exitCode: 0)

    var launched: seq[string] = @[]
    let fakeLauncher: InteractiveLauncher = proc(executable: string): int =
      launched.add(executable)
      0

    let config = WorkflowConfig(compiler: "fake-cxx", oj: "fake-oj", timeLimitSeconds: 2.0)
    check runInteractive(sourcePath, config, fakeRunner, fakeLauncher)
    check runInteractive(sourcePath, config, fakeRunner, fakeLauncher)
    check executables == @["fake-cxx", "fake-cxx"]
    let expectedExecutable = tempRoot / ".actk" / "build" / changeFileExt("A997", ExeExt)
    check launched == @[expectedExecutable, expectedExecutable]

  test "a failed compile does not run the old executable":
    let failingRunner: CommandRunner = proc(executable: string, args: seq[string]): CommandResult =
      CommandResult(output: "error: expected ';'", exitCode: 1)
    var launched = false
    let fakeLauncher: InteractiveLauncher = proc(executable: string): int =
      launched = true
      0

    let config = WorkflowConfig(compiler: "fake-cxx", oj: "fake-oj", timeLimitSeconds: 2.0)
    check not runInteractive(sourcePath, config, failingRunner, fakeLauncher)
    check not launched

  test "a crash is reported as a failure with a readable reason":
    let fakeRunner: CommandRunner = proc(executable: string, args: seq[string]): CommandResult =
      writeFile(args[args.find("-o") + 1], "fake executable")
      CommandResult(output: "", exitCode: 0)
    let crashingLauncher: InteractiveLauncher = proc(executable: string): int = 139

    let config = WorkflowConfig(compiler: "fake-cxx", oj: "fake-oj", timeLimitSeconds: 2.0)
    check not runInteractive(sourcePath, config, fakeRunner, crashingLauncher)
    check "segmentation fault" in exitCodeReason(139)
    check exitCodeReason(3) == ""

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
    check "reason: abnormal termination" in rendered
    check "exit code: 3" notin rendered
    check "stderr: boom" notin rendered
    check "[4/4] TLE" in rendered
    check "FAIL  1/4 passed  (WA 1, RE 1, TLE 1)" in rendered

  test "known runtime errors get a concise reason":
    let segfaultReport = TestReport(results: @[
      SampleResult(
        name: "sample-1",
        verdict: verdictRe,
        seconds: 0.010,
        reason: "return code -11"
      )
    ])
    check "reason: segmentation fault" in renderReport(segfaultReport, 2.0)

    let sanitizerReport = TestReport(results: @[
      SampleResult(
        name: "sample-1",
        verdict: verdictRe,
        seconds: 0.010,
        stderrLines: @["ERROR: AddressSanitizer: heap-buffer-overflow on address"]
      )
    ])
    check "reason: heap-buffer-overflow" in renderReport(sanitizerReport, 2.0)

