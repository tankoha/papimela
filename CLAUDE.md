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

## 実装担当の割り振り

`docs/DESIGN.md` 第11章の難易度列に従う。Low は qwen2.5-coder:14b、Medium は
Sonnet 5、High は Opus 5。**qwen はスキルも CLAUDE.md も読まない**ので、
qwen に渡すプロンプトには `docs/CODING-STYLE.md` の内容を明示的に含める。
