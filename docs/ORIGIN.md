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

## PipeWire のヘッダ（`tools/genpipewire.bb`）

`PaPiMeLa.Platform.PipeWire` は PipeWire 1.6.2 のヘッダ（MIT）のインライン関数を写し、定数と期待値は
`tools/genpipewire.bb` がヘッダで C を動かして作る（`src/generated/pipewire_consts.inc`、
`test/pipewire_abi_expected.inc`）。ビルドと CI はヘッダを要らない。作り直すときだけ要る。
システムに入れずに用意するには、開発用の .deb を落としてスクラッチに展開する:

```bash
apt-get download libpipewire-0.3-dev libspa-0.2-dev
dpkg-deb -x libpipewire-0.3-dev_*.deb /tmp/pwroot && dpkg-deb -x libspa-0.2-dev_*.deb /tmp/pwroot
tools/genpipewire.bb /tmp/pwroot/usr/include
```

PulseAudio と ALSA も同じやり方でヘッダを用意する（`tools/genpulse.bb` はヘッダの根を引数に取る）:

```bash
apt-get download libpulse-dev libasound2-dev
dpkg-deb -x libpulse-dev_*.deb /tmp/audioroot && dpkg-deb -x libasound2-dev_*.deb /tmp/audioroot
tools/genpulse.bb /tmp/audioroot/usr/include
```

ヘッダの版を上げたら、生成物の差分（構造体の並び・定数）と、写したインライン関数の元の差分を読む。

## デスクトップ GL のヘッダ（`tools/gengl.bb`）

`PaPiMeLa.Platform.GL`（Render.GL 用）の定数と関数表は、`tools/gengl.bb` が生成する（`src/generated/gl_constants.inc`、
`gl_functions.inc`、`gl_bind_*.inc`）。関数は `reference/SDL` の `SDL_glfuncs.h` の有効な行（コア）と、SDL が使う ARB / EXT の
`glext.h` の型（拡張）、定数の値は `GL/gl.h` と `GL/glext.h`（Mesa の `mesa-common-dev` と GLVND の `libgl-dev`）から。
`reference/SDL` の khronos には GL/ のヘッダが無い。ビルドと CI はヘッダを要らない。作り直すときだけ要る:

```bash
apt-get download libgl-dev mesa-common-dev
for d in libgl-dev_*.deb mesa-common-dev_*.deb; do dpkg-deb -x $d /tmp/glroot; done
tools/gengl.bb /tmp/glroot/usr/include
```

2026-10-25 に作った版: libgl-dev 1.7.0-3 と mesa-common-dev 26.0.3-1ubuntu1（arm64。ヘッダは版が同じなら amd64 と同じ）。

## Vulkan のヘッダ（`tools/genvulkan.bb`）

`PaPiMeLa.Platform.Vulkan`（Video.Wayland.Vulkan と Render.Vulkan 用）の型・定数・関数表は、`tools/genvulkan.bb` が
**`reference/SDL` が同梱する Khronos ヘッダ**（`src/video/khronos/vulkan/vulkan_core.h` と `vulkan_wayland.h`）を読んで生成する
（`src/generated/vulkan_*.inc`）。システムの Vulkan ヘッダは使わない（版が `reference/SDL` と揃う。GL と違って取り直しの手順が増えない）。
どの名前を取るかは、`tools/genvulkan.bb` の中の一覧（SDL の 4 ファイル `render/vulkan/SDL_render_vulkan.c`・`SDL_shaders_vulkan.c`・
`video/SDL_vulkan_utils.c`・`video/wayland/SDL_waylandvulkan.c` が使う名前から、Android と KHR display を除いたもの）。
Khronos のヘッダは Apache-2.0 または MIT（ヘッダの先頭の SPDX 行）。生成物は API の名前と値と並びだけで、CI は `--check` で古さを見る。

```bash
tools/genvulkan.bb            # 生成物を作る
tools/genvulkan.bb --check    # 古さの検査（CI）
tools/genvulkan.bb --layout   # gcc で配置の期待値 test/vulkan_layout.inc を作る（gcc が要る）
```

`reference/SDL` を進めたら、生成物と `--layout` の差分を読む。SDL が使う名前が増えていたら、一覧に足す。

## 版を上げるとき

1. `reference/SDL` を新しいコミットへ進め、この表のコミットと日付を書き換える
2. 生成器を回し直し、生成物の差分を読む（`tools/genscancodes.bb`、`tools/genkhronos.bb`、`tools/gendebugfont.bb`）
3. 移植したユニットの元ファイルの差分（`git -C reference/SDL diff 旧..新 -- 元ファイル`）を読み、
   取り込むか決める。上流の不具合として記録したもの（`docs/DEFECTS.md` の D-18、D-36、D-38）が
   直っていないかも見る
