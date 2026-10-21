import std/[os, strutils, times, unittest]

import atcoder_toolkit/[errors, initializer, problem, processes, reporting, workflow]

suite "contest initialization":
  test "creates A through D from template without overwriting existing files":
    let tempRoot = getTempDir() / ("ackt-init-create-" & $getTime().toUnix())
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
    expect AcktError:
      discard normalizeContestNumber("arc484")
    expect AcktError:
      discard normalizeContestNumber("abc")
    expect AcktError:
      discard normalizeContestNumber("000")

    let tempRoot = getTempDir() / ("ackt-init-missing-" & $getTime().toUnix())
    createDir(tempRoot)
    defer:
      if dirExists(tempRoot):
        removeDir(tempRoot)
    expect AcktError:
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

  test "tessoku tasks borrowed from Typical 90 use their real task IDs":
    check inferProblem("tessoku/A77.cpp").taskId == "typical90_a"
    check inferProblem("tessoku/C18.cpp").taskId == "typical90_s"

  test "numbered review files also work for tessoku problems":
    check inferProblem("競技プログラミングの鉄則/01_アルゴリズムと計算量/A04_2.cpp").taskId == "tessoku_book_d"
    check inferProblem("競技プログラミングの鉄則/03_二分探索/A12_3.cpp").taskId == "tessoku_book_l"

  test "missing tessoku problem numbers are rejected":
    expect AcktError:
      discard inferProblem("tessoku/A47.cpp")
    expect AcktError:
      discard inferProblem("tessoku/B05.cpp")

  test "explicit AtCoder URL is accepted":
    let problemInfo = validateAtCoderUrl(
      "https://atcoder.jp/contests/tessoku-book/tasks/tessoku_book_a"
    )
    check problemInfo.contestId == "tessoku-book"
    check problemInfo.taskId == "tessoku_book_a"

  test "non-AtCoder URL is rejected":
    expect AcktError:
      discard validateAtCoderUrl("https://example.com/contests/abc484/tasks/abc484_a")

suite "workflow":
  test "downloads once, then compiles and tests from cache":
    let tempRoot = getTempDir() / ("ackt-test-" & $getTime().toUnix())
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
    let expectedExecutable = tempRoot / ".ackt" / "build" / changeFileExt("A999", ExeExt)
    check fileExists(expectedExecutable)
    check fileExists(tempRoot / ".ackt" / "tests" / "abc999_a" / ".download-complete")

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

