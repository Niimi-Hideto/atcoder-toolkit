import std/[math, parseutils, sequtils, strutils]

type
  Verdict* = enum
    verdictUnknown,
    verdictAc,
    verdictWa,
    verdictRe,
    verdictTle

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

    if control.startsWith("[INFO] sample-"):
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

proc verdictText(verdict: Verdict): string =
  case verdict
  of verdictUnknown: "?"
  of verdictAc: "AC"
  of verdictWa: "WA"
  of verdictRe: "RE"
  of verdictTle: "TLE"

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
  MaxTableRows = 20
  MaxExpectedColumnWidth = 40
  MissingLine = "(なし)"
  TableIndent = "       "

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
    expectedWidth = max(expectedWidth, cell(expectedLines, index).len)
  expectedWidth = min(expectedWidth, MaxExpectedColumnWidth)
  let numberWidth = ($lineCount).len

  let summary =
    if differCount == 0: "  (" & $lineCount & "行とも同じに見える。空白の違いかもしれない)"
    else: "  (" & $lineCount & "行中" & $differCount & "行が違う)"
  result.add(resultLine & summary)
  result.add(TableIndent & "  " & repeat(' ', numberWidth) & "  " &
    alignLeft("expected", expectedWidth) & "  got")

  var previous = -1
  for index in shownIndices:
    if previous >= 0 and index > previous + 1:
      result.add(TableIndent & "  " & "...")
    let marker = if differs[index]: "> " else: "  "
    result.add(TableIndent & marker & align($(index + 1), numberWidth) & "  " &
      alignLeft(cell(expectedLines, index), expectedWidth) & "  " & cell(actualLines, index))
    previous = index

  if shownIndices.len < lineCount:
    result.add(TableIndent & "  ほか" & $(lineCount - shownIndices.len) &
      "行（--verbose で全文）")

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

proc renderReport*(report: TestReport, timeLimitSeconds: float): string =
  if report.results.len == 0:
    return ""

  let total = report.results.len
  let numberWidth = ($total).len
  var passed = 0
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
    of verdictWa: inc wrongAnswers
    of verdictRe: inc runtimeErrors
    of verdictTle: inc timeouts

    let position = "[" & align($(index + 1), numberWidth) & "/" & $total & "]"
    let verdict = alignLeft(verdictText(sample.verdict), 3)
    let elapsed = if sample.verdict == verdictTle:
      ">" & formatFloat(timeLimitSeconds, ffDecimal, 1) & " s"
    else:
      formatElapsed(sample.seconds)
    let resultLine = position & " " & verdict & "  " & align(elapsed, 7)

    if sample.verdict == verdictWa:
      lines.add(wrongAnswerLines(sample, resultLine))
    elif sample.verdict == verdictRe:
      lines.add(resultLine)
      lines.add("         reason: " & runtimeErrorReason(sample))
    else:
      lines.add(resultLine)

  # ケースの順にACを■、それ以外を□で並べ、どのケースが落ちたかを1行で見せる
  var marks = ""
  for sample in report.results:
    marks.add(if sample.verdict == verdictAc: "■" else: "□")

  lines.add("")
  if passed == total:
    lines.add("PASS  " & marks & "  " & $passed & "/" & $total &
      "  test time " & formatElapsed(totalSeconds))
  else:
    var counts: seq[string] = @[]
    if wrongAnswers > 0: counts.add("WA " & $wrongAnswers)
    if runtimeErrors > 0: counts.add("RE " & $runtimeErrors)
    if timeouts > 0: counts.add("TLE " & $timeouts)
    lines.add("FAIL  " & marks & "  " & $passed & "/" & $total & "  (" & counts.join(", ") & ")")
    lines.add("      test time " & formatElapsed(totalSeconds))

  lines.join("\n")

proc allPassed*(report: TestReport): bool =
  report.results.len > 0 and report.results.allIt(it.verdict == verdictAc)

proc isComplete*(report: TestReport, expectedCount: int): bool =
  report.results.len == expectedCount and
    report.results.allIt(it.verdict != verdictUnknown and it.seconds >= 0.0)
