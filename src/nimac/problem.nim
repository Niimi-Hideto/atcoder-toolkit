import std/[os, sequtils, strutils, uri]

import ./errors

type
  Problem* = object
    contestId*: string
    taskId*: string
    url*: string

proc validateAtCoderUrl*(rawUrl: string): Problem =
  let parsed = parseUri(rawUrl)
  if parsed.scheme != "https" or parsed.hostname.toLowerAscii() != "atcoder.jp":
    raise newException(NimacError, "AtCoderのHTTPS URLを指定してください: " & rawUrl)

  let parts = parsed.path.split('/').filterIt(it.len > 0)
  if parts.len != 4 or parts[0] != "contests" or parts[2] != "tasks":
    raise newException(
      NimacError,
      "問題URLは https://atcoder.jp/contests/<contest>/tasks/<task> の形式で指定してください"
    )

  result = Problem(
    contestId: parts[1],
    taskId: parts[3],
    url: "https://atcoder.jp/contests/" & parts[1] & "/tasks/" & parts[3]
  )

proc inferProblem*(sourcePath: string): Problem =
  let sourceName = splitFile(sourcePath).name
  if sourceName.len < 2 or not sourceName[0].isAlphaAscii():
    raise newException(
      NimacError,
      "ファイル名から問題を判定できません。例: ABC_A/A484.cpp または --url を指定してください"
    )

  let contestNumber = sourceName[1 .. ^1]
  if contestNumber.len == 0 or not contestNumber.allCharsInSet(Digits):
    raise newException(
      NimacError,
      "ファイル名から問題を判定できません。例: ABC_A/A484.cpp または --url を指定してください"
    )

  let contestId = "abc" & contestNumber
  let taskId = contestId & "_" & sourceName[0].toLowerAscii()
  result = Problem(
    contestId: contestId,
    taskId: taskId,
    url: "https://atcoder.jp/contests/" & contestId & "/tasks/" & taskId
  )

proc resolveProblem*(sourcePath, explicitUrl: string): Problem =
  if explicitUrl.len > 0:
    validateAtCoderUrl(explicitUrl)
  else:
    inferProblem(sourcePath)

