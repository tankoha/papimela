# 参照した SDL の版

各ソースの見出しにある `SDL revision: see docs/ORIGIN.md` の参照先。移植部分（Origin が
`ported from SDL` / `partially ported from SDL` のユニット）は、すべて下の 1 つの版を読んで
書いた。設計書 §1.4 の取り決めどおり、版はここ 1 箇所で管理する。

| 項目 | 値 |
|---|---|
| リポジトリ | https://github.com/libsdl-org/SDL |
| ブランチ | `main`（3.x 系） |
| コミット | `1ce4c5bc2916702e8e0f6df1f612dbd8633011da` |
| コミット日 | 2026-09-26（"ci: update cmake warning flags of the BSDs"） |
| 置き場所 | `reference/SDL`（`.gitignore` 済み。リポジトリには入っていない） |

## 取り直し方

`reference/SDL` はリポジトリに入っていないので、新しい作業環境では取り直す。

```bash
git clone https://github.com/libsdl-org/SDL.git reference/SDL
git -C reference/SDL checkout 1ce4c5bc2916702e8e0f6df1f612dbd8633011da
```

## 何がこれを読むか

ビルドと CI は `reference/SDL` を必要としない。要るのは、表や定数を**作り直す**ときと、
移植の続きを書くときだけ。

| 使うもの | 読む場所 |
|---|---|
| `tools/genscancodes.bb`（キーボードの表） | `include/SDL3/SDL_scancode.h`、`SDL_keycode.h`、`src/events/` の 4 ファイル |
| `tools/genkhronos.bb`（EGL / GLES2 の定数） | `src/video/khronos/EGL/`、`src/video/khronos/GLES2/` |
| `tools/gendebugfont.bb`（DebugText の字形） | `src/render/SDL_render_debug_font.h` |
| `tools/wlscan-pas`（Wayland プロトコルの生成） | `wayland-protocols/*.xml` |
| `tools/checkorigin.bb` | 読まない（設計書第 11 章とソースの見出しだけを突き合わせる） |

## 版を上げるとき

1. `reference/SDL` を新しいコミットへ進め、この表のコミットと日付を書き換える
2. 生成器を回し直し、生成物の差分を読む（`tools/genscancodes.bb`、`tools/genkhronos.bb`、`tools/gendebugfont.bb`）
3. 移植したユニットの元ファイルの差分（`git -C reference/SDL diff 旧..新 -- 元ファイル`）を読み、
   取り込むか決める。上流の不具合として記録したもの（`docs/DEFECTS.md` の D-18、D-36、D-38）が
   直っていないかも見る
