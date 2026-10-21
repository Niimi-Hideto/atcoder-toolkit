# nimac

`nimac`は、AtCoderのサンプルを初回だけ取得し、C++の解答をコンパイルして全サンプルを実行するNim製CLIです。

```text
nimac test ABC_A/A484.cpp
```

## 現在の機能

- `A484.cpp`というファイル名から`abc484_a`を判定
- 初回だけ公開問題ページからサンプルを取得
- 取得完了を確認できたサンプルは`.nimac/tests/<task-id>/`から再利用
- C++17としてコンパイル
- 全サンプルを実行し、`online-judge-tools`で期待値と比較
- `[1/10] AC  6 ms`形式で判定とローカル実行時間を表示
- WAでは最初に異なる行、REでは終了理由、TLEでは制限時間を簡潔に表示
- ログイン・提出・コード生成は行わない

## 必要なもの

- Nim 2.0以上
- C++17対応の`g++`
- [`online-judge-tools`](https://github.com/online-judge-tools/oj)の`oj`コマンド

公開済みの通常問題からサンプルを取得するだけなので、AtCoderアカウントへのログインは不要です。

## ビルド

```bash
nimble build -d:release
```

リポジトリ全体から使えるようにする場合は、Nimbleでインストールします。

```bash
nimble install
```

## 使い方

既存の`Atcorder`リポジトリのルートで実行します。

```bash
nimac test ABC_A/A484.cpp
```

```text
samples  2 cached
compile  OK  238 ms

[1/2] AC     27 ms
[2/2] AC      7 ms

PASS  2/2  test time 34 ms
```

失敗しても残りのサンプルを実行し、最後にまとめます。

```text
[1/4] AC     27 ms
[2/4] WA      9 ms
         expected: 42
         got:      41
[3/4] RE     13 ms
         exit code: 3
         stderr: boom
[4/4] TLE   >2.0 s

FAIL  1/4 passed  (WA 1, RE 1, TLE 1)
      test time 2.06 s
```

表示される時間はローカルでの計測値で、AtCoder上の実行時間とは一致しません。現在のローカル制限時間は1ケース2秒です。

現在のファイル命名規則では、先頭の英字を問題ラベル、残りの数字をABC番号として扱います。

| ファイル | 判定される問題 |
|---|---|
| `ABC_A/A484.cpp` | `abc484_a` |
| `ABC_B/B484.cpp` | `abc484_b` |
| `ABC_C/C484.cpp` | `abc484_c` |
鉄則本など命名規則が異なる問題ではURLを明示します。

```bash
nimac test main.cpp \
  --url https://atcoder.jp/contests/tessoku-book/tasks/tessoku_book_a
```

`oj`とコンパイラの元ログも確認したい場合は`--verbose`を付けます。

```bash
nimac test ABC_A/A484.cpp --verbose
```

処理の流れは次のとおりです。

1. 問題を判定する
2. サンプルがなければ`oj download`で取得する
3. `g++ -std=c++17 -O2 -Wall -Wextra`でコンパイルする
4. `oj test`で全サンプルを実行し、結果を簡潔な形式へ整形する

## テスト

```bash
nimble test
```

テストでは外部通信を行わず、偽物の`oj`と`g++`を使って初回取得とキャッシュ再利用を検証します。

## 生成ファイル

実行時のファイルは、対象のGitリポジトリ直下に作られます。

```text
.nimac/
├── build/
└── tests/
```

AtCoderの解答リポジトリ側でも`.nimac/`を`.gitignore`へ追加してください。

## 現在の対象外

- 自動提出
- AtCoderへのログイン
- ファイル保存時の自動再実行
- 自作テストケース管理
- デバッグ用サニタイザー
- PythonなどC++以外の解答

