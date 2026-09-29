# 図

正は英語版 [`README.md`](README.md)

papimela のクラス図。GitHub がそのまま描画するよう Mermaid で書いてある。

| 図 | 対象 | 設計書の節 |
|---|---|---|
| [`backend-abstraction_jp.md`](backend-abstraction_jp.md) | SDL の 98 関数ポインタの god object をどう分解したか。ビデオ軸と IME 軸 | §3.2、§3.3 |
| [`ownership-graph_jp.md`](ownership-graph_jp.md) | `TPMLContext` が何を所有するか。破棄順序 | §2.4 |
| [`base-classes_jp.md`](base-classes_jp.md) | `TPMLObject` / `TPMLSystemObject` / `TPMLOwnedObject`。つまり誰が `Free` してよいか | §4.1 |
| [`event-model_jp.md`](event-model_jp.md) | `TPMLEvent`、キュー、ポンプソース、ウォッチ | §6 |
| [`ime-model_jp.md`](ime-model_jp.md) | 変換中テキストと文節の値型 | §7.3 |

## 規約

1. **英語版が正。** 日本語版は `_jp` 接尾辞を付け、散文だけを翻訳する。
2. **Mermaid ブロックは英日でバイト単位に同一。** 識別子が英語なのでラベルも英語にしてある。
   `tools/check-diagrams.sh` が CI でこれを検査する。
3. **実装済みの型だけを描く。** 予定はあるが未実装のものは散文で触れるだけにし、図には入れない。
   `tools/check-diagrams.sh` が、図に出てくる型がすべて `src/` に実在することを検査する。
4. **生成プロトコルの型は除外**（リスナークラス 45、不透明プロキシ型 80）。機械的な
   バインディングなので、`Twl_registry_listener` 1 つで全体を代表させている。
5. **構造は図に、理由は図の外の散文に。** Mermaid の箱に散文を詰めると両方とも読めなくなる。
6. Mermaid は保守的な構文に留める。メソッドは括弧付き、属性は単一トークン、`namespace` や
   `direction` は使わない。ローカルに Mermaid の検証手段が無く、GitHub の描画が唯一の確認手段であるため。

## 検査

```sh
./tools/check-diagrams.sh
```

push ごとに CI で実行される。図が実装に追いつかなくなったことは検出できるが、
実装にあって図に無いものは検出しない。図は実装の部分集合でよいという方針なので、これでよい。
