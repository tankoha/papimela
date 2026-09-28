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

## 常に効く前提

- 初回スコープは **Linux / Wayland のコア機能のみ**。他プラットフォームは抽象化の
  拡張ポイントだけ用意し、実装しない。
- 移植部分は zlib ライセンスの派生物。ファイルヘッダの `Origin:` 行が必須で、
  `tools/checkorigin` が `docs/DESIGN.md` 第11章の由来列との一致を検査する。
- **SDL へのアップストリーム貢献は行わない。** SDL は AI 生成コードの貢献を
  受け付けない方針を明示している。バグを見つけても PR や Issue を出さない。
- 参照用の SDL ソースは `reference/SDL`（gitignore 済み）。

## CI（push ごとに走る）

`.github/workflows/lint.yml` が **rawpaco の静的解析を激辛モード（`--fail-on=warning`）** で走らせる。
warning 1 件でも CI が落ちる。現在の指摘は 0 件なので、その状態を維持すること。

- 特に踏みやすいのは **空の例外ハンドラ**（`on E: ... do ;`）。例外を握り潰すなら、
  最低限どこかに記録を残す（`PaPiMeLa.TextInput.Fcitx` の `FLastNonFatalError` が実例）
- 誤検知や意図的な例外は、対象行か直前行に `// rawpaco:ignore <RuleId>` と書けば抑制できる。
  ただし**抑制の前に直せないかを考える**こと
- ローカルで事前に確認する:
  `<rawpacoのパス>/src/rawpaco --fail-on=warning src/*.pas src/generated/*.pas test/*.pas spikes/*.pas tools/*.pas`
- 命名規則の既定（class `T`/`E`、interface `I`、pointer `P`、privateフィールド `F`）は
  papimela の規約と一致しているので `rawpaco.json` は置いていない

## 実装担当の割り振り

`docs/DESIGN.md` 第11章の難易度列に従う。Low は qwen2.5-coder:14b、Medium は
Sonnet 5、High は Opus 5。**qwen はスキルも CLAUDE.md も読まない**ので、
qwen に渡すプロンプトには `docs/CODING-STYLE.md` の内容を明示的に含める。
