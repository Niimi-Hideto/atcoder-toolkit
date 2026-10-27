import std/[algorithm, strutils]

type
  CompilerWarning* = object
    line*: int
    message*: string

const
  WarningMarker = ": warning: "
  MaxShownWarnings = 5
  FrameWidth = 40

# clang・GCC共通の「<path>:<line>:<col>: warning: <message> [-W<flag>]」形式を読む
proc parseCompilerWarnings*(output: string): seq[CompilerWarning] =
  for rawLine in output.splitLines():
    let marker = rawLine.find(WarningMarker)
    if marker < 0:
      continue

    # Windowsのパスにも「:」が含まれるため、右から行番号と列番号を取り出す
    let location = rawLine[0 ..< marker].rsplit(':', maxsplit = 2)
    if location.len < 3:
      continue
    var line: int
    try:
      line = parseInt(location[1])
    except ValueError:
      continue

    var message = rawLine[marker + WarningMarker.len .. ^1].strip()
    let flagStart = message.rfind(" [-W")
    if flagStart >= 0 and message.endsWith("]"):
      message.setLen(flagStart)

    let warning = CompilerWarning(line: line, message: message)
    if warning notin result:
      result.add(warning)

  result.sort(proc (a, b: CompilerWarning): int = cmp(a.line, b.line))

proc renderWarnings*(warnings: seq[CompilerWarning]): string =
  if warnings.len == 0:
    return ""

  # ACのときに見落とさないよう、一覧を「=」の線で上下から挟む
  let title = " warning " & $warnings.len & " "
  let leftRule = (FrameWidth - title.len) div 2
  let rightRule = FrameWidth - title.len - leftRule

  let shown = warnings[0 ..< min(warnings.len, MaxShownWarnings)]
  let labelWidth = ("L" & $shown[^1].line).len
  var lines = @[repeat('=', leftRule) & title & repeat('=', rightRule)]
  for warning in shown:
    lines.add("  " & alignLeft("L" & $warning.line, labelWidth) & "  " & warning.message)
  if warnings.len > shown.len:
    lines.add("  ほか" & $(warnings.len - shown.len) & "件（--verbose で表示）")
  lines.add(repeat('=', FrameWidth))
  lines.join("\n")
