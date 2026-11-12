import std/[monotimes, os, strformat, strutils, terminal, times]

import ./[cases, errors, problem, processes, reporting, warnings]

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

# 空振り起動に使う入力。サンプルがあればその1番目、なければ自作ケースの1番目
proc firstCaseInput(testDir: string): string =
  for prefix in ["sample-", CustomPrefix]:
    let numbers = caseNumbers(testDir, prefix)
    if numbers.len > 0:
      return testDir / (prefix & $numbers[0] & ".in")

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

# ファイルへの保存やパイプでは制御文字が混ざらないよう、端末に出すときだけ色を付ける
proc shouldUseColor(): bool =
  stdout.isatty() and not existsEnv("NO_COLOR")

proc runWorkflow*(
    sourcePath: string,
    explicitUrl = "",
    config = defaultWorkflowConfig(),
    runner: CommandRunner = runCommand,
    verbose = false,
    warmUp: WarmUpRunner = warmUpExecutable,
    forceDownload = false
  ): bool =
  validateSource(sourcePath)

  let resolvedSource = absolutePath(sourcePath)
  let problemInfo = resolveProblem(resolvedSource, explicitUrl)
  let projectRoot = findProjectRoot(resolvedSource)
  let testDir = projectRoot / ".actk" / "tests" / problemInfo.taskId
  let executablePath = prepareExecutablePath(resolvedSource)

  createDir(testDir)

  # 自作ケースがあれば、保存済みでないサンプルは取りに行かない。
  # コンテスト中はログインなしでサンプルを取れず、失敗を毎回待つことになるため
  let customCount = customCaseNumbers(testDir).len
  var sampleCount = 0
  if forceDownload or (not hasCompleteSampleCache(testDir) and customCount == 0):
    removeIncompleteSamples(testDir)
    removeFile(cacheMarkerPath(testDir))
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
      echo ""
      echo "コンテスト中などでサンプルを取れないときは、actk add で入力例を貼り付けて保存できます"
      return false
    sampleCount = samplePairCount(testDir)
    if sampleCount == 0:
      raise newException(ActkError, "サンプル取得後も .in/.out の組が見つかりません: " & testDir)
    writeFile(
      cacheMarkerPath(testDir),
      "url=" & problemInfo.url & "\n" & "samples=" & $sampleCount & "\n"
    )
    echo "samples  " & $sampleCount & " downloaded"
  elif hasCompleteSampleCache(testDir):
    sampleCount = samplePairCount(testDir)
    echo "samples  " & $sampleCount & " cached"
  else:
    # 中断で残った不完全なサンプルを、自作ケースと一緒に流さないよう消しておく
    removeIncompleteSamples(testDir)
    echo "samples  skipped  (--download で取得)"
  if customCount > 0:
    echo "custom   " & $customCount & " saved"

  let compiled = compileSolution(resolvedSource, executablePath, config, runner, verbose)
  if not compiled.succeeded:
    return false

  let warmUpInput = firstCaseInput(testDir)
  if warmUpInput.len > 0:
    warmUp(executablePath, warmUpInput, config.timeLimitSeconds)

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

  var report = parseOjReport(testResult.output)
  let caseCount = sampleCount + customCount
  if not report.isComplete(caseCount):
    if not verbose:
      showCommandOutput(testResult)
    raise newException(
      ActkError,
      "テスト結果を解釈できませんでした（" & $report.results.len & "/" & $caseCount & "件）"
    )
  report.orderCases()
  report.markUnanswered(unansweredCustomNames(testDir))

  echo renderReport(report, config.timeLimitSeconds, useColor = shouldUseColor())
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

proc testDirFor(sourcePath, explicitUrl: string): tuple[taskId, testDir: string] =
  validateSource(sourcePath)
  let resolvedSource = absolutePath(sourcePath)
  let problemInfo = resolveProblem(resolvedSource, explicitUrl)
  (problemInfo.taskId, findProjectRoot(resolvedSource) / ".actk" / "tests" / problemInfo.taskId)

# 入力と答えを貼り付けて、自作ケースとして保存する。何も貼らずに終えるまで続け、追加した件数を返す
proc addCustomCases*(
    sourcePath: string,
    explicitUrl = "",
    reader: BlockReader = readBlockFromStdin
  ): int =
  let (taskId, testDir) = testDirFor(sourcePath, explicitUrl)
  let existing = customCaseNumbers(testDir).len
  echo "problem  " & taskId & (if existing > 0: "  (自作ケース " & $existing & "件保存済み)" else: "")

  while true:
    echo ""
    echo "入力を貼り付けて Ctrl-D（追加を終えるなら、何も貼らずに Ctrl-D）"
    stdout.flushFile()
    let input = normalizeCaseText(reader())
    if input.len == 0:
      break
    echo "答えを貼り付けて Ctrl-D（答えがなければ、何も貼らずに Ctrl-D）"
    stdout.flushFile()
    let answer = normalizeCaseText(reader())
    let number = saveCustomCase(testDir, input, answer)
    echo "saved    custom " & $number & (if answer.len == 0: "  (答えなし)" else: "")
    inc result

  echo "added    " & $result & "  (自作ケースは全部で " & $(existing + result) & "件)"

proc listCustomCases*(sourcePath: string, explicitUrl = "") =
  let (taskId, testDir) = testDirFor(sourcePath, explicitUrl)
  let numbers = customCaseNumbers(testDir)
  echo "problem  " & taskId
  echo "folder   " & relativePath(testDir, getCurrentDir())
  if numbers.len == 0:
    echo ""
    echo "自作ケースはまだありません（actk add で追加）"
    return
  for number in numbers:
    let outputPath = customOutputPath(testDir, number)
    echo ""
    echo "custom " & $number & "  in   " & caseSummary(customInputPath(testDir, number))
    echo repeat(' ', ("custom " & $number).len) & "  out  " &
      (if fileExists(outputPath): caseSummary(outputPath) else: "(答えなし)")

# 番号か all を指定して、自作ケースを消す
proc deleteCustomCases*(sourcePath, target: string, explicitUrl = "") =
  let (_, testDir) = testDirFor(sourcePath, explicitUrl)
  var targets: seq[int] = @[]
  if target == "all":
    targets = customCaseNumbers(testDir)
  else:
    try:
      targets = @[parseInt(target)]
    except ValueError:
      raise newException(ActkError, "--delete には番号か all を指定してください: " & target)
  if targets.len == 0:
    echo "自作ケースはありません"
    return
  for number in targets:
    if not deleteCustomCase(testDir, number):
      raise newException(ActkError, "custom " & $number & " は見つかりません")
    echo "deleted  custom " & $number
