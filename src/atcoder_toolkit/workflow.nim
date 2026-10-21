import std/[monotimes, os, strformat, strutils, times]

import ./[errors, problem, processes, reporting]

type
  WorkflowConfig* = object
    compiler*: string
    oj*: string
    timeLimitSeconds*: float

proc defaultWorkflowConfig*(): WorkflowConfig =
  WorkflowConfig(
    compiler: getEnv("ACTK_CXX", "g++"),
    oj: getEnv("ACTK_OJ", "oj"),
    timeLimitSeconds: 2.0
  )

proc findProjectRoot*(sourcePath: string): string =
  var current = parentDir(absolutePath(sourcePath))
  while current.len > 0:
    let gitPath = current / ".git"
    if dirExists(gitPath) or fileExists(gitPath):
      return current

    let parent = parentDir(current)
    if parent == current:
      break
    current = parent

  getCurrentDir()

proc samplePairCount*(testDir: string): int =
  if not dirExists(testDir):
    return 0

  for kind, path in walkDir(testDir):
    if kind == pcFile and path.endsWith(".in") and splitFile(path).name.startsWith("sample-"):
      let outputPath = changeFileExt(path, "out")
      if fileExists(outputPath):
        inc result

proc cacheMarkerPath(testDir: string): string =
  testDir / ".download-complete"

proc hasCompleteSampleCache(testDir: string): bool =
  fileExists(cacheMarkerPath(testDir)) and samplePairCount(testDir) > 0

proc showCommandOutput(commandResult: CommandResult) =
  if commandResult.output.len > 0:
    stdout.write(commandResult.output)
    if not commandResult.output.endsWith("\n"):
      stdout.write("\n")

proc outputExecutablePath(buildDir, sourcePath: string): string =
  let executableName = changeFileExt(splitFile(sourcePath).name, ExeExt)
  buildDir / executableName

proc runWorkflow*(
    sourcePath: string,
    explicitUrl = "",
    config = defaultWorkflowConfig(),
    runner: CommandRunner = runCommand,
    verbose = false
  ): bool =
  if not fileExists(sourcePath):
    raise newException(ActkError, "C++ファイルが見つかりません: " & sourcePath)
  if splitFile(sourcePath).ext.toLowerAscii() != ".cpp":
    raise newException(ActkError, "現在対応している解答ファイルは .cpp だけです")

  let resolvedSource = absolutePath(sourcePath)
  let problemInfo = resolveProblem(resolvedSource, explicitUrl)
  let projectRoot = findProjectRoot(resolvedSource)
  let stateDir = projectRoot / ".actk"
  let testDir = stateDir / "tests" / problemInfo.taskId
  let buildDir = stateDir / "build"
  let executablePath = outputExecutablePath(buildDir, resolvedSource)

  createDir(testDir)
  createDir(buildDir)

  var sampleCount: int
  if not hasCompleteSampleCache(testDir):
    let downloadResult = runner(
      config.oj,
      @["download", "-d", testDir, problemInfo.url]
    )
    if verbose:
      showCommandOutput(downloadResult)
    if downloadResult.exitCode != 0:
      echo "samples  FAILED"
      if not verbose:
        showCommandOutput(downloadResult)
      return false
    sampleCount = samplePairCount(testDir)
    if sampleCount == 0:
      raise newException(ActkError, "サンプル取得後も .in/.out の組が見つかりません: " & testDir)
    writeFile(
      cacheMarkerPath(testDir),
      "url=" & problemInfo.url & "\n" & "samples=" & $sampleCount & "\n"
    )
    echo "samples  " & $sampleCount & " downloaded"
  else:
    sampleCount = samplePairCount(testDir)
    echo "samples  " & $sampleCount & " cached"

  let compileStarted = getMonoTime()
  let compileResult = runner(
    config.compiler,
    @["-std=c++17", "-O2", "-Wall", "-Wextra", resolvedSource, "-o", executablePath]
  )
  let compileSeconds = (getMonoTime() - compileStarted).inNanoseconds.float / 1_000_000_000.0
  if compileResult.exitCode != 0:
    echo "compile  FAILED  " & formatElapsed(compileSeconds)
    showCommandOutput(compileResult)
    return false
  if verbose:
    showCommandOutput(compileResult)
  echo "compile  OK  " & formatElapsed(compileSeconds)

  if not fileExists(executablePath):
    raise newException(ActkError, "コンパイル後の実行ファイルが見つかりません: " & executablePath)

  echo ""
  let testResult = runner(
    config.oj,
    @[
      "test",
      "-d", testDir,
      "-c", quoteShell(executablePath),
      "-t", &"{config.timeLimitSeconds:.3f}",
      "--no-print-input"
    ]
  )
  if verbose:
    showCommandOutput(testResult)
    echo ""

  let report = parseOjReport(testResult.output)
  if not report.isComplete(sampleCount):
    if not verbose:
      showCommandOutput(testResult)
    raise newException(
      ActkError,
      "テスト結果を解釈できませんでした（" & $report.results.len & "/" & $sampleCount & "件）"
    )

  echo renderReport(report, config.timeLimitSeconds)
  allPassed(report)

