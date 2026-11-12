# 自作ケースのファイル操作。サンプルと同じフォルダーに custom-1.in / custom-1.out として置く。
# 名前が sample- で始まらないので、サンプルの取り直しで消されることはない
import std/[algorithm, os, strutils]

import ./reporting

proc caseNumbers*(testDir, prefix: string): seq[int] =
  if not dirExists(testDir):
    return
  for kind, path in walkDir(testDir):
    let (_, name, ext) = splitFile(path)
    if kind == pcFile and ext == ".in" and name.startsWith(prefix):
      let number = caseNumber(name)
      if number > 0:
        result.add(number)
  result.sort()

proc customCaseNumbers*(testDir: string): seq[int] =
  caseNumbers(testDir, CustomPrefix)

proc customInputPath*(testDir: string, number: int): string =
  testDir / (CustomPrefix & $number & ".in")

proc customOutputPath*(testDir: string, number: int): string =
  testDir / (CustomPrefix & $number & ".out")

# 答え（.out）を登録していない自作ケースの名前
proc unansweredCustomNames*(testDir: string): seq[string] =
  for number in customCaseNumbers(testDir):
    if not fileExists(customOutputPath(testDir, number)):
      result.add(CustomPrefix & $number)

# 貼り付けた文字列を保存用にそろえる。改行をLFにし、末尾の空行を落として最後を改行で終える。
# 中身が空白だけなら空文字列を返す
proc normalizeCaseText*(text: string): string =
  var lines = text.replace("\r\n", "\n").replace('\r', '\n').split('\n')
  while lines.len > 0 and lines[^1].strip().len == 0:
    lines.setLen(lines.len - 1)
  if lines.len == 0:
    return ""
  lines.join("\n") & "\n"

# 次の番号で保存し、その番号を返す。削除で欠番があっても、番号は使い回さない
proc saveCustomCase*(testDir, input, answer: string): int =
  let numbers = customCaseNumbers(testDir)
  result = (if numbers.len > 0: numbers[^1] else: 0) + 1
  createDir(testDir)
  writeFile(customInputPath(testDir, result), input)
  if answer.len > 0:
    writeFile(customOutputPath(testDir, result), answer)

proc deleteCustomCase*(testDir: string, number: int): bool =
  let inputPath = customInputPath(testDir, number)
  if not fileExists(inputPath):
    return false
  removeFile(inputPath)
  removeFile(customOutputPath(testDir, number))
  true

# 一覧用に、ファイルの中身を「/」でつないだ1行にする
proc caseSummary*(path: string): string =
  const MaxLength = 60
  let text = normalizeCaseText(readFile(path)).strip(leading = false)
  result = text.replace("\n", " / ")
  if result.len > MaxLength:
    result = result[0 ..< MaxLength] & " ..."
  if result.len == 0:
    result = "(empty)"
