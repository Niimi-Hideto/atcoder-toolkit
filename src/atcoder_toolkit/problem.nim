import std/[os, sequtils, strutils, uri]

import ./errors

type
  Problem* = object
    contestId*: string
    taskId*: string
    url*: string

const TessokuContestId = "tessoku-book"

proc makeProblem(contestId, taskId: string): Problem =
  Problem(
    contestId: contestId,
    taskId: taskId,
    url: "https://atcoder.jp/contests/" & contestId & "/tasks/" & taskId
  )

proc isValidTessokuProblem(section: char, number: int): bool =
  case section
  of 'A':
    number in 1 .. 46 or number in 49 .. 77
  of 'B':
    case number
    of 1, 2, 3, 4, 6, 7, 8, 9,
        11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 23, 24,
        26, 27, 28, 29, 30, 31, 32, 33, 34, 36, 37, 38, 39,
        40, 41, 42, 43, 44, 45, 51, 52, 54, 55, 56, 57, 58,
        59, 61, 62, 63, 64, 65, 66, 67, 68, 69:
      true
    else:
      false
  of 'C':
    number in 1 .. 20
  else:
    false

proc toAlphabeticId(value: int): string =
  var remaining = value
  while remaining > 0:
    dec remaining
    result = char(ord('a') + remaining mod 26) & result
    remaining = remaining div 26

proc inferTessokuProblem(sourceName: string): Problem =
  let section = sourceName[0].toUpperAscii()
  let number = parseInt(sourceName[1 .. 2])
  if not isValidTessokuProblem(section, number):
    raise newException(
      AcktError,
      "鉄則本の問題番号が見つかりません: " & sourceName &
        "（AtCoder掲載のA01-A77・B01-B69・C01-C20のみ対応）"
    )

  let taskId =
    if section == 'A' and number == 77:
      "typical90_a"
    elif section == 'C' and number == 18:
      "typical90_s"
    else:
      let sequentialNumber = (ord(section) - ord('A')) * 77 + number
      "tessoku_book_" & toAlphabeticId(sequentialNumber)

  makeProblem(TessokuContestId, taskId)

proc validateAtCoderUrl*(rawUrl: string): Problem =
  let parsed = parseUri(rawUrl)
  if parsed.scheme != "https" or parsed.hostname.toLowerAscii() != "atcoder.jp":
    raise newException(AcktError, "AtCoderのHTTPS URLを指定してください: " & rawUrl)

  let parts = parsed.path.split('/').filterIt(it.len > 0)
  if parts.len != 4 or parts[0] != "contests" or parts[2] != "tasks":
    raise newException(
      AcktError,
      "問題URLは https://atcoder.jp/contests/<contest>/tasks/<task> の形式で指定してください"
    )

  result = makeProblem(parts[1], parts[3])

proc inferProblem*(sourcePath: string): Problem =
  let sourceName = splitFile(sourcePath).name
  if sourceName.len < 2 or not sourceName[0].isAlphaAscii():
    raise newException(
      AcktError,
      "ファイル名から問題を判定できません。例: ABC_A/A484.cpp または --url を指定してください"
    )

  if sourceName.len == 3 and
      sourceName[0].toUpperAscii() in {'A', 'B', 'C'} and
      sourceName[1 .. 2].allCharsInSet(Digits):
    return inferTessokuProblem(sourceName)

  let contestNumber = sourceName[1 .. ^1]
  if contestNumber.len == 0 or not contestNumber.allCharsInSet(Digits):
    raise newException(
      AcktError,
      "ファイル名から問題を判定できません。例: ABC_A/A484.cpp または --url を指定してください"
    )

  let contestId = "abc" & contestNumber
  let taskId = contestId & "_" & sourceName[0].toLowerAscii()
  result = makeProblem(contestId, taskId)

proc resolveProblem*(sourcePath, explicitUrl: string): Problem =
  if explicitUrl.len > 0:
    validateAtCoderUrl(explicitUrl)
  else:
    inferProblem(sourcePath)

