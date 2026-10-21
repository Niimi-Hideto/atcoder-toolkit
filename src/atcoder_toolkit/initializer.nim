import std/[os, strutils]

import ./errors

const TaskLetters = ['A', 'B', 'C', 'D']

type
  InitResult* = object
    contestId*: string
    created*: seq[string]
    skipped*: seq[string]

proc normalizeContestNumber*(rawContest: string): string =
  var number = rawContest.strip().toLowerAscii()
  if number.startsWith("abc"):
    number = if number.len == 3: "" else: number[3 .. ^1]

  if number.len == 0 or not number.allCharsInSet(Digits):
    raise newException(
      ActkError,
      "ABCのコンテスト番号を指定してください。例: 484 または abc484"
    )

  var firstNonZero = 0
  while firstNonZero < number.len and number[firstNonZero] == '0':
    inc firstNonZero
  if firstNonZero == number.len:
    raise newException(ActkError, "ABCのコンテスト番号は1以上を指定してください")

  number = number[firstNonZero .. ^1]
  if number.len < 3:
    number = repeat('0', 3 - number.len) & number
  number

proc initializeContest*(rawContest, projectRoot: string): InitResult =
  let contestNumber = normalizeContestNumber(rawContest)
  let templatePath = projectRoot / "template.cpp"
  if not dirExists(projectRoot):
    raise newException(ActkError, "作業フォルダーが見つかりません: " & projectRoot)
  if not fileExists(templatePath):
    raise newException(
      ActkError,
      "template.cppが見つかりません。Atcorderリポジトリのルートで実行してください"
    )

  let templateText =
    try:
      readFile(templatePath)
    except OSError as error:
      raise newException(ActkError, "template.cppを読み込めません: " & error.msg)

  result.contestId = "abc" & contestNumber
  for task in TaskLetters:
    let directoryName = "ABC_" & $task
    let fileName = $task & contestNumber & ".cpp"
    let relativePath = directoryName & "/" & fileName
    let targetDirectory = projectRoot / directoryName
    let targetPath = targetDirectory / fileName

    if fileExists(targetPath):
      result.skipped.add(relativePath)
      continue

    try:
      createDir(targetDirectory)
      writeFile(targetPath, templateText)
      result.created.add(relativePath)
    except OSError as error:
      raise newException(ActkError, "ファイルを作成できません: " & relativePath & "\n" & error.msg)

proc initializeContest*(rawContest: string): InitResult =
  initializeContest(rawContest, getCurrentDir())
