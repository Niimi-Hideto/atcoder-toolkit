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
    var resultLine = position & " " & verdict & "  " & align(elapsed, 7)

    if sample.verdict == verdictWa:
      let difference = firstDifference(sample)
      if max(sample.expectedLines.len, sample.actualLines.len) > 1 or difference.lineNumber > 1:
        resultLine.add("  line " & $difference.lineNumber)
      lines.add(resultLine)
      lines.add("         expected: " & difference.expected)
      lines.add("         got:      " & difference.actual)
    elif sample.verdict == verdictRe:
      lines.add(resultLine)
      if sample.reason.startsWith("return code "):
        lines.add("         exit code: " & sample.reason["return code ".len .. ^1])
      elif sample.reason.len > 0:
        lines.add("         reason: " & sample.reason)
      if sample.stderrLines.len > 0:
        lines.add("         stderr: " & visibleLine(sample.stderrLines[0]))
    else:
      lines.add(resultLine)

  lines.add("")
  if passed == total:
    lines.add("PASS  " & $passed & "/" & $total & "  test time " & formatElapsed(totalSeconds))
  else:
    var counts: seq[string] = @[]
    if wrongAnswers > 0: counts.add("WA " & $wrongAnswers)
    if runtimeErrors > 0: counts.add("RE " & $runtimeErrors)
    if timeouts > 0: counts.add("TLE " & $timeouts)
    lines.add("FAIL  " & $passed & "/" & $total & " passed  (" & counts.join(", ") & ")")
    lines.add("      test time " & formatElapsed(totalSeconds))

  lines.join("\n")

proc allPassed*(report: TestReport): bool =
  report.results.len > 0 and report.results.allIt(it.verdict == verdictAc)

proc isComplete*(report: TestReport, expectedCount: int): bool =
  report.results.len == expectedCount and
    report.results.allIt(it.verdict != verdictUnknown and it.seconds >= 0.0)
