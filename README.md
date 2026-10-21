# AtCoderToolKit

`actk`は、ABCの解答ファイルを準備し、AtCoderのサンプルを初回だけ取得して、C++の解答をコンパイル・テストするNim製ツールキットです。

```text
actk test ABC_A/A484.cpp
```

## 現在の機能

- `A484.cpp`というファイル名から`abc484_a`を判定
- `A484_2.cpp`のような復習用ファイルを元の問題として判定
- `A01.cpp`・`B01.cpp`・`C01.cpp`形式から鉄則本の問題を判定
- `template.cpp`からABCのA〜Dファイルを一括作成
- 初回だけ公開問題ページからサンプルを取得
- 取得完了を確認できたサンプルは`.actk/tests/<task-id>/`から再利用
- C++17としてコンパイル
- 全サンプルを実行し、`online-judge-tools`で期待値と比較
- `[1/10] AC  6 ms`形式で判定とローカル実行時間を表示
- WAでは最初に異なる行、REでは終了理由、TLEでは制限時間を簡潔に表示
- ログイン・提出・AIによる解答生成は行わない

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

### コンテスト前の準備

```bash
actk init 484
```

ルートの`template.cpp`をコピーして、次の4ファイルを作成します。`actk init abc484`でも同じ結果になります。

```text
ABC_A/A484.cpp
ABC_B/B484.cpp
ABC_C/C484.cpp
ABC_D/D484.cpp
```

```text
contest  abc484
created  ABC_A/A484.cpp
created  ABC_B/B484.cpp
created  ABC_C/C484.cpp
created  ABC_D/D484.cpp

READY  4 created, 0 skipped
```

既存ファイルは上書きせず`skipped`と表示します。ネットワーク通信やサンプル取得は行いません。

### サンプルテスト

```bash
actk test ABC_A/A484.cpp
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
         reason: abnormal termination
[4/4] TLE   >2.0 s

FAIL  1/4 passed  (WA 1, RE 1, TLE 1)
      test time 2.06 s
```

REでは、判別できる場合は`segmentation fault`や`heap-buffer-overflow`などを表示し、それ以外は`abnormal termination`と表示します。終了コードや標準エラーを含む元ログは`--verbose`で確認できます。

表示される時間はローカルでの計測値で、AtCoder上の実行時間とは一致しません。ローカル制限時間は既定で1ケース2秒です。制限時間が長い問題では`--tl`で秒数を指定します。

```bash
actk test ABC_C/C484.cpp --tl 3
```

「絶対誤差または相対誤差が10^-6以下なら正解」のように小数を答える問題では、`--error`で許容誤差を指定します。指定しないと出力の完全一致で判定するため、正しい答えでもWAになることがあります。

```bash
actk test ABC_B/B484.cpp --error 1e-6
```

末尾の`_2`・`_3`など数字の接尾辞は復習回数として無視します。フォルダーの位置は判定に影響しないため、たとえば`ABC_Re_B/B474_2.cpp`は`B474.cpp`と同じ問題、鉄則本の章フォルダー内にある`A04_2.cpp`は`A04.cpp`と同じ問題として扱います。

接尾辞を除いた名前が`A`・`B`・`C`と2桁の数字だけで構成されていれば鉄則本として扱い、それ以外は従来の`A484.cpp`形式としてABCを判定します。

| ファイル | 判定される問題 |
|---|---|
| `ABC_A/A484.cpp` | `abc484_a` |
| `ABC_Re_B/B474_2.cpp` | `abc474_b` |
| `ABC_B/B484.cpp` | `abc484_b` |
| `ABC_C/C484.cpp` | `abc484_c` |
| `tessoku/A01.cpp` | `tessoku_book_a` |
| `競技プログラミングの鉄則/01_アルゴリズムと計算量/A04_2.cpp` | `tessoku_book_d` |
| `tessoku/B01.cpp` | `tessoku_book_bz` |
| `tessoku/A06.cpp` | `math_and_algorithm_ai` |
| `tessoku/B16.cpp` | `dp_a` |
| `tessoku/A77.cpp` | `typical90_a` |
| `tessoku/C18.cpp` | `typical90_s` |

鉄則本の演習ページには、他のコンテストの問題をそのまま掲載している番号が14問あります（`A06`・`A27`・`A29`・`A39`・`A50`・`A62`・`A63`・`A77`・`B07`・`B16`・`B28`・`B63`・`C09`・`C18`）。これらは掲載先の問題IDで判定するため、鉄則本はURLを付けずに実行できます。

```bash
actk test tessoku/A01.cpp
actk test tessoku/B01.cpp
```

AtCoderの鉄則本演習ページに掲載されていない欠番（`A47`、`B05`など）は、誤ったURLへアクセスせずエラーにします。その他のコンテストや異なる命名規則ではURLを明示します。

```bash
actk test main.cpp \
  --url https://atcoder.jp/contests/tessoku-book/tasks/tessoku_book_a
```

`oj`とコンパイラの元ログも確認したい場合は`--verbose`を付けます。

```bash
actk test ABC_A/A484.cpp --verbose
```

処理の流れは次のとおりです。

1. 問題を判定する
2. サンプルがなければ`oj download`で取得する
3. `g++ -std=c++17 -O2 -Wall -Wextra`でコンパイルする
4. `oj test`で全サンプルを実行し、結果を簡潔な形式へ整形する

使うコマンドは環境変数で差し替えられます。たとえばmacOSの`g++`（Apple clang）で`bits/stdc++.h`が見つからない場合は、Homebrewの`g++-15`などを指定します。

| 環境変数 | 既定値 | 用途 |
|---|---|---|
| `ACTK_CXX` | `g++` | コンパイラ |
| `ACTK_OJ` | `oj` | `online-judge-tools`のコマンド |

```bash
ACTK_CXX=g++-15 actk test ABC_A/A484.cpp
```

## テスト

```bash
nimble test
```

テストでは外部通信を行わず、`oj`と`g++`の呼び出しを偽物に差し替えて、初回取得・キャッシュ再利用・中断後の再取得を検証します。

## 生成ファイル

実行時のファイルは、対象のGitリポジトリ直下に作られます。

```text
.actk/
├── build/
└── tests/
```

AtCoderの解答リポジトリ側でも`.actk/`を`.gitignore`へ追加してください。

## 現在の対象外

- 自動提出
- AtCoderへのログイン
- ファイル保存時の自動再実行
- 自作テストケース管理
- デバッグ用サニタイザー
- PythonなどC++以外の解答

