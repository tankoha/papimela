# papimela 設計ドキュメント v2 — SDL3 の Free Pascal 再実装

- 文書の性格: 実装前の設計方針を固めるためのもの。実装コードは含まず、クラス宣言の骨格スニペット程度に留める
- 対象コンパイラ: Free Pascal 3.2.2 以降（3.3.x trunk の機能には依存しない）
- 初回ターゲット: **Linux / Wayland のみ**、**コア機能のみ**（Video / Events / Render / Audio / Input / IME / Threads / IO / Timer）
- 参照実装: `reference/SDL`（libsdl-org/SDL の shallow clone、3.x 系 main ブランチ）
- 前バージョン: `docs/archive/DESIGN-v1-wrapper.md`（v1）。v1 は「SDL3 の C API を薄くラップするバインディング」という誤った前提で書かれていた。本書は前提を改め、v1 のうち再実装でも通用する章（例外階層の考え方、幾何・色型、ジェネリクス/インターフェース方針、文字列・メモリ規約、命名規則）だけを引き継ぐ。v1 の二層構造（`SDL3.Api.*` + ラッパー）と不透明ハンドルの RAII ラッパー設計（`TSDLHandleObject<T>`、ハンドル→ラッパー逆引き、`OwnsHandle`）は**破棄**する
- 最終セクション（第 11 章）は、後続の実装担当（qwen2.5-coder:14b / Claude Sonnet 5 / Claude Opus 5）への振り分け一覧表になっている

> 本文中の **[要検証]** は、設計判断の根拠となる事実のうち、まだ実機・実ソースで確認していないものを示す。

---

## 0. 用語

| 用語 | 意味 |
|---|---|
| 再実装 (reimplementation / port) | C で書かれた SDL 本体を Object Pascal で書き直した独立実装。**SDL の C API を呼ぶコードは一行も無い**。プラットフォーム API（Wayland、D-Bus、evdev、ALSA/PipeWire 等）に対して Pascal から直接実装する |
| 移植 (transliterate) | SDL の C ソースを関数単位・ロジック単位で Pascal に書き換えること。法的には派生著作物になる（1.4） |
| クリーンルーム (clean-room) | SDL のソース構造に倣わず、要求仕様から papimela 独自に設計・実装すること。本書では「構造を新たに設計した」ことを指し、法的な意味での厳密なクリーンルーム手順（ソースを一切見ない）とは区別する（1.4 で補足） |
| バックエンド | プラットフォーム API（Wayland、IBus、PipeWire 等）に接して、抽象クラスの契約を実装する派生クラス群 |
| 軸 (axis) | 独立に差し替え可能なバックエンドの種類。本書では **ビデオ軸**（Wayland / 将来 X11・Win32…）、**IME 軸**（IBus / Fcitx / text-input-v3 / 将来 Windows TSF…）、**オーディオ軸**、**ジョイスティック軸** を独立に持つ |
| 所有 (owned) | オブジェクトが子オブジェクトの寿命に責任を持つこと。所有者の `Destroy` が子を `Free` する |
| 借用 (borrowed) | 参照するだけで寿命に責任を持たないこと。papimela では借用参照の生存はすべて所有グラフ（2.4）によって保証する |

---

## 1. プロジェクトの位置づけと方針

### 1.1 何を作るのか

papimela は、SDL3 が提供する機能（ウィンドウ・入力・描画・音声・スレッド・IO）を、**Free Pascal のクラス階層として一から構成した独立ライブラリ**である。SDL の設計上の知見と、長年蓄積されたプラットフォーム固有の回避策（workaround）を継承しつつ、C で手書きされていたオブジェクト指向（関数ポインタ表と `void *driverdata`）を言語機能としてのクラス・継承・仮想メソッド・例外・プロパティに置き換える。

SDL の C ソースの「良い部分」と「悪い部分」は既に評価済みで、本書はその評価を前提とする:

- **良い部分（機械的に抽象クラスへ落とせる）**: `SDL_AudioDriverImpl`（22 関数ポインタ / 411 行）、`SDL_RenderDriver`（35）、`SDL_sysjoystick`（21）、`SDL_syscamera`（13）。責務が単一で境界が明確。全 vtable が第 1 引数を `_this` として受けており、Pascal の `Self` に素直に対応する。バックエンド固有状態の `internal` / `driverdata` void\* は派生クラスのフィールドに置き換えればキャストが消えて改善になる。
- **悪い部分（分解が必要）**: `SDL_VideoDevice`（`src/video/SDL_sysvideo.h`）は**単一構造体に 98 個の関数ポインタ**を持つ god object。初期化 / ディスプレイ列挙 / ウィンドウ操作 44 個 / OpenGL 11 個 / Vulkan 6 個 / Metal 3 個 / イベントポンプ / スクリーンセーバー / テキスト入力 4 個 / スクリーンキーボード 4 個 / クリップボード＋プライマリ選択 10 個 / メッセージボックス / ヒットテスト / D&D / システムメニューが混在する。さらに `src/video/SDL_video.c` の `static SDL_VideoDevice *_this` グローバルシングルトンが 456 箇所から参照されている。継承が無いため X11 / Wayland 共通の EGL 処理などが `#ifdef` と別ファイルで処理されている。

### 1.2 ハイブリッド戦略

| 扱い | 対象 | 理由 |
|---|---|---|
| **移植**（C から移植して軽くリファクタ。回避策の知見を継承） | audio（変換・リサンプル・キュー・WAV）、render（ソフトウェア・GL 系ドライバ、共通のバッチ処理）、joystick / evdev / udev、gamepad マッピング DB、events 中核（キュー、キーボード・マウス状態機械、キーマップ）、thread、io、filesystem、timer、pixels / surface / blit、properties、hints、log | アルゴリズムとプラットフォーム回避策が価値の中心で、構造上の問題が小さい |
| **クリーンルーム**（要求から再設計） | **ビデオデバイス層**（98 ポインタの god object を `TPMLVideoBackend` / `TPMLWindowBackend` / `TPMLGLBackend` / `TPMLVulkanBackend` / `TPMLClipboardBackend` / `TPMLCursorBackend` / `TPMLMessageBoxBackend` 等に分解。第 3 章）、**IME / テキスト入力の全経路**（第 7 章）、初期化と所有グラフ（2.4）、イベントディスパッチのアプリ向け API（第 6 章）、例外体系（第 5 章） | 構造そのものが問題（god object、グローバル、情報を削る IME 経路）であり、移植すると問題も一緒に移植される |
| **一部移植** | Wayland バックエンド（プロトコル処理の回避策——xdg-decoration の有無、fractional-scale、libdecor 相当の判断、フォーカス喪失時のキー解放、等——は SDL から継承するが、クラス構造は第 3 章の抽象に合わせて再構成する）、EGL 共通処理、キーボード・マウスの状態機械のうちバックエンド境界に接する部分 | 知見は欲しいが構造は変える |
| **丸ごと捨てる** | `src/dynapi`（ABI トランポリン。Pascal では不要）、`src/stdlib` / `src/libm`（FPC RTL の `SysUtils` / `Math` / `StrUtils` で代替）、ベンダーされた C ヘッダ群（`src/video/khronos` 73k 行、`src/video/directx` 44k 行）、`src/video/stb_image.h` / `miniz.h`（初回スコープ外。必要になれば FPC の `fcl-image` / `paszlib` を使う）、`SDL_hashtable.c`（`Generics.Collections.TDictionary` で代替）、`SDL_list.c`、`SDL_utils.c` の大半、`SDL_assert.c`（`Assert` + 例外で代替）、`SDL_error.c`（スレッドローカルエラー文字列は例外に置き換える） | 言語・ランタイムが提供する、または対象外 |

移植であっても **C コードを無検証で写してはならない**。実例: `src/core/linux/SDL_ibus.c` 115 行目の `SDL_strncmp(struct_id, struct_id, id_size)` は自分自身との比較であり、D-Bus のバリアント型名検証が常に成功する実バグである。移植担当は「同じロジックか」ではなく「意図した振る舞いか」を確認し、疑わしい箇所には `// PORT-NOTE:` コメントを残す（5.6）。

### 1.3 初回スコープ

**実装対象**: Linux、Wayland（xdg-shell）、以下のサブシステム。

| サブシステム | 初回で作るもの | 初回で作らないもの（拡張点のみ用意） |
|---|---|---|
| Video | Wayland バックエンド（ウィンドウ、ディスプレイ、カーソル、クリップボード、EGL）、ヘッドレス Dummy バックエンド | X11、KMS/DRM、Win32、Cocoa、Android、Vulkan サーフェス（P3）、Metal |
| Events / Input | キーボード（xkbcommon）、マウス、ホイール、ウィンドウイベント、D&D 受信、タッチ（wl_touch）、ジョイスティック（evdev + udev）、ゲームパッドマッピング | ペン / タブレット（tablet-v2、P3）、センサー、カメラ、HIDAPI 経路のジョイスティック |
| Render | 2D レンダラ抽象、ソフトウェアレンダラ、OpenGL ES 2 レンダラ（Wayland の既定） | OpenGL 3 レンダラ（P3）、Vulkan レンダラ（P3）、GPU API（`SDL_gpu.h` 相当。スコープ外） |
| Audio | デバイス列挙と論理デバイス、ストリーム、変換・リサンプル、WAV、PipeWire / PulseAudio / ALSA バックエンド、Dummy | 録音は設計に含めるが検証は再生を優先 |
| IME | 文節配列・周辺テキスト・周辺削除を持つテキスト入力モデル、IBus（D-Bus）バックエンド、text-input-v3 バックエンド、Fcitx バックエンド（P2） | Windows TSF、macOS NSTextInputClient（拡張点のみ） |
| Threads / IO / Timer / FileSystem | pthread ベースの同期プリミティブ、`TStream` 統合の IO、高精度タイマ、XDG パス | AsyncIO（io_uring）、Storage、Process、Dialog、Tray |

抽象化は将来の複数バックエンドを前提に設計する（第 3 章）。「Wayland しか無いから抽象クラスを省く」ことはしない。ただし Wayland 以外の派生クラスは書かない。

### 1.4 SDL との関係とライセンス運用

SDL は zlib ライセンスである。移植した部分は法的に派生著作物であり、zlib ライセンスは「(2) 改変した場合はその旨を明示すること、(3) 告知を削除・改変しないこと」を要求する。クリーンルーム部分はその義務を負わないが、本プロジェクトの担当者は SDL のソースを読んで設計しているため、法的に厳密な「クリーンルーム」の証明は困難である。したがって次の運用にする:

1. **プロジェクト全体を zlib ライセンスで配布する**。SDL と同じライセンスにすることで、由来の分類を誤っても利用者側の義務は変わらない。由来の区別は「どのファイルに SDL の著作権告知を付すか」だけに影響する。
2. **モジュール一覧表（第 11 章）に「由来」列を設ける**（`移植` / `クリーンルーム` / `一部移植`）。`移植` と `一部移植` のユニットには SDL の著作権告知を付す。`クリーンルーム` のユニットには付さない。この判定は表から機械的に決まる。
3. **ファイルヘッダの書式**を統一する（下記）。移植元ファイル名と参照した SDL のコミットハッシュを記載し、`docs/ORIGIN.md` にコミットハッシュと取得日を 1 箇所で管理する。
4. **SDL へのアップストリーム貢献は行わない**。SDL プロジェクトは AI 生成コードの貢献を受け付けない方針を明示しているため、papimela で見つけた SDL 側のバグ（1.2 の `SDL_ibus.c` の例など）はコードとしては送らず、`docs/UPSTREAM-NOTES.md` に記録するに留める。バグ報告（Issue）を人間が行うかどうかは本書の範囲外。
5. **第三者ライブラリの取り扱い**: Wayland プロトコル XML（MIT）、xkbcommon（MIT）、libdbus（AFL/GPL のデュアル。動的ロードで利用し、静的リンクしない）、PipeWire（MIT）、PulseAudio クライアント（LGPL。動的ロードで利用）、ALSA（LGPL。動的ロード）。**すべて実行時 `dlopen` で結合し、ヘッダ相当の定義のみ Pascal に翻訳する**。ヘッダ翻訳は各ライブラリの告知を保持する。

**ファイルヘッダ書式**（移植 / 一部移植）:

```pascal
{
  PaPiMeLa.Audio.Convert — オーディオフォーマット変換

  Origin : ported from SDL (src/audio/SDL_audiocvt.c, src/audio/SDL_audiotypecvt.c)
           SDL revision: see docs/ORIGIN.md
  Scope  : 一部移植の場合、移植した関数を列挙する（例: ConvertAudio, ResampleAudio）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.
  （zlib ライセンス本文を続ける）
}
```

**ファイルヘッダ書式**（クリーンルーム）:

```pascal
{
  PaPiMeLa.TextInput — テキスト入力 / IME の公開 API

  Origin : original work (clean-room design; not derived from SDL sources)

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文）
}
```

`Origin` 行は機械可読にし、CI で「第 11 章の由来列」と「実ファイルの `Origin` 行」の不一致を検出する（スクリプトは 9.6）。

---

## 2. 全体アーキテクチャ

### 2.1 層構造

```
┌────────────────────────────────────────────────────────────────────────┐
│ アプリケーション                                                         │
├────────────────────────────────────────────────────────────────────────┤
│ 公開 API 層   PaPiMeLa.Video / .Render / .Audio / .Events / .TextInput   │
│               TPMLContext, TPMLWindow, TPMLRenderer, TPMLAudioStream ...  │
│               （プラットフォーム非依存。バックエンド抽象クラスにのみ依存）  │
├────────────────────────────────────────────────────────────────────────┤
│ バックエンド抽象層  PaPiMeLa.Video.Backend / .Audio.Backend /              │
│                    .Joystick.Backend / .TextInput.Backend / .Render.Backend│
│               抽象クラス（TPMLVideoBackend, TPMLWindowBackend, ...）        │
├──────────────┬──────────────┬──────────────┬──────────────┬─────────────┤
│ Video.Wayland│ TextInput.   │ Audio.       │ Joystick.    │ Render.     │
│ Video.Dummy  │  IBus/Fcitx/ │  PipeWire/   │  Linux(evdev)│  Software/  │
│              │  WaylandTI   │  Pulse/Alsa  │  Virtual     │  GLES2      │
├──────────────┴──────────────┴──────────────┴──────────────┴─────────────┤
│ プラットフォーム結合層  PaPiMeLa.Platform.*                                │
│   Wayland.Client（libwayland-client）, Wayland.Protocols.*（XML から生成）, │
│   XKB, DBus, EGL, GLES2, Evdev, Udev, Alsa, PipeWire, Pulse, Posix, DynLib│
│   （型定義と external/関数ポインタのみ。ロジックを置かない）                 │
├────────────────────────────────────────────────────────────────────────┤
│ 基盤層  PaPiMeLa.Core / .Errors / .Types / .Unicode / .Log / .Properties  │
│         .Threading / .Atomic / .Time                                       │
└────────────────────────────────────────────────────────────────────────┘
```

依存の方向は上から下への一方向とする。特に:

- **公開 API 層は具象バックエンドを `uses` しない**。バックエンドの選択は `PaPiMeLa.Backends`（登録ユニット。アプリが `uses` することで利用可能なバックエンドが決まる）が行う。これにより、アプリが Wayland 以外を使わないとき Wayland 関連ユニットがリンクされない。
- **プラットフォーム結合層はロジックを持たない**。`libwayland-client` 等の C 関数は `dlopen` 経由の関数ポインタ変数として宣言し、構造体・列挙・定数を `{$packrecords c}` で翻訳する。
- **IME 軸はビデオ軸と独立**（3.6、第 7 章）。`PaPiMeLa.TextInput.*` は `PaPiMeLa.Video.Wayland` に依存しない。Wayland の text-input-v3 バックエンドが `wl_seat` を必要とする問題は、小さなインターフェース `IPMLWaylandSeatProvider`（`PaPiMeLa.Video.Wayland.Types` に置く）で解決する。

### 2.2 ユニット構成（名前空間）

FPC のドット付きユニット名で `PaPiMeLa.<Layer>.<Name>` とする。全ユニットの一覧・規模・由来は第 11 章の表に集約するので、ここでは階層の設計意図だけ示す。

| 名前空間 | 内容 | 依存してよいもの |
|---|---|---|
| `PaPiMeLa` | アンブレラ。公開 API 層の型を型エイリアスで再エクスポートし、`PaPiMeLa.Backends` も `uses` する | すべて |
| `PaPiMeLa.Core`, `.Errors`, `.Types`, `.Unicode`, `.Log`, `.Properties`, `.Atomic`, `.Threading`, `.Time` | 基盤。プラットフォーム非依存（`.Threading` / `.Time` は内部で `BaseUnix` / `pthreads` を使うが、公開型は非依存） | RTL、`Generics.Collections`、基盤層内 |
| `PaPiMeLa.Platform.*` | C ライブラリの型と関数ポインタ。`Platform.Wayland.Protocols.*` は生成物 | `.Core`, `.Errors`（ロード失敗の例外） |
| `PaPiMeLa.Video`, `.Video.Backend`, `.Video.EGL`, `.Pixels`, `.Surface`, `.Surface.Blit`, `.Surface.BMP` | ビデオ公開 API と抽象、共通 EGL 実装、ピクセル処理 | 基盤層、`.Events`（キューへの投入）、`Platform.EGL` |
| `PaPiMeLa.Video.Wayland`, `.Video.Wayland.*`, `.Video.Dummy` | ビデオ具象バックエンド | `.Video.Backend`, `Platform.Wayland.*`, `Platform.XKB`, `.Events` |
| `PaPiMeLa.Events`, `.Events.Keyboard`, `.Events.Mouse`, `.Events.Touch`, `.Events.Keymap` | イベントキューと入力状態機械。**バックエンドはここへ投入する** | 基盤層 |
| `PaPiMeLa.Render`, `.Render.Backend`, `.Render.Software`, `.Render.GLES2`, `.Render.GL` | 2D レンダラ | `.Video`, `.Surface`, `Platform.GLES2` |
| `PaPiMeLa.Audio`, `.Audio.Backend`, `.Audio.Convert`, `.Audio.Queue`, `.Audio.Wave`, `.Audio.PipeWire`, `.Audio.Pulse`, `.Audio.Alsa`, `.Audio.Dummy` | オーディオ | 基盤層、`.Events`（デバイス追加/削除イベント）、`Platform.*` |
| `PaPiMeLa.Joystick`, `.Joystick.Backend`, `.Joystick.Linux`, `.Joystick.Virtual`, `.Gamepad`, `.Haptic`, `.Haptic.Linux` | ジョイスティック軸 | 基盤層、`.Events`、`Platform.Evdev`, `Platform.Udev` |
| `PaPiMeLa.TextInput`, `.TextInput.Backend`, `.TextInput.IBus`, `.TextInput.Fcitx`, `.TextInput.WaylandTI`, `.TextInput.Null` | IME 軸 | 基盤層、`.Events`、`Platform.DBus`、`Platform.Wayland.*`、`.Video.Wayland.Types`（インターフェースのみ） |
| `PaPiMeLa.IO`, `.FileSystem`, `.Clipboard`, `.App`, `.Backends` | IO、パス、クリップボード公開 API、アプリケーションループ、バックエンド登録 | 各公開 API 層 |

命名の接頭辞は `TPML` / `EPML` / `IPML`（`PaPiMeLa` の略）とする。v1 の `TSDL` 接頭辞は使わない。本ライブラリは SDL ではなく、SDL の API 互換性も提供しないため、`SDL` を型名に含めると誤解を招く（8.2）。

### 2.3 サブシステム間の依存関係

```
                 ┌──────────┐
                 │ Context  │ ← アプリが生成する唯一のルート
                 └────┬─────┘
    ┌──────┬──────┬───┴───┬─────────┬──────────┬──────────┐
    ▼      ▼      ▼       ▼         ▼          ▼          ▼
 Events  Video  Audio  Joystick  TextInput  Timer     Hints/Log/Props
    ▲      │      │       │         │  ▲
    │      │      │       │         │  │ (Video が「フォーカスウィンドウ変化」を通知)
    └──────┴──────┴───────┴─────────┘  │
        すべてのサブシステムは Events に投入する      Video ──▶ TextInput（通知のみ、逆依存なし）
 Render ──▶ Video（ウィンドウのバックエンドを介して GL コンテキスト / サーフェスを得る）
 Gamepad ──▶ Joystick
 Clipboard ──▶ Video（Video バックエンドの Clipboard 部品を公開 API に露出）
```

- `Events` はどのサブシステムにも依存しない（イベントレコードは ID とプレーンな値しか持たない。6.2）。
- `TextInput` は `Video` に依存しない。`Video` が `TextInput` にフォーカス変更とウィンドウ座標を通知する方向にのみ結合があり、それは `TPMLContext` が両者を結線するときに `IPMLFocusObserver` インターフェースで行う。
- `Render` は `Video` に依存する（ウィンドウが必要）。逆はない。

### 2.4 初期化と所有グラフ — グローバルシングルトンを使わない

図: `docs/diagrams/ownership-graph.md`（Mermaid。日本語版は `ownership-graph_jp.md`）

SDL の `SDL_Init()` と `static SDL_VideoDevice *_this` に相当するものは作らない。代わりに **アプリケーションが `TPMLContext` を明示的に生成し、それがすべてのサブシステムを所有する**。

```pascal
type
  TPMLSubsystem  = (Video, Audio, Joystick, Gamepad, Haptic, TextInput);
  TPMLSubsystems = set of TPMLSubsystem;

  TPMLContext = class sealed(TPMLObject)
  public
    constructor Create(ASubsystems: TPMLSubsystems; AOptions: TPMLContextOptions = nil);
    destructor  Destroy; override;      // 所有する順序の逆（TextInput → Joystick → Audio → Video → Events）に破棄
    property Events    : TPMLEventQueue      read FEvents;      // 常に存在
    property Timer     : TPMLTimerService    read FTimer;       // 常に存在
    property Hints     : TPMLHints           read FHints;
    property Log       : TPMLLog             read FLog;
    property Video     : TPMLVideoSystem     read FVideo;       // Video が要求されていなければ nil
    property Audio     : TPMLAudioSystem     read FAudio;
    property Joysticks : TPMLJoystickSystem  read FJoysticks;
    property TextInput : TPMLTextInputSystem read FTextInput;
    property MainThreadID: TThreadID         read FMainThreadID;
    procedure RunOnMainThread(AProc: TPMLThreadProc; AWait: Boolean);
  end;
```

所有グラフ（矢印は「所有する」。破棄は矢印の末端から）:

```
TPMLContext
 ├─ TPMLEventQueue
 │    ├─ TPMLKeyboardState   （キーボード状態機械。events/SDL_keyboard.c 由来）
 │    ├─ TPMLMouseState      （events/SDL_mouse.c 由来）
 │    └─ TPMLTouchState
 ├─ TPMLTimerService ── タイマースレッド
 ├─ TPMLVideoSystem
 │    ├─ TPMLVideoBackend（Wayland: TPMLWaylandVideoBackend）
 │    │    ├─ TPMLGLBackend / TPMLVulkanBackend / TPMLClipboardBackend / TPMLCursorBackend ...（部品。3.2）
 │    │    └─ Wayland 接続オブジェクト（wl_display, wl_registry, seats, outputs）
 │    ├─ TPMLDisplay[]       （バックエンドが列挙。TPMLDisplayBackend を各自所有）
 │    └─ TPMLWindow[]        （公開クラス。各自 TPMLWindowBackend を所有）
 │         ├─ TPMLGLContext[]（ウィンドウが所有）
 │         └─ TPMLRenderer   （ウィンドウが所有。Renderer は TPMLTexture[] を所有）
 ├─ TPMLAudioSystem
 │    ├─ TPMLAudioBackend（PipeWire 等。1 つだけ選択）
 │    ├─ TPMLAudioDevice[]（物理。バックエンドの hotplug で増減）
 │    │    └─ TPMLLogicalAudioDevice[]（アプリが Open。デバイススレッドを 1 つ持つ）
 │    └─ TPMLAudioStream[]（アプリ所有。論理デバイスに bind される「参照」）
 ├─ TPMLJoystickSystem
 │    ├─ TPMLJoystickBackend[]（Linux evdev、Virtual。複数同時）
 │    └─ TPMLJoystick[] → TPMLGamepad（Joystick 上のビュー。所有は Joystick）
 └─ TPMLTextInputSystem
      ├─ TPMLTextInputBackend（IBus / Fcitx / WaylandTI / Null。1 つ選択、実行時切替可）
      └─ TPMLTextInputSession[]（ウィンドウごと。アプリの IPMLTextInputClient を借用）
```

規約:

1. **親は子への参照を持ち、子は親への参照（`Owner`）を持つ**。循環参照を許すが、破棄は常に親から始める。子の `Destroy` は親の `RemoveChild(Self)` を呼ぶ。
2. **アプリが `Free` してよいオブジェクト**は、アプリが `Create` したものだけ（`TPMLWindow`、`TPMLRenderer`、`TPMLTexture`、`TPMLAudioStream`、`TPMLLogicalAudioDevice`、`TPMLGLContext`、`TPMLSurface`、`TPMLJoystick.Open` の戻り）。それ以外（`TPMLDisplay`、`TPMLAudioDevice`（物理）、バックエンド）は所有者だけが破棄する。この区別は 4.1 の基底クラス `TPMLOwnedObject` / `TPMLSystemObject` で型として表す。
3. **複数の `TPMLContext` を同一プロセスに生成することを禁止しない**（Wayland 接続を 2 本張るのは合法）。ただし初回は 1 つのみをテストする。グローバル状態は「プロセスに 1 つしか存在し得ないもの」（`dlopen` したライブラリのハンドル、シグナルハンドラ）に限り、`PaPiMeLa.Platform.*` の `initialization` 節ではなく、参照カウント付きの明示ロード（`TPMLDynLib.Acquire/Release`）で扱う。
4. **メインスレッド制約**: `TPMLVideoSystem` と `TPMLWindow` の操作は `Context.MainThreadID` のスレッドからのみ行う。デバッグビルド（`{$ifdef PAPIMELA_DEBUG}`）では違反を `EPMLThreadAffinity` で検出する。他スレッドからは `RunOnMainThread` を使う。
5. **`finalization` 節で何もしない**。破棄順序はアプリの `Context.Free` に委ねる。

### 2.5 FPC のコンパイラモードと言語機能

ライブラリ本体の全ユニットは先頭に共通インクルード `papimela.inc` を置く:

```pascal
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch typehelpers}
{$interfaces corba}        // 既定インターフェースを非参照カウントに（8.4）
{$scopedenums on}
{$packrecords c}           // Platform.* の構造体は C レイアウト。それ以外のユニットでは既定に戻してよい
{$warn 5024 off}           // 未使用パラメータ（仮想メソッドの空実装で頻出）
```

| 言語機能 | 使う箇所 | 制限 |
|---|---|---|
| クラス・仮想メソッド・抽象メソッド | バックエンド抽象（第 3 章）全般。SDL の関数ポインタ表 1 つ = 抽象クラス 1 つ | `abstract` メソッドの未実装呼び出しは `EAbstractError`。バックエンドの「未対応」は例外ではなく能力集合（3.3）で表す |
| 例外 | エラー経路すべて（第 5 章） | C コールバックの境界を越えさせない（5.5） |
| advanced records + 演算子オーバーロード | 幾何・色型（8.3）、イベントレコード | レコードの可変部に管理型を置けない（6.2 で対処） |
| ジェネリクス（`Generics.Collections`） | 内部のリストと辞書、`TPMLRingBuffer<T>` | 公開 API に `specialize` 構文を露出しない（8.5） |
| インターフェース（CORBA） | リスナー、`IPMLTextInputClient`、`IPMLWaylandSeatProvider` などの契約 | COM（参照カウント）は Texture / Surface の共有 opt-in にのみ使用（8.4） |
| `cdecl` 手続きと `of object` メソッドポインタ | Wayland リスナー、D-Bus フィルタ、PipeWire コールバックのサンク（6.4） | 匿名メソッドは FPC 3.3 のため使わない。`is nested` はコールバック寿命が越えるため使わない |
| 型ヘルパ（`type helper`） | `TPMLKeycode`、`TPMLScancode` などの列挙・整数に `ToString` を付ける | — |
| `class sealed` / `strict private` | 静的ユーティリティクラス、フィールド隠蔽 | — |
| `{$if SizeOf(...)}` 静的アサート | `Platform.*` の構造体レイアウト検証 | — |
| スレッド | `cthreads` を**アプリ側**の `program` の `uses` 先頭に置く必要がある。`PaPiMeLa.Core` は `{$ifdef UNIX}{$ifndef FPC_HAS_THREADMANAGER}` 相当のチェックで、スレッドマネージャ未設定なら `EPMLInitError('cthreads is required')` を投げる **[要検証: 実行時に判定する確実な方法。`GetThreadManager` の `InitThreads` が RTL 既定かで判定できる見込み]** | — |

---

## 3. バックエンド抽象化の設計

### 3.1 分解の原則

SDL の `SDL_VideoDevice` を、**責務ごとの抽象クラスに分解し、それらを「部品」としてビデオバックエンドが所有する**構成にする。原則:

1. **1 抽象クラス = 1 責務 = SDL の 1 関数ポインタ群**。関数ポインタ 98 個を責務別に束ね直し、束ごとに抽象クラスを 1 つ作る。
2. **インスタンスの寿命が異なるものは別クラス**。ウィンドウ単位の操作（44 個）はウィンドウごとに生成される `TPMLWindowBackend` へ、デバイス単位の操作は `TPMLVideoBackend` へ。SDL では両方が `SDL_VideoDevice` にあり、ウィンドウ関数が `(SDL_VideoDevice *_this, SDL_Window *window)` の 2 引数を取っていた。
3. **「未対応」は nil ではなく能力集合で表す**。SDL はサポートしない機能を関数ポインタ `NULL` で表し、呼び出し側が 456 箇所で `if (_this->Xxx)` を書いている。papimela ではバックエンドが `Capabilities: TPMLVideoCapabilities`（`set of`）を公開し、公開 API 層が 1 箇所で `EPMLUnsupported` を投げる。抽象メソッドは全部 `virtual` で既定実装（何もしない / `EPMLUnsupported`）を持たせ、`abstract` は必須メソッドに限る。
4. **共通実装は継承で共有する**。EGL の初期化・コンフィグ選択・コンテキスト生成は `TPMLEGLBackend`（`src/video/SDL_egl.c` 由来）に置き、Wayland 派生は「ネイティブディスプレイ / ネイティブウィンドウの取得」だけを実装する。
5. **軸を分ける**。ビデオ・IME・オーディオ・ジョイスティックの各軸は互いに独立に選択される。SDL では IME（`StartTextInput` 等 4 個 + `SDL_IME_*` の Linux 固有ファイル）がビデオデバイスにぶら下がっていたため、Wayland ビデオを使うと text-input-v3 の情報量に縛られていた。

### 3.2 ビデオ軸の抽象クラス群

図: `docs/diagrams/backend-abstraction.md`（Mermaid。日本語版は `backend-abstraction_jp.md`）

```
TPMLVideoBackend（デバイス単位。1 Context に 1 つ）
  ├─ 必須: Connect / Disconnect / EnumerateDisplays / CreateWindowBackend / PumpEvents / WaitEvents / WakeEventLoop
  ├─ 部品（プロパティ。nil = 未搭載、Capabilities で判定）:
  │    GL         : TPMLGLBackend          ← GL 11 個（LoadLibrary, GetProcAddress, UnloadLibrary, CreateContext, MakeCurrent,
  │                                            SetSwapInterval, GetSwapInterval, SwapWindow, DestroyContext, GetEGLSurface, DefaultProfileConfig）
  │    Vulkan     : TPMLVulkanBackend      ← Vulkan 6 個
  │    Clipboard  : TPMLClipboardBackend   ← クリップボード 5 個 + プライマリ選択 5 個
  │    Cursors    : TPMLCursorBackend      ← マウスカーソル生成/表示/ワープ/相対モード/キャプチャ（SDL では SDL_Mouse 構造体側の関数ポインタ 10 個）
  │    ScreenSaver: TPMLScreenSaverBackend ← SuspendScreenSaver 1 個
  │    MessageBox : TPMLMessageBoxBackend  ← ShowMessageBox 1 個
  │    SystemMenu : TPMLSystemMenuBackend  ← ShowWindowSystemMenu 1 個（xdg_toplevel.show_window_menu）
  │    Screenkbd  : TPMLScreenKeyboardBackend ← スクリーンキーボード 4 個（初回は Null 実装のみ）
  └─ Capabilities : set of TPMLVideoCapability

TPMLDisplayBackend（ディスプレイ単位。wl_output + xdg_output ごと）
  └─ GetBounds / GetUsableBounds / EnumerateModes / SetMode / GetContentScale / GetOrientation / GetHDRProperties

TPMLWindowBackend（ウィンドウ単位。ウィンドウ操作 44 個をここに集約）
  ├─ 生成・破棄: 初期フラグ・親ウィンドウ・ポップアップ属性を受け取るコンストラクタ、Destroy
  ├─ 属性: SetTitle, SetIcon, SetPosition, SetSize, SetMinimumSize, SetMaximumSize, SetAspectRatio, SetBordered, SetResizable,
  │        SetAlwaysOnTop, SetOpacity, SetShape, SetFocusable, SetParent, SetModal
  ├─ 状態: Show, Hide, Raise, Maximize, Minimize, Restore, SetFullscreen(Display, Mode), Sync, Flash, RequestFocus
  ├─ 入力: SetMouseGrab, SetKeyboardGrab, SetMouseRect, SetHitTest（コールバックは公開層が保持）
  ├─ 問い合わせ: GetSizeInPixels, GetSafeArea, GetDisplayIndex, GetICCProfile
  └─ ネイティブ: NativeHandles: TPMLNativeWindowHandles（Wayland: wl_surface / xdg_surface / xdg_toplevel / wl_egl_window。
                 型は `Pointer` で、名前付きフィールドとして公開。X11 追加時に Display/Window フィールドが増える）
```

SDL の 98 個との対応で**捨てるもの**: `StartTextInput` / `StopTextInput` / `UpdateTextInputArea` / `ClearComposition`（IME 軸へ。3.6）、`HasScreenKeyboardSupport` 等はスクリーンキーボード部品へ、`Metal_*` 3 個（macOS 専用。将来 `TPMLMetalBackend` 部品として追加できる余地だけ残す）、`SetWindowsMessageHook`/`X11 EventHook` 等（プラットフォーム固有フック。派生クラスの公開プロパティとして各バックエンドが独自に提供する）、`free`（デストラクタ）、`quirk_flags`（能力集合へ）、`dynapi` 関連。

**Wayland バックエンドの内部構成**（一部移植）:

```
TPMLWaylandVideoBackend
  ├─ TPMLWaylandConnection      wl_display, wl_registry, グローバル束縛（compositor, shm, xdg_wm_base, seat[], output[], 各拡張）
  │     → `SDL_waylandvideo.c` の registry ハンドラ相当。拡張の有無を Capabilities に写す
  ├─ TPMLWaylandSeat[]          wl_seat + wl_keyboard/wl_pointer/wl_touch、xkb_state、キーリピートタイマ、
  │                             pointer-constraints、relative-pointer、cursor-shape、（tablet-v2 は P3）
  │     → `SDL_waylandevents.c` 3917 行の大半。**text_input_* リスナーは含めない**（IME 軸へ移す）
  ├─ TPMLWaylandOutput[]        wl_output + xdg_output + fractional_scale → TPMLDisplayBackend 実装
  ├─ TPMLWaylandWindowBackend   wl_surface, xdg_surface, xdg_toplevel / xdg_popup, xdg_decoration, viewporter, fractional-scale,
  │                             xdg-activation, idle-inhibit → `SDL_waylandwindow.c` 3931 行
  ├─ TPMLWaylandDataManager     wl_data_device / primary_selection → TPMLClipboardBackend 実装 + D&D 受信
  ├─ TPMLWaylandCursorBackend   wl_cursor 相当（libwayland-cursor をロード、または cursor-shape-v1）
  ├─ TPMLWaylandEGL             TPMLEGLBackend 派生。wl_egl_window の生成/リサイズだけ実装
  ├─ TPMLWaylandVulkan          （P3）VK_KHR_wayland_surface
  └─ TPMLWaylandMessageBox      zenity 子プロセス（`SDL_waylandmessagebox.c` → `dialog/unix` の zenity 実装）
```

SDL の `SDL_waylandeventthread.c`（読み取りスレッドで `wl_display_prepare_read` を回し、メインループを起こす仕組み）は初回では移植せず、`PumpEvents` はメインスレッドで `wl_display_dispatch_pending` + `poll(2)` を行う。`WaitEvents(Timeout)` は wl_display の fd と内部の wake eventfd を `poll` する。

### 3.3 能力集合

```pascal
type
  TPMLVideoCapability = (
    OpenGL, OpenGLES, Vulkan,
    Clipboard, PrimarySelection, DragAndDrop,
    WindowPositioning,        // Wayland は False（xdg-shell はウィンドウ位置を持たない）
    ServerSideDecoration,     // xdg-decoration の有無
    FractionalScale, HighDPI,
    RelativeMouse, MouseConfine, MouseWarp,   // Wayland: MouseWarp は pointer-warp-v1 があるときのみ
    KeyboardGrab, SystemMenu, IdleInhibit, WindowActivation,
    SetIcon,                  // xdg-toplevel-icon-v1
    Touch, Tablet, MessageBox, ScreenKeyboard
  );
  TPMLVideoCapabilities = set of TPMLVideoCapability;
```

公開 API 層（`TPMLWindow.Position := ...` など）は `if not (WindowPositioning in Backend.Capabilities) then raise EPMLUnsupported.Create(...)` を 1 箇所で行い、バックエンド実装は「呼ばれたら必ずできる」前提で書く。Wayland では拡張の有無で実行時に能力が変わるため、`Capabilities` は `Connect` 後に確定する。

### 3.4 共通実装を継承で共有する箇所

| 共通基底 | 由来 | 派生（初回） | 派生が実装するもの |
|---|---|---|---|
| `TPMLEGLBackend` (`PaPiMeLa.Video.EGL`) | `src/video/SDL_egl.c`（1426 行、移植） | `TPMLWaylandEGL` | `GetNativeDisplay: EGLNativeDisplayType`（`wl_display*`）、`CreateNativeWindow(WindowBackend): EGLNativeWindowType`（`wl_egl_window_create`）、`DestroyNativeWindow`（**実装では** `ResizeNativeWindow` を置かず、ウィンドウのバックエンドが configure で `wl_egl_window_resize` を呼ぶ。SDL も configure の中で呼んでいる）。EGL ライブラリのロード、`eglGetPlatformDisplay` の選択、コンフィグ選択、コンテキスト属性、`EGL_KHR_create_context` 等の拡張判定は基底に置く |
| `TPMLPosixFileSystem` | `filesystem/unix` | — | 派生なし。XDG ディレクトリ解決は Linux 固有だが `#ifdef` は不要 |
| `TPMLZenityMessageBox` | `dialog/unix/SDL_zenitymessagebox.c` | `TPMLWaylandMessageBox` は単なる別名 | X11 追加時に X11 側のネイティブメッセージボックスと並列になる |
| `TPMLUnixAudioBackend`（`TPMLAudioBackend` 派生の中間基底） | `audio/SDL_audio.c` の共通部 | PipeWire / Pulse / Alsa | デバイススレッドの起動・優先度設定（`core/linux/SDL_threadprio.c` の D-Bus RealtimeKit 経路）を共有 |
| `TPMLEvdevJoystickBackend` の下の `TPMLUdevMonitor` | `core/linux/SDL_udev.c` | — | ジョイスティック以外（将来のキーボード hotplug 等）からも使えるよう独立ユニット |

### 3.5 オーディオ軸・ジョイスティック軸・レンダラ軸

これらは SDL の vtable が良質なので、**関数ポインタ 1 本 = 仮想メソッド 1 本**で機械的に写す。

```pascal
type
  // audio/SDL_sysaudio.h の SDL_AudioDriverImpl（22 関数ポインタ）に対応
  TPMLAudioBackend = class abstract(TPMLSystemObject)
  protected
    function  DetectDevices: Boolean; virtual; abstract;          // 初回列挙。hotplug スレッドを起動してもよい
    function  OpenDevice(ADevice: TPMLAudioDevice): TPMLAudioDeviceHandle; virtual; abstract;
    procedure CloseDevice(AHandle: TPMLAudioDeviceHandle); virtual; abstract;
    procedure ThreadInit(AHandle: TPMLAudioDeviceHandle); virtual;   // 既定: 何もしない
    procedure ThreadDeinit(AHandle: TPMLAudioDeviceHandle); virtual;
    function  WaitDevice(AHandle: TPMLAudioDeviceHandle): Boolean; virtual;
    function  PlayDevice(AHandle: TPMLAudioDeviceHandle; ABuf: Pointer; ASize: Integer): Boolean; virtual;
    function  GetDeviceBuf(AHandle: TPMLAudioDeviceHandle; var ASize: Integer): Pointer; virtual;
    function  WaitRecordingDevice(...): Boolean; virtual;
    function  RecordDevice(...): Integer; virtual;
    procedure FlushRecording(...); virtual;
    procedure FreeDeviceHandle(AHandle: TPMLAudioDeviceHandle); virtual;
    procedure Deinitialize; virtual; abstract;
  public
    property Name: String read GetName;
    property Capabilities: TPMLAudioCapabilities;   // ProvidesOwnCallbackThread, HasRecordingSupport, OnlyHasDefaultPlayback, ...
  end;
```

`SDL_AudioDriverImpl` の `bool` フラグ群（`ProvidesOwnCallbackThread`、`HasRecordingSupport`、`OnlyHasDefaultPlaybackDevice` 等）は能力集合に、`void *impl_data` は派生クラスのフィールドに置き換える。`TPMLAudioDeviceHandle` はバックエンド固有のデバイス状態を表す抽象クラス（SDL の `struct SDL_PrivateAudioData`）で、PipeWire なら `pw_stream` を、ALSA なら `snd_pcm_t` を派生クラスが持つ。

ジョイスティック（`joystick/SDL_sysjoystick.h` の 21 関数ポインタ → `TPMLJoystickBackend`）、レンダラ（`render/SDL_sysrender.h` の 35 関数ポインタ → `TPMLRenderDriver` と `TPMLRenderBackendTexture`）も同じ方針。レンダラでは SDL の「コマンドキュー（`SDL_RenderCommand` の連結リスト）を貯めて `RunCommandQueue` で一括実行する」構造をそのまま移植する。これはドライバ間で共通の最適化であり、捨てる理由がない。

### 3.6 IME 軸の独立

IME 軸は第 7 章で詳述するが、境界だけここで定める。

```pascal
type
  TPMLTextInputBackend = class abstract(TPMLSystemObject)
  protected
    function  Connect: Boolean; virtual; abstract;                      // IBus: D-Bus 接続、WaylandTI: zwp_text_input_v3 取得
    procedure Disconnect; virtual; abstract;
    procedure Activate(ASession: TPMLTextInputSession); virtual; abstract;    // フォーカスイン + 有効化
    procedure Deactivate; virtual; abstract;
    procedure Reset; virtual; abstract;                                 // 変換中テキストを破棄
    procedure UpdateSurroundingText(const AText: String; ACursorByte, AAnchorByte: Integer); virtual;
    procedure UpdateCursorRect(const ARect: TPMLRect); virtual;         // ウィンドウ座標
    procedure UpdateContentType(AType: TPMLTextInputType; AHints: TPMLTextInputHints); virtual;
    function  FilterKey(const AKey: TPMLKeyEventData): TPMLKeyFilterResult; virtual;  // Consumed / PassThrough / Deferred（7.5）
    procedure Pump; virtual;                                            // D-Bus のディスパッチ等
  public
    property Capabilities: TPMLTextInputCapabilities;  // Segments, Candidates, SurroundingText, DeleteSurrounding, CursorRect, KeyFilter
    property Sink: IPMLTextInputSink;                  // バックエンド → TextInputSystem への通知（Preedit/Commit/DeleteSurrounding/Candidates）
  end;
```

- IME バックエンドは **ビデオバックエンドの型を知らない**。フォーカスウィンドウ・カーソル矩形・キーイベントは `TPMLTextInputSystem` が公開層の型（`TPMLWindow`、`TPMLRect`、`TPMLKeyEventData`）で渡す。
- text-input-v3 バックエンド（`PaPiMeLa.TextInput.WaylandTI`）だけが `wl_seat` と `wl_surface` を必要とする。これは `PaPiMeLa.Video.Wayland.Types` の `IPMLWaylandSeatProvider`（`GetDisplay: Pwl_display; GetSeats: array of Pwl_seat; GetSurfaceOf(Window): Pwl_surface`）で受け取り、Wayland ビデオバックエンドがこのインターフェースを実装する。他のビデオバックエンド下では WaylandTI は `Connect` で `False` を返して選ばれない。
- 選択は `TPMLTextInputSystem` が起動時と `PAPIMELA_IME` 環境変数で行う（7.6）。

### 3.7 将来の軸の追加

| 追加したいもの | 変更範囲 |
|---|---|
| X11 ビデオ | `PaPiMeLa.Video.X11.*` を追加し `PaPiMeLa.Backends` に登録。`TPMLEGLBackend` 派生を 1 つ書く。公開層は無変更。IME 軸の IBus / Fcitx はそのまま動く（XIM バックエンドを追加してもよい） |
| Win32 ビデオ + TSF IME | `Video.Win32.*` と `TextInput.TSF` を独立に追加。WGL は `TPMLGLBackend` の別派生（EGL 基底は使わない） |
| 別の IME | `TPMLTextInputBackend` 派生 1 つ。ビデオ側は無変更 |
| HIDAPI ジョイスティック | `TPMLJoystickBackend` 派生。`joystick/hidapi` 31k 行の移植になるため初回スコープ外 |

---

## 4. クラス階層と公開 API

### 4.1 基底クラス

図: `docs/diagrams/base-classes.md`（Mermaid。日本語版は `base-classes_jp.md`）

v1 の `TSDLObject` / `TSDLHandleObject<T>` / `OwnsHandle` / `CreateFromHandle` / ハンドル逆引きは**すべて廃止**する。再実装では不透明ハンドルが存在せず、オブジェクトそれ自体が実装本体である。残るのは所有グラフの規約（2.4）を型で表す最小の基底だけ:

```pascal
type
  TPMLObject = class abstract(TObject)
  strict private
    FContext: TPMLContext;             // ルートへの借用参照。ログ・ヒント・イベントキューへの到達経路
  protected
    procedure CheckMainThread; inline;  // PAPIMELA_DEBUG 時のみ実体を持つ
  public
    property Context: TPMLContext read FContext;
  end;

  // 所有者（サブシステム）だけが生成・破棄する。アプリは Free してはならない
  TPMLSystemObject = class abstract(TPMLObject)
  strict private
    FOwner: TPMLObject;
  public
    property Owner: TPMLObject read FOwner;
  end;

  // アプリが Create し、アプリまたは所有者のどちらが先に Free してもよい
  TPMLOwnedObject = class abstract(TPMLObject)
  protected
    procedure DetachFromOwner; virtual;    // 所有者のリストから自分を外す。Destroy が呼ぶ
    procedure OwnerDestroying; virtual;    // 所有者が先に死ぬとき呼ばれる。既定: Free
  public
    destructor Destroy; override;
  end;
```

- `TPMLWindow` が破棄されるとき、配下の `TPMLRenderer` / `TPMLGLContext` に `OwnerDestroying` を送る。既定動作は自己破棄なので、アプリが `Renderer.Free` を忘れてもリークしない。逆にアプリが先に `Renderer.Free` すれば `DetachFromOwner` で親リストから消える。
- v1 の「無効化後アクセス検出（`IsValid`）」は不要になる。オブジェクトが生きていれば実装も生きている。
- 参照カウントは既定でしない（v1 2.3 を維持）。`TPMLTexture` / `TPMLSurface` の共有だけ COM インターフェース `IPMLTexture` / `IPMLSurface` で opt-in（8.4）。

### 4.2 Video

| クラス | 基底 | 生成 | 主な API |
|---|---|---|---|
| `TPMLVideoSystem` | `TPMLSystemObject` | `TPMLContext` | `Displays: TArray<TPMLDisplay>`、`PrimaryDisplay`、`Windows`、`CreateWindow(const AOptions: TPMLWindowOptions): TPMLWindow`、`WindowFromID(ID)`、`Backend: TPMLVideoBackend`（読み取り専用。ネイティブ連携用）、`Capabilities`、`ScreenSaverEnabled`、`SystemTheme`、`Clipboard: TPMLClipboard` |
| `TPMLDisplay` | `TPMLSystemObject` | `TPMLVideoSystem`（バックエンドの列挙で生成・hotplug で増減） | `ID`、`Name`、`Bounds`、`UsableBounds`、`ContentScale`、`Orientation`、`CurrentMode`、`DesktopMode`、`FullscreenModes`。v1 では record だったが、hotplug で状態が変わりイベントの発生源にもなるためクラスにする |
| `TPMLDisplayMode` | record | 値 | `Format`、`Width`、`Height`、`PixelDensity`、`RefreshRate`（分子/分母も保持） |
| `TPMLWindowOptions` | advanced record | 値 | `Title`、`Width`、`Height`、`Flags: TPMLWindowFlags`、`Parent`、`Position`（Wayland では無視）、`Display`。流暢 API（`.WithTitle('x').Resizable.HighPixelDensity`）を record メソッドで提供。SDL の `SDL_CreateWindowWithProperties` の代替 |
| `TPMLWindow` | `TPMLOwnedObject` | `TPMLVideoSystem.CreateWindow` | `ID`、`Title`、`Size`、`SizeInPixels`、`Position`（能力次第）、`MinimumSize`、`MaximumSize`、`Flags`、`Fullscreen`、`FullscreenMode`、`Opacity`、`Display`、`PixelDensity`、`DisplayScale`、`SafeArea`、`Show/Hide/Raise/Maximize/Minimize/Restore/Sync/Flash`、`SetHitTest(AHandler: TPMLHitTestMethod)`、`MouseGrab`、`KeyboardGrab`、`RelativeMouseMode`、`CreateGLContext(const AAttrs): TPMLGLContext`、`CreateRenderer(const ADriver: String = ''): TPMLRenderer`、`Renderer`（所有中のもの）、`NativeHandles`、`Backend: TPMLWindowBackend`。イベント: `OnResized`、`OnCloseRequested`、`OnFocusGained/Lost`、`OnExposed`（`of object`。6.3 の自己登録） |
| `TPMLWindowFlags` | `set of TPMLWindowFlag` | 値 | v1 の未解決事項 4（64 ビットのビットマスクを `set` にできない）は、C との互換が不要になったので**素直に `set of` にする**。`Fullscreen, OpenGL, Occluded, Hidden, Borderless, Resizable, Minimized, Maximized, MouseGrabbed, InputFocus, MouseFocus, HighPixelDensity, MouseCapture, AlwaysOnTop, Utility, Tooltip, PopupMenu, KeyboardGrabbed, Vulkan, Transparent, NotFocusable` |
| `TPMLGLContext` | `TPMLOwnedObject` | `TPMLWindow.CreateGLContext` | `MakeCurrent`、`SwapInterval`、`Window`。`GetProcAddress` は `TPMLVideoSystem.GL.GetProcAddress`。`SwapWindow` は `TPMLWindow.SwapGL` |
| `TPMLClipboard` | `TPMLSystemObject` | `TPMLVideoSystem` | `Text`、`HasText`、`SetData(const AMimeTypes: array of String; AProvider: IPMLClipboardDataProvider)`、`GetData(const AMime): TBytes`、`MimeTypes`、`PrimarySelectionText`。`IPMLClipboardDataProvider` は CORBA インターフェース（8.4） |
| `TPMLCursor` | `TPMLOwnedObject` | `TPMLVideoSystem.Cursors.Create(Surface, HotX, HotY)` / `CreateSystem(Kind)` | `TPMLVideoSystem.Cursors.Current := ...`、`Visible` |

### 4.3 Render

| クラス | 基底 | 生成 | 主な API |
|---|---|---|---|
| `TPMLRenderer` | `TPMLOwnedObject`（所有者 `TPMLWindow`、または `TPMLSurface` 上のソフトウェアレンダラ） | `TPMLRenderer.CreateForWindow(Window)` / `TPMLRenderer.CreateSoftware(Surface)`（当初は `TPMLWindow.CreateRenderer` だったが、Video が Render に依存しないよう変更。ウィンドウは `IPMLWindowDependent` 経由でレンダラを先に畳む） | `DrawColor: TPMLColor`、`DrawColorF: TPMLFColor`、`Scale`、`Viewport`、`ClipRect`、`LogicalPresentation`、`VSync`、`Target: TPMLTexture`、`OutputSize`、`Clear`、`DrawPoint(s)`、`DrawLine(s)`、`DrawRect(s)`、`FillRect(s)`、`RenderTexture`、`RenderTextureRotated`、`RenderTexture9Grid`、`RenderTextureTiled`、`RenderGeometry(const AVertices: array of TPMLVertex; const AIndices: array of Integer)`、`DebugText`、`Present`、`Flush`、`WindowToRender` / `RenderToWindow`、`CreateTexture(...)`、`CreateTextureFromSurface`、`Driver: TPMLRenderDriver`、`DriverName`、`Textures` |
| `TPMLTexture` | `TPMLOwnedObject`（所有者 `TPMLRenderer`） | `TPMLRenderer.CreateTexture*` | `Width`、`Height`、`Format`、`Access`、`ColorMod`、`AlphaMod`、`BlendMode`、`ScaleMode`、`Update(const ARect; APixels; APitch)`、`UpdateYUV/NV`、`Lock/Unlock`、`LockToSurface`、`Renderer` |
| `TPMLVertex` | record | 値 | `Position: TPMLFPoint`、`Color: TPMLFColor`、`TexCoord: TPMLFPoint` |
| `TPMLRenderDriver` | `TPMLSystemObject` | `PaPiMeLa.Backends` で登録 | 内部。`SDL_RenderDriver` の 35 関数ポインタ。`TPMLRenderDriverClass` の配列を `TPMLRenderDriverRegistry` に登録し、`CreateRenderer` が名前と `Window.Flags`（OpenGL / Vulkan）から選ぶ |

`SDL_render.c`（6372 行）の公開関数のうち、レンダラ状態の管理・コマンドキュー・座標変換・9-grid / tiled の頂点生成は移植。`SDL_Renderer` 構造体の公開フィールドは `TPMLRenderer` のプロパティになる。

### 4.4 Surface / Pixels

| クラス | 基底 | 備考 |
|---|---|---|
| `TPMLPixelFormat` | 列挙 + 型ヘルパ | `SDL_PixelFormat` の値をそのまま（ビットパックされた整数列挙）。型ヘルパで `BitsPerPixel`、`BytesPerPixel`、`Masks`、`IsAlpha`、`IsIndexed`、`ToString` |
| `TPMLPixelFormatDetails` | record | `SDL_GetPixelFormatDetails` 相当。`Format`、`Masks`、`Shifts`、`Loss`。SDL はライブラリ内のキャッシュを返すが、papimela では値型で返す |
| `TPMLPalette` | `TPMLOwnedObject`（所有者は `TPMLSurface` または nil） | `Colors: TArray<TPMLColor>`、`SetColors` |
| `TPMLSurface` | `TPMLOwnedObject`（所有者 nil = アプリ） | `Width`、`Height`、`Pitch`、`Format`、`Pixels: Pointer`、`Palette`、`Colorspace`、`ColorKey`、`ColorMod`、`AlphaMod`、`BlendMode`、`ClipRect`、`Lock/Unlock`（RLE 時のみ必要。`MustLock`）、`Blit(Src, SrcRect, Dst, DstRect)`、`BlitScaled`、`Blit9Grid`、`BlitTiled`、`FillRect(s)`、`Convert(Format)`、`Duplicate`、`Scale(W, H, Mode)`、`Flip`、`MapRGBA`、`ReadPixel`、`WritePixel`、`SaveBMP/LoadBMP`、`PremultiplyAlpha`、`RLEEnabled`。`IPMLSurface` で共有 opt-in |

`src/video/SDL_blit_auto.c`（11542 行）は SDL 側で `sdlgenblit.pl` から生成されたコードである。**Pascal でも生成する**（9.5）。手で移植しない。`SDL_blit_N.c`、`SDL_blit_A.c`、`SDL_blit_0/1.c`、`SDL_RLEaccel.c`、`SDL_stretch.c`、`SDL_rotate.c`、`SDL_fillrect.c` は移植（SIMD 部分は落とし、スカラー版のみ。9.5）。`SDL_yuv.c` は P3。

### 4.5 Audio

| クラス | 基底 | 生成 | 主な API |
|---|---|---|---|
| `TPMLAudioSystem` | `TPMLSystemObject` | `TPMLContext` | `PlaybackDevices` / `RecordingDevices: TArray<TPMLAudioDevice>`、`DefaultPlayback` / `DefaultRecording: TPMLAudioDevice`、`OpenDevice(ADevice; const ASpec): TPMLLogicalAudioDevice`、`OpenDeviceStream(ADevice; const ASpec; ACallback): TPMLAudioStream`（簡易パス）、`Backend`、`DriverName`、`LoadWAV(AStream: TStream): TPMLWaveData` |
| `TPMLAudioDevice`（物理） | `TPMLSystemObject` | バックエンドの列挙 / hotplug | `ID`、`Name`、`IsRecording`、`Format: TPMLAudioSpec`、`SampleFrames`、`IsDefault`、`LogicalDevices` |
| `TPMLLogicalAudioDevice` | `TPMLOwnedObject`（所有者 `TPMLAudioDevice`） | `TPMLAudioSystem.OpenDevice` | `Paused`、`Pause/Resume`、`Gain`、`BindStream(s)`、`UnboundStreams`、`Streams`、`PostmixCallback`、`Physical` |
| `TPMLAudioStream` | `TPMLOwnedObject`（所有者 nil = アプリ。論理デバイスへの bind は参照） | `TPMLAudioStream.Create(const ASrc, ADst: TPMLAudioSpec)` | `PutData(ABuf; ALen)`、`GetData(ABuf; ALen): Integer`、`Available`、`Queued`、`Flush`、`Clear`、`Gain`、`FrequencyRatio`、`InputChannelMap` / `OutputChannelMap`、`SrcSpec` / `DstSpec`、`Lock/Unlock`、`OnGet` / `OnPut`（`of object`。オーディオスレッドから呼ばれる）、`BoundDevice`、`Pause/Resume`（デバイス側の便宜） |
| `TPMLAudioSpec` | record | 値 | `Format: TPMLAudioFormat`、`Channels`、`Freq`、`FrameSize` |
| `TPMLWaveData` | `TPMLOwnedObject` | `LoadWAV` | `Spec`、`Data: TBytes`。v1 の `SDL_free` 問題は消える |

`audio/SDL_audio.c`（2765 行）の設計——物理/論理デバイスの分離、デバイススレッド、ストリームの `bind`、`SDL_AudioQueue` による可変長トラック管理、`SDL_audiocvt.c` の変換パイプライン（型変換 → チャンネル変換 → リサンプル → 型変換）——はそのまま移植する。スレッド安全性の規約（デバイスロック、ストリームロック、`Destroy` 中にコールバックが走る競合）は SDL のロック順序を踏襲し、5.5 の例外遮断を加える。

### 4.6 Input（Joystick / Gamepad / Keyboard / Mouse）

| クラス | 基底 | 備考 |
|---|---|---|
| `TPMLJoystickSystem` | `TPMLSystemObject` | `Joysticks: TArray<TPMLJoystickInfo>`（接続中。ID とメタ情報）、`Open(ID): TPMLJoystick`、`Update`（イベントポンプから呼ばれる）、`Backends`、`AttachVirtual(const ADesc): TPMLJoystickID` |
| `TPMLJoystick` | `TPMLOwnedObject`（所有者 `TPMLJoystickSystem`） | `ID`、`Name`、`Path`、`GUID`、`Type`、`Axes[i]`、`Buttons[i]`、`Hats[i]`、`Balls[i]`、`Rumble`、`RumbleTriggers`、`SetLED`、`SendEffect`、`PowerInfo`、`ConnectionState`、`Connected`。切断時は `Connected = False` になりオブジェクトは残る（アプリが `Free` する） |
| `TPMLGamepad` | `TPMLSystemObject`（所有者 `TPMLJoystick`。`Joystick.Gamepad` で取得、マッピングがあるときだけ非 nil） | `Buttons[TPMLGamepadButton]`、`Axes[TPMLGamepadAxis]`、`ButtonLabel`、`Type`、`Mapping`、`Bindings`、`Touchpads`、`Sensors`。SDL では `SDL_Gamepad` は `SDL_Joystick` を内包する別オブジェクトだが、1 対 1 なので Joystick 上のビューにする |
| `TPMLGamepadMappingDB` | `TPMLSystemObject` | `joystick/SDL_gamepad.c` 4448 行と `controller_type.c` の移植。`AddMapping`、`AddMappingsFromStream`、`Reload`、環境変数 `SDL_GAMECONTROLLERCONFIG` 相当の `PAPIMELA_GAMEPAD_CONFIG` |
| `TPMLKeyboardState` / `TPMLMouseState` / `TPMLTouchState` | `TPMLSystemObject`（所有者 `TPMLEventQueue`） | `events/SDL_keyboard.c` / `SDL_mouse.c` / `SDL_touch.c` の状態機械。公開側: `Context.Events.Keyboard.IsDown[Scancode]`、`.ModState`、`.FocusWindow`、`Context.Events.Mouse.Position`、`.Buttons`、`.FocusWindow`。バックエンド側: `SendKey(Window, Timestamp, Scancode, Keycode, Down, Repeat)`、`SendMotion(...)`、`SendButton(...)`、`SendWheel(...)`、`SendTouch(...)`。**バックエンドはイベントキューに直接 push せず、必ず状態機械を通す**（SDL と同じ） |
| `TPMLKeymap` | `TPMLSystemObject` | `events/SDL_keymap.c` の移植。Wayland では xkbcommon から構築する |

### 4.7 IO / FileSystem / Threads / Timer

| クラス | 備考 |
|---|---|
| `TPMLIOStream` | **FPC の `TStream` を第一級にする**。SDL の `SDL_IOStream` インターフェース（5 コールバック）は `TStream` の仮想メソッド（`Read` / `Write` / `Seek` / `SetSize`）に対応しているため、独自の抽象は作らない。`PaPiMeLa.IO` には `TPMLFileStream`（`io/SDL_iostream.c` の `stdio`/`fd` 実装の回避策——大きな読み書きの分割、`EINTR` 再試行——を持つ `THandleStream` 派生）、`TPMLMemoryStream`（読み取り専用 / 動的）、型付き読み書きのヘルパ（`ReadU16LE` 等）、`LoadFile(Path): TBytes` を置く。`TPMLSurface.LoadBMP(AStream: TStream)` のように、全 API は `TStream` を受け取る |
| `TPMLFileSystem` | `class sealed` 静的。`BasePath`、`PrefPath(Org, App)`、`UserFolder(Kind)`（XDG user-dirs）、`CurrentDirectory`、`EnumerateDirectory(Path, ACallback)`、`Glob`、`PathInfo`、`CreateDirectory`、`RemovePath`、`RenamePath`、`CopyFile`。`filesystem/unix` の移植（`readlink /proc/self/exe` 等の回避策を継承） |
| `TPMLThread` | `TThread` の**薄い派生**。名前設定（`pthread_setname_np`）、優先度（`thread/pthread/SDL_systhread.c` + `core/linux/SDL_threadprio.c` の RealtimeKit 経路）。独自のスレッド抽象は作らない |
| `TPMLMutex` / `TPMLRWLock` / `TPMLSemaphore` / `TPMLCondition` | `thread/pthread` の移植。RTL の `TRTLCriticalSection` ではなく pthread を直接使うのは、`TryLock`、再帰ロック、タイムアウト付き `Wait` を確実に提供するため。`TPMLMutex.Lock` / `Unlock` は失敗しない（例外なし）。`TPMLLockGuard`（管理レコードによるスコープガード）は FPC 3.2 で利用可能なので**採用する**（v1 では保留） |
| `TPMLAtomicInt` / `TPMLAtomicU32` / `TPMLAtomicPointer` / `TPMLSpinLock` | FPC の `InterlockedCompareExchange` 等の RTL 組み込みで実装する record。`atomic/SDL_spinlock.c` の「スピン → `sched_yield` → `nanosleep`」バックオフは移植 |
| `TPMLTimerService` | `timer/SDL_timer.c` の移植。タイマースレッド 1 本、`AddTimer(IntervalMS, ACallback): TPMLTimerID`、`AddTimerNS`、`RemoveTimer`。`Ticks` / `TicksNS` / `PerformanceCounter` / `Delay` / `DelayNS` / `DelayPrecise` は `class function`（`clock_gettime(CLOCK_MONOTONIC)`） |

### 4.8 コンストラクタ / デストラクタによるリソース管理の規約

1. **コンストラクタで資源を確保し、失敗したら例外を投げる**。FPC はコンストラクタで例外が発生するとデストラクタを自動的に呼ぶので、デストラクタは「部分的に構築された状態」（フィールドが nil）を許容するよう書く（`if Assigned(FBackend) then FBackend.Free`）。
2. **デストラクタは例外を投げない**。バックエンド側の破棄失敗はログに記録する。
3. **`try ... finally Free end` の通常イディオム**で使えること。`TPMLContext` も同様。
4. **所有者による自動破棄**（4.1）は安全網であり、アプリはリソースを生成した逆順で `Free` することを推奨する。ドキュメントにそう書く。
5. **スレッドをまたぐ破棄**: オーディオデバイススレッド・タイマースレッド・udev 監視スレッドを持つオブジェクトのデストラクタは、スレッドの停止と `Join` を完了してから戻る。SDL の `SDL_AudioDevice` 破棄手順（`shutdown` フラグ → スレッド待ち → デバイスクローズ）を踏襲する。

---

## 5. エラー処理

### 5.1 原則

SDL の「`false` を返して `SDL_SetError()` にスレッドローカルのエラー文字列を置く」方式は使わない。**エラーは例外**。`SDL_error.c` / `SDL_GetError` は移植しない。

### 5.2 例外階層（v1 3.2 を引き継ぎ、再実装向けに調整）

```pascal
type
  EPMLError = class(Exception)
  strict private
    FSubsystem  : TPMLSubsystemTag;    // どの層で発生したか（Video / Audio / ...）
    FBackendName: String;              // 'wayland', 'ibus', 'pipewire' 等。空なら公開層
    FNativeCode : Int64;               // errno、EGL エラー、wl_display_get_error 等。0 なら無し
  public
    constructor Create(const AMsg: String);
    constructor CreateFmt(const AFmt: String; const AArgs: array of const);
    constructor CreateNative(const AMsg: String; ANativeCode: Int64; const ABackend: String = '');
    property Subsystem  : TPMLSubsystemTag read FSubsystem;
    property BackendName: String read FBackendName;
    property NativeCode : Int64 read FNativeCode;
  end;

  // サブシステム別（1 サブシステム = 1 クラス。関数単位の例外は作らない）
  EPMLInitError      = class(EPMLError);   // Context 生成、バックエンド接続失敗
  EPMLVideoError     = class(EPMLError);   // Window / Display / GL / Clipboard
  EPMLRenderError    = class(EPMLError);
  EPMLAudioError     = class(EPMLError);
  EPMLInputError     = class(EPMLError);   // Joystick / Gamepad / Keyboard / Mouse
  EPMLTextInputError = class(EPMLError);   // IME 経路（D-Bus 切断等）
  EPMLIOError        = class(EPMLError);   // ファイル・パス。RTL の EStreamError はそのまま通す
  EPMLThreadError    = class(EPMLError);
  EPMLEventError     = class(EPMLError);   // キュー満杯で Push 失敗（既定では古いイベントを捨てるので稀）

  // 状態系（Error 接尾辞なし）
  EPMLUnsupported    = class(EPMLError);   // 能力集合に無い機能を呼んだ（3.3）
  EPMLArgument       = class(EPMLError);   // Pascal 側で検出できる引数不正
  EPMLThreadAffinity = class(EPMLError);   // メインスレッド制約違反（デバッグビルド）
  EPMLBackendLost    = class(EPMLError);   // Wayland 接続断、PipeWire デーモン終了。回復不能。Context を作り直す必要がある
  EPMLPlatformLibrary= class(EPMLInitError); // dlopen / dlsym 失敗。BackendName にライブラリ名
```

- `Message` は `'[<BackendName>] <説明>: <ネイティブ説明>'`。例: `[wayland] xdg_wm_base is not advertised by the compositor`。
- **`EPMLBackendLost` は特別扱い**: Wayland の `wl_display_get_error() != 0` や D-Bus 切断は「以後この Context のバックエンドは使えない」ことを意味する。`PumpEvents` がこれを検出したら、まず `TPMLEventKind.BackendLost` イベントをキューに入れ、次に `PumpEvents` の呼び出し元へ `EPMLBackendLost` を投げる。アプリはイベントで穏やかに知るか、例外で強制的に知るかを選べる。

### 5.3 移植コードの `return false` を例外に変換する規約

C の SDL コードは 3 種類の `false` を返している。移植担当は各 `return false` / `return NULL` を次のいずれかに分類し、判断を `// PORT-NOTE:` で残す:

| C 側のパターン | 意味 | Pascal での扱い |
|---|---|---|
| `return SDL_SetError("...")` / `SDL_OutOfMemory()` / `SDL_InvalidParamError()` | 呼び出し側の誤りまたはシステム障害 | **例外** `raise EPMLXxxError.CreateFmt(...)`。エラーメッセージの文言は SDL のものを踏襲してよい |
| `return false` without `SDL_SetError`（`SDL_PollEvent` のキュー空、`SDL_TryLockMutex`、`SDL_WaitEventTimeout` のタイムアウト、`SDL_HasProperty`、`SDL_GetAsyncIOResult` の結果なし） | 正常系の分岐 | **`Boolean` 戻りのまま**。関数名は `Try*` / `Has*` / `Poll` にする |
| バックエンドの初期化で `return false`（「このドライバは使えないから次を試せ」） | 選択ループの制御 | **`Boolean` 戻りのまま**（`TPMLVideoBackend.Connect: Boolean`）。理由はログ（`Log.Debug`）に出す。全バックエンドが失敗したら公開層が `EPMLInitError` を投げる |
| 内部ヘルパの `return -1` / `NULL`（バッファ確保失敗、テーブル検索の不一致） | 混在 | 呼び出し元の扱いを見て判断。確保失敗は `EOutOfMemory`（RTL がすでに投げる。明示チェック不要）、検索不一致は `Boolean` または `nil` 戻り |

- **`goto` によるクリーンアップ**（`goto error;` → `SDL_free` の連鎖）は `try ... finally` または `try ... except ... raise` に置き換える。
- **`SDL_assert`** は `Assert` に置き換え、リリースビルドでは消える。`SDL_assert_release` 相当は `EPMLError` を投げる。
- **`SDL_GetError()` の読み出し**（C 側で呼び出し先のエラーを付け足すパターン）は、例外の `raise ... at` 連鎖ではなく、捕捉して新しい例外の `Message` に `E.Message` を含めて再送出する。
- 移植した関数の**戻り値の型が変わったら、呼び出し側もすべて変える**。「`Boolean` を返す移植関数の戻り値を無視する」コードを残してはならない。

### 5.4 ホットパス

`RenderTexture`、`PutData`、`SendMotion` 等のフレーム毎・サンプル毎の関数でも既定は例外（失敗は稀）。`Try` 版はホットパス関数に限って併設する（v1 3.4 を維持）。

### 5.5 コールバック境界

再実装では C コールバックの境界は「Pascal → C ライブラリ → Pascal」の形で残る。該当箇所:

| 境界 | 呼び出し側 | 例外の扱い |
|---|---|---|
| Wayland リスナー（`wl_*_listener` の `cdecl` 手続き） | `libwayland-client` の `wl_display_dispatch*` | サンクで捕捉し `TPMLWaylandConnection.FPendingException` に格納。`PumpEvents` が `dispatch` から戻った直後に再送出する。同一ディスパッチ中に 2 つ目が起きたら最初のものを優先し、2 つ目はログ |
| D-Bus メッセージフィルタ / 保留中の返信 | `libdbus` の `dbus_connection_dispatch` | 同上。`TPMLDBusConnection.FPendingException` |
| PipeWire / PulseAudio のストリームコールバック | 各ライブラリのスレッドループ | 捕捉してログ。デバイスを `Failed` 状態にし、`AudioDeviceRemoved` イベントを投げる（SDL の `SDL_AudioDeviceDisconnected` 相当） |
| 自前スレッド（オーディオデバイススレッド、タイマースレッド、udev 監視） | papimela | `TThread.Execute` 内で捕捉し `FatalException` に保存。所有者の `Destroy` でログ |
| アプリのコールバック（`OnGet` / `OnPut`、ヒットテスト、タイマー、リスナー） | papimela | **アプリの例外は papimela の内部を通過させない**。捕捉して `Log.Error` に記録し、`Context.OnCallbackException` イベント（`of object`）があれば渡す。オーディオスレッド上ではストリームを一時停止する |

---

## 6. イベントシステム

図: `docs/diagrams/event-model.md`（Mermaid。日本語版は `event-model_jp.md`）

### 6.1 要件

1. ゲームループでの**ゼロアロケーション**ポーリング（v1 4.1 を維持）。
2. リスナー / オブザーバーで関心ごとに処理を分割できること。
3. 古典的な `while Poll(Ev) do case Ev.Kind of ...` と、`TPMLApplication` によるコールバック駆動の両立。
4. **可変長データ（テキスト入力、IME の文節配列、候補一覧、D&D のパス）をイベントに安全に載せられること**。SDL は `const char *text` をイベント内に持ち、`SDL_free` のタイミングを `SDL_PollEvent` の内部で管理している（`SDL_CleanupEvent`）。Pascal では管理型で自然に解決する。
5. バックエンド（Wayland 等）が別スレッドから投入しても安全なこと（初回は投入はメインスレッドのみだが、オーディオ・ジョイスティック hotplug・タイマーは別スレッドから投入する）。

### 6.2 イベントレコード

C との共用体互換が不要になったので、`TPMLEvent` は **固定サイズの可変部レコード + 管理型のフィールド**にする。FPC ではレコードの可変部（`case`）に管理型を置けないが、可変部の前に置くことはできる。

```pascal
type
  TPMLEventKind = (
    Quit, BackendLost, Terminating, LowMemory, WillEnterBackground, DidEnterBackground, WillEnterForeground, DidEnterForeground,
    LocaleChanged, SystemThemeChanged,
    DisplayAdded, DisplayRemoved, DisplayOrientation, DisplayMoved, DisplayDesktopModeChanged, DisplayCurrentModeChanged, DisplayContentScaleChanged,
    WindowShown, WindowHidden, WindowExposed, WindowMoved, WindowResized, WindowPixelSizeChanged, WindowMetalViewResized,
    WindowMinimized, WindowMaximized, WindowRestored, WindowMouseEnter, WindowMouseLeave, WindowFocusGained, WindowFocusLost,
    WindowCloseRequested, WindowHitTest, WindowICCProfChanged, WindowDisplayChanged, WindowDisplayScaleChanged, WindowSafeAreaChanged,
    WindowOccluded, WindowEnterFullscreen, WindowLeaveFullscreen, WindowDestroyed, WindowHDRStateChanged,
    KeyDown, KeyUp, TextEditing, TextInput, KeymapChanged, KeyboardAdded, KeyboardRemoved, TextEditingCandidates,
    TextInputDeleteSurrounding,     // papimela 独自（7.3）
    MouseMotion, MouseButtonDown, MouseButtonUp, MouseWheel, MouseAdded, MouseRemoved,
    JoystickAxisMotion, JoystickBallMotion, JoystickHatMotion, JoystickButtonDown, JoystickButtonUp, JoystickAdded, JoystickRemoved,
    JoystickBatteryUpdated, JoystickUpdateComplete,
    GamepadAxisMotion, GamepadButtonDown, GamepadButtonUp, GamepadAdded, GamepadRemoved, GamepadRemapped,
    GamepadTouchpadDown, GamepadTouchpadMotion, GamepadTouchpadUp, GamepadSensorUpdate, GamepadUpdateComplete, GamepadSteamHandleUpdated,
    FingerDown, FingerUp, FingerMotion, FingerCanceled,
    ClipboardUpdate,
    DropFile, DropText, DropBegin, DropComplete, DropPosition,
    AudioDeviceAdded, AudioDeviceRemoved, AudioDeviceFormatChanged,
    RenderTargetsReset, RenderDeviceReset, RenderDeviceLost,
    User);   // User + オフセットは Kind の整数値で表す（TPMLEventKind(Ord(User) + N)）

  TPMLEvent = record
  public
    Kind      : TPMLEventKind;
    Timestamp : UInt64;                   // ナノ秒、Context.Timer.TicksNS
    WindowID  : TPMLWindowID;             // 0 = ウィンドウ無関係
    // ---- 管理型フィールド（可変部の外）。使わない Kind では空のまま（nil ポインタ = コスト無し）
    Text      : String;                   // TextInput / TextEditing / DropFile / DropText / User
    Segments  : TPMLCompositionSegments;  // TextEditing（7.3）。dynamic array
    Strings   : TArray<String>;           // TextEditingCandidates の候補一覧
    // ---- 固定部
    case Integer of
      0: (Key       : TPMLKeyEventData);         // Scancode, Keycode, Mod, Raw, Down, Repeat, KeyboardID
      1: (Edit      : TPMLTextEditingData);      // CursorChar, CursorByte, SelectionStartChar, SelectionLengthChars, FocusedSegment
      2: (DeleteSurrounding: TPMLDeleteSurroundingData);  // BeforeBytes, AfterBytes（7.3）
      3: (Motion    : TPMLMouseMotionData);      // MouseID, State, X, Y, XRel, YRel
      4: (Button    : TPMLMouseButtonData);
      5: (Wheel     : TPMLMouseWheelData);
      6: (Window    : TPMLWindowEventData);      // Data1, Data2
      7: (Display   : TPMLDisplayEventData);
      8: (JAxis     : TPMLJoyAxisData);   9: (JButton: TPMLJoyButtonData);  10: (JHat: TPMLJoyHatData);  11: (JDevice: TPMLJoyDeviceData);
      12: (GAxis    : TPMLGamepadAxisData); 13: (GButton: TPMLGamepadButtonData); 14: (GTouchpad: TPMLGamepadTouchpadData); 15: (GSensor: TPMLGamepadSensorData);
      16: (Finger   : TPMLTouchFingerData);
      17: (Drop     : TPMLDropData);             // X, Y。パスは Text
      18: (Audio    : TPMLAudioDeviceEventData); // DeviceID, IsRecording
      19: (User     : TPMLUserEventData);        // Code, Data1, Data2: Pointer
  end;
```

- `SizeOf(TPMLEvent)` は 64〜96 バイト程度になる見込み。イベントキューはこれを値として持つリングバッファ（`TPMLRingBuffer<TPMLEvent>`）で、上書き時に管理型フィールドの参照カウントが自動で減る。**ヒープ確保は管理型フィールドが実際に使われるイベント（テキスト・D&D）にだけ発生**し、キー・マウス・ジョイスティックはゼロアロケーション。
- `TPMLEvent.Text` は UTF-8 `String`。バックエンドが Wayland から受けた `PChar` を一度だけコピーし、以後はキュー → アプリまで参照カウントで渡る。
- `TPMLKeyEventData.Scancode` は `{$scopedenums}` の列挙で、値は SDL の `SDL_Scancode`（USB HID Usage）と同一にし、既存資料との対応を保つ。FPC は値を指定した列挙を配列の添字に使えないので、0..511 の隙間の無い列挙にして SDL の値の無いところを `UnusedNNN` で埋めた。`Key`（キーコード）は列挙にしない。印字できるキーの値は Unicode のコードポイントで範囲が開いているため、`TPMLKeycode = type LongWord` と `PMLK_*` 定数にした。旧 `Keycode`（evdev + 8）は SDL3 に合わせて `Raw` に改名した。

### 6.3 キューとディスパッチャ

```pascal
type
  TPMLEventQueue = class sealed(TPMLSystemObject)
  public
    // ---- アプリ向け（メインスレッド）
    function  Poll(out AEvent: TPMLEvent): Boolean;                        // Pump してから 1 つ取り出す
    function  Wait(out AEvent: TPMLEvent): Boolean;                        // False = Quit 要求ではなく BackendLost
    function  WaitTimeout(out AEvent: TPMLEvent; ATimeoutMS: Integer): Boolean;   // False = タイムアウト
    procedure Pump;                                                        // 全バックエンドの PumpEvents を呼び、状態機械を更新
    procedure Push(const AEvent: TPMLEvent);                               // 任意スレッドから可。満杯時は最古を捨てて Log.Warn
    function  Peek(AKind: TPMLEventKind): Boolean;
    procedure Flush(AKinds: TPMLEventKinds);
    property  Enabled[AKind: TPMLEventKind]: Boolean;                      // SDL_SetEventEnabled
    function  RegisterUserEvents(ACount: Integer): TPMLEventKind;
    procedure AddWatch(AWatch: IPMLEventWatch); procedure RemoveWatch(AWatch: IPMLEventWatch);   // Push したスレッドで呼ばれる
    property  Filter: IPMLEventFilter;                                     // Push 時に落とす。1 つだけ
    property  Dispatcher: TPMLEventDispatcher;                             // 遅延生成
    // ---- 状態機械（バックエンドとアプリの両方から）
    property  Keyboard: TPMLKeyboardState;  property Mouse: TPMLMouseState;  property Touch: TPMLTouchState;
    // ---- バックエンド向け
    procedure RegisterPumpSource(ASource: IPMLEventPumpSource);            // Video / Joystick / TextInput / Audio が登録。Pump の呼び出し順は登録順
    procedure WakeUp;                                                      // Wait 中のスレッドを起こす（eventfd）
  end;
```

- **`Pump` の順序**: Video バックエンド（Wayland のディスパッチ） → TextInput バックエンド（D-Bus のディスパッチ） → Joystick（evdev 読み取り、udev） → Audio（hotplug の反映）→ タイマーの期限切れ。`IPMLEventPumpSource.Pump(ATimeoutMS)` は「待ってもよい時間」を受け、`Wait` の実装は最初のソース（Video）だけに待ちを許す。複数の fd を待つ必要があるため、`TPMLEventQueue` が `poll(2)` セットを組み立て、各ソースは `IPMLEventPumpSource.GetPollFDs` で fd を寄与する。これで Wayland fd と D-Bus fd と eventfd を 1 回の `poll` で待てる。
- **スレッド安全性**: リングバッファは `TPMLMutex` で保護し、`Wait` は `TPMLCondition` ではなく eventfd で起こす（`poll` と統一するため）。`Poll` / `Wait` はメインスレッド専用（デバッグビルドで検査）。
- **状態機械を通す規約**: バックエンドは `Push` を直接呼ばない。`Keyboard.SendKey` 等が重複排除・修飾キー計算・フォーカス追跡・**IME への転送（7.5）**を行ってから `Push` する。これは `events/SDL_keyboard.c` / `SDL_mouse.c` の移植であり、SDL の `SDL_SendKeyboardKey` 系の回避策（フォーカス喪失時の全キー解放、マウスボタンの二重押下抑制、相対モードでの座標クランプ）を継承する。
- **ディスパッチャ**（`TPMLEventDispatcher`）は v1 4.2 の設計を維持する: CORBA インターフェースの型別リスナー（`IPMLWindowListener`、`IPMLKeyboardListener`、`IPMLTextInputListener`、`IPMLMouseListener`、`IPMLGamepadListener`、…）を `AddListener` 1 回で `Supports` 検出し、`Dispatch(const AEvent)` が `case Kind of` で振り分ける。配信順: 汎用 `IPMLEventListener.HandleEvent(var AHandled)` → 型別インターフェース → `of object` メソッドポインタ → `OnUnhandled`。配信中の Add / Remove は遅延適用。ウィンドウ別リスナー（`AddWindowListener(WindowID, ...)`）を持つ。
- **`TPMLWindow` の自己登録**: `TPMLWindow` は生成時に自分の `WindowID` でディスパッチャに登録し、`WindowResized` 等を受けて自分のキャッシュ（`Size`、`Flags`）を更新し、`OnResized` を再発火する。`PaPiMeLa.Events` は `PaPiMeLa.Video` に依存しない（v1 4.3 を維持）。ディスパッチャを使わないアプリ（生の `Poll`）のために、`TPMLVideoSystem` も `Pump` の中でウィンドウのキャッシュ更新を直接行う（バックエンドが `TPMLWindow` の内部メソッド `HandleBackendResize` を呼ぶ）。つまりウィンドウのキャッシュ更新はディスパッチャに依存しない。

### 6.4 Wayland リスナーからの流入経路

```
libwayland-client: wl_display_dispatch_pending()
   │ C コールバック（cdecl、data = TPMLWaylandSeat 等の Pascal オブジェクト）
   ▼
PaPiMeLa.Video.Wayland.Seat: keyboard_key(data, wl_keyboard, serial, time, key, state)   ← 静的 cdecl サンク
   │ TPMLWaylandSeat(data).OnKeyboardKey(serial, time, key, state)   ← try/except で例外を FPendingException へ
   ▼
TPMLWaylandSeat.OnKeyboardKey
   ├─ xkb_state_update_key → keysym / UTF-8
   ├─ キーリピートタイマの起動/停止
   ├─ Scancode 変換（evdev keycode → TPMLScancode。events/SDL_keymap.c + scancodes_linux.h の表）
   ▼
Context.Events.Keyboard.SendKey(Window, TimestampNS, Scancode, Keycode, Down, IsRepeat, KeyboardID)
   ├─ TextInput.FilterKey(...)  （7.5。Consumed なら以下をスキップ）
   ├─ 修飾状態更新、重複排除
   ▼
Context.Events.Push(Ev)   → リングバッファ
   ▼
アプリ: Poll / Dispatcher
```

- Wayland のリスナー構造体（`wl_keyboard_listener` 等）は **`PaPiMeLa.Platform.Wayland.Protocols.*` に生成された `record` 型**で、フィールドは `cdecl` 手続きポインタ。`data` には Pascal オブジェクトの参照を渡す（`wl_proxy_add_listener(proxy, @Listener, Self)`）。サンクは `TPMLWaylandSeat(data)` のようにキャストしてメソッドへ委譲する 1 行 + 例外遮断で、ユニットローカルに置く。
- **タイムスタンプ**: Wayland の `time`（ミリ秒、起点不定）は使わず、イベント到着時の `TicksNS` を使う（SDL と同じ判断。`input-timestamps-v1` があれば高精度化。P3）。
- **シリアル**: `wl_keyboard.key` 等の `serial` は `TPMLWaylandSeat.LastSerial` に保存し、`xdg_toplevel.move` や `set_selection`、text-input-v3 の `commit` の引数に使う。公開イベントには載せない。
- **フォーカス**: `wl_keyboard.enter/leave` は `Keyboard.SetFocus(Window)` を呼び、それが `WindowFocusGained/Lost` を生成し、`TPMLTextInputSystem` に `IPMLFocusObserver.FocusChanged(Window)` で通知する。SDL はここで `SDL_IME_SetFocus` を直接呼んでいた。

### 6.5 アプリケーションループ（`PaPiMeLa.App`）

```pascal
type
  TPMLAppResult = (Continue, Success, Failure);

  TPMLApplication = class
  protected
    function  DoInit(const AArgs: TArray<String>): TPMLAppResult; virtual;     // Context を生成する場所
    function  DoIterate: TPMLAppResult; virtual;
    function  DoEvent(const AEvent: TPMLEvent): TPMLAppResult; virtual;        // 既定: Context.Events.Dispatcher.Dispatch
    procedure DoQuit(AResult: TPMLAppResult); virtual;                         // Context を Free する場所
  public
    property Context: TPMLContext;
    function Run: Integer;                    // DoInit → loop { Pump; while Poll do DoEvent; DoIterate } → DoQuit
    property WaitForEvents: Boolean;          // True なら DoIterate を呼ばず Wait で眠る（ツール系アプリ向け）
    class function RunMain(AClass: TPMLApplicationClass): Integer;
  end;
```

SDL のメインコールバック（`SDL_AppInit` 等）は「プラットフォームがメインループを所有する」問題への回答だが、Linux / Wayland ではアプリがループを所有できる。`TPMLApplication` は将来 Android / Emscripten を追加するときに `Run` の実装を差し替える場所として用意する。`Run` を使わず `Context` を直接作ってループを書くことも当然できる。

---

## 7. IME / テキスト入力の設計

本プロジェクトの中核であり、SDL に対する最大の差別化要素。全経路をクリーンルームで設計する。

### 7.1 SDL の限界と papimela の目標

SDL の `SDL_TextEditingEvent` は `text` / `start` / `length` の 3 フィールドしか持たず、変換中テキストの「注目文節 1 つ」しか表現できない。日本語入力では、変換中の文字列全体がどこで文節に区切られ、どの文節に注目しているか、各文節が未変換か変換済みかをアプリが描き分ける必要がある（かな漢字変換の下線表示）。また文脈を使う変換のためにアプリ側の確定済みテキストを IME に供給する経路と、IME が確定済みテキストの一部を削除して再変換する経路が SDL には無い。

papimela の 3 つの設計目標:

1. **全文節の区切り**: 変換中テキスト全体の文節境界配列。各文節に範囲 + 状態（未変換 / 変換済み / 注目文節）。
2. **周辺テキスト**（アプリ → IME）: カーソル周辺の確定済みテキストを IME に供給する。
3. **周辺削除**（IME → アプリ）: 「カーソル前後 N 文字を削除せよ」という要求をアプリに届ける。

### 7.2 情報源の分析 — どこから何が取れるか

| 情報 | Wayland text-input-v3 | IBus (D-Bus) | Fcitx5 (D-Bus) |
|---|---|---|---|
| 変換中テキスト | `preedit_string(text, cursor_begin, cursor_end)` | `UpdatePreeditText(IBusText, cursor_pos, visible)` | `UpdateFormattedPreedit(a(si), cursor)` |
| **文節区切り** | **取得不可**。引数は `text` / `cursor_begin` / `cursor_end` のみ。プロトコル XML に "styling" は一度も登場しない（v1/v2 にあった `preedit_styling` は v3 で削除された） | **取得可**。`IBusText` の `IBusAttrList` に属性配列。属性型 `1=underline`（値 `0=NONE, 1=SINGLE, 2=DOUBLE, 3=LOW, 4=ERROR`）、`2=foreground`、`3=background`。各属性が `start_index` / `end_index`（UTF-8 文字単位）を持つ。**下線 SINGLE = 未変換または変換済み文節、DOUBLE = 注目文節**（エンジン依存。7.4） | **取得可**。`a(si)` の各要素が (文字列, フォーマットフラグ) で、フラグに `Underline=1, HighLight=2, DontCommit=4, Bold=8, Strike=16, Italic=32`。文節ごとに要素が分かれる |
| 確定 | `commit_string(text)` | `CommitText(IBusText)` | `CommitString(s)` |
| **周辺テキスト供給** | **可**。`set_surrounding_text(text, cursor, anchor)`（バイト単位。テキストは 4000 バイト以内） | **可**。`SetSurroundingText(IBusText, cursor_pos, anchor_pos)`（文字単位）。クライアント能力 `IBUS_CAP_SURROUNDING_TEXT (1<<5)` の宣言が必要 | **可**。`SetSurroundingText(s, cursor, anchor)`（文字単位）。能力 `CAPABILITY_SURROUNDING_TEXT` |
| **周辺削除** | **可**。`delete_surrounding_text(before_length, after_length)` イベント（バイト単位） | **可**。`DeleteSurroundingText(offset: int32, n_chars: uint32)` シグナル（文字単位。`offset` はカーソルからの相対位置で負なら前方） | **可**。`DeleteSurroundingText(offset, size)` シグナル（文字単位） |
| 候補一覧 | 不可（IME 側が描画） | `UpdateLookupTable(IBusLookupTable, visible)`。能力 `IBUS_CAP_LOOKUP_TABLE (1<<2)` で埋め込み描画を要求できる | `UpdateClientSideUI` 系（能力 `CAPABILITY_CLIENT_SIDE_UI`） |
| カーソル矩形 | `set_cursor_rectangle(x, y, w, h)`（サーフェス座標） | `SetCursorLocation(x, y, w, h)` はスクリーン座標。**Wayland ではグローバル座標が取れない**ため、`SetCursorLocationRelative`（IBus 1.5.x 以降）を使う **[要検証: 最低バージョンとコンポジタ側の対応状況]** | `SetCursorRect(x, y, w, h)`（同じ問題） |
| キーイベント | 不要（コンポジタが IME に渡す） | **必要**。`ProcessKeyEvent(keyval, keycode, state)` を呼び、戻り `handled` で消費判定。非同期呼び出しが可能 | **必要**。`ProcessKeyEvent(keyval, keycode, state, isRelease, time)` |
| 有効化 | `enable` + `commit` | `FocusIn` / `FocusOut` | `FocusIn` / `FocusOut` |

SDL の現状: text-input-v3 の `set_surrounding_text` を一度も呼ばず、`delete_surrounding_text` のハンドラは `// FIXME: Do we care about this event?` の空実装（`src/video/wayland/SDL_waylandevents.c` 3081 行付近）。`src/core/linux/SDL_ibus.c` は `IBusAttrList` の全属性を走査しているが（147〜181 行）、`// We only use the background type to determine the selection` として背景色（type 3）だけを見て単一範囲を作り、**下線属性（type 1）を全部捨てている**。データは届いていて捨てられているだけである。

結論: **文節区切りが必要なら IBus / Fcitx と D-Bus で直接話す必要があり、周辺テキスト・周辺削除はどの経路でも取れる**。したがって:

- IME バックエンドをビデオバックエンドから独立させる（Wayland ビデオ + IBus IME の組み合わせが成立する。3.6）。
- text-input-v3 は「IBus / Fcitx が使えない環境（例: 別の IME フレームワーク、sandbox 内で D-Bus が無い、コンポジタ内蔵 IME）でのフォールバック」として位置付け、文節無しの単一範囲で動く。

### 7.3 公開モデル（アプリが見るもの）

図: `docs/diagrams/ime-model.md`（Mermaid。日本語版は `ime-model_jp.md`）

```pascal
type
  TPMLSegmentState = (Unconverted, Converted, Focused);   // 未変換 / 変換済み / 注目文節

  TPMLCompositionSegment = record
    StartByte, EndByte : Integer;     // Ev.Text 内の UTF-8 バイト範囲 [Start, End)
    StartChar, EndChar : Integer;     // 同じ範囲をコードポイント単位で
    State              : TPMLSegmentState;
    Underline          : TPMLUnderlineStyle;   // None, Single, Double, Low, Error（IBus の生値。State の根拠として残す）
    HasColors          : Boolean;
    Foreground, Background: TPMLColor;         // HasColors のとき有効。エンジンが指定した色（アプリは無視してよい）
  end;
  TPMLCompositionSegments = array of TPMLCompositionSegment;

  TPMLTextEditingData = record
    CursorByte, CursorChar           : Integer;   // 変換中テキスト内のキャレット。-1 = 非表示
    SelectionStartChar, SelectionLengthChars: Integer;  // 従来 SDL 互換の単一範囲。Segments から導出した値も入る（Focused 文節）
    FocusedSegment                   : Integer;   // Segments のインデックス。-1 = なし
    SegmentsReliable                 : Boolean;   // False = バックエンドが文節を提供しない（text-input-v3）。Segments は 1 要素（全体）
  end;

  TPMLDeleteSurroundingData = record
    BeforeBytes, AfterBytes : Integer;    // カーソルの前後で削除すべき UTF-8 バイト数（アプリのテキスト上）
    BeforeChars, AfterChars : Integer;    // 同じ量をコードポイント単位で
  end;
```

イベント:

| Kind | ペイロード | 意味 |
|---|---|---|
| `TextEditing` | `Text`（変換中テキスト全体）、`Segments`、`Edit` | 変換中テキストが更新された。`Text = ''` は変換中テキストの消滅 |
| `TextEditingCandidates` | `Strings`（候補）、`Edit.SelectedCandidate`、`Edit.PageStart`、`Edit.Horizontal` | 候補一覧（バックエンドが埋め込み描画を許すときだけ） |
| `TextInput` | `Text` | 確定文字列 |
| `TextInputDeleteSurrounding` | `DeleteSurrounding` | **周辺削除要求**。アプリは自分のバッファからカーソル前 `BeforeBytes`・後 `AfterBytes` を削除する。`TextInput` と同一の `Pump` で連続して届くことが多い（削除 → 確定で再変換結果を挿入） |

**バイトと文字の二重表現**: Pascal の `String` は UTF-8 バイト列なので、アプリはバイト範囲で部分文字列を切り出すのが最も自然である。一方 IBus / Fcitx はコードポイント単位で話す。papimela は**両方を常に埋める**ことにし、変換は `PaPiMeLa.Unicode` の `UTF8CharToByteOffset` / `UTF8ByteToCharOffset` で行う。イベントに載せるのは変換済みの値なので、アプリは変換コードを書かない。

**アプリが実装する契約**（周辺テキスト供給）:

```pascal
type
  IPMLTextInputClient = interface   // CORBA。寿命はアプリが管理
    ['{...}']
    // IME が要求したときに呼ばれる。カーソル周辺の確定済みテキストを返す。
    // AText は UTF-8。ACursorByte / AAnchorByte は AText 内のバイト位置（選択が無ければ同じ値）。
    // 4000 バイト以内に切ってよい（text-input-v3 の上限）。切る場合は文字境界で切ること。
    function  GetSurroundingText(out AText: String; out ACursorByte, AAnchorByte: Integer): Boolean;
    // キャレット矩形（ウィンドウ座標、ピクセル）。候補ウィンドウの位置決めに使う
    function  GetCursorRect: TPMLRect;
  end;

  TPMLTextInputSession = class(TPMLOwnedObject)     // ウィンドウごと。TPMLTextInputSystem.Start(Window, Client, Options) が返す
  public
    procedure Stop;                                  // = Free
    procedure NotifyTextChanged;                     // アプリがバッファを変更した（IME 以外の要因: マウスクリック、Undo）。周辺テキストの再送を促す
    procedure NotifyCursorRectChanged;
    procedure ResetComposition;                      // 変換中テキストを破棄（フォーカス移動、Escape 等）
    property  Window     : TPMLWindow;
    property  Client     : IPMLTextInputClient;
    property  InputType  : TPMLTextInputType;        // Text, Name, Email, Username, Password, Number, ...
    property  Hints      : TPMLTextInputHints;       // Multiline, AutoCorrect, Capitalization, ...
    property  Composing  : Boolean;                  // 変換中テキストがある
    property  Composition: TPMLComposition;          // 最新の TextEditing の内容（イベントを取りこぼしたアプリ向け）
    property  Capabilities: TPMLTextInputCapabilities;   // 現在のバックエンドが提供する能力
  end;
```

`GetSurroundingText` は **IME が要求したとき、および `NotifyTextChanged` / `TextInput` 確定後 / 周辺削除適用後に papimela が呼ぶ**。アプリの契約は「呼ばれたら現在のバッファを返す」だけで、能動的に送る必要はない。`Client = nil` で開始したセッションでは周辺テキスト機能を無効にする（IBus に `IBUS_CAP_SURROUNDING_TEXT` を宣言しない）。

**周辺削除の適用**: アプリは `TextInputDeleteSurrounding` を受けたら**同期的に**削除を適用しなければならない。IME は次に `TextInput`（確定）を送ってくるため、削除が遅れると挿入位置がずれる。papimela はこの 2 イベントを同じ `Pump` 内で連続してキューに入れることを保証する（間に他イベントを挟まない）。

### 7.4 IBus バックエンドの設計（`PaPiMeLa.TextInput.IBus`）

SDL の `SDL_ibus.c`（743 行）を参考にするが構造は新設計。D-Bus 結合は `PaPiMeLa.Platform.DBus`（libdbus-1 を `dlopen`）。

**接続手順**（SDL から継承する知見）:

1. アドレス解決: 環境変数 `IBUS_ADDRESS` → なければ `$XDG_CONFIG_HOME/ibus/bus/<machine-id>-<display>` を読む。`<display>` は Wayland では `WAYLAND_DISPLAY`（`unix-wayland-0` 形式）、X11 では `DISPLAY` から。SDL はこのファイルを inotify で監視し、IBus デーモンの再起動を追従する。**監視は移植する**（`inotify_add_watch`）。
2. `dbus_connection_open_private(address)` で IBus 専用バスに接続（セッションバスではない）。
3. `org.freedesktop.IBus.CreateInputContext(client_name)` → 入力コンテキストのオブジェクトパス。
4. `org.freedesktop.IBus.InputContext.SetCapabilities(caps)`。papimela は `PREEDIT_TEXT (1<<0) | FOCUS (1<<3) | SURROUNDING_TEXT (1<<5)` を常に、`LOOKUP_TABLE (1<<2)` をオプション `EmbedCandidates` のときに宣言する。
5. シグナル購読: `CommitText`、`UpdatePreeditText`、`UpdatePreeditTextWithMode`、`ShowPreeditText`、`HidePreeditText`、`DeleteSurroundingText`、`RequireSurroundingText`、`UpdateLookupTable`、`ShowLookupTable`、`HideLookupTable`、`ForwardKeyEvent`。

**`IBusText` の完全な解析**（ここが SDL との差）:

```
IBusText = variant( struct( s "IBusText", a{sv} attachments, s text, v attr_list ) )
IBusAttrList = variant( struct( s "IBusAttrList", a{sv}, av attributes ) )
IBusAttribute = variant( struct( s "IBusAttribute", a{sv}, u type, u value, u start_index, u end_index ) )
```

`TPMLIBusTextParser` はこの構造を再帰的に読み、**型名の検証を正しく行う**（SDL の 115 行目のバグを再現しない。期待する型名と `struct_id` を比較する）。属性配列は全部読んで `TArray<TPMLIBusAttribute>` にする。

**属性 → 文節配列への変換**（`TPMLIBusSegmenter`）:

1. 下線属性（type 1、value <> 0）の `[start_index, end_index)` を文節候補として集める。
2. 隣接・重複する範囲を、**境界が一致しないものは分割**して、重なりの無い区間列にする（複数エンジンが重ねて属性を出す場合に備える）。
3. 各区間の `State`: 下線 `DOUBLE` → `Focused`。`SINGLE` → 背景色属性（type 3）が同区間を覆うなら `Focused`（Mozc / Anthy は注目文節を背景色でも示す。SDL はこの背景色だけを見ていた）、覆わないなら `Converted`。下線 `LOW` / `NONE` で背景色なし → `Unconverted`。`ERROR` → `Unconverted` + `Underline = Error`。
4. 属性が 1 つも無いのにテキストがある場合（一部のエンジンや ASCII 直接入力） → 全体を 1 文節 `Unconverted` にし、`SegmentsReliable = True`（「文節が 1 つ」という情報は信頼できる）。
5. 属性の付かない隙間（文節間に空白等が入る場合）は `Unconverted` の区間として埋め、`Segments` が `Text` 全体を被覆するようにする。**アプリは `Segments` を順に描けば `Text` 全体を描ける**という不変条件。

エンジンごとの属性の使い方（Mozc: 注目文節に DOUBLE、他に SINGLE。Anthy: 注目文節に SINGLE + 背景反転、他に SINGLE。SKK: 変換中は下線なし）は **[要検証: 実機で ibus-mozc / ibus-anthy / ibus-skk / ibus-libpinyin の属性を `dbus-monitor` で採取し、上記 3 のルールを確定する]**。ルールは `TPMLIBusSegmenter` に集約し、エンジン名（`GlobalEngine` プロパティで取得可）による分岐を入れられる余地を持たせる。

**周辺テキスト**: `RequireSurroundingText` シグナルを受けたら、および `FocusIn` 直後・確定直後・削除適用直後に、`Client.GetSurroundingText` を呼び、バイト位置を文字位置に変換して `SetSurroundingText(IBusText(text), cursor_pos, anchor_pos)` を送る。送った `text` は `FLastSurrounding` として保持する。

**周辺削除**: `DeleteSurroundingText(offset, n_chars)` シグナルを受けたら、`FLastSurrounding` とそのカーソル位置を使って文字単位の (offset, n_chars) を `BeforeChars` / `AfterChars` に分け、さらにバイト数に変換して `TextInputDeleteSurrounding` イベントを発行する。`FLastSurrounding` が無ければ（`Client = nil`）ログを出して無視する。

**キーイベント転送**: 7.5 参照。`ProcessKeyEvent(keyval, keycode - 8, state)` を**非同期**（`dbus_connection_send_with_reply`）で送り、返信 `handled` が来るまでキーイベントを `Deferred` として保留する。SDL は同期呼び出し（タイムアウト付き）で実装しており、IME の応答が遅いとメインループが止まる。非同期化は設計上の改善点であり、順序保証（保留中に次のキーが来た場合は FIFO で保留）を `TPMLDeferredKeyQueue` が担う。`ForwardKeyEvent` シグナル（IME が「このキーはアプリに渡せ」と返す）は、保留中の対応キーを `PassThrough` に変えて解放する。

**カーソル位置**: `SetCursorLocationRelative(x, y, w, h)` を使う（ウィンドウ相対で IBus 側がコンポジタと連携して候補ウィンドウを置く）。Wayland でグローバル座標が無い問題への IBus 側の回答であり、GTK4 の ibus IM モジュールも同じ方法を採る **[要検証]**。`EmbedCandidates` オプションが有効なら `UpdateLookupTable` を `TextEditingCandidates` に変換し、IBus 側のポップアップは表示されない。

### 7.5 キーイベントの経路と IME フィルタ

```
TPMLKeyboardState.SendKey(Window, TS, Scancode, Keycode, Down, Repeat)
   │
   ├─ if TextInput.Active(Window) then
   │      case TextInput.FilterKey(KeyData) of
   │        Consumed    : exit;                            // IME が消費（例: 変換中の Space）
   │        PassThrough : (続行);                          // IME が不要と判断
   │        Deferred    : (KeyData を Deferred キューへ。返信が来たら SendKeyResolved で再入)  // IBus / Fcitx の非同期返信待ち
   │      end;
   ▼
   通常のキー処理 → KeyDown / KeyUp イベント
```

- text-input-v3 バックエンドの `FilterKey` は常に `PassThrough`（コンポジタが IME 処理済みのキーだけを送ってくるため）。
- IBus / Fcitx バックエンドは `Deferred` を返す。`TPMLKeyboardState` は Deferred 中のキーとその後に来たキーを順序を保って保留し、返信で解決する。保留中に `WindowFocusLost` が来たら全部 `PassThrough` で解放する。
- **修飾キー単独押下**（Shift 等）も IBus に送る必要がある（エンジンがモード切替に使う）。
- キーリピートは Wayland 側（`wl_keyboard.repeat_info`）で生成されるので、リピートキーも同じ経路を通る。
- **二重入力の防止**: IBus 直結を選んだときは、Wayland text-input-v3 を**有効化しない**（`zwp_text_input_v3.enable` を送らない）。GNOME（mutter）はそれ自身が IBus クライアントであり、text-input-v3 を有効化したサーフェスに対してだけ IBus を仲介する。無効なら仲介しないため、アプリの直結と競合しない **[要検証: GNOME 46+ / KDE Plasma 6 + fcitx5 / Sway + fcitx5 の 3 環境で、IBus 直結時に text-input-v3 を無効にしたまま IME が動くこと。GTK4 アプリで `GTK_IM_MODULE=ibus` を指定した場合と同じ状況なので動く見込み]**。

### 7.6 バックエンドの選択と切替

```
TPMLTextInputSystem.SelectBackend:
  1. 環境変数 PAPIMELA_IME（"ibus" | "fcitx" | "wayland" | "none"）があればそれのみ試す
  2. なければ順に Connect を試す: IBus（アドレスファイルが存在し接続できる）→ Fcitx（セッションバスに org.fcitx.Fcitx5 がある）
     → WaylandTI（ビデオバックエンドが IPMLWaylandSeatProvider を実装し、コンポジタが zwp_text_input_manager_v3 を広告）→ Null
  3. 選択結果を Log.Info に出す
```

- `TPMLTextInputSystem.Backend` は実行時に切り替え可能（`SwitchBackend(Name)`）。切替時は現在のセッションを `Deactivate` → 新バックエンドで `Activate`。IBus デーモン再起動の追従（inotify）も同じ経路で行う。
- `Capabilities` はバックエンドごとに異なる。アプリは `Session.Capabilities` で `Segments` が無ければ単一範囲表示にフォールバックする（`SegmentsReliable = False` でも同じ情報）。

### 7.7 text-input-v3 バックエンド（`PaPiMeLa.TextInput.WaylandTI`）

- `IPMLWaylandSeatProvider` から `wl_seat` を得て `zwp_text_input_manager_v3.get_text_input(seat)`。`enter(surface)` / `leave(surface)` で対象ウィンドウを判定する。
- `Activate`: `enable` → `set_content_type(hint, purpose)` → `set_cursor_rectangle` → **`set_surrounding_text(text, cursor, anchor)`**（SDL が呼んでいなかったもの）→ `set_text_change_cause(input_method | other)` → `commit`。
- `preedit_string` / `commit_string` / `delete_surrounding_text` を受けて `done(serial)` で**まとめて適用**する（プロトコルの規定。SDL は `has_preedit` フラグで部分的にしか守っていない）。`done` 時の適用順序: 周辺削除 → 確定 → 変換中テキスト、の順でイベント発行。これは仕様書の "The application must proceed by evaluating the changes in the following order: 1. Replace existing preedit string with the cursor. 2. Delete requested surrounding text. 3. Insert commit string with the cursor at its end. 4. Calculate surrounding text to send. 5. Insert new preedit text in cursor position. 6. Place cursor inside preedit text." に従う。
- `preedit_string` の `cursor_begin` / `cursor_end` から単一の `Focused` 文節を作り、残りは `Unconverted`。`SegmentsReliable = False`。
- `set_surrounding_text` は 4000 バイト制限があるため、`Client.GetSurroundingText` の結果をカーソルを中心に文字境界で切り詰める。

### 7.8 Fcitx5 バックエンド（`PaPiMeLa.TextInput.Fcitx`、P2）

- セッションバスの `org.fcitx.Fcitx5` → `org.fcitx.Fcitx.InputMethod1.CreateInputContext(a(ss))` → `org.fcitx.Fcitx.InputContext1`。
- `UpdateFormattedPreedit(a(si), cursor)` の各要素が文節に相当する。フラグ → 状態の対応は **fcitx5-mozc で実測して次の規則に確定した**（`test/test_fcitx_textinput.pas` が検証）:
  1. `HighLight` を持つ文節 → `Focused`
  2. `HighLight` がどの文節にも無ければ、**全文節を `Unconverted`**
  3. `HighLight` がどこかにあり、その文節が `Underline` のみ → `Converted`

  規則 2 が必要な理由: ローマ字入力中（変換前）の「わたしのなまえ」は `Underline` 単独で届く。「`Underline` のみ → `Converted`」と単純に決めると、未変換のかなを変換済みとして描いてしまう。`HighLight` の有無が変換段階に入ったかの判定になる。**[要検証: fcitx5-anthy / fcitx5-chinese-addons]**
- `UpdateFormattedPreedit` の `cursor` は **UTF-8 バイトオフセット**だが、`SetSurroundingText` の `cursor` / `anchor` は**コードポイント単位**。この非対称は fcitx5 側の仕様であり、papimela が `PaPiMeLa.Unicode` で吸収する。
- `SetSurroundingText` / `DeleteSurroundingText` は IBus とほぼ同形。能力 `CAPABILITY_SURROUNDING_TEXT (1<<5)`、`CAPABILITY_PREEDIT (1<<1)`、`CAPABILITY_FORMATTED_PREEDIT (1<<4)`。
- SDL の `SDL_fcitx.c`（441 行）は Fcitx5 の D-Bus API を使っているので接続手順は参考にできる。

### 7.9 アプリ側の典型的な実装

```
1. Session := Context.TextInput.Start(Window, Self { IPMLTextInputClient }, Options);
2. イベントループ:
   TextEditing        → 自分の描画用に Ev.Text と Ev.Segments を保存。Segments[i].State で下線の種類を変える
   TextInput          → カーソル位置に Ev.Text を挿入。その後 papimela が GetSurroundingText を呼ぶ
   TextInputDeleteSurrounding → カーソル前 BeforeBytes / 後 AfterBytes を削除（同期的に）
   TextEditingCandidates → 候補ウィンドウを自前描画（EmbedCandidates オプション時のみ）
   KeyDown            → IME が消費しなかったキー（矢印、Enter、Backspace）だけが届く
3. マウスでカーソルを動かした / Undo した → Session.NotifyTextChanged; Session.NotifyCursorRectChanged;
4. フォーカスを失う / 別フィールドへ → Session.ResetComposition または Session.Stop
```

---

## 8. OOP 機能の活用方針と命名規則

v1 の 5 章・6 章を引き継ぎ、再実装向けに調整する。変更点は太字。

### 8.1 プロパティ構文

- 状態を持つ getter/setter ペアは `property`。**再実装では状態の真の所有者が papimela 自身なので、キャッシュの是非という問題が消える**: `TPMLWindow.Title` は `TPMLWindow` のフィールドが真の値であり、setter がバックエンドに反映する。SDL の「SDL が真の状態を持つのでラッパーはキャッシュしない」という v1 の判断は不要。
- 副作用が大きい・引数が複数ある操作はメソッド（`SetFullscreenMode(Display, Mode)`）。
- インデックスプロパティは配列アクセスに（`Joystick.Axes[i]`、`Events.Enabled[Kind]`）。
- `class property` は静的クラス（`TPMLFileSystem.BasePath`）で使う。
- **バックエンド抽象クラスの契約メソッドは `protected` に置き**、公開層だけが `friend` 的に呼ぶ（同一ユニットではないので、公開層側の抽象クラスに `public` の薄い転送メソッドを用意するか、抽象クラスを公開層と同じユニットに置く。後者を採用: `PaPiMeLa.Video.Backend` は `PaPiMeLa.Video` から `uses` され、契約メソッドは `public` だがドキュメントで「バックエンド実装者と公開層のみが呼ぶ」と明記する）。

### 8.2 命名規則

| 対象 | 規則 | 例 |
|---|---|---|
| **接頭辞** | **`PML`**（v1 の `SDL` を置き換え）。理由: 本ライブラリは SDL ではなく API 互換も無い。SDL の名を型名に含めると SDL の C API を呼んでいると誤解される | `TPMLWindow`、`EPMLVideoError`、`IPMLKeyboardListener` |
| クラス | `T` + `PML` + 概念名 | `TPMLRenderer`、`TPMLWaylandSeat` |
| バックエンド抽象クラス | `TPML` + 責務 + `Backend`（ビデオ軸・IME 軸・オーディオ軸）、または SDL 用語を残して `Driver`（レンダラ軸のみ。「レンダラドライバ」は定着した用語） | `TPMLWindowBackend`、`TPMLTextInputBackend`、`TPMLRenderDriver` |
| バックエンド具象クラス | `TPML` + プラットフォーム名 + 責務 | `TPMLWaylandWindowBackend`、`TPMLIBusTextInputBackend`、`TPMLPipeWireAudioBackend` |
| レコード（値型） | `T` + `PML` + 名 | `TPMLRect`、`TPMLEvent`、`TPMLCompositionSegment` |
| イベントペイロードレコード | `TPML` + 名 + `Data` | `TPMLKeyEventData`、`TPMLDeleteSurroundingData` |
| インターフェース | `I` + `PML` + 名。リスナーは `Listener`、アプリ実装契約は `Client`、内部通知は `Sink` / `Observer` / `Provider` | `IPMLKeyboardListener`、`IPMLTextInputClient`、`IPMLTextInputSink`、`IPMLWaylandSeatProvider` |
| 例外 | `E` + `PML` + 名 + `Error`（状態系は `Error` を付けない） | `EPMLAudioError`、`EPMLUnsupported` |
| 列挙型 | `T` + `PML` + 名（単数形）。`{$scopedenums}` | `TPMLGamepadButton.South`、`TPMLSegmentState.Focused` |
| 集合型 | 列挙名の複数形 | `TPMLWindowFlags = set of TPMLWindowFlag`、`TPMLVideoCapabilities` |
| メソッドポインタ型 | `TPML` + 名 + `Event`（イベント）/ `Method`（コールバック） | `TPMLKeyEventHandler`、`TPMLTimerMethod` |
| 静的クラス | `TPML` + 名、`class sealed`、`constructor Create` を `private` に | `TPMLFileSystem`、`TPMLUnicode` |
| フィールド | `F` プレフィックス、`strict private` | `FBackend` |
| 引数 | `A` プレフィックス | `AWindow`、`const AText: String` |
| **Platform.\* の C 由来の識別子** | **C の名前を保つ**（`wl_display`、`xkb_state`、`snd_pcm_t`、`DBusMessageIter`）。型は `T` を付けず、ポインタ型は `P` + C 名（`Pwl_display`）。関数ポインタ変数も C 名（`wl_display_dispatch: function(...): cint; cdecl;`）。理由: プロトコル仕様・man ページとの照合を容易にする。生成コードもこの規則 | `wl_registry_listener`、`zwp_text_input_v3_set_surrounding_text` |
| 移植した内部関数 | Pascal 規則に直す（`SDL_` を除き PascalCase）。**ヘッダの `Origin` 行と `PORT-NOTE` コメントで元関数名を参照できるようにする** | `SDL_ConvertAudio` → `TPMLAudioConverter.Convert`（`// PORT-NOTE: SDL_ConvertAudio`） |
| ユニット | `PaPiMeLa.` + PascalCase。層の階層は `.` 区切り | `PaPiMeLa.TextInput.IBus`、`PaPiMeLa.Platform.Wayland.Protocols.XdgShell` |
| SDL 用語の踏襲 | SDL3 の用語（`Renderer`、`Gamepad`、`Playback/Recording`、`South/East/West/North`）を優先 | — |
| ブール | 状態は形容詞/受動態（`Paused`、`Connected`）、能力は `Can*`/`Has*`/`Supports*` | `Window.Fullscreen`、`Backend.Capabilities` |
| `Try` 接頭辞 | 例外を投げず `Boolean` を返す版 | `TryRenderTexture` |
| 破棄 | `Destroy`（デストラクタ）のみ。`Close` / `Stop` は「オブジェクトは残して状態を変える」操作に限定。`TPMLTextInputSession.Stop` は `Free` の別名なので**例外**（テキスト入力の「開始/停止」という語彙に合わせる） | — |
| 単位 | 名前に含める: `Ticks`（ms）、`TicksNS`、`DelayNS`、`Timestamp`（ns、接尾辞なし）、`*Byte(s)` / `*Char(s)`（7.3） | — |

### 8.3 演算子オーバーロードと幾何・色型（`PaPiMeLa.Types`）

v1 5.2 をそのまま採用する（C レイアウト互換の静的アサートだけ削る。**ただし `Platform.*` に渡す構造体（`wl_region` の矩形等）とは別型で、変換は明示的に行う**）。

- `TPMLPoint`（`Int32` x2）、`TPMLFPoint`（`Single` x2）、`TPMLRect`（`Int32` x4）、`TPMLFRect`（`Single` x4）、`TPMLColor`（`UInt8` x4）、`TPMLFColor`（`Single` x4）、`TPMLGUID`（16 バイト）。
- 演算子: `=` / `<>`（要素比較）、`+` / `-`（Point + Point、Rect + Point 平行移動、Color 飽和加算）、`*` / `/`（スカラー倍）、単項 `-`、`in`（`Point in Rect`）、`*`（Rect 交差）、`+`（Rect 包含）、`Implicit`（拡大方向: Point → FPoint、Rect → FRect、Color → FColor）、`Explicit`（縮小方向、`Color ↔ UInt32` パック）。
- メソッド: `Create`、`FromLTRB`、`Empty`、`IsEmpty`、`Center`、`Inflate`、`Offset`、`Intersects`、`Contains`、`Union`、`Right` / `Bottom`、`TPMLColor.FromHex`、`Lerp`、`class function White/Black/Transparent`。
- `src/video/SDL_rect.c` / `SDL_rect_impl.h`（`SDL_GetRectAndLineIntersection` 等のアルゴリズム）は `TPMLRect` のメソッドとして移植。

### 8.4 インターフェース

- **CORBA（非参照カウント）が既定**。リスナー、`IPMLTextInputClient`、`IPMLClipboardDataProvider`、`IPMLEventWatch` / `IPMLEventFilter`、`IPMLEventPumpSource`、`IPMLFocusObserver`、`IPMLWaylandSeatProvider`、`IPMLTextInputSink`。寿命は所有者が管理し、インターフェースは契約のみ。GUID は `Supports` のため必ず付ける。
- **COM（参照カウント）は `IPMLTexture` / `IPMLSurface` の共有 opt-in にのみ**（v1 2.3）。`TPMLTexture.CreateShared` で生成したものだけ `_Release` で `Free` する。
- **バックエンド抽象はインターフェースではなく抽象クラス**にする。理由: 共通実装を継承で共有したい（3.4）、フィールド（`Capabilities`、`Owner`）を持たせたい、CORBA インターフェースにするとキャストが増える。
- 公開 API の抽象化（`IPMLWindow` を作って `TPMLWindow` に実装させる等）は**しない**（v1 5.4 を維持）。

### 8.5 ジェネリクス

- `Generics.Collections`（`TList<T>`、`TDictionary<K,V>`、`TObjectList<T>`）を内部で自由に使う。`SDL_hashtable.c` の代替。
- 独自ジェネリック: `TPMLRingBuffer<T>`（イベントキュー、オーディオキュー）、`TPMLObjectPool<T>`（`TPMLEvent` 用ではない。Wayland のバッファプール等）。
- 公開 API には `TArray<T>` だけを露出し、`specialize` 構文を使わせない（v1 5.3 を維持）。

### 8.6 コールバックの統一パターン（サンク）

v1 5.5 を維持し、対象が「SDL の C コールバック」から「プラットフォームライブラリの C コールバック」に変わるだけ。

- `cdecl` のユニットローカル手続きが `data: Pointer` を Pascal オブジェクトにキャストしてメソッドへ委譲する。1 コールバック = 1 サンク。
- 例外遮断は 5.5 の表に従う。
- Wayland リスナーは**イベント数が多い**（`wl_pointer` 11、`wl_keyboard` 6、`xdg_toplevel` 4、`zwp_text_input_v3` 6 等）ので、リスナー構造体の初期化とサンクの束を**プロトコル生成器（9.2）が生成する**。生成器は各イベントについて「`data` を `TObject` として受け、`IPML<Interface>_<event>` を呼ぶ」ではなく、より単純に **`T<Interface>Listener` 抽象クラス（1 イベント = 1 仮想メソッド、既定は空）を生成し、サンクは `T<Interface>Listener(data).<event>(args)` を呼ぶ**。バックエンドはこの抽象クラスを継承またはフィールドに持つ。これにより SDL の C コードにあった 3917 行のリスナー定義の 3 分の 1 程度（構造体宣言と空ハンドラ）が消える。

### 8.7 移植コードの整形規約

- **`PORT-NOTE:` コメント**: C 側の関数名、意図的に変えた振る舞い、疑わしい元コードの箇所を記す。`PORT-NOTE(bug):` は元コードのバグを直した箇所（1.2 の `SDL_ibus.c` 115 行のような）。`docs/UPSTREAM-NOTES.md` に集約する。
- **`#ifdef` は消す**。初回スコープ外のプラットフォーム分岐は移植しない。将来必要になったら派生クラスで解決する。Linux 内の分岐（`SDL_PLATFORM_LINUX`、`HAVE_*`）は実行時の `dlopen` 成否に置き換える。
- **`goto` は `try/finally` に**、**`void *` は具象型に**、**`(cast)` は派生クラスのフィールド参照に**、**`static` グローバルは所有者オブジェクトのフィールドに**。移植担当はこの 4 変換を機械的に適用する。
- SIMD（SSE/AVX/NEON の `#ifdef`）部分は移植せず、スカラー版だけ移植する。**FPC のインラインアセンブラや intrinsics への移植は P4**（9.5）。

---

## 9. 前提となる基盤整備

実装に入る前に用意が必要なもの。多くは SDL の `*dyn.c` / `*sym.h`（動的ロード用のシンボル表）に相当するが、papimela では生成器で機械化する。

### 9.1 動的ロード基盤（`PaPiMeLa.Platform.DynLib`）

- `dlopen` / `dlsym` の薄いラッパー `TPMLDynLib`。**すべてのプラットフォームライブラリは実行時ロード**（1.4 のライセンス方針、および「PipeWire が無い環境で PulseAudio にフォールバック」のため）。
- 関数ポインタ変数の束（`wl_display_connect: function(...): Pwl_display; cdecl;` の列）を 1 つのレコードにまとめ、`Load(const ALibNames: array of String)` が `dlsym` で埋める。1 つでも欠けたらそのライブラリは「使えない」（`EPMLPlatformLibrary` を投げるか、バックエンド選択ループでは `False`）。オプショナルなシンボル（新しいバージョンにしか無い関数）は別レコードにし、欠けても続行する。
- SDL の `SDL_waylanddyn.c` / `SDL_waylandsym.h` の `SDL_WAYLAND_MODULE` / `SDL_WAYLAND_SYM` マクロ相当の一覧を、**シンボル表の Pascal 宣言と `dlsym` 呼び出しの両方を 1 つの定義ファイルから生成する**（`tools/gensyms`。9.6）。

### 9.2 Wayland プロトコル XML → Pascal 生成器（`tools/wlscan-pas`）

wayland-scanner の Pascal 版。C の `wayland-scanner` が生成する `*-client-protocol.h` / `*-protocol.c` に相当するものを生成する。**これが Wayland バックエンド実装の前提であり、最初に作る**。

生成対象 XML（`reference/SDL/wayland-protocols/` にあるものを起点とし、必要なら wayland-protocols 上流から取る）: `wayland.xml`（コア）、`xdg-shell.xml`、`xdg-decoration-unstable-v1.xml`、`xdg-output-unstable-v1.xml`、`xdg-activation-v1.xml`、`viewporter.xml`、`fractional-scale-v1.xml`、`text-input-unstable-v3.xml`、`primary-selection-unstable-v1.xml`、`pointer-constraints-unstable-v1.xml`、`relative-pointer-unstable-v1.xml`、`cursor-shape-v1.xml`、`idle-inhibit-unstable-v1.xml`、`keyboard-shortcuts-inhibit-unstable-v1.xml`、`xdg-toplevel-icon-v1.xml`、`tablet-v2.xml`（P3）、`pointer-warp-v1.xml`、`xdg-dialog-v1.xml`、`alpha-modifier-v1.xml`、`color-management-v1.xml`（P3）、`input-timestamps-unstable-v1.xml`（P3）。

生成物（1 XML = 1 ユニット `PaPiMeLa.Platform.Wayland.Protocols.<Name>`）:

| 要素 | C の wayland-scanner | Pascal 生成 |
|---|---|---|
| インターフェース記述子 | `const struct wl_interface xdg_toplevel_interface` + メッセージ表 + 型配列 | **[解決済み]** 定数式では書けない（`types` はポインタ配列で相互参照するため）。生成器は `EnsureProtocolInitialized` 手続きを出力し、実行時に `types` 配列・メッセージ表・記述子を組む。**コアプロトコルは libwayland が記述子を公開しているので `dlsym` で引き、拡張プロトコルだけ自前で構築する**（libwayland が内部でポインタ比較する経路があるため、コアを二重に定義しない）。実機の labwc で xdg-shell と text-input-v3 の記述子が受理され、`configure` イベントも届くことを `test/test_wayland_protocols.pas` で確認 |
| リクエスト | `static inline void xdg_toplevel_set_title(struct xdg_toplevel*, const char*)` → `wl_proxy_marshal_flags` | **[解決済み]** `cdecl; varargs` で直接呼べる。**`dlopen` した関数ポインタ経由でも正しく渡る**ことを実測で確認したので、`wl_proxy_marshal_array_flags` による回避は不要。生成形は C と同じ（`destructor` 属性のリクエストは `WL_MARSHAL_FLAG_DESTROY`、`new_id` はプレースホルダの `nil` を引数位置に置く） |
| イベントリスナー | `struct xdg_toplevel_listener { void (*configure)(...); ... }` | `xdg_toplevel_listener = record configure: procedure(data: Pointer; ...); cdecl; ... end;` + **`Txdg_toplevel_listener` 抽象クラス**（1 イベント = 1 仮想メソッド。8.6）+ サンク束 + `xdg_toplevel_add_listener_object(p, obj: Txdg_toplevel_listener)` |
| 列挙 | `enum xdg_toplevel_state { ... }` | `{$scopedenums}` の列挙は使わず、`const XDG_TOPLEVEL_STATE_MAXIMIZED = 1;` の整数定数（プロトコル値は疎で、ビットフラグ列挙もある） |
| バージョン | `XDG_TOPLEVEL_SET_TITLE_SINCE_VERSION` | 同名の定数 |

生成器自体は **Free Pascal で書く**（`fcl-xml` で XML を読む。ビルド時依存を FPC だけにする）。`instantfpc` でも動く単一ファイルの `program` にする。

### 9.3 libwayland-client / libwayland-egl / libwayland-cursor の結合（`PaPiMeLa.Platform.Wayland.Client`）

- 手書き（生成器の対象外）: `wl_display_connect/disconnect/dispatch/dispatch_pending/flush/roundtrip/get_fd/prepare_read/read_events/cancel_read/get_error`、`wl_proxy_*`（`marshal_array_flags`、`add_listener`、`set_user_data`、`get_user_data`、`get_version`、`destroy`、`set_queue`、`wrap`）、`wl_event_queue_*`、`wl_list`、`wl_array`。SDL の `SDL_waylandsym.h`（247 行）が一覧になっている。
- `wl_egl_window_create/destroy/resize`、`wl_cursor_theme_load/destroy`、`wl_cursor_theme_get_cursor`、`wl_cursor_image_get_buffer`、`wl_cursor_frame`。

### 9.4 その他のプラットフォーム結合

| ユニット | ライブラリ | 内容 | 由来 / 参考 |
|---|---|---|---|
| `Platform.XKB` | `libxkbcommon.so.0`（+ `libxkbcommon-x11` は不要） | `xkb_context_*`、`xkb_keymap_*`、`xkb_state_*`、`xkb_compose_*`、キーシム定数（`XKB_KEY_*` は 2000 以上あるが、必要なのは SDL の `SDL_keysym_to_scancode.c` / `imKStoUCS.c` が参照する範囲） | `SDL_waylandsym.h` の xkbcommon 節 |
| `Platform.DBus` | `libdbus-1.so.3` | `dbus_bus_get_private`、`dbus_connection_open_private`、`_send_with_reply`、`_add_filter`、`dbus_message_*`、`dbus_message_iter_*`（`recurse`、`get_arg_type`、`get_basic`、`next`、`open_container`、`append_basic`）、`dbus_pending_call_*`、`dbus_error_*`、`dbus_connection_set_watch_functions`（イベントループ統合。6.3 の `poll` セットに fd を寄与するため **`dbus_connection_get_unix_fd` ではなく watch 関数で fd を追跡する**） | `core/linux/SDL_dbus.c`（2052 行）の `SDL_DBusContext` 構造体が一覧。Pascal 側は関数ポインタレコード + `TPMLDBusConnection`（接続・フィルタ・保留呼び出しの管理、例外遮断）。**IBus 直結には D-Bus のバリアント/構造体の再帰読み取りが必要**で、SDL は手で `iter_recurse` を書いている。papimela は `TPMLDBusReader`（シグネチャ駆動の再帰リーダ）を用意し、`IBusText` の解析（7.4）をそれで書く |
| `Platform.EGL` / `Platform.GLES2` / `Platform.GL` | `libEGL.so.1`、`libGLESv2.so.2`、`libGL.so.1` | EGL 1.5 + `EGL_EXT_platform_base` / `EGL_KHR_platform_wayland` の関数と定数。GLES2 / GL の関数は `eglGetProcAddress` で取るので、レンダラが必要とする関数だけを宣言（SDL の `SDL_glesfuncs.h` / `SDL_glfuncs.h` の一覧に倣う）。**`src/video/khronos` の 73k 行は使わず、必要な定数と関数だけ手で書く** | `SDL_egl.c`、`render/opengles2/SDL_glesfuncs.h` |
| `Platform.Evdev` | カーネル ABI（ライブラリなし） | `input_event`、`input_absinfo`、`input_id`、`EVIOCG*` ioctl 番号（`_IOR` / `_IOW` マクロの計算を Pascal 定数式で）、`EV_*` / `KEY_*` / `BTN_*` / `ABS_*` / `FF_*` 定数、`ff_effect` 構造体（Haptic 用） | `core/linux/SDL_evdev_capabilities.c`、`joystick/linux/SDL_sysjoystick.c`。**FPC の `BaseUnix.FpIOCtl` を使う** |
| `Platform.Udev` | `libudev.so.1` | `udev_new`、`udev_monitor_*`、`udev_enumerate_*`、`udev_device_*`。SDL は udev が無い環境用に inotify フォールバックも持つ（`SDL_udev.c` + `SDL_sysjoystick.c` の inotify 経路）。**両方移植する** | `core/linux/SDL_udev.c` |
| `Platform.Alsa` | `libasound.so.2` | `snd_pcm_*`（open/close/hw_params/sw_params/writei/readi/recover/avail/wait/drain）、`snd_device_name_hint`、`snd_ctl_*`。SDL の `SDL_alsa_audio.c` が使う約 60 関数 | `audio/alsa/SDL_alsa_audio.c`（1708 行）冒頭のシンボル表 |
| `Platform.PipeWire` | `libpipewire-0.3.so.0` | `pw_init/deinit`、`pw_thread_loop_*`、`pw_context_*`、`pw_core_*`、`pw_registry_*`、`pw_stream_*`、`pw_properties_*`、`spa_*` の **インライン関数群**（`spa_pod_builder_*`、`spa_format_audio_raw_build` は C ヘッダのインライン / マクロなので Pascal に**再実装**が必要。SDL の `SDL_pipewire.c` が使う範囲に限る）。`spa_pod` のバイナリレイアウトを正確に写す **[要検証: `spa_pod_builder` の Pascal 再実装。SDL は C ヘッダをインクルードしているので参考にならない。PipeWire のヘッダ `spa/pod/builder.h` を直接読む必要がある]** | `audio/pipewire/SDL_pipewire.c`（1493 行） |
| `Platform.Pulse` | `libpulse.so.0` | `pa_threaded_mainloop_*`、`pa_context_*`、`pa_stream_*`、`pa_operation_*`、`pa_proplist_*`。約 50 関数 | `audio/pulseaudio/SDL_pulseaudio.c`（1156 行） |
| `Platform.Posix` | libc / カーネル | `poll`、`eventfd`、`timerfd`（タイマスレッドの代替候補）、`inotify_*`、`memfd_create`（wl_shm バッファ用）、`mmap`、`clock_gettime`、`sched_*`、`prctl`、`pthread_setname_np`。FPC の `BaseUnix` / `Linux` ユニットに無いものだけ宣言 | — |

### 9.5 生成器とツール

| ツール | 目的 | 対応する SDL 側 |
|---|---|---|
| `tools/wlscan-pas` | 9.2 | `wayland-scanner`（外部ツール） |
| `tools/gensyms` | 9.1 のシンボル表定義（1 行 1 シンボル: `ライブラリ, 名前, 型, 必須/任意`）から関数ポインタレコード + `dlsym` ローダを生成 | `SDL_*sym.h` + `SDL_*dyn.c` のマクロ |
| `tools/genblit` | ピクセルフォーマット組み合わせのブリッタ生成（`PaPiMeLa.Surface.Blit.Auto`） | `src/video/sdlgenblit.pl`（Perl）。**Perl を FPC に移植する**（生成ルールは単純な組み合わせ展開） |
| `tools/genscancodes` | evdev keycode → Scancode 表、xkb keysym → Scancode / Keycode 表の生成 | `src/events/scancodes_linux.h`、`SDL_keysym_to_scancode.c`、`imKStoUCS.c`（手書き表。表データを Pascal 配列にそのまま写す） |
| `tools/checkorigin` | 各ユニットの `Origin` ヘッダ行と第 11 章の由来列の整合、`移植` のユニットに SDL 告知があるかを検査（CI） | — |
| テスト基盤 | `fpcunit`。ヘッドレス実行のため `PaPiMeLa.Video.Dummy`、`PaPiMeLa.Audio.Dummy`、`PaPiMeLa.TextInput.Null` を最初から用意。Wayland のテストは `weston --backend=headless` または `sway` のヘッドレスモードで CI 実行 **[要検証: CI 環境で weston headless + text-input-v3 が動くか。IBus のテストは `ibus-daemon --panel disable` を CI で起動できるか]** | `test/` |
| ビルド | `fpmake`（FPC 標準）+ Lazarus パッケージ（`.lpk`）の両方。`fpmake` を正とし `.lpk` は生成する | CMake |

### 9.6 開発環境の前提

- FPC 3.2.2 以降、Linux x86_64（aarch64 も動くはずだが初回は x86_64 のみテスト）。
- 実行時: `libwayland-client.so.0`、`libwayland-egl.so.1`、`libwayland-cursor.so.0`、`libxkbcommon.so.0`、`libEGL.so.1`、`libGLESv2.so.2`。オプション: `libdbus-1.so.3`（IME、RealtimeKit）、`libpipewire-0.3.so.0` / `libpulse.so.0` / `libasound.so.2`（いずれか）、`libudev.so.1`。**ビルド時には C ヘッダも C コンパイラも不要**。
- 検証用: `weston` または `sway`、`ibus` + `ibus-mozc`（または `ibus-anthy`）、`fcitx5` + `fcitx5-mozc`、`dbus-monitor`、`WAYLAND_DEBUG=1`。

---

## 10. 未解決事項・要検討事項

影響の大きい順。

1. **IBus の属性 → 文節状態のマッピング規則**（7.4 の手順 3）。ibus-mozc / ibus-anthy / ibus-skk / ibus-libpinyin / ibus-hangul で `dbus-monitor` を使って実際の `IBusAttrList` を採取し、`TPMLIBusSegmenter` の規則を確定する。エンジンごとの差異が大きければエンジン名で分岐する。**Fcitx5 側は実測済み**（`spikes/RESULTS.md`）: `UpdateFormattedPreedit` の要素が文節に 1 対 1 対応し、注目文節は `HighLight (16)`、非注目文節は `Underline (8)`。IBus 経路も同じ規則（`DOUBLE` = 注目）である見込みだが未実測。
2. ~~**IBus 直結時の text-input-v3 との競合**~~ → **検証済み（`spikes/RESULTS.md`）**。labwc (wlroots) + fcitx5 で、`zwp_text_input_manager_v3` を bind せずに D-Bus 直結する構成が成立することを確認した。競合は起きない（text-input-v3 は加算的な機能であり、text_input オブジェクトを作らなければコンポジタは通常クライアントとして扱い、キーは `wl_keyboard` から届く）。**残る検証対象は GNOME (mutter) / KDE (kwin)**。mutter が IBus の唯一のクライアントであることを前提にした最適化があると成立しない可能性があるため、この 2 環境では別途確認が必要。
3. **IBus / Fcitx5 `ProcessKeyEvent` の非同期化と順序保証**（7.4、7.5）。返信待ちの間にアプリがキー状態（`Keyboard.IsDown`）を参照したときの見え方。「IME 返信待ちのキーは未押下として見せる」か「押下として見せるがイベントは遅延」か。前者を仮採用。
4. **候補ウィンドウ位置の伝達**。IBus の `SetCursorLocationRelative` は対応状況が不明（最低バージョン、コンポジタ側の実効性）。**Fcitx5 には `SetCursorRectV2(i,i,i,i,d)` があり、第 5 引数がスケール値**なので Wayland のグローバル座標問題を回避できる（introspect で確認済み）。Fcitx5 経路ではこちらを使う。使えない場合も候補ウィンドウの位置がずれるだけで機能は動く。
5. ~~**`wl_proxy_marshal_flags` の可変長引数を FPC から呼ぶ方法**~~ → **検証済み（`spikes/RESULTS.md`）**。FPC 3.2.2 の `cdecl; varargs` で直接呼べることを実証した（NULL 1 個のみのケース、および uint32 + 文字列 + uint32 + NULL の混在ケースの両方）。`wl_proxy_marshal_array_flags` による回避は不要。生成器は C の生成コードと同じ形（`marshal_flags` 直接呼び出し）を出力してよい。
6. **Wayland 読み取りスレッド**（`SDL_waylandeventthread.c` 相当）の要否。メインスレッドがブロックしているときにコンポジタからのイベントを取りこぼしてキーリピートや `ping` の応答が遅れる問題への対処。初回は無し。`Wait` ベースのアプリなら問題にならない。
7. **`spa_pod_builder` の Pascal 再実装**（9.4）。PipeWire のヘッダ内インライン関数を再実装するのはライセンス（MIT）上問題ないが、バイナリレイアウトの正確性検証が必要。難しければ初回は PulseAudio バックエンドを既定にし、PipeWire は pipewire-pulse 経由で使う（機能は同等、レイテンシは劣る）。
8. **ブリッタ生成器**（9.5）。`sdlgenblit.pl` を FPC に移植するか、Perl のまま `tools/` に置くか。ビルド時依存を FPC だけにしたいので移植を仮採用。生成された 11k 行のコンパイル時間も確認する。
9. **`TPMLEvent` のサイズと管理型フィールドのコスト**（6.2）。**サイズは実測で 72 バイト**（x86_64、管理型 3 個を含む。6.2 の予想 64〜96 の範囲内。`test/test_fcitx_textinput.pas` が毎回報告する）。残る検証は、`nil` の管理型に対する `Finalize` のコストがリングバッファ上書きで無視できることの測定。問題があれば管理型フィールドを 1 つの `TPMLEventPayload` クラス参照（nil が普通）にまとめる。
10. **`cthreads` の要求方法**（2.5）。実行時判定の確実な方法。
11. **文字列型**: `String`（`{$H+}` の `AnsiString`、UTF-8 前提）で行く。`UTF8String` との相互変換は暗黙。v1 の Windows コードページ問題は初回スコープ外だが、公開 API の型を後で変えられないので、`{$codepage utf8}` を全ユニットに付けるかを決める必要がある。付けない（Lazarus と同じ）を仮採用。
12. **`TPMLDisplay` をクラスにした**（4.2）ことによる、hotplug で消えたディスプレイの参照をアプリが保持している場合の扱い。`Connected = False` にしてオブジェクトを `TPMLVideoSystem` が次の `Pump` まで生かす（ジョイスティックと同じ）か、即時 `Free` して `DisplayRemoved` イベントには ID だけ載せるか。後者を仮採用（ジョイスティックはアプリが `Open` するので前者、ディスプレイはアプリが生成しないので後者、という区別）。
13. **レンダラ軸で初回に GLES2 だけを実装する**判断。Mesa の全ドライバが GLES2 を提供するので Linux では十分だが、`SDL_render_gles2.c` はシェーダを内蔵しており（YUV 変換含む）、シェーダソースも移植対象になる。OpenGL 3 レンダラ（`SDL_render_gl.c`）を P3 に置く。
14. **HDR / 色管理**（`SDL_waylandcolor.c`、`color-management-v1`）。P3。`TPMLDisplay.HDRProperties` の型だけ用意する。
15. **libdecor**（クライアントサイド装飾。GNOME は xdg-decoration を提供しない）。SDL は libdecor を動的ロードして使う。初回は「装飾なし（ボーダーレス相当）」で妥協し、libdecor 結合は P2 とする。ウィンドウの移動・リサイズはアプリが `xdg_toplevel.move` 相当の `TPMLWindow.BeginInteractiveMove/Resize` を呼べるようにする。
16. **ゲームパッドマッピング DB の同期**。`SDL_gamepad_db.h` は頻繁に更新される巨大な文字列表。papimela では実行時に読み込む外部ファイル（`gamecontrollerdb.txt` 互換）を第一級にし、内蔵表は最小限にする。ライセンス上は SDL の表（zlib）を同梱してよい。
17. **`TPMLThread` を `TThread` 派生にした**（4.7）ことで、`TThread` の `Synchronize` / `Queue` と papimela の `RunOnMainThread` が二重になる。`RunOnMainThread` は `TThread.Queue` に委譲せず、イベントキューに `User` 種別の内部イベントを入れて `Pump` 時に実行する（`CheckSynchronize` をアプリが呼ぶ必要をなくすため）。
18. **サテライト**（画像ローダ、フォント、ミキサ）は別プロジェクト。`TStream` 統合により `fcl-image` との接続は容易。

---

## 11. モジュール分割・由来・実装担当の一覧表

### 11.1 難易度の定義と担当モデルの対応（再実装版）

| 難易度 | 判断基準 | 担当 |
|---|---|---|
| **Low** | 目の前の C コードを Pascal へ機械的に移植する作業が中心で、設計判断が残っていない。8.7 の 4 変換（`goto`→`try/finally`、`void*`→具象型、キャスト→フィールド、`static`→フィールド）と 5.3 の `return false` 分類を適用するだけで完成する。生成器を回してコンパイルを通す作業も含む。量が多くてもよい | qwen2.5-coder:14b（ローカル） |
| **Medium** | 移植しつつ構造を整える判断が必要（複数の C ファイルを 1 クラスに再構成、所有関係の当てはめ、`TStream` 等 RTL への寄せ方）、または本書で形が決まった設計に沿った新規実装 | Claude Sonnet 5 |
| **High** | クリーンルーム設計そのもの、バックエンド抽象化の基盤、IME 経路、スレッド安全性、Wayland プロトコルの状態機械、他モジュールの土台になるもの | Claude Opus 5 |

由来: **移植** = SDL ソースを関数単位で書き換え（SDL 告知必須）／**一部移植** = 一部の関数・表・回避策を SDL から取り、構造は本書に従う（SDL 告知必須、`Scope` 行に移植した関数を列挙）／**クリーンルーム** = SDL を参考にしない、または振る舞いの理解にのみ参照（SDL 告知不要）。

優先度: **P0** = 他のすべての前提、**P1** = ウィンドウを開いて描いて日本語を入力できる最小構成、**P2** = 音声・ジョイスティック・クリップボード・ファイル、**P3** = 高度機能、**P4** = 将来。

規模: 小 < 500 行、中 500〜2000 行、大 > 2000 行（Pascal 換算の目安。移植では C の行数に近い）。

### 11.2 一覧表

| # | ユニット | 対応する SDL ソース | 規模 | 依存 | 優先度 | 由来 | 難易度 | 担当 | 注意点 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `PaPiMeLa.Errors` | （`SDL_error.c` は捨てる） | 小 | — | P0 | クリーンルーム | Medium | Sonnet | 5.2 の階層。`CreateNative` の書式、`EPMLBackendLost` の扱い |
| 2 | `PaPiMeLa.Core`、`.Core.Base` | `SDL.c`（初期化順序の知見のみ） | 中 | 1 | P0 | クリーンルーム | **High** | Opus | `TPMLContext`、`TPMLObject` / `TPMLSystemObject` / `TPMLOwnedObject`、所有グラフ（2.4）、`RunOnMainThread`、メインスレッド検査。全モジュールの土台 |
| 3 | `PaPiMeLa.Types` | `video/SDL_rect.c`、`SDL_rect_impl.h`、`SDL_guid.c` | 中 | 1 | P0 | クリーンルーム | Low | qwen | 8.3 の表どおり。矩形アルゴリズム（線分クリップ等）は移植、演算子は新規 |
| 4 | `PaPiMeLa.Unicode` | （`SDL_stdinc.h` の UTF-8 部を参考） | 小 | — | P0 | クリーンルーム | Low | qwen | `UTF8CharToByteOffset` / `UTF8ByteToCharOffset` / `UTF8Length` / 文字境界での切り詰め。IME 経路が依存。テストを厚く |
| 5 | `PaPiMeLa.Log` | `SDL_log.c` (870) | 小 | 1, 2 | P0 | 移植 | Low | qwen | カテゴリ・優先度・出力関数フック。`Context.Log` のインスタンス。stderr 出力と `journald` は不要 |
| 6 | `PaPiMeLa.Properties` | `SDL_properties.c` (855)、`SDL_hints.c` (404) | 中 | 2 | P0 | 移植 | Low | qwen | ハッシュ表は `TDictionary`。ヒントは環境変数 `PAPIMELA_*` を読む。ヒントコールバック |
| 7 | `PaPiMeLa.Atomic` | `atomic/` (573) | 小 | — | P0 | 移植 | Medium | Sonnet | FPC の `Interlocked*` へのマッピング、メモリバリア、スピンロックのバックオフ |
| 8 | `PaPiMeLa.Threading` | `thread/pthread/` (1003)、`thread/` (772)、`core/linux/SDL_threadprio.c` (345) | 中 | 1, 2, 7 | P0 | 移植 | **High** | Opus | pthread 直接使用、`TThread` 派生の `TPMLThread`、`TPMLLockGuard`（管理レコード）、RealtimeKit 経路は D-Bus（#16）完成後に追加、`cthreads` 検査 |
| 9 | `PaPiMeLa.Time` | `timer/SDL_timer.c` (795)、`timer/unix/` (180) | 小 | 2, 8 | P0 | 移植 | Medium | Sonnet | タイマースレッドと期限管理、`DelayPrecise`、`CLOCK_MONOTONIC` |
| 10 | `PaPiMeLa.Platform.DynLib`、`.Platform.Posix` | `loadso/dlopen/` (82) | 小 | 1 | P0 | クリーンルーム | Medium | Sonnet | 参照カウント付きロード、必須/任意シンボルの区別、`eventfd` / `inotify` / `memfd_create` / `poll` の宣言 |
| 11 | `tools/gensyms` | `SDL_*sym.h` / `SDL_*dyn.c` のマクロ機構 | 小 | — | P0 | クリーンルーム | Medium | Sonnet | 9.1。定義ファイル形式の設計と生成器（FPC で書く） |
| 12 | `tools/wlscan-pas` | （`wayland-scanner` 相当） | 中 | — | P0 | クリーンルーム | **High** | Opus | 9.2。`wl_interface` 定数表の生成、`wl_proxy_marshal_array_flags` 経由のリクエスト、リスナー抽象クラスとサンク束の生成。**Wayland 実装全体の前提** |
| 13 | `PaPiMeLa.Platform.Wayland.Client` | `SDL_waylandsym.h` (247)、`SDL_waylanddyn.c` (217) | 小 | 10, 11 | P0 | クリーンルーム | Low | qwen | libwayland-client / -egl / -cursor のシンボル表を `gensyms` 定義に写す |
| 14 | `PaPiMeLa.Platform.Wayland.Protocols.*`（21 ユニット） | `wayland-protocols/*.xml` | 大（生成） | 12, 13 | P0 | クリーンルーム（生成） | Low | qwen | 生成器を回し、コンパイルエラーを生成器側に差し戻す。手で生成物を直さない |
| 15 | `PaPiMeLa.Platform.XKB` | `SDL_waylandsym.h` の xkbcommon 節 | 小 | 10 | P0 | クリーンルーム | Low | qwen | 関数約 40、キーシム定数は #26 が参照する範囲 |
| 16 | `PaPiMeLa.Platform.DBus` | `core/linux/SDL_dbus.c` (2052) | 中 | 8, 10 | P1 | クリーンルーム | **High** | Opus | `TPMLDBusConnection`（watch 関数で fd をイベントループへ）、`TPMLDBusReader`（シグネチャ駆動の再帰読み取り）、例外遮断。IME 経路の土台 |
| 17 | `PaPiMeLa.Platform.EGL`、`.GLES2`、`.GL`、`.Wayland.EGL`（libwayland-egl） | `SDL_egl.h` 系、`render/opengles2/SDL_glesfuncs.h`、`render/opengl/SDL_glfuncs.h` | 中 | 10 | P0 | 一部移植 | Low | qwen | khronos ヘッダは使わない。必要な定数・関数のみ。`eglGetProcAddress` 経由。**EGL と GLES2 は実装済み**: 定数は `tools/genkhronos.bb` がヘッダから生成、関数の宣言と読み込みは qwen（GLES2 の 57 個は型の並びを機械的に突き合わせた）。`.GL`（デスクトップ GL）は未着手 |
| 18 | `PaPiMeLa.Platform.Evdev` | `core/linux/SDL_evdev_capabilities.c` (168)、Linux `input.h` | 小 | — | P2 | 一部移植 | Low | qwen | ioctl 番号を定数式で計算、`ff_effect`。`BaseUnix.FpIOCtl` |
| 19 | `PaPiMeLa.Platform.Udev` | `core/linux/SDL_udev.c` (690) | 小 | 8, 10 | P2 | 移植 | Medium | Sonnet | 監視スレッド、udev 不在時の inotify フォールバック |
| 20 | `PaPiMeLa.Platform.Alsa`、`.Platform.Pulse` | `audio/alsa/`、`audio/pulseaudio/` の冒頭シンボル表 | 中 | 10 | P2 | 一部移植 | Low | qwen | 各 50〜60 関数の宣言 |
| 21 | `PaPiMeLa.Platform.PipeWire` | `audio/pipewire/SDL_pipewire.c` の冒頭 + PipeWire `spa/` ヘッダ | 中 | 10 | P2 | 一部移植 | **High** | Opus | `spa_pod_builder` の Pascal 再実装（未解決 7）。PipeWire ヘッダ（MIT）の告知 |
| 22 | `PaPiMeLa.Events` | `events/SDL_events.c` (2090)、`SDL_eventwatch.c`、`SDL_quit.c` | 大 | 2, 7, 8, 9 | P1 | クリーンルーム | **High** | Opus | 6.2 のレコード、リングバッファ、`poll` セットの統合、`WakeUp`、`Push` のスレッド安全性、ウォッチ/フィルタ。SDL のキュー実装の回避策（センチネル、満杯時の扱い）は移植 |
| 23 | `PaPiMeLa.Events.Dispatcher` | （v1 4.2 の設計） | 中 | 22 | P1 | クリーンルーム | Medium | Sonnet | 型別リスナーの `Supports` 検出、配信中の Add/Remove、ウィンドウ別振り分け、`of object` イベント |
| 24 | `PaPiMeLa.Events.Keyboard`、`.Events.Keymap` | `events/SDL_keyboard.c` (969)、`SDL_keymap.c` (1231) | 大 | 22, 4 | P1 | 一部移植 | **High** | Opus | 状態機械は移植。**IME フィルタフック（7.5）と `TPMLDeferredKeyQueue` は新規**。フォーカス喪失時の全キー解放。**実装済み（Pong の F-1〜F-3）**: `.Events.Keymap` は独立したユニット、押下状態（`IsDown`）と全キー解放は `TPMLKeyboardState` として `PaPiMeLa.Events` に置いた（`.Events.Keyboard` は作らなかった）。キーマップは「修飾なし」と「Shift」の 2 段のみ |
| 25 | `PaPiMeLa.Events.Mouse`、`.Events.Touch` | `events/SDL_mouse.c` (1991)、`SDL_touch.c` (635) | 大 | 22 | P1 | 移植 | Medium | Sonnet | 相対モード、クリック回数、二重押下抑制、`TPMLCursorBackend` との境界 |
| 26 | `PaPiMeLa.Keycodes`、`.Keycodes.Tables`（`tools/genscancodes.bb` が生成） | `events/scancodes_linux.h`、`SDL_keysym_to_scancode.c` (439)、`imKStoUCS.c` (349)、`SDL_scancode_tables.c` | 中 | — | P1 | 移植 | Low | qwen | 表データを Pascal 配列へ。**手でも qwen でも写さず、生成器が SDL のソースから抜き出す**（件数を元と突き合わせる）。`imKStoUCS.c` の範囲判定に上流の不具合があり（D-36）、生成器が警告する |
| 27 | `PaPiMeLa.Pixels` | `video/SDL_pixels.c` (1711) | 中 | 3 | P1 | 移植 | Low | qwen | フォーマット詳細、パレット、色空間、`MapRGBA` |
| 28 | `PaPiMeLa.Surface`、`.Surface.BMP` | `video/SDL_surface.c` (3169)、`SDL_bmp.c` (945) | 大 | 27, 64 | P1 | 移植 | Medium | Sonnet | `IPMLSurface` 共有 opt-in、`TStream` での BMP 入出力、Blit 系のオーバーロード整理 |
| 29 | `PaPiMeLa.Surface.Blit`（手書きブリッタ群） | `SDL_blit.c`、`SDL_blit_0/1/A/N/slow/copy.c`（計約 8000）、`SDL_RLEaccel.c` (1395)、`SDL_stretch.c` (950)、`SDL_rotate.c` (605)、`SDL_fillrect.c` (437) | 大 | 27 | P1 | 移植 | Low | qwen | **スカラー版のみ**。SIMD `#ifdef` は落とす。マクロ展開（`DUFFS_LOOP` 等）は素直なループに |
| 30 | `tools/genblit` + `PaPiMeLa.Surface.Blit.Auto` | `sdlgenblit.pl` → `SDL_blit_auto.c` (11542) | 大（生成） | 27 | P1 | 移植 | Medium | Sonnet | Perl 生成器を FPC に移植。生成物のコンパイル時間を確認（未解決 8） |
| 31 | `PaPiMeLa.Video.Backend` | `video/SDL_sysvideo.h` (623)（分解元） | 中 | 2, 3, 22 | P1 | クリーンルーム | **High** | Opus | 3.2 の抽象クラス群、能力集合、`TPMLNativeWindowHandles`。**他の全ビデオモジュールの土台** |
| 32 | `PaPiMeLa.Video`（公開 API）、`.Clipboard` | `video/SDL_video.c` (6592)、`SDL_clipboard.c` (487) | 大 | 31, 22, 23 | P1 | クリーンルーム | **High** | Opus | `TPMLVideoSystem` / `TPMLDisplay` / `TPMLWindow`。フルスクリーン・表示モードの状態遷移、ウィンドウフラグの整合性検査、親子ウィンドウは SDL から移植。`_this` 参照 456 箇所を所有グラフに置き換える |
| 33 | `PaPiMeLa.Video.EGL` | `video/SDL_egl.c` (1426) | 中 | 17, 31 | P1 | 移植 | Medium | Sonnet | `TPMLEGLBackend` 基底。プラットフォーム固有 4 メソッドを抽象に。コンフィグ選択の回避策を継承。**実装済み（Sonnet、受け入れ検査 T-21）**。Mesa の eglGetProcAddress は無い名前にも番地を返すので、コア関数は libGLESv2 から引く |
| 34 | `PaPiMeLa.Video.Dummy` | `video/dummy/` (414) | 小 | 31 | P1 | クリーンルーム | Low | qwen | ヘッドレステスト用。#31 の最初の実装例として先に書く |
| 35 | `PaPiMeLa.Video.Wayland`（接続・レジストリ・出力）、`.Wayland.Types` | `SDL_waylandvideo.c` (2083)、`SDL_waylandutil.c` | 大 | 13, 14, 31 | P1 | 一部移植 | **High** | Opus | グローバル束縛と能力集合への写像、`wl_output` / `xdg_output` / `fractional-scale` → `TPMLDisplayBackend`、`IPMLWaylandSeatProvider` 実装、`PumpEvents` / `poll` 統合、`FPendingException` |
| 36 | `PaPiMeLa.Video.Wayland.Window` | `SDL_waylandwindow.c` (3931) | 大 | 35 | P1 | 一部移植 | **High** | Opus | xdg-shell の `configure` / `ack_configure` 状態機械、フルスクリーン・最大化の往復、viewporter によるスケーリング、xdg-activation、ポップアップ。回避策は移植、構造は `TPMLWindowBackend` に合わせる |
| 37 | `PaPiMeLa.Video.Wayland.Seat`、`.Wayland.PointerGrab`、`.Wayland.Cursor` | `SDL_waylandevents.c` (3917、`text_input_*` を除く)、`SDL_waylandkeyboard.c` (280)、`SDL_waylandmouse.c` (1530) | 大 | 35, 15, 24, 25, 26 | P1 | 一部移植 | **High** | Opus | `wl_keyboard` / `wl_pointer` / `wl_touch`、xkb 状態、キーリピートタイマ、pointer-constraints / relative-pointer / cursor-shape、`TPMLCursorBackend` 実装。**text-input-v3 は含めない**（#49 へ） |
| 38 | `PaPiMeLa.Video.Wayland.Data` | `SDL_waylanddatamanager.c` (847)、`SDL_waylandclipboard.c` (217) | 中 | 35 | P2 | 移植 | Medium | Sonnet | `TPMLClipboardBackend` 実装、primary selection、D&D 受信（パイプ読み取り） |
| 39 | `PaPiMeLa.Video.Wayland.EGL`、`.Wayland.Shm` | `SDL_waylandopengles.c` (228)、`SDL_waylandshmbuffer.c` (214) | 小 | 33, 35 | P1 | 一部移植 | Medium | Sonnet | `TPMLEGLBackend` 派生 4 メソッド、`wl_shm` バッファプール（カーソル・ソフトウェアレンダラの表示用）。**`.Wayland.EGL` も実装済み（Sonnet、T-21）**。VSync は SDL と同じく eglSwapInterval(0) にしてフレームコールバックで自前で待つ（ソフトウェアの表示と同じ仕組みを使う）。**`.Wayland.Shm` は先行して実装済み**（ウィンドウへ描くレンダラと一体の変更だったため Opus が担当）。SDL は `wl_buffer.release` を無視するが、papimela は毎フレーム書き換えるので release を追跡する。そのため由来は「一部移植」 |
| 40 | `PaPiMeLa.Video.Wayland.MessageBox` | `SDL_waylandmessagebox.c` (42)、`dialog/unix/SDL_zenitymessagebox.c` | 小 | 35 | P3 | 移植 | Low | qwen | zenity 子プロセス。`TProcess`（FCL）を使う |
| 41 | `PaPiMeLa.Render`（公開 API とドライバの抽象。設計時の `.Render.Backend` はここへ統合） | `render/SDL_render.c` (6372)、`SDL_sysrender.h` | 大 | 32, 28 | P1 | 移植 | **High** | Opus | `TPMLRenderDriver`（35 メソッド）、コマンドキューとバッチ、論理プレゼンテーション、`TPMLTexture` 所有。全レンダラドライバの土台 |
| 42 | `PaPiMeLa.Render.Software`、`.Render.Software.Raster` | `render/software/` (5175)、`SDL_yuv_sw.c` (486) | 大 | 41, 29 | P1 | 移植 | Low | qwen | 三角形ラスタライザ、回転ブリット。#41 の最初のドライバ実装例 |
| 43 | `PaPiMeLa.Render.GLES2` | `render/opengles2/` (3256) | 大 | 41, 33, 17 | P1 | 移植 | Medium | Sonnet | シェーダソース（GLSL ES）を Pascal 文字列定数に、YUV シェーダ、シェーダキャッシュ、コンテキスト喪失。**実装済み（Sonnet、受け入れ検査 T-22）**: 矩形と転送は上書きせず三角形の既定の経路（SDL と同じ）。窓の無い GL（Mesa surfaceless）のオフスクリーンでも描け、CI では llvmpipe で比べる。線の端の延ばし量（SDL の 1/4 → 0.75 画素）とテクセルの境目の寄せは、ソフトウェアのドライバと画素を揃えるための実測に基づく逸脱。YUV・パレット・描画先テクスチャ・コンテキスト喪失は未実装 |
| 44 | `PaPiMeLa.Render.GL` | `render/opengl/` (3401) | 大 | 41, 33, 17 | P3 | 移植 | Low | qwen | #43 を手本に。OpenGL 2.1 / 3.x コア |
| 45 | `PaPiMeLa.App`、`PaPiMeLa.Backends`、`PaPiMeLa`（アンブレラ） | `main/` (234) | 小 | 全部 | P1 | クリーンルーム | Medium | Sonnet | 6.5 の `TPMLApplication`、バックエンド登録、型エイリアス再エクスポート |
| 46 | `PaPiMeLa.TextInput`（公開モデル、`TPMLTextInputSystem`、`TPMLTextInputSession`、バックエンド選択） | — | 中 | 2, 4, 22, 24 | P1 | クリーンルーム | **High** | Opus | 7.3 / 7.6。`IPMLTextInputClient` の呼び出しタイミング、周辺削除→確定の順序保証、`IPMLFocusObserver`。**本プロジェクトの中核** |
| 47 | `PaPiMeLa.TextInput.Backend`、`.TextInput.Null` | — | 小 | 46 | P1 | クリーンルーム | **High** | Opus | 3.6 の抽象クラス、`IPMLTextInputSink`、能力集合。#46 と同一担当で同時に設計する |
| 48 | `PaPiMeLa.TextInput.IBus` | （`core/linux/SDL_ibus.c` (743) は接続手順の参考のみ。バグあり: 115 行目） | 大 | 16, 46, 47 | P1 | クリーンルーム | **High** | Opus | 7.4。アドレス解決と inotify 追従、`IBusText` の完全解析、`TPMLIBusSegmenter`、非同期 `ProcessKeyEvent`、`SetSurroundingText` / `DeleteSurroundingText`、`SetCursorLocationRelative`、埋め込み候補。**未解決 1〜4 の実機検証を伴う** |
| 49 | `PaPiMeLa.TextInput.WaylandTI` | （`SDL_waylandevents.c` の `text_input_*` は参考のみ） | 中 | 14, 46, 47, `Video.Wayland.Types` | P1 | クリーンルーム | **High** | Opus | 7.7。`done` での一括適用順序、`set_surrounding_text` の 4000 バイト切り詰め、`enter` / `leave` によるウィンドウ判定。IBus 直結時は `enable` を送らない |
| 50 | `PaPiMeLa.TextInput.Fcitx` | （`core/linux/SDL_fcitx.c` (441) は参考のみ） | 中 | 16, 46, 47 | P2 | クリーンルーム | Medium | Sonnet | 7.8。#48 を手本に。`UpdateFormattedPreedit` のフラグ → 文節状態 |
| 51 | `PaPiMeLa.Audio.Backend`、`PaPiMeLa.Audio`（公開 API） | `audio/SDL_audio.c` (2765)、`SDL_sysaudio.h`、`SDL_audiodev.c` | 大 | 2, 8, 22, 53 | P2 | 移植 | **High** | Opus | 物理/論理デバイス、デバイススレッド、bind、ロック順序、破棄とコールバックの競合、hotplug イベント。全オーディオバックエンドの土台 |
| 52 | `PaPiMeLa.Audio.Convert` | `SDL_audiocvt.c` (1590)、`SDL_audiotypecvt.c` (986)、`SDL_audioresample.c` (706) | 大 | 3 | P2 | 移植 | Low | qwen | スカラー版のみ。リサンプラの係数表はそのまま |
| 53 | `PaPiMeLa.Audio.Queue`、`.Audio.Mixer` | `SDL_audioqueue.c` (652)、`SDL_mixer.c` (290) | 中 | 8 | P2 | 移植 | Medium | Sonnet | 可変長トラックのキュー、`TPMLRingBuffer<T>` の適用判断 |
| 54 | `PaPiMeLa.Audio.Wave` | `SDL_wave.c` (2163) | 大 | 64 | P2 | 移植 | Low | qwen | ADPCM / IEEE float / 拡張ヘッダの解析。`TStream` 入力 |
| 55 | `PaPiMeLa.Audio.Dummy` | `audio/dummy/` (166) | 小 | 51 | P2 | 移植 | Low | qwen | テスト用。#51 の最初の実装例 |
| 56 | `PaPiMeLa.Audio.PipeWire` | `audio/pipewire/` (1493) | 中 | 51, 21 | P2 | 移植 | **High** | Opus | `pw_thread_loop` とデバイススレッドの関係、hotplug、`spa_pod` 組み立て |
| 57 | `PaPiMeLa.Audio.Pulse` | `audio/pulseaudio/` (1156) | 中 | 51, 20 | P2 | 移植 | Medium | Sonnet | `pa_threaded_mainloop` のロック規約、hotplug 購読 |
| 58 | `PaPiMeLa.Audio.Alsa` | `audio/alsa/` (1708) | 中 | 51, 20 | P2 | 移植 | Medium | Sonnet | `snd_pcm_recover`、デバイス名ヒント列挙、hotplug スレッド |
| 59 | `PaPiMeLa.Joystick.Backend`、`PaPiMeLa.Joystick`（公開 API） | `joystick/SDL_joystick.c` (4363)、`SDL_sysjoystick.h` | 大 | 2, 22 | P2 | 移植 | Medium | Sonnet | 21 メソッドの抽象、ID 管理、`Connected` の寿命規約、電源情報、複数バックエンド同時 |
| 60 | `PaPiMeLa.Joystick.Linux` | `joystick/linux/` (2965)、`core/linux/SDL_evdev.c` の関連部 | 大 | 59, 18, 19 | P2 | 移植 | Medium | Sonnet | evdev 軸の正規化、udev / inotify 列挙、Steam 仮想ゲームパッドの除外、`FF` ランブル |
| 61 | `PaPiMeLa.Joystick.Virtual` | `joystick/virtual/` (1074) | 中 | 59 | P3 | 移植 | Low | qwen | — |
| 62 | `PaPiMeLa.Gamepad` | `joystick/SDL_gamepad.c` (4448)、`controller_type.c`、`SDL_gamepad_db.h` | 大 | 59 | P2 | 移植 | Medium | Sonnet | マッピング文字列パーサ、外部 DB ファイル第一級（未解決 16）、方角ボタンとラベル |
| 63 | `PaPiMeLa.Haptic`、`.Haptic.Linux` | `haptic/` (1122)、`haptic/linux/` (1133) | 中 | 59, 18 | P3 | 移植 | Low | qwen | `ff_effect` への変換表 |
| 64 | `PaPiMeLa.IO` | `io/SDL_iostream.c` (2499) の fd / stdio 実装部 | 小 | 1 | P1 | 一部移植 | Medium | Sonnet | `TStream` 第一級。`TPMLFileStream` の `EINTR` 再試行・分割読み書き、型付き読み書き、`LoadFile` |
| 65 | `PaPiMeLa.FileSystem` | `filesystem/unix/` (664)、`filesystem/SDL_filesystem.c` | 小 | 1 | P2 | 移植 | Low | qwen | XDG user-dirs の解析、`/proc/self/exe`、glob |
| 66 | `PaPiMeLa.Video.Wayland.Tablet`、`.Events.Pen` | `SDL_waylandevents.c` の tablet 部、`events/SDL_pen.c` (726) | 中 | 37 | P3 | 移植 | Medium | Sonnet | tablet-v2 プロトコル、ペン軸 |
| 67 | `PaPiMeLa.Video.Wayland.Vulkan`、`PaPiMeLa.Render.Vulkan` | `SDL_waylandvulkan.c` (207)、`SDL_vulkan_utils.c` (487)、`render/vulkan/` (6646) | 大 | 36, 41 | P3 | 移植 | **High** | Opus | Vulkan 型の宣言を papimela が持つか外部バインディングに委ねるかの判断、スワップチェーン再生成 |
| 68 | `PaPiMeLa.Surface.YUV` | `video/SDL_yuv.c` (2739) | 大 | 27 | P3 | 移植 | Low | qwen | スカラー版のみ |
| 69 | `PaPiMeLa.Video.Wayland.LibDecor` | `SDL_waylandwindow.c` の libdecor 部、`SDL_waylandsym.h` の libdecor 節 | 中 | 36 | P2 | 一部移植 | Medium | Sonnet | クライアントサイド装飾。GNOME で必要（未解決 15） |
| 70 | `tools/checkorigin`、テスト基盤（fpcunit、headless 実行スクリプト） | — | 小 | — | P0 | クリーンルーム | Medium | Sonnet | 9.5。`Origin` 行と本表の整合検査、weston headless / ibus-daemon の CI 起動 |

### 11.3 内訳サマリ

| 難易度 | 数 | 担当 | 該当 # |
|---|---|---|---|
| Low | 24 | qwen2.5-coder:14b | 3, 4, 5, 6, 13, 14, 15, 17, 18, 20, 26, 27, 29, 34, 40, 42, 44, 52, 54, 55, 61, 63, 65, 68 |
| Medium | 26 | Claude Sonnet 5 | 1, 7, 9, 10, 11, 19, 23, 25, 28, 30, 33, 38, 39, 43, 45, 50, 53, 57, 58, 59, 60, 62, 64, 66, 69, 70 |
| High | 20 | Claude Opus 5 | 2, 8, 12, 16, 21, 22, 24, 31, 32, 35, 36, 37, 41, 46, 47, 48, 49, 51, 56, 67 |

| 由来 | 数 | 該当 # | SDL 告知 |
|---|---|---|---|
| 移植 | 38 | 5, 6, 7, 8, 9, 19, 25, 26, 27, 28, 29, 30, 33, 34, 38, 39, 40, 41, 42, 43, 44, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 65, 66, 67, 68 | 必須 |
| 一部移植 | 17 | 3, 10, 13, 15, 16, 17, 18, 20, 21, 22, 24, 32, 35, 36, 37, 64, 69 | 必須（`Scope` 行に移植関数を列挙） |
| クリーンルーム | 15 | 1, 2, 4, 11, 12, 14, 23, 31, 45, 46, 47, 48, 49, 50, 70 | 不要（`Origin: original work`） |

（合計 70 行。#14 は 21 ユニットの生成物をまとめて 1 行にしている。ユニット数としては約 95。）

### 11.4 推奨実装順序

```
フェーズ 0（基盤。並列可）:
    #1 Errors → #2 Core → #4 Unicode → #3 Types → #5 Log → #6 Properties → #7 Atomic → #8 Threading → #9 Time
    → #10 DynLib/Posix → #11 gensyms → #70 checkorigin/テスト基盤
    マイルストーン: fpcunit が回り、Context を生成・破棄できる

フェーズ 1（プラットフォーム結合）:
    #12 wlscan-pas → #13 Wayland.Client → #14 Protocols（生成）→ #15 XKB → #17 EGL/GLES2 → #26 スキャンコード表
    マイルストーン: wl_display_connect してレジストリのグローバルを列挙するサンプルが動く

フェーズ 2（ウィンドウと描画）:
    #22 Events → #23 Dispatcher → #24 Keyboard → #25 Mouse/Touch
    → #31 Video.Backend → #34 Video.Dummy → #32 Video → #64 IO → #27 Pixels → #28 Surface → #29 Blit → #30 genblit
    → #33 Video.EGL → #35 Wayland → #36 Wayland.Window → #37 Wayland.Seat → #39 Wayland.EGL/Shm
    → #41 Render → #42 Render.Software → #43 Render.GLES2 → #45 App/Backends/アンブレラ
    マイルストーン: Wayland でウィンドウを開き、GLES2 で三角形を描き、キー・マウスイベントを受ける

フェーズ 3（IME。中核）:
    #16 DBus → #46 TextInput → #47 TextInput.Backend/Null → #48 IBus → #49 WaylandTI → #50 Fcitx → #38 Wayland.Data（クリップボード）
    マイルストーン: テキストエディタのサンプルで ibus-mozc の文節下線・注目文節・再変換（周辺削除）が動く。
                    PAPIMELA_IME=wayland で text-input-v3 にフォールバックして単一範囲で動く

フェーズ 4（音声・ジョイスティック・ファイル）:
    #53 Audio.Queue → #52 Audio.Convert → #54 Wave → #51 Audio → #55 Audio.Dummy → #20 Alsa/Pulse 定義 → #57 Pulse → #58 Alsa
    → #21 PipeWire 定義 → #56 Audio.PipeWire
    → #18 Evdev → #19 Udev → #59 Joystick → #60 Joystick.Linux → #62 Gamepad → #65 FileSystem → #69 LibDecor
    マイルストーン: WAV 再生、ゲームパッド入力、GNOME でのウィンドウ装飾

フェーズ 5（P3）:
    #44 Render.GL → #40 MessageBox → #61 Joystick.Virtual → #63 Haptic → #66 Tablet/Pen → #68 YUV → #67 Vulkan
```

運用上の注意:

- **Low モジュールは、依存先が完成し、かつ同じ形の Medium / High モジュールが 1 つ実装済みでお手本になる状態になってから着手させる**。具体的な手本の対応: #34 Dummy → #35 Wayland の前ではなく後（Dummy は Opus が #31 の検証用に先に書く）、#42 Software は #41 と同時に Opus が骨格を作りドライバ本体を qwen に渡す、#44 GL は #43 GLES2 を手本、#55 Audio.Dummy は #51 の検証用、#29 Blit は #28 Surface の完成後、#52 Convert は #3 Types のスタイルを手本。
- **各 Low モジュールには着手前に本書の 5.3（`return false` の分類）、8.7（移植の 4 変換と `PORT-NOTE`）、1.4（ヘッダ書式）、および該当行を必読として渡す**。
- **High モジュール #46〜#49（IME）は同一担当が連続して行う**。設計判断が相互に依存する（文節状態の規則、非同期キーの順序保証、フォールバック条件）。
- **移植モジュールのレビューでは「振る舞いが同じか」ではなく「元コードが正しいか」を問う**（1.2）。疑わしい箇所は `PORT-NOTE(bug)` として `docs/UPSTREAM-NOTES.md` に集約する。

---

## 付録 A. v1 からの引き継ぎ対応表

| v1 の章 | 扱い | 本書での位置 |
|---|---|---|
| 0 用語 / SDL2→3 変更点 | 破棄（バインディング前提） | 0 章を再定義 |
| 1.1 二層構造、1.4 リンク方式 | **破棄** | 2.1 の層構造に置き換え |
| 1.2 コンパイラモード | 引き継ぎ・拡張 | 2.5 |
| 1.3 ユニット構成 | 再設計（名前空間の考え方は継承） | 2.2、11.2 |
| 2.1 `TSDLObject` / `TSDLHandleObject<T>` / `OwnsHandle`、2.2 逆引き | **破棄** | 4.1 の最小基底に置き換え |
| 2.3 参照カウント方針 | 引き継ぎ | 4.1、8.4 |
| 2.4 クラス一覧 | 再設計（クラス名・API の多くは継承） | 4.2〜4.7 |
| 2.5 Properties | 引き継ぎ（移植対象に） | 11.2 #6 |
| 2.6 文字列・メモリ規約 | 引き継ぎ（`SDL_free` の問題は消滅） | 8.2 単位規則、未解決 11 |
| 2.7 初期化 | **破棄**（静的クラス `TSDL`） | 2.4 の `TPMLContext` |
| 3 エラー処理 | 引き継ぎ・拡張 | 5 章 |
| 4 イベントシステム | 引き継ぎ（レコード設計は変更） | 6 章 |
| 5 OOP 機能 | 引き継ぎ・調整 | 8 章 |
| 6 命名規則 | 引き継ぎ（接頭辞変更） | 8.2 |
| 7 未解決事項 | 大半が消滅（C 層調達、リンク方式、共用体レイアウト等）。文字列型・匿名メソッド・テスト戦略は継承 | 10 章 |
| 8 一覧表 | 再作成（由来列を追加、難易度基準を変更） | 11 章 |

