import std/[algorithm, math, parseutils, sequtils, strutils, unicode]

type
  Verdict* = enum
    verdictUnknown,
    verdictAc,
    verdictWa,
    verdictRe,
    verdictTle,
    verdictNoAnswer  # 答えを登録していない自作ケース。判定せず出力だけ見せる

  SampleResult* = object
    name*: string
    verdict*: Verdict
    seconds*: float
    reason*: string
    stderrLines*: seq[string]
    actualLines*: seq[string]
    expectedLines*: seq[string]

  TestReport* = object
    results*: seq[SampleResult]

  OutputSection = enum
    sectionNone,
    sectionActual,
    sectionExpected

proc stripAnsi(value: string): string =
  var index = 0
  while index < value.len:
    if value[index] == '\e' and index + 1 < value.len and value[index + 1] == '[':
      index += 2
      while index < value.len and not value[index].isAlphaAscii():
        inc index
      if index < value.len:
        inc index
    else:
      result.add(value[index])
      inc index

proc parseSeconds(line: string): float =
  const Prefix = "[INFO] time: "
  if not line.startsWith(Prefix):
    return -1.0

  var parsed: float
  let consumed = parseFloat(line, parsed, Prefix.len)
  if consumed == 0:
    return -1.0
  parsed

proc trimReportLines(lines: seq[string]): seq[string] =
  result = lines
  while result.len > 0 and result[^1].len == 0:
    result.setLen(result.len - 1)
  if result.len == 1 and result[0] == "(empty)":
    result.setLen(0)

proc parseOjReport*(rawOutput: string): TestReport =
  var current = -1
  var section = sectionNone

  for rawLine in rawOutput.replace("\r\n", "\n").splitLines():
    let line = stripAnsi(rawLine)
    let control = line.strip()

    if control.startsWith("[INFO] sample-") or control.startsWith("[INFO] custom-"):
      result.results.add(SampleResult(
        name: control["[INFO] ".len .. ^1],
        seconds: -1.0
      ))
      current = result.results.high
      section = sectionNone
      continue

    if current < 0:
      continue

    if control.startsWith("[INFO] slowest:") or
        control.startsWith("[SUCCESS] test success:") or
        control.startsWith("[FAILURE] test failed:"):
      section = sectionNone
      continue

    let seconds = parseSeconds(control)
    if seconds >= 0.0:
      result.results[current].seconds = seconds
      section = sectionNone
    elif control == "[SUCCESS] AC":
      result.results[current].verdict = verdictAc
      section = sectionNone
    elif control == "[FAILURE] WA":
      result.results[current].verdict = verdictWa
      section = sectionNone
    elif control.startsWith("[FAILURE] RE"):
      result.results[current].verdict = verdictRe
      let separator = control.find(':')
      if separator >= 0 and separator + 1 < control.len:
        result.results[current].reason = control[separator + 1 .. ^1].strip()
      section = sectionNone
    elif control == "[FAILURE] TLE":
      result.results[current].verdict = verdictTle
      section = sectionNone
    elif control == "output:":
      section = sectionActual
    elif control == "expected:":
      section = sectionExpected
    elif section == sectionActual:
      result.results[current].actualLines.add(line)
    elif section == sectionExpected:
      result.results[current].expectedLines.add(line)
    elif control.len > 0 and not control.startsWith('['):
      result.results[current].stderrLines.add(control)

  for sample in result.results.mitems:
    sample.actualLines = trimReportLines(sample.actualLines)
    sample.expectedLines = trimReportLines(sample.expectedLines)

const CustomPrefix* = "custom-"

proc isCustomCase*(name: string): bool =
  name.startsWith(CustomPrefix)

# 「sample-2」「custom-10」の末尾の番号。数字でなければ0
proc caseNumber*(name: string): int =
  let dash = name.rfind('-')
  if dash < 0:
    return 0
  try:
    parseInt(name[dash + 1 .. ^1])
  except ValueError:
    0

# ojは名前の文字列順（custom-1、sample-1、sample-10、sample-2）で実行するので、
# サンプル → 自作ケースの順に、それぞれ番号順へ並べ直す
proc orderCases*(report: var TestReport) =
  report.results.sort(proc(a, b: SampleResult): int =
    result = cmp(a.name.isCustomCase(), b.name.isCustomCase())
    if result == 0:
      result = cmp(a.name.caseNumber(), b.name.caseNumber())
    if result == 0:
      result = cmp(a.name, b.name))

# 答え（.out）のない自作ケースは、ojがACと表示するので「答えなし」に直す。
# REやTLEは答えがなくても分かるので、そのまま残す
proc markUnanswered*(report: var TestReport, names: seq[string]) =
  for sample in report.results.mitems:
    if sample.name in names and sample.verdict == verdictAc:
      sample.verdict = verdictNoAnswer

proc verdictText(verdict: Verdict): string =
  case verdict
  of verdictUnknown: "?"
  of verdictAc: "AC"
  of verdictWa: "WA"
  of verdictRe: "RE"
  of verdictTle: "TLE"
  of verdictNoAnswer: "--"

proc formatElapsed*(seconds: float): string =
  if seconds < 0.0:
    return "?"
  if seconds < 0.001:
    return "<1 ms"
  if seconds < 1.0:
    return $max(1, int(round(seconds * 1000.0))) & " ms"
  formatFloat(seconds, ffDecimal, 2) & " s"

proc visibleLine(line: string): string =
  var cleaned = line
  if cleaned.endsWith("\\r"):
    cleaned.setLen(cleaned.len - 2)
  if cleaned.len == 0:
    return "(empty)"
  const MaxLength = 100
  if cleaned.len > MaxLength:
    cleaned[0 ..< MaxLength] & "..."
  else:
    cleaned

proc firstDifference(sample: SampleResult): tuple[lineNumber: int, expected, actual: string] =
  let lineCount = max(sample.expectedLines.len, sample.actualLines.len)
  for index in 0 ..< lineCount:
    let expected = if index < sample.expectedLines.len: sample.expectedLines[index] else: ""
    let actual = if index < sample.actualLines.len: sample.actualLines[index] else: ""
    if expected != actual:
      return (index + 1, visibleLine(expected), visibleLine(actual))

  (1, "(output differs)", "(output differs)")

const
  MaxTableRows = 100
  MaxExpectedColumnWidth = 40
  MissingLine = "(なし)"
  TableIndent = "       "

# 端末での見た目の幅。日本語などASCII以外の文字は2マス分として数える
proc displayWidth(text: string): int =
  for rune in text.runes:
    result += (if rune.int < 0x80: 1 else: 2)

proc padRight(text: string, width: int): string =
  text & repeat(' ', max(0, width - displayWidth(text)))

# 複数行の答えのWAを、expectedとgotを並べた表にする。違う行には「>」を付ける
proc wrongAnswerLines(sample: SampleResult, resultLine: string): seq[string] =
  let expectedLines = sample.expectedLines
  let actualLines = sample.actualLines
  let lineCount = max(expectedLines.len, actualLines.len)

  if lineCount <= 1:
    let difference = firstDifference(sample)
    return @[
      resultLine,
      "         expected: " & difference.expected,
      "         got:      " & difference.actual
    ]

  var differs = newSeq[bool](lineCount)
  var differCount = 0
  for index in 0 ..< lineCount:
    differs[index] = index >= expectedLines.len or index >= actualLines.len or
      expectedLines[index] != actualLines[index]
    if differs[index]:
      inc differCount

  # 長い答えは、違う行とその前後1行だけを残す
  var shownIndices: seq[int] = @[]
  for index in 0 ..< lineCount:
    let nearDifference = (index > 0 and differs[index - 1]) or differs[index] or
      (index + 1 < lineCount and differs[index + 1])
    if lineCount <= MaxTableRows or nearDifference:
      shownIndices.add(index)
  if shownIndices.len > MaxTableRows:
    shownIndices.setLen(MaxTableRows)

  proc cell(lines: seq[string], index: int): string =
    if index < lines.len: visibleLine(lines[index]) else: MissingLine

  var expectedWidth = "expected".len
  for index in shownIndices:
    expectedWidth = max(expectedWidth, displayWidth(cell(expectedLines, index)))
  expectedWidth = min(expectedWidth, MaxExpectedColumnWidth)
  let numberWidth = ($lineCount).len

  let summary =
    if differCount == 0: "  (" & $lineCount & "行とも同じに見える。空白の違いかもしれない)"
    else: "  (" & $lineCount & "行中" & $differCount & "行が違う)"
  result.add(resultLine & summary)
  result.add(TableIndent & "  " & repeat(' ', numberWidth) & "  " &
    padRight("expected", expectedWidth) & "  got")

  var previous = -1
  for index in shownIndices:
    if previous >= 0 and index > previous + 1:
      result.add(TableIndent & "  " & "...")
    let marker = if differs[index]: "> " else: "  "
    result.add(TableIndent & marker & align($(index + 1), numberWidth) & "  " &
      padRight(cell(expectedLines, index), expectedWidth) & "  " & cell(actualLines, index))
    previous = index

  if shownIndices.len < lineCount:
    result.add(TableIndent & "  ほか" & $(lineCount - shownIndices.len) &
      "行（--verbose で全文）")

# 答えなしのケースの出力。1行ならその場に、複数行なら下に並べる
proc unansweredLines(sample: SampleResult, resultLine: string): seq[string] =
  let outputLines = sample.actualLines
  if outputLines.len <= 1:
    let shown = if outputLines.len == 0: "(empty)" else: visibleLine(outputLines[0])
    return @[resultLine, "         output: " & shown]
  result.add(resultLine)
  result.add("         output:")
  for index, line in outputLines:
    if index >= MaxTableRows:
      result.add(TableIndent & "    ほか" & $(outputLines.len - MaxTableRows) &
        "行（--verbose で全文）")
      break
    result.add(TableIndent & "    " & visibleLine(line))

proc runtimeErrorReason(sample: SampleResult): string =
  let diagnostic = sample.stderrLines.join("\n").toLowerAscii()
  let rawReason = sample.reason.toLowerAscii()

  for memoryError in [
      "heap-buffer-overflow",
      "stack-buffer-overflow",
      "global-buffer-overflow",
      "heap-use-after-free",
      "stack-use-after-scope"
    ]:
    if memoryError in diagnostic:
      return memoryError

  if "stack overflow" in diagnostic or
      "return code 3221225725" in rawReason or
      "return code -1073741571" in rawReason:
    return "stack overflow"
  if "segmentation fault" in diagnostic or
      "sigsegv" in diagnostic or
      "access violation" in diagnostic or
      "return code 3221225477" in rawReason or
      "return code -1073741819" in rawReason or
      "return code -11" in rawReason:
    return "segmentation fault"
  if "division by zero" in diagnostic:
    return "division by zero"
  if "floating point exception" in diagnostic or "sigfpe" in diagnostic:
    return "floating-point exception"
  if "std::bad_alloc" in diagnostic or "out of memory" in diagnostic:
    return "out of memory"
  if "terminate called after throwing" in diagnostic or "uncaught exception" in diagnostic:
    return "uncaught exception"

  "abnormal termination"

const
  AcColor = "\e[38;5;118m"     # 黄緑
  NotAcColor = "\e[38;5;220m"  # 黄色
  ResetColor = "\e[0m"

proc renderReport*(report: TestReport, timeLimitSeconds: float, useColor = false): string =
  if report.results.len == 0:
    return ""

  proc paint(text: string, accepted: bool): string =
    if not useColor:
      return text
    (if accepted: AcColor else: NotAcColor) & text & ResetColor

  let total = report.results.len
  let numberWidth = ($total).len
  var passed = 0
  var unanswered = 0
  var wrongAnswers = 0
  var runtimeErrors = 0
  var timeouts = 0
  var totalSeconds = 0.0
  var lines: seq[string] = @[]

  for index, sample in report.results:
    if sample.seconds > 0.0:
      totalSeconds += sample.seconds

    case sample.verdict
    of verdictUnknown: discard
    of verdictAc: inc passed
    of verdictNoAnswer: inc unanswered
    of verdictWa: inc wrongAnswers
    of verdictRe: inc runtimeErrors
    of verdictTle: inc timeouts

    let position = "[" & align($(index + 1), numberWidth) & "/" & $total & "]"
    let verdictCell = alignLeft(verdictText(sample.verdict), 3)
    let verdict =
      if sample.verdict == verdictNoAnswer: verdictCell
      else: paint(verdictCell, sample.verdict == verdictAc)
    let elapsed = if sample.verdict == verdictTle:
      ">" & formatFloat(timeLimitSeconds, ffDecimal, 1) & " s"
    else:
      formatElapsed(sample.seconds)
    var resultLine = position & " " & verdict & "  " & align(elapsed, 7)
    # 自作ケースだけ名前を添え、サンプルと区別できるようにする
    if sample.name.isCustomCase():
      resultLine.add("  custom " & $sample.name.caseNumber())

    case sample.verdict
    of verdictWa:
      lines.add(wrongAnswerLines(sample, resultLine))
    of verdictRe:
      lines.add(resultLine)
      lines.add("         reason: " & runtimeErrorReason(sample))
    of verdictNoAnswer:
      lines.add(unansweredLines(sample, resultLine))
    else:
      lines.add(resultLine)

  # ケースの順にACを■、AC以外を□、答えなしを-で並べ、どのケースが落ちたかを1行で見せる
  var marks = ""
  for sample in report.results:
    marks.add(
      case sample.verdict
      of verdictAc: "■"
      of verdictNoAnswer: "-"
      else: "□")

  # 答えなしのケースは判定していないので、合格数・ケース数には数えない
  let judged = total - unanswered
  let unansweredNote = if unanswered > 0: "  (答えなし " & $unanswered & ")" else: ""
  lines.add("")
  if judged == 0:
    lines.add("DONE  " & marks & unansweredNote & "  test time " & formatElapsed(totalSeconds))
  elif passed == judged:
    lines.add(paint("PASS", true) & "  " & marks & "  " & $passed & "/" & $judged &
      unansweredNote & "  test time " & formatElapsed(totalSeconds))
  else:
    var counts: seq[string] = @[]
    if wrongAnswers > 0: counts.add("WA " & $wrongAnswers)
    if runtimeErrors > 0: counts.add("RE " & $runtimeErrors)
    if timeouts > 0: counts.add("TLE " & $timeouts)
    if unanswered > 0: counts.add("答えなし " & $unanswered)
    lines.add(paint("FAIL", false) & "  " & marks & "  " & $passed & "/" & $judged &
      "  (" & counts.join(", ") & ")")
    lines.add("      test time " & formatElapsed(totalSeconds))

  lines.join("\n")

# 答えなしのケースは、落ちていなければ合格として扱う
proc allPassed*(report: TestReport): bool =
  report.results.len > 0 and
    report.results.allIt(it.verdict in {verdictAc, verdictNoAnswer})

proc isComplete*(report: TestReport, expectedCount: int): bool =
  report.results.len == expectedCount and
    report.results.allIt(it.verdict != verdictUnknown and it.seconds >= 0.0)
