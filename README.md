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
- 初回だけ公開問題ページからサンプルを取得し、2回目以降は保存済みのサンプルを再利用
- C++17としてコンパイルし、全サンプルを`online-judge-tools`で期待値と比較
- `[1/10] AC  6 ms`形式で判定とローカル実行時間を表示
- WAでは最初に異なる行、REでは終了理由、TLEでは制限時間を簡潔に表示
- 制限時間（`--tl`）と小数の許容誤差（`--error`）を指定可能
- コンパイルしてから、入力を手打ちで試せる（`actk run`）
- コンパイラの警告を、行番号順に1件1行で表示
- ログイン・提出・AIによる解答生成は行わない

## 導入

### 必要なもの

- Nim 2.0以上
- C++17対応の`g++`（`#include <bits/stdc++.h>`を使える環境）
- [`online-judge-tools`](https://github.com/online-judge-tools/oj)の`oj`コマンド

公開済みの通常問題からサンプルを取得するだけなので、AtCoderアカウントへのログインは不要です。

### インストール（macOS）

NimとNimble（Nimのパッケージ管理）はHomebrewで、`oj`はpipで入れます。

```bash
brew install nim
pip install online-judge-tools
```

このリポジトリを取得して、`actk`をインストールします。

```bash
git clone https://github.com/Niimi-Hideto/atcoder-toolkit.git
cd atcoder-toolkit
nimble install
```

`actk`は`~/.nimble/bin`に入ります。どのフォルダーからでも`actk`だけで起動できるように、`~/.zshrc`へ次の行を追加してPATHに登録します。

```bash
export PATH="$HOME/.nimble/bin:$PATH"
```

ターミナルを開き直す（または`source ~/.zshrc`を実行する）と反映されます。使い方が表示されれば完了です。

```bash
actk --help
```

Windowsでも、NimとNimble、`oj`を入れて`nimble install`を実行し、`%USERPROFILE%\.nimble\bin`をPATHへ追加すれば同様に使えます。

ツール自体を修正したときは、`nimble install`をもう一度実行すると反映されます。インストールせずに試す場合は、リポジトリ内でビルドして直接実行します。

```bash
nimble build -d:release
./actk --help
```

## 使い方

### コンテスト前の準備

`template.cpp`がある`Atcorder`リポジトリのルートで実行します。

```bash
actk init 484
```

`template.cpp`をコピーして、次の4ファイルを作成します。`actk init abc484`でも同じ結果になります。

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

解答ファイルを指定します。`test`はリポジトリ内のどのフォルダーからでも実行できます。

```bash
actk test ABC_A/A484.cpp
```

```text
samples  2 cached
compile  OK  238 ms

[1/2] AC     27 ms
[2/2] AC      7 ms

PASS  ■■  2/2  test time 34 ms
```

失敗しても残りのサンプルを実行し、最後にまとめます。`PASS`／`FAIL`の行の■□はケースの順に並んだ判定で、■がAC、□がAC以外です。

```text
[1/4] AC     27 ms
[2/4] WA      9 ms
         expected: 42
         got:      41
[3/4] RE     13 ms
         reason: abnormal termination
[4/4] TLE   >2.0 s

FAIL  ■□□□  1/4  (WA 1, RE 1, TLE 1)
      test time 2.06 s
```

REでは、判別できる場合は`segmentation fault`や`heap-buffer-overflow`などを表示し、それ以外は`abnormal termination`と表示します。

表示される時間はローカルでの計測値で、AtCoder上の実行時間とは一致しません。

### コンパイラの警告

コンパイルに成功しても警告があれば、件数をコンパイル行に、内容を結果の後ろに表示します（`test`・`run`共通）。

```text
compile  OK  462 ms  (warning 3)
...
PASS  ■■■  3/3  test time 34 ms

warning  3
  L8   unused variable 'b'
  L12  variable 'sum' is uninitialized when used here
  L14  '&&' within '||'
```

- 行番号の順に、コンパイラの原文を1件1行で表示します
- 直し方の提案（`note:`）は表示しません。元の出力は`--verbose`で確認できます
- 6件以上ある場合は5件まで表示し、残りは件数だけ表示します

サンプルがACでも、初期化していない変数のように提出先で結果が変わる原因になる警告があります。ACのときも確認してください。

### 手打ちで試す

境界値など、自分で考えた入力を試すときは`run`を使います。毎回コンパイルし直してから実行するので、古い実行ファイルが動くことはありません。

```bash
actk run ABC_Re_B/B474_2.cpp
```

```text
compile  OK  380 ms

run      入力を打ってEnter（入力の終わりは Ctrl-D）
----------------------------------------
10
1
----------------------------------------
exit     0
```

2つの線の間で入力を打つと、解答の出力がそのまま表示されます。入力を最後まで読む解答では、`Ctrl-D`で入力の終わりを伝えます。

異常終了した場合は終了コードと原因の目安を表示します（例：`exit 139  segmentation fault（範囲外アクセスなど）`）。コンパイルに失敗したときは実行しません。

入力が長いときは、ファイルに保存して流し込むこともできます。

```bash
actk run ABC_C/C484.cpp < input.txt
```

### オプション

オプションは**解答ファイルの後ろ**に書きます。`actk test --tl 3 ABC_C/C484.cpp`のように前へ書くとエラーになります。`run`で使えるのは`--verbose`だけです。

| オプション | 用途 |
|---|---|
| `--tl <秒>` | 1ケースの制限時間。既定は2秒。制限時間が長い問題で指定する |
| `--error <許容誤差>` | 小数を答える問題で、数値として誤差の範囲内なら正解にする |
| `--url <問題URL>` | ファイル名から判定できない問題で、問題を直接指定する |
| `--verbose` | `oj`とコンパイラの元ログ（終了コードや標準エラーを含む）も表示する |

```bash
actk test ABC_C/C484.cpp --tl 3
actk test ABC_B/B484.cpp --error 1e-6
actk test main.cpp --url https://atcoder.jp/contests/arc180/tasks/arc180_a
actk test ABC_A/A484.cpp --verbose
```

`--error`は、問題文に「絶対誤差または相対誤差が10^-6以下なら正解」のように書かれているときに使います。指定しないと出力の完全一致で判定するため、`0.5`と`0.5000000000`のように値が同じでもWAになります。

## ファイル名からの問題判定

ファイル名から問題を判定するため、通常は`--url`なしで実行できます。

- 末尾の`_2`・`_3`など数字の接尾辞は、復習回数として無視します
- フォルダーの位置は判定に影響しません
- 接尾辞を除いた名前が`A`・`B`・`C`と2桁の数字なら鉄則本、それ以外は`A484`形式のABCとして判定します

| ファイル | 判定される問題 |
|---|---|
| `ABC_A/A484.cpp` | `abc484_a` |
| `ABC_C/C484.cpp` | `abc484_c` |
| `ABC_Re_B/B474_2.cpp` | `abc474_b` |
| `競技プログラミングの鉄則/01_アルゴリズムと計算量/A04_2.cpp` | `tessoku_book_d` |
| `競技プログラミングの鉄則/02_累積和/A06.cpp` | `math_and_algorithm_ai` |
| `競技プログラミングの鉄則/04_動的計画法/B16.cpp` | `dp_a` |

鉄則本の演習ページには、他のコンテストの問題をそのまま掲載している番号が14問あります（`A06`・`A27`・`A29`・`A39`・`A50`・`A62`・`A63`・`A77`・`B07`・`B16`・`B28`・`B63`・`C09`・`C18`）。これらも掲載先の問題IDで判定します。

演習ページに掲載されていない欠番（`A47`、`B05`など）は、誤ったURLへアクセスせずエラーにします。

## 処理の流れ

1. ファイル名（または`--url`）から問題を判定する
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

## 生成ファイル

実行時のファイルは、解答ファイルを含むGitリポジトリの直下に作られます。

```text
.actk/
├── build/              # コンパイルした実行ファイル（test・run共通）
└── tests/<問題ID>/     # 取得したサンプル
```

解答リポジトリ側の`.gitignore`へ`.actk/`を追加してください。

サンプルを取り直したいときは、その問題のフォルダーを消すと次回の実行で再取得します。取得が途中で中断された場合は、消さなくても自動で取り直します。

```bash
rm -rf .actk/tests/abc484_a
```

## 正しく判定できないケース

- **ABC001〜ABC019：** 問題IDが`abc001_1`のような数字形式のため、ファイル名からは判定できません。`--url`で指定してください
- **答えが複数ある問題：** 「条件を満たすものをどれか1つ出力」のような問題は、正しい答えでも期待値と違えばWAと表示されます
- **インタラクティブ問題：** 対応していません

## 現在の対象外

- 自動提出
- AtCoderへのログイン
- ファイル保存時の自動再実行
- 自作テストケース管理
- デバッグ用サニタイザー
- PythonなどC++以外の解答

## テスト

```bash
nimble test
```

テストでは外部通信を行わず、`oj`と`g++`の呼び出しを偽物に差し替えて、初回取得・キャッシュ再利用・中断後の再取得を検証します。
