# papimela

SDL3 を Free Pascal (FPC) の Object Pascal で書き直す再実装プロジェクト。
バインディングではない。SDL の C API を呼ぶコードは存在しない。

## 必ず読むもの

| 文書 | 内容 |
|---|---|
| `docs/DESIGN.md` | 設計の全体。11章の表が由来・難易度・実装担当の割り当て |
| `docs/CODING-STYLE.md` | コメント規約、ファイルヘッダ、移植コードの変換規則、命名 |
| `spikes/RESULTS.md` | 実測済みの事実（Wayland varargs、fcitx5 の文節取得） |
| `docs/TEST-LOG.md` | テスト実行一覧。未検証項目もここに列挙してある |
| `docs/DEFECTS.md` | 不具合一覧（修正済みも含む全件）。同じ罠を踏まないために読む |
| `docs/diagrams/` | クラス図5枚（Mermaid）。英語版が正、`_jp` が日本語版。`tools/check-diagrams.sh` が CI で整合性を検査する |

## 常に効く前提

- 初回スコープは **Linux / Wayland のコア機能のみ**。他プラットフォームは抽象化の
  拡張ポイントだけ用意し、実装しない。
- 移植部分は zlib ライセンスの派生物。ファイルヘッダの `Origin:` 行が必須で、
  `tools/checkorigin.bb` が `docs/DESIGN.md` 第11章の由来列との一致を CI で検査する。
- **SDL へのアップストリーム貢献は行わない（現時点では）。** SDL は AI 生成コードの
  貢献を受け付けない方針を明示している。バグを見つけても PR や Issue を出さない。
  ただし「AI が見つけたバグの報告まで含めて出すべきでないか」は結論が出ておらず、
  README で公開して意見を募っている。**結論が変わるまではこの規則に従う。**
- 参照用の SDL ソースは `reference/SDL`（gitignore 済み）。

## CI（push ごとに走る）

`.github/workflows/lint.yml` が **rawpaco の静的解析を激辛モード（`--fail-on=warning`）** で走らせる。
warning 1 件でも CI が落ちる。現在の指摘は 0 件なので、その状態を維持すること。

- 特に踏みやすいのは **空の例外ハンドラ**（`on E: ... do ;`）。例外を握り潰すなら、
  最低限どこかに記録を残す（`PaPiMeLa.TextInput.Fcitx` の `FLastNonFatalError` が実例）
- 誤検知や意図的な例外は、対象行か直前行に `// rawpaco:ignore <RuleId>` と書けば抑制できる。
  ただし**抑制の前に直せないかを考える**こと
- ローカルで事前に確認する:
  `<rawpacoのパス>/src/rawpaco --fail-on=warning src/*.pas src/generated/*.pas test/*.pas spikes/*.pas tools/*.pas examples/*.pas`
- 命名規則の既定（class `T`/`E`、interface `I`、pointer `P`、privateフィールド `F`）は
  papimela の規約と一致しているので `rawpaco.json` は置いていない

## 実装担当の割り振り

`docs/DESIGN.md` 第11章の難易度列に従う。Low は qwen2.5-coder:14b、Medium は
Sonnet 5、High は Opus 5。**qwen はスキルも CLAUDE.md も読まない**ので、
qwen に渡すプロンプトには `docs/CODING-STYLE.md` の内容を明示的に含める。

**qwen の呼び出しは `tools/qwen-gen.bb` を使う。** `ollama run` は TUI が ANSI
エスケープ（カーソル移動・行消去）を出力に混ぜるため、長い行が折り返される位置で
ソースが壊れる。`qwen-gen.bb` は HTTP API を叩くので素のテキストが返る。

```bash
tools/qwen-gen.bb プロンプトファイル 出力ファイル
```

実際の進め方（#34 で確立）:

1. interface 部（設計にあたる部分）はこちらで書く
2. 「implementation 部だけを書け」という指示と `docs/CODING-STYLE.md` の全文、
   各メソッドの振る舞いを 1 行ずつ書いた仕様、interface 部を渡す
3. 返ってきた実装を**必ず読んでから**採用する。#34 では 3 箇所（引数の取り違え、
   環境変数の部分適用、無駄な再計算）、#27 では中核 1 関数を丸ごと書き直した
4. **読むだけでは足りない。** #27 では読んで直したあとも 2 つ残っており、
   テストの往復検査で初めて出た（D-31）。規則を算出に置き換えた箇所は
   必ず機械的な検査を付ける
5. **検査を先に書き、空の実装で落ちることを確かめてから渡す**（#42 で確立）。
   空の実装で通ってしまう検査は何も保証しない。#42 では扇の検査がそうなっていた
6. **演算子の優先順位は仕様に括弧まで書く。** qwen は一貫して落とす（#27 の `shl`、
   #42 の `and` / `or` / `>=`）。Pascal は `and` が `or` より、`or` が比較より先に結合する
7. **仕様に大文字小文字だけで区別した名前を書かない**（`px` と `PX`）。Pascal では同じ名前
   になり、qwen はそのとおりに書いてくる（D-33）
8. 検査の「歯」を確かめるためにソースを差し替えるときは **`fpc -B`** で作り直す。
   同じ秒に書き戻すと古い `.ppu` が使われ、正しい修正を誤りと見誤る（D-34）

大きな定数表は qwen に書き写させない。#27 の 67 個の形式定数は SDL のヘッダから
awk で抽出し、手で書いた分と突き合わせて一致を確認してから採用した。
