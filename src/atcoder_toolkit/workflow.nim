import std/[monotimes, os, strformat, strutils, times]

import ./[errors, problem, processes, reporting, warnings]

type
  WorkflowConfig* = object
    compiler*: string
    oj*: string
    timeLimitSeconds*: float
    errorTolerance*: float  # 0なら完全一致で比較する

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

# oj downloadは同名ファイルがあると取得を拒否するため、中断で残ったサンプルを消しておく
proc removeIncompleteSamples(testDir: string) =
  for kind, path in walkDir(testDir):
    let (_, name, ext) = splitFile(path)
    if kind == pcFile and name.startsWith("sample-") and ext in [".in", ".out"]:
      removeFile(path)

proc showCommandOutput(commandResult: CommandResult) =
  if commandResult.output.len > 0:
    stdout.write(commandResult.output)
    if not commandResult.output.endsWith("\n"):
      stdout.write("\n")

proc outputExecutablePath(buildDir, sourcePath: string): string =
  let executableName = changeFileExt(splitFile(sourcePath).name, ExeExt)
  buildDir / executableName

proc validateSource(sourcePath: string) =
  if not fileExists(sourcePath):
    raise newException(ActkError, "C++ファイルが見つかりません: " & sourcePath)
  if splitFile(sourcePath).ext.toLowerAscii() != ".cpp":
    raise newException(ActkError, "現在対応している解答ファイルは .cpp だけです")

proc prepareExecutablePath(resolvedSource: string): string =
  let buildDir = findProjectRoot(resolvedSource) / ".actk" / "build"
  createDir(buildDir)
  outputExecutablePath(buildDir, resolvedSource)

type
  CompileOutcome = object
    succeeded: bool
    warnings: seq[CompilerWarning]

proc compileSolution(
    resolvedSource, executablePath: string,
    config: WorkflowConfig,
    runner: CommandRunner,
    verbose: bool
  ): CompileOutcome =
  let compileStarted = getMonoTime()
  let compileResult = runner(
    config.compiler,
    @["-std=c++17", "-O2", "-Wall", "-Wextra", resolvedSource, "-o", executablePath]
  )
  let compileSeconds = (getMonoTime() - compileStarted).inNanoseconds.float / 1_000_000_000.0
  if compileResult.exitCode != 0:
    echo "compile  FAILED  " & formatElapsed(compileSeconds)
    showCommandOutput(compileResult)
    return CompileOutcome(succeeded: false)
  if verbose:
    showCommandOutput(compileResult)

  result = CompileOutcome(
    succeeded: true,
    warnings: parseCompilerWarnings(compileResult.output)
  )
  var compileLine = "compile  OK  " & formatElapsed(compileSeconds)
  if result.warnings.len > 0:
    compileLine.add("  (warning " & $result.warnings.len & ")")
  echo compileLine

  if not fileExists(executablePath):
    raise newException(ActkError, "コンパイル後の実行ファイルが見つかりません: " & executablePath)

proc showWarnings(warnings: seq[CompilerWarning]) =
  if warnings.len > 0:
    echo ""
    echo renderWarnings(warnings)

proc runWorkflow*(
    sourcePath: string,
    explicitUrl = "",
    config = defaultWorkflowConfig(),
    runner: CommandRunner = runCommand,
    verbose = false
  ): bool =
  validateSource(sourcePath)

  let resolvedSource = absolutePath(sourcePath)
  let problemInfo = resolveProblem(resolvedSource, explicitUrl)
  let projectRoot = findProjectRoot(resolvedSource)
  let testDir = projectRoot / ".actk" / "tests" / problemInfo.taskId
  let executablePath = prepareExecutablePath(resolvedSource)

  createDir(testDir)

  var sampleCount: int
  if not hasCompleteSampleCache(testDir):
    removeIncompleteSamples(testDir)
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

  let compiled = compileSolution(resolvedSource, executablePath, config, runner, verbose)
  if not compiled.succeeded:
    return false

  echo ""
  var testArgs = @[
    "test",
    "-d", testDir,
    "-c", quoteShell(executablePath),
    "-t", &"{config.timeLimitSeconds:.3f}",
    "--no-print-input"
  ]
  if config.errorTolerance > 0.0:
    testArgs.add(["-e", $config.errorTolerance])
  let testResult = runner(config.oj, testArgs)
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
  showWarnings(compiled.warnings)
  allPassed(report)

# macOS・Linuxでシグナルにより終了したときの終了コード（128 + シグナル番号）
proc exitCodeReason*(exitCode: int): string =
  case exitCode
  of 133: "trap（nullポインタ参照などの未定義動作）"
  of 134: "abort（例外やassertの失敗など）"
  of 136: "floating-point exception（0除算など）"
  of 138: "bus error（不正なメモリアクセス）"
  of 139: "segmentation fault（範囲外アクセスなど）"
  else: ""

proc runInteractive*(
    sourcePath: string,
    config = defaultWorkflowConfig(),
    runner: CommandRunner = runCommand,
    launcher: InteractiveLauncher = launchInteractive,
    verbose = false
  ): bool =
  validateSource(sourcePath)

  let resolvedSource = absolutePath(sourcePath)
  let executablePath = prepareExecutablePath(resolvedSource)
  let compiled = compileSolution(resolvedSource, executablePath, config, runner, verbose)
  if not compiled.succeeded:
    return false

  echo ""
  echo "run      入力を打ってEnter（入力の終わりは Ctrl-D）"
  echo "----------------------------------------"
  stdout.flushFile()
  let exitCode = launcher(executablePath)
  echo "----------------------------------------"
  let reason = exitCodeReason(exitCode)
  echo "exit     " & $exitCode & (if reason.len > 0: "  " & reason else: "")
  showWarnings(compiled.warnings)
  exitCode == 0
