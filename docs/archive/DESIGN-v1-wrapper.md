# papimela 設計ドキュメント — SDL3 用 Free Pascal オブジェクト指向バインディング

- 対象: SDL 3.2.x 系の安定 API を基準とする（3.4 / 3.6 で追加された API は「オプション」扱いとし、本文中に **[要検証]** を付す）
- 対象コンパイラ: Free Pascal 3.2.2 以降（3.3.x trunk の機能には依存しない）
- 文書の性格: 実装前の設計方針を固めるためのもの。実装コードは含まず、骨格程度のスニペットのみ示す
- 本文書の最終セクション（第 8 章）は、後続の実装担当（qwen2.5-coder:14b / Claude Sonnet 5 / Claude Opus 5）への振り分け一覧表になっている

> 情報源について: 本文書の SDL3 API に関する記述は、libsdl-org/SDL の `include/SDL3/` ヘッダ一覧、SDL3 wiki の README-migration、CategoryGPU / CategoryAudio / CategoryAsyncIO、README-main-functions、および `SDL_properties.h` / `SDL_events.h` / `SDL_notification.h` の内容を 2026-09 時点で確認して書いている。確認できなかった細部（構造体フィールド名、引数順など）は **[要検証]** と明記した。

---

## 0. 用語と前提

| 用語 | 意味 |
|---|---|
| C バインディング層 | SDL3 の C 関数・構造体・列挙をそのまま Pascal に translate したユニット群。`SDL3.Api.*` と呼ぶ |
| OOP ラッパー層 | C バインディング層の上に被せる Object Pascal のクラス群。プロジェクト名 **papimela**、ユニット接頭辞 `PaPiMeLa.*` |
| ハンドル | SDL が返す不透明ポインタ（`SDL_Window*` 等）または整数 ID（`SDL_WindowID`、`SDL_JoystickID` 等） |
| 所有 (owned) | ラッパーオブジェクトが破棄時に対応する `SDL_Destroy*` / `SDL_Close*` / `SDL_Release*` を呼ぶ責任を持つこと |
| 借用 (borrowed) | ラッパーがハンドルを参照するだけで、破棄責任を持たないこと |

SDL2 → SDL3 の主要な破壊的変更のうち、本設計に直接影響するものを先に列挙する（README-migration に基づく）:

1. **戻り値が `bool` に統一**: 従来「負の値でエラー」だった関数が `true`/`false` を返す。ラッパーのエラー検査はここに一本化できる。
2. **プロパティシステム (`SDL_PropertiesID`)** の導入: `SDL_CreateWindowWithProperties`、`SDL_GetTextureProperties` 等。`SDL_QueryTexture` は廃止されプロパティ照会に置き換わった。
3. **オーディオのストリーム化**: コールバック中心のモデルから「`SDL_AudioStream` をデバイスにバインドする」モデルへ。論理デバイス/物理デバイスの分離。
4. **GPU API の新設** (`SDL_gpu.h`): Vulkan/D3D12/Metal を抽象化したモダン API。
5. **ゲームパッドの再編**: `SDL_GameController*` → `SDL_Gamepad*`、ボタンは方角名 (South/East/West/North)。デバイス列挙はインデックスではなく ID 配列 (`SDL_GetJoysticks()`、`SDL_GetGamepads()`)。
6. **メインコールバック** (`SDL_AppInit` / `SDL_AppIterate` / `SDL_AppEvent` / `SDL_AppQuit`) の追加。
7. **イベント型のフラット化**: `SDL_WINDOWEVENT` コンテナが廃止され、`SDL_EVENT_WINDOW_*` が直接トップレベルに並ぶ。タイムスタンプはナノ秒。
8. **`SDL_RWops` → `SDL_IOStream`**: `SDL_ReadIO` はバイト数を返す。カスタム実装は `SDL_IOStreamInterface` 構造体で行う。
9. **新規サブシステム**: Camera、Storage、AsyncIO、Dialog、Tray、Process、Pen、（3.6 で）Notification **[要検証]**。
10. Gesture API は本体から削除（別ライブラリ化）、`SDL_bool` は C の `bool` に。

---

## 1. 全体アーキテクチャ方針

### 1.1 二層構造

```
┌──────────────────────────────────────────────────────────────┐
│ アプリケーション (ユーザーコード)                              │
├──────────────────────────────────────────────────────────────┤
│ OOP ラッパー層  PaPiMeLa.*                                    │
│   TSDLWindow, TSDLRenderer, TSDLTexture, TSDLGPUDevice, ...  │
│   ESDLError 例外階層 / イベントディスパッチャ / 幾何レコード   │
├──────────────────────────────────────────────────────────────┤
│ C バインディング層  SDL3.Api.*                                │
│   SDL_CreateWindow, SDL_Event, SDL_FRect, ... (素直な translate) │
├──────────────────────────────────────────────────────────────┤
│ libSDL3.so / SDL3.dll / libSDL3.dylib                        │
└──────────────────────────────────────────────────────────────┘
```

- **C バインディング層 (`SDL3.Api.*`)** は SDL3 のヘッダ 1 本につき原則 1 ユニット。関数は `cdecl; external` で宣言し、名前・引数順・型は C と同一に保つ。ここには一切のロジックを置かない（インライン関数・マクロの再現のみ許容）。
- **OOP ラッパー層 (`PaPiMeLa.*`)** は C バインディング層のみに依存し、libSDL3 を直接 `external` 参照しない。逆に C バインディング層は OOP 層を一切参照しない。
- ユーザーは OOP 層だけを `uses` するのが基本。ただし OOP 層が未対応の関数へ「エスケープハッチ」として C 層を併用できるよう、すべてのラッパーオブジェクトは `Handle` プロパティで生ハンドルを公開する。

C バインディング層については、既存のコミュニティ製バインディング（例: PascalGameDevelopment の SDL3-for-Pascal）を採用する選択肢もある。本文書では **C 層の内部設計には踏み込まず**、「`SDL3.Api.*` という名前空間で、ヘッダ対応のユニットが存在する」ことだけを前提として OOP 層の設計に集中する（採用判断は第 7 章の未解決事項に記載）。

### 1.2 コンパイラモードと言語機能

ライブラリ本体のすべてのユニットは以下を先頭に置く:

```pascal
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$interfaces corba}   // 既定インターフェースを非参照カウントにする（後述 5.4）
{$scopedenums on}     // 列挙型はスコープ付き（TSDLWindowFlag.Resizable など）
```

- `objfpc` モードを採用する理由: FPC 標準ライブラリ（FCL/RTL）との整合性、`specialize` による明示的なジェネリクス具体化で可読性が高い。ユーザーコードは `delphi` モードでも利用できることを保証する（`specialize` を要求する API を public に露出しない設計とする）。
- 演算子オーバーロードと `advancedrecords`（レコード内メソッド・プロパティ）を幾何・色型で多用する。
- `{$interfaces corba}` により、リスナー系インターフェースが参照カウントに巻き込まれて意図せずオブジェクトを破棄する事故を防ぐ。参照カウントが必要な箇所だけ明示的に `IInterface` 継承（COM 型）を使う。

### 1.3 ユニット構成（名前空間的分割）

FPC はドット付きユニット名をサポートするので、`PaPiMeLa.<Subsystem>` を採用する。

| ユニット | 役割 | 主に対応する SDL3 ヘッダ |
|---|---|---|
| `PaPiMeLa` | アンブレラユニット。主要ユニットを再エクスポート（型エイリアス）し、`uses PaPiMeLa;` 一行で使えるようにする | — |
| `PaPiMeLa.Core` | `TSDLObject` 基底、`TSDLSubsystems` 初期化管理、バージョン、メモリ/文字列ヘルパ | SDL_init.h, SDL_version.h, SDL_stdinc.h(一部) |
| `PaPiMeLa.Errors` | `ESDLError` 例外階層、`SDLCheck` ヘルパ | SDL_error.h |
| `PaPiMeLa.Types` | `TSDLPoint`/`TSDLFPoint`/`TSDLRect`/`TSDLFRect`/`TSDLColor`/`TSDLFColor`/`TSDLGUID` と演算子 | SDL_rect.h, SDL_pixels.h(色), SDL_guid.h |
| `PaPiMeLa.Properties` | `TSDLProperties` | SDL_properties.h |
| `PaPiMeLa.Hints` | `TSDLHints` 静的クラス、ヒントコールバック | SDL_hints.h |
| `PaPiMeLa.Log` | `TSDLLog`、カテゴリ、出力関数のフック | SDL_log.h |
| `PaPiMeLa.Time` | `TSDLTimer`、時刻/日時変換、`SDL_Delay*` | SDL_timer.h, SDL_time.h |
| `PaPiMeLa.Pixels` | ピクセルフォーマット詳細、`TSDLPalette`、色空間 | SDL_pixels.h |
| `PaPiMeLa.Surface` | `TSDLSurface`、ブレンド、BMP 入出力 | SDL_surface.h, SDL_blendmode.h |
| `PaPiMeLa.Video` | `TSDLWindow`、`TSDLDisplay`、`TSDLDisplayMode`、OpenGL/EGL コンテキスト、`TSDLWindowBuilder` | SDL_video.h |
| `PaPiMeLa.Render` | `TSDLRenderer`、`TSDLTexture`、頂点描画、デバッグテキスト | SDL_render.h |
| `PaPiMeLa.GPU` | `TSDLGPUDevice` とリソース群、コマンドバッファ・パス | SDL_gpu.h |
| `PaPiMeLa.Audio` | `TSDLAudioDevice`、`TSDLAudioStream`、`TSDLAudioSpec`、WAV 読み込み | SDL_audio.h |
| `PaPiMeLa.Events` | `TSDLEvent`（レコード）、`TSDLEventQueue`、`TSDLEventDispatcher`、リスナーインターフェース | SDL_events.h |
| `PaPiMeLa.Input.Keyboard` | キーボード状態、スキャンコード/キーコード、テキスト入力 | SDL_keyboard.h, SDL_keycode.h, SDL_scancode.h |
| `PaPiMeLa.Input.Mouse` | マウス状態、`TSDLCursor` | SDL_mouse.h |
| `PaPiMeLa.Input.Touch` | タッチデバイス、指の列挙 | SDL_touch.h |
| `PaPiMeLa.Input.Pen` | ペン軸・型定義（イベント中心のため小さい） | SDL_pen.h |
| `PaPiMeLa.Joystick` | `TSDLJoystick`、仮想ジョイスティック | SDL_joystick.h |
| `PaPiMeLa.Gamepad` | `TSDLGamepad`、マッピング文字列 | SDL_gamepad.h |
| `PaPiMeLa.Haptic` | `TSDLHaptic`、エフェクト | SDL_haptic.h |
| `PaPiMeLa.Sensor` | `TSDLSensor` | SDL_sensor.h |
| `PaPiMeLa.Camera` | `TSDLCamera`、フォーマット列挙 | SDL_camera.h |
| `PaPiMeLa.IO` | `TSDLIOStream`、`TStream` との相互アダプタ | SDL_iostream.h |
| `PaPiMeLa.AsyncIO` | `TSDLAsyncIO`、`TSDLAsyncIOQueue`、結果レコード | SDL_asyncio.h |
| `PaPiMeLa.Storage` | `TSDLStorage`（Title/User/File ストレージ） | SDL_storage.h |
| `PaPiMeLa.FileSystem` | パス取得、ディレクトリ列挙、glob、`TSDLPathInfo` | SDL_filesystem.h |
| `PaPiMeLa.Threading` | `TSDLThread`、`TSDLMutex`、`TSDLRWLock`、`TSDLSemaphore`、`TSDLCondition`、`TSDLInitState`、TLS | SDL_thread.h, SDL_mutex.h |
| `PaPiMeLa.Atomic` | `TSDLAtomicInt`、`TSDLAtomicU32`、`TSDLSpinLock`、アトミックポインタ | SDL_atomic.h |
| `PaPiMeLa.Dialog` | ファイルダイアログ（非同期コールバック） | SDL_dialog.h |
| `PaPiMeLa.MessageBox` | `TSDLMessageBox` ビルダ、簡易表示 | SDL_messagebox.h |
| `PaPiMeLa.Tray` | `TSDLTray`、`TSDLTrayMenu`、`TSDLTrayEntry` | SDL_tray.h |
| `PaPiMeLa.Process` | `TSDLProcess`、標準入出力のリダイレクト | SDL_process.h |
| `PaPiMeLa.System` | 電源、ロケール、クリップボード、CPU 情報、プラットフォーム、URL オープン、`SDL_system.h` のプラットフォーム固有 API | SDL_power.h, SDL_locale.h, SDL_clipboard.h, SDL_cpuinfo.h, SDL_platform.h, SDL_misc.h, SDL_system.h |
| `PaPiMeLa.LoadSO` | `TSDLSharedObject`（動的ライブラリ） | SDL_loadso.h |
| `PaPiMeLa.App` | `TSDLApplication`（メインコールバック統合 / 古典ループ両対応） | SDL_main.h |
| `PaPiMeLa.Notification` | システム通知 **[要検証: SDL 3.6 で追加]** | SDL_notification.h |
| `PaPiMeLa.Graphics.Vulkan` / `.Metal` / `.OpenGL` | 各グラフィクス API との橋渡し（オプション） | SDL_vulkan.h, SDL_metal.h, SDL_opengl*.h, SDL_egl.h |

方針:

- **1 ヘッダ = 1 ユニット**を原則としつつ、小さいヘッダ（power/locale/clipboard/cpuinfo/misc）は `PaPiMeLa.System` にまとめる。
- キーボード/マウス/タッチ/ペンは `PaPiMeLa.Input.*` の階層に置き、ジョイスティック/ゲームパッド/ハプティック/センサーは頻繫に単独で使われるためトップレベルに置く。
- 循環 `uses` を避けるため、依存方向は「Core → Errors → Types → Properties → 各サブシステム → Events → App」とし、Events は各サブシステムの ID 型にのみ依存させる（`TSDLWindow` オブジェクトそのものは参照しない。詳細は 4.3）。
- `SDL_test*.h`、`SDL_begin_code.h` / `SDL_close_code.h`、`SDL_oldnames.h`、`SDL_main_impl.h`、`SDL_intrin.h`、`SDL_bits.h`、`SDL_endian.h`、`SDL_assert.h`、`SDL_copying.h`、`SDL_revision.h`、`SDL_dlopennote.h`、`SDL_hidapi.h`、`SDL_openxr.h` は OOP 層の対象外とする（`SDL_hidapi.h` と `SDL_openxr.h` は将来のオプション）。

### 1.4 リンク方式

C 層が静的リンク（`{$linklib SDL3}`）と動的ロード（`SDL_LoadObject`/`dlopen` 経由で関数ポインタを解決）のどちらを採るかは OOP 層の設計に影響しない。ただし動的ロードの場合、OOP 層の `TSDLSubsystems.Init` より前にロードが完了している必要があるため、`PaPiMeLa.Core` の `initialization` 節でロード状態を確認する API（`SDLApiLoaded: Boolean`）を C 層に要求する。決定は未解決事項（第 7 章）。

---

## 2. クラス階層設計

### 2.1 基底クラス `TSDLObject`

```pascal
type
  TSDLObject = class abstract(TObject)
  strict private
    FOwnsHandle: Boolean;
  protected
    procedure DestroyHandle; virtual; abstract;   // SDL_Destroy*/SDL_Close*/SDL_Release* を呼ぶ
    function  GetIsValid: Boolean; virtual; abstract;
    procedure CheckValid; inline;                 // 無効なら ESDLInvalidHandle
  public
    destructor Destroy; override;                 // OwnsHandle なら DestroyHandle
    procedure  ReleaseHandle;                     // 所有権を放棄してハンドルを外部へ渡す
    property   OwnsHandle: Boolean read FOwnsHandle write FOwnsHandle;
    property   IsValid: Boolean read GetIsValid;
  end;

  // 不透明ポインタ型ハンドルを持つオブジェクトのジェネリック基底
  generic TSDLHandleObject<THandle> = class abstract(TSDLObject)
  strict private
    FHandle: THandle;
  protected
    function GetIsValid: Boolean; override;       // FHandle <> nil
    procedure SetHandle(AHandle: THandle);
  public
    constructor CreateFromHandle(AHandle: THandle; AOwns: Boolean);
    property Handle: THandle read FHandle;
  end;

  // 整数 ID 型ハンドル（SDL_WindowID, SDL_JoystickID など）を持つオブジェクトの基底
  generic TSDLIDObject<TID> = class abstract(TSDLObject)
    ...
    property ID: TID read FID;
  end;
```

設計上のポイント:

- **RAII 的管理**: コンストラクタで SDL リソースを生成し、失敗時は例外を投げる（オブジェクトは生成されない）。デストラクタで `DestroyHandle` を呼ぶ。ユーザーは `try ... finally Free end` の通常の Pascal イディオムで扱える。
- **`CreateFromHandle`**: SDL から既存のハンドルが返ってくる場面（`SDL_GetRenderWindow`、イベント中の `windowID`、GPU スワップチェーンテクスチャなど）向け。`AOwns = False` なら借用。
- **無効化後アクセス**: `IsValid = False` のオブジェクトへの操作は `ESDLInvalidHandle` を投げる。「破棄済みハンドルへの use-after-free」を Pascal 側で検知するため。
- `TSDLObject` は `TComponent` を継承しない（LCL/FCL への依存を避ける）。Lazarus 統合は別パッケージの責務とする。

### 2.2 親子所有ツリーとハンドル → ラッパー逆引き

SDL は「レンダラー破棄時に配下のテクスチャも破棄」「GPU デバイス破棄前にリソースをすべて解放していること」など、親子関係を持つ。二重解放や dangling を防ぐため、ラッパー側でも親子を追跡する。

```pascal
type
  TSDLOwnerObject = class abstract(TSDLObject)   // 子を持てる基底
  strict private
    FChildren: TSDLObjectList;                   // specialize TObjectList<TSDLObject>(False)
    FChildrenLock: TSDLMutex;                    // 子リストへの並行アクセス保護（非所有）
  protected
    procedure RegisterChild(AChild: TSDLObject);
    procedure UnregisterChild(AChild: TSDLObject);
    procedure DestroyChildren;                   // 逆順に Free
  public
    destructor Destroy; override;                // DestroyChildren → inherited
  end;
```

- `TSDLRenderer`（`TSDLTexture` の親）、`TSDLGPUDevice`（すべての `TSDLGPU*` リソースの親）、`TSDLWindow`（`TSDLRenderer` の親。ただし SDL は Window 破棄時に Renderer を自動破棄するので、ラッパーは先に子を破棄する）、`TSDLTray`（`TSDLTrayMenu`/`TSDLTrayEntry` の親）がこれに該当する。
- 子オブジェクトの `Destroy` は親の `UnregisterChild` を呼ぶ。親が先に破棄された場合は子を先に `Free` する（親のデストラクタが `DestroyChildren`）。子を「借用」で作った場合は `OwnsHandle=False` なので SDL 呼び出しはスキップされる。

**ハンドル → ラッパー逆引き**: イベント（`windowID`）やコールバックから「対応する Pascal オブジェクト」を得たい場面が多い。SDL3 のプロパティシステムを活用する:

- プロパティを持つオブジェクト（Window / Renderer / Texture / Surface / GPUDevice / AudioStream / IOStream / Joystick / Gamepad / Process / Camera など。**[要検証: Camera・Sensor がプロパティを持つか]**）は、生成時に `SDL_SetPointerProperty(props, 'papimela.wrapper', Self)` を書き込む。`TSDLWindow.FromID(id)` は `SDL_GetWindowFromID` → `SDL_GetWindowProperties` → ポインタ取得、で O(1) に逆引きできる。
- プロパティを持たないハンドル（Mutex、Thread、Haptic、Sensor 等）は逆引きの需要が低いので、必要になった箇所だけ `PaPiMeLa.Core` の `TSDLHandleRegistry`（`TThreadedDictionary<Pointer, TSDLObject>` 相当、`TSDLMutex` で保護）に登録する。
- 逆引きで見つからない（C 層で直接生成されたハンドル等）場合は、`AOwns=False` の一時ラッパーを返すか `nil` を返すかを呼び出し側が選べる（`FromID(id, ACreateBorrowed: Boolean = False)`）。

### 2.3 参照カウントの方針

Object Pascal のクラスインスタンスは参照カウントされない。papimela の既定は **単一所有 + 親子ツリー**（上記）であり、大半のゲーム/アプリケーションではこれで十分である。

参照カウントが「必要になりそうな箇所」は以下と想定する:

| 箇所 | 状況 | 方針 |
|---|---|---|
| `TSDLTexture` をスプライト・UI 部品など複数のオーナーが共有 | アトラス化したテクスチャの寿命が個々のスプライトより長い | `ISDLTexture`（COM 型 = 参照カウント付き）インターフェースを `TSDLTexture` が実装する。`TSDLTexture.CreateShared(...)` で生成したものだけ `FRefCounted := True` になり、`_Release` でカウントが 0 になると `Free` する。通常の `Create` では `_AddRef/_Release` はカウントしない（`TInterfacedObject` 相当の「非カウントモード」） |
| `TSDLSurface` を複数のテクスチャ生成元として共有 | 読み込み画像のキャッシュ | 同上 `ISDLSurface` |
| GPU バッファ/サンプラーを複数パイプラインで共有 | シーン全体で使うサンプラーなど | GPU リソースは常に `TSDLGPUDevice` が親なので、参照カウントではなく**デバイス所有 + 借用参照**で扱う。共有の管理はユーザー側（マテリアルシステム等）の責務とする |
| `TSDLAudioStream` をミキサーとデバイス双方が参照 | — | デバイスへの bind は「参照」であり所有ではないため、参照カウント不要。ストリーム破棄時に自動 unbind されることを SDL が保証する **[要検証]** |

つまり「**既定はカウントしない。共有が必要な資産系（Texture/Surface）のみ COM インターフェース経由で opt-in**」とする。FPC 3.2 の管理レコード（`Initialize/Finalize/Copy/AddRef` 管理演算子）によるスマートポインタも候補だが、コンパイラバージョン依存とデバッグの難しさから初版では採用しない（第 7 章）。

### 2.4 主要リソース系クラス一覧

以下、ヘッダごとにクラス化方針を示す。「所有」列は既定のコンストラクタで生成した場合。

#### Video (`PaPiMeLa.Video`)

| クラス | ハンドル | 所有 | 備考 |
|---|---|---|---|
| `TSDLWindow` | `PSDL_Window` | ○ | `Create(Title, W, H, Flags)`、`CreateWithProperties(Props)`、`CreatePopup(Parent, ...)`。プロパティ: `Title`、`Size`、`Position`、`Flags`、`Fullscreen`、`Opacity`、`MinimumSize`、`Display`、`PixelDensity`、`DisplayScale`、`SafeArea`、`ICCProfile`、`Properties`。メソッド: `Show/Hide/Raise/Maximize/Minimize/Restore/Sync/Flash`、`SetShape(Surface)`、`SetHitTest(callback)`。ネイティブハンドル取得はプロパティ経由（`SDL_PROP_WINDOW_WIN32_HWND_POINTER` 等）を `NativeHandles` レコードで型付けして提供 |
| `TSDLWindowBuilder` | — | — | プロパティ生成を流暢 API で: `TSDLWindowBuilder.Create.Title('x').Size(800,600).Resizable.HighPixelDensity.Build` |
| `TSDLDisplay` | `SDL_DisplayID` | 借用 | **advanced record**（クラスではない）。`Name`、`Bounds`、`UsableBounds`、`ContentScale`、`Orientation`、`CurrentMode`、`DesktopMode`、`FullscreenModes: TArray<TSDLDisplayMode>`。`TSDLDisplay.All` / `TSDLDisplay.Primary` |
| `TSDLDisplayMode` | 構造体 | — | レコード。`PSDL_DisplayMode` はライブラリ所有のため値コピーで保持 |
| `TSDLGLContext` | `SDL_GLContext` | ○ | `TSDLWindow.CreateGLContext`。`MakeCurrent`、`SwapWindow` は Window 側。`SDL_GL_SetAttribute` は `TSDLGL` 静的クラス |
| `TSDLEGL*` | — | — | `SDL_egl.h` は関数ポインタ取得中心。`TSDLGL.GetProcAddress` 等に統合 |

#### Render (`PaPiMeLa.Render`)

| クラス | ハンドル | 所有 | 備考 |
|---|---|---|---|
| `TSDLRenderer` | `PSDL_Renderer` | ○（親: Window） | `Create(Window, DriverName='')`、`CreateWithProperties`、`CreateSoftware(Surface)`。プロパティ: `DrawColor: TSDLColor`、`DrawColorF: TSDLFColor`、`Scale`、`Viewport`、`ClipRect`、`LogicalPresentation`、`VSync`、`Target: TSDLTexture`、`Window`、`OutputSize`、`Properties`。描画: `Clear`、`DrawPoint(s)`、`DrawLine(s)`、`DrawRect(s)`、`FillRect(s)`、`RenderTexture`（`Copy` ではない）、`RenderTextureRotated`、`RenderTexture9Grid`、`RenderTextureTiled`、`RenderGeometry(Vertices, Indices)`、`RenderGeometryRaw`、`DebugText`、`Present`、`Flush`。座標変換: `WindowToRender`、`RenderToWindow`、`ConvertEventToRenderCoordinates` |
| `TSDLTexture` | `PSDL_Texture` | ○（親: Renderer） | `Create(Renderer, Format, Access, W, H)`、`CreateFromSurface`、`CreateWithProperties`。`Width/Height/Format/Access` は `SDL_GetTextureProperties` から読み取り（`SDL_QueryTexture` 廃止のため。`SDL_GetTextureSize` は W/H のみ）。`ColorMod`、`AlphaMod`、`BlendMode`、`ScaleMode`（既定は linear、ピクセルアート向け nearest を明示）。`Update(Rect, Pixels, Pitch)`、`UpdateYUV/NV`、`Lock/Unlock`、`LockToSurface` |
| `TSDLVertex` | 構造体 | — | `SDL_Vertex` 互換レコード。色は `TSDLFColor`（0..1 の浮動小数） |

#### GPU (`PaPiMeLa.GPU`)

SDL3 の目玉であり、papimela でも最も設計難易度が高い。SDL の所有モデルは「デバイスがすべてのリソースを所有し、`SDL_ReleaseGPU*(device, res)` で解放する」「コマンドバッファは `Acquire → Submit/Cancel` で寿命が終わる」「パスは `Begin/End` で囲むだけで解放不要」である。これをそのまま反映する:

| クラス/型 | ハンドル | 所有 | 種別 | 備考 |
|---|---|---|---|---|
| `TSDLGPUDevice` | `PSDL_GPUDevice` | ○ | class (`TSDLOwnerObject`) | `Create(ShaderFormats, DebugMode, Name='')`、`CreateWithProperties`。`ClaimWindow(Window)` / `ReleaseWindow`、`SetSwapchainParameters`、`Driver`、`ShaderFormats`、`WaitForIdle`、`AcquireCommandBuffer: TSDLGPUCommandBuffer` |
| `TSDLGPUResource` | — | ○（親: Device） | class 抽象 | `Device` プロパティ。派生: `TSDLGPUBuffer`、`TSDLGPUTransferBuffer`、`TSDLGPUTexture`、`TSDLGPUSampler`、`TSDLGPUShader`、`TSDLGPUGraphicsPipeline`、`TSDLGPUComputePipeline`、`TSDLGPUFence` |
| `TSDLGPUTransferBuffer` | `PSDL_GPUTransferBuffer` | ○ | class | `Map(Cycle): Pointer` / `Unmap`。`MapAs<T>` のような型付きビューはジェネリック record `TSDLGPUMappedRange<T>` で提供 |
| `TSDLGPUTexture` | `PSDL_GPUTexture` | ○ / **借用**（スワップチェーン） | class | スワップチェーンテクスチャは `AcquireSwapchainTexture` が返す借用インスタンス（`OwnsHandle=False`）。コマンドバッファ単位でプールして毎フレームの確保を避ける |
| `TSDLGPUCommandBuffer` | `PSDL_GPUCommandBuffer` | — | **advanced record** | 値型。`BeginRenderPass(ColorTargets, DepthTarget): TSDLGPURenderPass`、`BeginCopyPass`、`BeginComputePass`、`PushVertexUniformData<T>`、`WaitAndAcquireSwapchainTexture(Window): TSDLGPUTexture`、`Submit`、`SubmitAndAcquireFence: TSDLGPUFence`、`Cancel`。SDL 側がライフサイクルを管理するので Pascal 側で所有しない。ヒープ確保ゼロ |
| `TSDLGPURenderPass` / `TSDLGPUCopyPass` / `TSDLGPUComputePass` | 各 `PSDL_GPU*Pass` | — | advanced record | `BindGraphicsPipeline`、`BindVertexBuffers`、`BindFragmentSamplers`、`SetViewport`、`SetScissor`、`DrawPrimitives`、`DrawIndexedPrimitives`、`DrawPrimitivesIndirect`、`Finish`（= `SDL_EndGPU*Pass`）。`Finish` 忘れをデバッグビルドで検出できるよう、`{$ifdef PAPIMELA_DEBUG}` 時のみ Begin/End の対応をコマンドバッファ側でカウントする |
| `TSDLGPU*CreateInfo` 群 | 構造体 | — | record | `SDL_GPUGraphicsPipelineCreateInfo` 等は C 構造体と同レイアウトのレコードにし、既定値を埋める `Default` クラス関数と、`TSDLGPUGraphicsPipelineBuilder` を用意する（構造体のネストが深く、生で書くのは苦痛なため） |

#### Audio (`PaPiMeLa.Audio`)

| クラス | ハンドル | 所有 | 備考 |
|---|---|---|---|
| `TSDLAudioDeviceInfo` | `SDL_AudioDeviceID`（物理） | 借用 | advanced record。`Name`、`Format: TSDLAudioSpec`、`SampleFrames`。`TSDLAudioDeviceInfo.PlaybackDevices` / `RecordingDevices` で列挙（「capture → recording」「output → playback」の用語変更を反映） |
| `TSDLAudioDevice` | `SDL_AudioDeviceID`（論理） | ○ | `Open(Physical: TSDLAudioDeviceInfo; Spec)`、`OpenDefaultPlayback` / `OpenDefaultRecording`。`Pause/Resume`、`Paused`、`Gain: Single`（0.0..1.0 の float ボリューム）、`BindStream(s)`、`UnbindStream(s)`、`SetPostmixCallback(method)`。`Close` = `SDL_CloseAudioDevice` |
| `TSDLAudioStream` | `PSDL_AudioStream` | ○ | `Create(SrcSpec, DstSpec)`、`TSDLAudioStream.OpenDeviceStream(Device, Spec, Callback)`（`SDL_OpenAudioDeviceStream` の簡易パス。デバイスは一時停止で開始する点をドキュメント化）。`PutData(Buf, Len)`、`GetData(Buf, Len): Integer`、`Available`、`Queued`、`Flush`、`Clear`、`Gain`、`FrequencyRatio`、`Format`（Src/Dst の spec）、`Lock/Unlock`、`SetGetCallback` / `SetPutCallback`、`BoundDevice`、`Properties` |
| `TSDLAudioSpec` | 構造体 | — | record。`Format: TSDLAudioFormat`、`Channels`、`Freq`。`FrameSize` 計算プロパティ |
| `TSDLWavData` | — | ○ | `LoadWAV(Path/IOStream)` が返す `SDL_malloc` されたバッファを `SDL_free` で解放する所有ラッパー |

**スレッド安全性**: `SDL_AudioStreamCallback` / `SDL_AudioPostmixCallback` はオーディオスレッドで呼ばれる。ラッパーは `of object` メソッドポインタへのサンク（後述 5.5）を提供し、「コールバック内で `TSDLAudioStream` 以外の papimela オブジェクトに触らない」「例外を外へ漏らさない（サンク内で catch し `TSDLLog` に記録）」を規約にする。

#### 入力デバイス

| クラス | ハンドル | 所有 | ユニット | 備考 |
|---|---|---|---|---|
| `TSDLJoystick` | `PSDL_Joystick` + `SDL_JoystickID` | ○ | `.Joystick` | `Open(ID)`、`TSDLJoystick.Connected: TArray<SDL_JoystickID>`（`SDL_GetJoysticks` を `SDL_free` 込みでラップ）。`Axis[i]`、`Button[i]`、`Hat[i]`、`Ball[i]`、`Rumble`、`RumbleTriggers`、`SetLED`、`PowerInfo`、`ConnectionState`、`GUID`、`Properties`。`TSDLVirtualJoystick`: `SDL_AttachVirtualJoystick` の設定構造体と `SetVirtual*` をまとめる |
| `TSDLGamepad` | `PSDL_Gamepad` + `SDL_JoystickID` | ○ | `.Gamepad` | `Open(ID)`、`Connected`。`Axis[TSDLGamepadAxis]`、`Button[TSDLGamepadButton]`（`South/East/West/North` の位置名列挙。旧 A/B/X/Y は `ButtonLabel` で取得）、`Type`、`Mapping`、`Touchpads`、`Sensor[..]`、`SensorEnabled[..]`、`Rumble*`、`SetLED`、`SendEffect`、`Bindings`。`TSDLGamepadMapping` 静的クラス: `AddMapping`、`AddMappingsFromFile/IO`、`ReloadMappings` |
| `TSDLHaptic` | `PSDL_Haptic` + `SDL_HapticID` | ○ | `.Haptic` | `Open(ID)`、`OpenFromJoystick`、`OpenFromMouse`。`TSDLHapticEffect` は `SDL_HapticEffect` 共用体のレコードラップ + `EffectID` 管理 |
| `TSDLSensor` | `PSDL_Sensor` + `SDL_SensorID` | ○ | `.Sensor` | `Open(ID)`、`Data(Count)`、`Type`、`NonPortableType` |
| `TSDLCamera` | `PSDL_Camera` + `SDL_CameraID` | ○ | `.Camera` | `Open(ID, Spec)`。`PermissionState`（Approved/Denied はイベントでも通知）、`Format`、`AcquireFrame: TSDLSurface(借用) + Timestamp`、`ReleaseFrame`。フレーム取得を `for Frame in Camera.Frames` にするかは未解決 |
| `TSDLKeyboard` / `TSDLMouse` / `TSDLTouch` | — | — | `.Input.*` | インスタンス化しない静的クラス（`class function` 群）。`TSDLMouse.Position`、`TSDLMouse.Buttons`、`TSDLKeyboard.State: PBoolean 配列ビュー`、`TSDLKeyboard.ModState`、`TSDLKeyboard.StartTextInput(Window)`。`TSDLCursor` のみ所有クラス（`SDL_CreateCursor` / `SDL_DestroyCursor`）。システムカーソルは借用 |

#### I/O・ストレージ

| クラス | ハンドル | 所有 | ユニット | 備考 |
|---|---|---|---|---|
| `TSDLIOStream` | `PSDL_IOStream` | ○ | `.IO` | `FromFile(Path, Mode)`、`FromMem(P, Size)`、`FromConstMem`、`FromDynamicMem`。`Read(Buf, Size): NativeUInt`、`Write`、`Seek`、`Tell`、`Size`、`Status`、`Flush`、型付き `ReadU8/ReadU16LE/...`、`LoadFile`、`Properties`。**`TSDLIOStreamFromStream`**: 任意の `TStream` を `SDL_IOStreamInterface` 経由で SDL に渡す（SDL_image 等との連携で重要）。**`TSDLStreamOverIO`**: 逆に `SDL_IOStream` を `TStream` 派生として見せる |
| `TSDLAsyncIO` | `PSDL_AsyncIO` | ○ | `.AsyncIO` | `FromFile(Path, Mode)`。`Read(Queue, Buf, Offset, Size, UserData)`、`Write`、`Close(Flush, Queue)`（Close 自体が非同期でキューに結果が来る点に注意） |
| `TSDLAsyncIOQueue` | `PSDL_AsyncIOQueue` | ○ | `.AsyncIO` | `TryGetResult(out Outcome: TSDLAsyncIOOutcome): Boolean`、`WaitResult(out Outcome; TimeoutMS): Boolean`、`Signal`。`TSDLAsyncIOOutcome` はレコード（`AsyncIO`、`TaskType`、`Result`、`Buffer`、`Offset`、`BytesRequested`、`BytesTransferred`、`UserData` **[要検証: フィールド名]**）。`LoadFileAsync(Path, Queue, UserData)` はクラス関数 |
| `TSDLStorage` | `PSDL_Storage` | ○ | `.Storage` | `OpenTitle(Override, Props)`、`OpenUser(Org, App, Props)`、`OpenFile(Path)`、`OpenCustom(Interface, UserData)`。`Ready`、`FileSize`、`ReadFile`、`WriteFile`、`CreateDirectory`、`EnumerateDirectory(callback)`、`RemovePath`、`RenamePath`、`CopyFile`、`PathInfo`、`SpaceRemaining`、`Glob` |
| `TSDLFileSystem` | — | — | `.FileSystem` | 静的クラス。`BasePath`（SDL 所有、コピー不要）、`PrefPath(Org, App)`（`SDL_free` 必要）、`UserFolder(Kind)`、`CurrentDirectory`、`EnumerateDirectory`、`Glob`、`GetPathInfo`、`CreateDirectory`、`RemovePath`、`RenamePath`、`CopyFile` |

#### スレッド・同期

| クラス | ハンドル | 所有 | 備考 |
|---|---|---|---|
| `TSDLThread` | `PSDL_Thread` | ○ | `Create(Name, Method: TSDLThreadMethod)` / 抽象 `Execute` をオーバーライドする `TSDLThreadEx`。`Wait: Integer`、`Detach`、`ID`、`State`、`SetPriority`。RTL の `TThread` と併用可能だが、SDL の API（`SDL_SetCurrentThreadPriority`、TLS）を使う場合のみ推奨、と明記 |
| `TSDLMutex` / `TSDLRWLock` / `TSDLSemaphore` / `TSDLCondition` | 各ポインタ | ○ | SDL3 では Lock/Unlock は `void`（失敗しない）ので例外を出さない。`TryLock`、`WaitTimeout` は `Boolean` 戻り（タイムアウトは例外ではない）。`TSDLMutex.Guard: TSDLLockGuard`（管理レコードによるスコープガード）は FPC 3.2 依存のためオプション |
| `TSDLInitState` | 構造体 | — | `SDL_InitState` を包む record。`ShouldInit/SetInitialized/ShouldQuit` |
| `TSDLTLS` | `SDL_TLSID` | — | record。`Get/Set(Value, Destructor)` |
| `TSDLAtomicInt` / `TSDLAtomicU32` / `TSDLSpinLock` | 構造体 | — | advanced record。`Add`、`CompareAndSwap`、`Get/Set`。ポインタ CAS は `TSDLAtomicPointer` |

#### その他

| クラス | ユニット | 備考 |
|---|---|---|
| `TSDLProperties` | `.Properties` | 2.5 参照 |
| `TSDLHints` | `.Hints` | 静的クラス。`SetHint(Name, Value)`、`SetHintWithPriority`、`GetHint`、`GetHintBoolean`、`ResetHint(s)`、`AddCallback(Name, Method)` |
| `TSDLLog` | `.Log` | 静的クラス。`Info/Warn/Error/Debug/Trace(Category, Fmt, Args)`、`Priorities[Category]`、`SetOutputFunction(Method)`、`SetPriorityPrefix` |
| `TSDLTimer` | `.Time` | `Ticks`、`TicksNS`、`PerformanceCounter`、`Delay`、`DelayNS`、`DelayPrecise`。コールバックタイマーは `TSDLTimerHandle`（`SDL_TimerID`）record + `AddTimer(Interval, Method)` / `AddTimerNS`。コールバックはタイマースレッドで動く |
| `TSDLMessageBox` | `.MessageBox` | `ShowSimple(Flags, Title, Msg, Parent)` と、ボタン・色スキームを組めるビルダ |
| `TSDLFileDialog` | `.Dialog` | `ShowOpenFile(Window, Callback, Filters, DefaultLocation, AllowMany)`、`ShowSaveFile`、`ShowOpenFolder`、`ShowWithProperties`。コールバックはメインスレッド（イベントループ）から呼ばれる。結果はコールバック時のみ有効な文字列配列なので `TArray<String>` にコピーして渡す |
| `TSDLTray` / `TSDLTrayMenu` / `TSDLTrayEntry` | `.Tray` | 所有ツリー: Tray → Menu → Entry → (Submenu)。Entry のコールバックは `of object`。`SDL_UpdateTrays` **[要検証: 3.2 以降で必要か]** |
| `TSDLProcess` | `.Process` | `Create(Args, PipeStdio)`、`CreateWithProperties`。`Input: TSDLIOStream`、`Output: TSDLIOStream`（借用）、`ReadAll(out ExitCode)`、`Kill`、`Wait(Block, out ExitCode)` |
| `TSDLPower` / `TSDLLocale` / `TSDLClipboard` / `TSDLCPUInfo` / `TSDLPlatform` | `.System` | 静的クラス群。`TSDLClipboard.Text`（`SDL_free` 込み）、`SetData(MimeTypes, Callbacks)`。`SDL_system.h` のプラットフォーム固有 API は `{$ifdef}` で分岐した `TSDLSystem` に集約 |
| `TSDLSharedObject` | `.LoadSO` | `Load(Path)`、`GetFunction(Name): Pointer` |
| `TSDLNotification` | `.Notification` | **[要検証: SDL 3.6.0 新規]** `RequestPermission`、`Show(Title, Msg, Image, Actions): TSDLNotificationID`、`Remove(ID)`。`SDL_EVENT_NOTIFICATION_ACTION_INVOKED` をイベント側で受ける |

### 2.5 `TSDLProperties`

SDL3 全体の横串となる仕組みなので独立ユニットとする。

```pascal
type
  TSDLProperties = class(TSDLObject)
  public
    constructor Create;                                    // SDL_CreateProperties（所有）
    constructor CreateBorrowed(AID: SDL_PropertiesID);     // 他オブジェクトのプロパティ（借用）
    class function Global: TSDLProperties;                 // SDL_GetGlobalProperties（借用シングルトン）
    function  Has(const AName: String): Boolean;
    function  TypeOf(const AName: String): TSDLPropertyType;
    procedure Clear(const AName: String);
    procedure CopyTo(ADest: TSDLProperties);
    procedure Lock; procedure Unlock;
    procedure Enumerate(ACallback: TSDLPropertyEnumMethod);
    procedure SetPointerWithCleanup(const AName: String; AValue: Pointer; ACleanup: TSDLCleanupMethod);
    property Strings [const AName: String]: String  read GetString  write SetString;
    property Numbers [const AName: String]: Int64   read GetNumber  write SetNumber;
    property Floats  [const AName: String]: Single  read GetFloat   write SetFloat;
    property Booleans[const AName: String]: Boolean read GetBoolean write SetBoolean;
    property Pointers[const AName: String]: Pointer read GetPointer write SetPointer;
    property ID: SDL_PropertiesID read FID;
  end;
```

- 各リソースクラスは `Properties: TSDLProperties`（借用、遅延生成、オブジェクトと同寿命）を公開する。
- `SDL_PROP_*` 定数は C 層にあるものをそのまま使うが、頻出のもの（ウィンドウのネイティブハンドル、テクスチャの幅高さ等）は型付きプロパティとしてラッパー側に昇格させる。
- 「`Get*Property` の既定値引数」は Pascal 側でもデフォルト引数として露出する（`GetNumber(Name, Default)`）。インデックスプロパティでは既定値を渡せないため、`Numbers[]` の読み出しは `0` / `''` / `False` / `nil` を既定とし、必要なら明示メソッドを使う。

### 2.6 文字列とメモリの規約

- SDL は UTF-8 の `char*` を返す。ラッパーは **`String`（`AnsiString`、`{$H+}`）を UTF-8 として扱う**。ユニット先頭で `{$codepage UTF8}` は指定せず、`UTF8String` との相互変換は暗黙のまま（Lazarus 環境では `String` = UTF-8 が既定）。Windows のシステムコードページ環境との衝突は未解決事項として第 7 章に載せる。
- SDL が返す文字列のうち「SDL 所有（`const char*`）」はコピーのみ、「呼び出し側が `SDL_free` すべきもの」（`SDL_GetClipboardText`、`SDL_GetPrefPath`、`SDL_GetJoysticks` 等の配列、`SDL_LoadFile` の結果など）はラッパー内で必ず `SDL_free` する。**`FreeMem` を SDL の返したポインタに使ってはならない**（SDL のアロケータが差し替わっている可能性がある）。
- `SDL_malloc` 系を Pascal 側から使う必要がある場合（`SDL_free` される前提のバッファを渡す API）は `PaPiMeLa.Core.SDLAlloc/SDLFree` を経由する。

### 2.7 初期化 (`PaPiMeLa.Core`)

```pascal
type
  TSDLSubsystem = (Audio, Video, Joystick, Haptic, Gamepad, Events, Sensor, Camera);
  TSDLSubsystems = set of TSDLSubsystem;

  TSDL = class sealed   // 静的クラス
  public
    class procedure Init(ASubsystems: TSDLSubsystems);        // SDL_Init。失敗時 ESDLInitError
    class procedure InitSubSystem(ASubsystems: TSDLSubsystems);
    class procedure QuitSubSystem(ASubsystems: TSDLSubsystems);
    class function  WasInit(ASubsystems: TSDLSubsystems): TSDLSubsystems;
    class procedure Quit;
    class procedure SetAppMetadata(const AName, AVersion, AIdentifier: String);
    class function  Version: TSDLVersion;                     // ランタイムの SDL_GetVersion
    class function  IsMainThread: Boolean;
    class procedure RunOnMainThread(AMethod: TThreadMethod; AWaitComplete: Boolean);
  end;
```

- `SDL_INIT_TIMER` / `SDL_INIT_EVERYTHING` は SDL3 で削除されたため列挙に含めない。
- 自動 `SDL_Quit` は `finalization` 節で行わない（順序が不定でクラッシュの元になるため）。`TSDLApplication`（4.5）を使う場合はそちらが責任を持つ。
- ランタイムバージョンがコンパイル時想定より古い場合、`Init` は警告ログを出し、3.4/3.6 固有 API を呼ぶラッパーは `ESDLNotSupported` を投げる。

---

## 3. エラー処理方針

### 3.1 C API のエラー規約

- SDL3 の CamelCase 関数は `bool`（成功 `true`）、ポインタ（失敗 `nil`）、ID（失敗 `0`）、または「負の値」（`SDL_PeepEvents` など少数）で失敗を返し、詳細は `SDL_GetError()`（**スレッドローカル**）に格納される。
- 一部の `false` は「エラーではない」（`SDL_WaitEventTimeout` のタイムアウト、`SDL_HasProperty`、`SDL_TryLockMutex`、`SDL_PollEvent` のキュー空、`SDL_GetAsyncIOResult` の結果なし）。ラッパーはこれらを `Boolean` 戻りのまま残す。

### 3.2 例外階層

```pascal
type
  ESDLError = class(Exception)
  strict private
    FSDLMessage: String;      // SDL_GetError() の内容
    FFunctionName: String;    // 失敗した SDL 関数名（例: 'SDL_CreateWindow'）
  public
    constructor CreateFromSDL(const AFunctionName: String);   // SDL_GetError を読み、SDL_ClearError する
    property SDLMessage: String read FSDLMessage;
    property FunctionName: String read FFunctionName;
  end;

  ESDLInitError        = class(ESDLError);    // SDL_Init / サブシステム
  ESDLVideoError       = class(ESDLError);    // Window / Display / GL
  ESDLRenderError      = class(ESDLError);    // Renderer / Texture
  ESDLGPUError         = class(ESDLError);    // GPU デバイス・リソース・コマンド
  ESDLAudioError       = class(ESDLError);
  ESDLInputError       = class(ESDLError);    // Joystick / Gamepad / Haptic / Sensor / Camera / Keyboard / Mouse
  ESDLIOError          = class(ESDLError);    // IOStream / AsyncIO / Storage / FileSystem / Process
  ESDLThreadError      = class(ESDLError);    // Thread / Mutex / TLS
  ESDLEventError       = class(ESDLError);    // PushEvent / RegisterEvents 失敗
  ESDLSystemError      = class(ESDLError);    // Dialog / Tray / Clipboard / Power / Locale / LoadSO / Notification

  // SDL_GetError に依らない、ラッパー自身の状態エラー
  ESDLInvalidHandle    = class(ESDLError);    // 破棄済み/未初期化オブジェクトの使用
  ESDLNotSupported     = class(ESDLError);    // ランタイム SDL が古い、プラットフォーム非対応
  ESDLArgument         = class(ESDLError);    // Pascal 側で検出できる引数不正（負のサイズ等）
```

- **1 サブシステム = 1 例外クラス**の粒度にする。ユーザーは `on E: ESDLError` で一括捕捉でき、必要なら `ESDLGPUError` だけを別扱いできる。個々の関数単位の例外クラスは作らない。
- `Message` は `'<FunctionName> failed: <SDLMessage>'` の形式。`SDLMessage` が空文字（SDL がエラー文字列を設定しなかった場合）でも例外は投げる。

### 3.3 チェックヘルパ

```pascal
procedure SDLCheck(AOk: Boolean; const AFunc: String; AExcClass: ESDLErrorClass = nil); inline;
function  SDLCheckPtr(P: Pointer; const AFunc: String; AExcClass: ESDLErrorClass = nil): Pointer; inline;
function  SDLCheckID(AID: UInt32; const AFunc: String; AExcClass: ESDLErrorClass = nil): UInt32; inline;
```

- 各ラッパーメソッドはこれらで包む。`AExcClass` 省略時は `ESDLError`。ユニットごとに `SDLCheckVideo` 等の薄い別名を用意して定型化する（Low 難易度の実装作業をパターン化するため）。
- 例外生成コスト回避のため、`SDLCheck` 自身は `inline` で分岐のみ、例外生成は非インライン関数に委ねる。

### 3.4 ホットパスの扱い

`RenderTexture`、`PutAudioStreamData`、`DrawGPUPrimitives` のようなフレーム毎・サンプル毎に呼ばれる関数でも、**既定は例外を投げる**（失敗はプログラムミスかデバイス喪失であり、頻発しない）。ただし、ユーザーが例外コストや制御フローを避けたい場合のために、`Try` プレフィックスの `Boolean` 戻り版（`TryRenderTexture`）を**ホットパス関数に限って**併設する。すべての関数に `Try` 版を用意することはしない。

### 3.5 コールバック境界

SDL からの C コールバック（オーディオ、タイマー、イベントウォッチ、ダイアログ、Enumerate 系、ヒント、ログ出力、IOStream/Storage インターフェース）内で Pascal 例外を発生させると、C フレームを巻き戻して未定義動作になる。すべてのサンク（5.5）は `try ... except` で例外を捕捉し、`TSDLLog.Error(Category.Error, ...)` に記録した上で「失敗」を意味する戻り値（`false` / 0 / `SDL_ENUM_FAILURE` 等）を返す。捕捉した例外は `TSDL.LastCallbackException` に保存し、メインスレッドから再スローできるようにする（オプション）。

---

## 4. イベントシステム設計

### 4.1 要件

1. ゲームループでの**ゼロアロケーション**ポーリングが可能であること（毎フレーム数十〜数百イベントがオブジェクト生成を伴うと GC のない Pascal でも断片化・オーバーヘッドが問題になる）。
2. アプリケーション規模が大きくなったときに、**リスナー/オブザーバー**で関心ごとに処理を分割できること。
3. SDL3 のメインコールバック方式（iOS/Emscripten/Wayland で必須になりうる）と、古典的な `while PollEvent` ループの**両方**を同じユーザーコードから利用できること。
4. `SDL_Event` が 128 バイト固定の共用体であることを活かし、C 層との変換コストをゼロにする。

### 4.2 三層構造

```
 [C]  SDL_Event 共用体 (128 bytes)
        │  型付きビュー（変換なし）
 [1]  TSDLEvent  — advanced record。SDL_Event と同一レイアウト。Kind と各種アクセサを持つ
        │  ポーリング: TSDLEventQueue.Poll(out Ev: TSDLEvent): Boolean
 [2]  TSDLEventDispatcher — TSDLEvent を種別ごとにリスナーインターフェース / メソッドポインタへ振り分ける
        │
 [3]  TSDLApplication — メインコールバック or 古典ループを隠蔽し、Dispatcher を駆動する
```

**層 1: `TSDLEvent`（レコード）**

```pascal
type
  TSDLEventKind = SDL_EventType;   // C の列挙をそのまま利用。{$scopedenums} は C 層次第

  TSDLEvent = record               // SizeOf(TSDLEvent) = SizeOf(SDL_Event) = 128 を静的アサート
  public
    function Kind: TSDLEventKind; inline;
    function Timestamp: UInt64; inline;                        // ナノ秒
    function IsWindowEvent: Boolean; inline;                   // SDL_EVENT_WINDOW_FIRST..LAST
    function IsUserEvent: Boolean; inline;
    // 型付きビュー: 対応しない Kind でアクセスしても未定義値を返すだけ（例外は出さない。ホットパスのため）
    property Window   : TSDLWindowEvent    read GetWindow;     // = SDL_WindowEvent 互換 record
    property Key      : TSDLKeyboardEvent  read GetKey;
    property Text     : TSDLTextInputEvent read GetText;
    property Motion   : TSDLMouseMotionEvent  read GetMotion;
    property Button   : TSDLMouseButtonEvent  read GetButton;
    property Wheel    : TSDLMouseWheelEvent   read GetWheel;
    property GamepadAxis, GamepadButton, GamepadDevice, ... ;  // 各 SDL_*Event と 1:1
    property Drop     : TSDLDropEvent ...;
    property User     : TSDLUserEvent ...;
  case Integer of                                              // C 共用体と同一
    0: (Raw: SDL_Event);
    ...
  end;
```

- 各 `TSDLXxxEvent` は C 構造体と同レイアウトのレコードで、必要に応じて計算プロパティ（例: `TSDLMouseButtonEvent.Position: TSDLFPoint`、`TSDLKeyboardEvent.Down: Boolean`、`TSDLWindowEvent.WindowID`）を追加する。
- `TSDLEvent.Window` のような **オブジェクト参照は返さない**。`WindowID` から `TSDLWindow.FromID` を呼ぶのはユーザーまたは Dispatcher の責務（`PaPiMeLa.Events` が `PaPiMeLa.Video` に依存しないようにするため。1.3 の依存方向を参照）。

**層 1: `TSDLEventQueue`（静的クラス）**

```pascal
type
  TSDLEventQueue = class sealed
  public
    class function  Poll(out AEvent: TSDLEvent): Boolean;           // SDL_PollEvent
    class function  Wait(out AEvent: TSDLEvent): Boolean;           // SDL_WaitEvent
    class function  WaitTimeout(out AEvent: TSDLEvent; ATimeoutMS: Int32): Boolean;  // false = タイムアウト（例外なし）
    class procedure Pump;                                           // SDL_PumpEvents
    class procedure Push(const AEvent: TSDLEvent);                  // 失敗時 ESDLEventError（フィルタで落とされた場合は例外なし false → 未解決）
    class function  Peep(var AEvents: array of TSDLEvent; AAction: TSDLEventAction; AMin, AMax: TSDLEventKind): Integer;
    class function  Has(AKind: TSDLEventKind): Boolean;
    class procedure Flush(AKind: TSDLEventKind);
    class procedure SetEnabled(AKind: TSDLEventKind; AEnabled: Boolean);
    class function  RegisterUserEvents(ACount: Integer): TSDLEventKind;   // 0 なら ESDLEventError
    class procedure SetFilter(AFilter: ISDLEventFilter);              // SDL_SetEventFilter（1 つだけ）
    class function  AddWatch(AWatch: ISDLEventWatch): TSDLEventWatchHandle;   // SDL_AddEventWatch
    class procedure RemoveWatch(AHandle: TSDLEventWatchHandle);
  end;
```

**層 2: `TSDLEventDispatcher`**

```pascal
type
  // リスナーは CORBA インターフェース（非参照カウント）。実装オブジェクトの寿命はユーザーが管理する
  ISDLEventListener = interface ['{...}']
    procedure HandleEvent(const AEvent: TSDLEvent; var AHandled: Boolean);
  end;

  ISDLWindowListener = interface ['{...}']
    procedure WindowShown(const E: TSDLWindowEvent);
    procedure WindowResized(const E: TSDLWindowEvent);
    procedure WindowCloseRequested(const E: TSDLWindowEvent);
    ...   // SDL_EVENT_WINDOW_* 1 つにつき 1 メソッド。使わないものは空実装で良いよう抽象基底 TSDLWindowListenerBase も提供
  end;

  ISDLKeyboardListener = interface ... KeyDown, KeyUp, TextInput, TextEditing, TextEditingCandidates, KeymapChanged ...
  ISDLMouseListener    = interface ... Motion, ButtonDown, ButtonUp, Wheel, DeviceAdded, DeviceRemoved ...
  ISDLGamepadListener  = interface ... AxisMotion, ButtonDown, ButtonUp, Added, Removed, Remapped, Touchpad*, SensorUpdate ...
  ISDLJoystickListener, ISDLTouchListener, ISDLPenListener, ISDLDropListener, ISDLAudioDeviceListener,
  ISDLCameraListener, ISDLSensorListener, ISDLDisplayListener, ISDLClipboardListener, ISDLAppLifecycleListener,
  ISDLRenderListener, ISDLUserEventListener

  TSDLEventDispatcher = class
  public
    procedure AddListener(AListener: ISDLEventListener);            // 型別インターフェースは Supports() で自動検出する
    procedure RemoveListener(AListener: ISDLEventListener);
    procedure AddWindowListener(AWindowID: SDL_WindowID; AListener: ISDLWindowListener);   // ウィンドウ別に絞り込み
    procedure Dispatch(const AEvent: TSDLEvent);                    // 1 イベントを配信
    function  PumpAndDispatch: Boolean;                             // Poll ループを回し QUIT なら False
    // Lazarus/Delphi 風のメソッドポインタイベント（インターフェース実装が面倒な小規模用途向け）
    property OnQuit:      TSDLNotifyEvent;
    property OnKeyDown:   TSDLKeyboardEventHandler;                 // procedure(const E: TSDLKeyboardEvent) of object
    property OnMouseMotion: ...;
    property OnUnhandled: TSDLEventHandler;                         // どのリスナーも処理しなかったもの
  end;
```

- 配信順: (1) `ISDLEventListener.HandleEvent`（汎用、`AHandled` で打ち切り可） → (2) 型別インターフェース → (3) メソッドポインタ → (4) `OnUnhandled`。
- リスナー登録は 1 オブジェクトに複数の型別インターフェースが実装されていても `AddListener` 1 回で済む（`Supports(Obj, ISDLKeyboardListener, Intf)` を登録時に評価し、種別ごとのリストにキャッシュする）。
- `Dispatch` 中の Add/Remove は遅延適用（配信中はリストをスナップショットして走査）。
- 内部で Kind → 「型別リスナーリスト + 呼び出すメソッド」の変換は `case` 文で行う。ヒープ確保はしない（イベント引数は `const` 参照渡し）。
- **判断: ポーリング API は残す。** 小規模プログラムやサンプル、既存 SDL2 コードからの移植では `while TSDLEventQueue.Poll(Ev) do case Ev.Kind of ...` が最も理解しやすく、Dispatcher は「あると便利」な追加層と位置付ける。両者は同じ `TSDLEvent` レコードを使うので混在できる。

### 4.3 ウィンドウ ID とオブジェクトの結び付け

`TSDLEventDispatcher.AddWindowListener(WindowID, ...)` はウィンドウイベント（およびそのウィンドウで発生したキーボード/マウス/テキスト/ドロップイベント）だけをそのリスナーに届ける。`PaPiMeLa.Video` 側では `TSDLWindow` が `ISDLWindowListener` を実装して自分自身の状態（キャッシュした Size など）を更新し、さらに `TSDLWindow.OnResized` のようなメソッドポインタイベントを再発火する「自己登録」を行う。これで `PaPiMeLa.Events` → `PaPiMeLa.Video` の依存を作らずに済む。

### 4.4 イベントウォッチ／フィルタ

`SDL_AddEventWatch` のコールバックは**イベントを push したスレッド**で呼ばれる（メインスレッドとは限らない）。`ISDLEventWatch` の実装者に「スレッド安全に書くこと」「ブロックしないこと」を要求し、Dispatcher とは別の仕組みとして提供する。`SDL_SetEventFilter` は 1 つしか登録できないため、papimela 内部では使わず（ユーザーに開放）、`SDL_EVENT_POLL_SENTINEL` の扱いも C 層任せとする。

### 4.5 `TSDLApplication`（`PaPiMeLa.App`）

```pascal
type
  TSDLAppResult = (Continue, Success, Failure);   // SDL_AppResult

  TSDLApplication = class
  protected
    function  DoInit(const AArgs: TArray<String>): TSDLAppResult; virtual;   // SDL_AppInit 相当
    function  DoIterate: TSDLAppResult; virtual;                            // SDL_AppIterate 相当
    function  DoEvent(const AEvent: TSDLEvent): TSDLAppResult; virtual;     // 既定: Dispatcher.Dispatch
    procedure DoQuit(AResult: TSDLAppResult); virtual;                      // SDL_AppQuit 相当
  public
    property Dispatcher: TSDLEventDispatcher;
    function Run: Integer;                        // 実装は 2 種類（下記）
    class function RunMain(AClass: TSDLApplicationClass): Integer;   // program の本体で 1 行呼ぶ
  end;
```

- **メインコールバックモード**: `SDL_EnterAppMainCallbacks(argc, argv, @AppInitThunk, @AppIterateThunk, @AppEventThunk, @AppQuitThunk)` を呼ぶ。SDL 側が用意する C の `main` は使わない（Pascal の `program` が `main` を持つため）。サンク関数は `cdecl` のユニットローカル関数で、`appstate` に `TSDLApplication` インスタンスを入れる。**[要検証: FPC から `SDL_EnterAppMainCallbacks` を直接呼んで iOS / Emscripten で正しく動くか。README-main-functions は「非 C 言語からの利用はより複雑」と述べるのみ。Windows/Linux/macOS では問題ないと想定]**
- **古典ループモード**: `DoInit` → `while DoIterate = Continue do begin PollEvent → DoEvent end` → `DoQuit`。
- モードは `{$define PAPIMELA_MAIN_CALLBACKS}` または `Run(AMode)` の引数で選択。ユーザーコードは `DoInit/DoIterate/DoEvent/DoQuit` をオーバーライドするだけで、どちらでも動く。
- `SDL_MAIN_USE_CALLBACKS` マクロは Pascal からは無関係（ヘッダ専用の仕組み）。`SDL_SetMainReady` / `SDL_RunApp` は `SDL_main.h` にあるがヘッダ側の `main` 差し替え用であり、papimela では `SDL_RunApp` を Windows での `WinMain` 相当（引数の UTF-8 化など）を得るために使うか検討する（未解決）。

---

## 5. OOP 機能の活用方針

### 5.1 プロパティ構文

- **状態を持つ getter/setter ペア**（`SDL_GetWindowTitle` / `SDL_SetWindowTitle`）は `property Title: String read GetTitle write SetTitle` にする。SDL 呼び出しが伴うことは名前から明らかにし、キャッシュはしない（SDL が真の状態を持つ）。ただしイベント経由で更新される値（ウィンドウサイズ）はキャッシュ可。
- **読み取り専用の状態** は read-only プロパティ（`Renderer.OutputSize`、`Joystick.NumAxes`）。
- **配列アクセス** はインデックスプロパティ（`Joystick.Axis[i]`、`Properties.Strings['x']`、`Gamepad.Button[TSDLGamepadButton.South]`）。
- **副作用が大きい・引数が複数ある操作**（`SetWindowFullscreenMode(Mode)`、`SetLogicalPresentation(W, H, Mode)`）はメソッドにする。「プロパティ代入でウィンドウが再生成される」ような驚きを避けるため。
- **`default` プロパティ** はコレクション的なクラスに限る（`TSDLTrayMenu.Entries[i]`）。
- **クラスプロパティ**（`class property`）を静的クラス（`TSDLMouse.Position`、`TSDLKeyboard.ModState`）で使う。

### 5.2 演算子オーバーロード（`PaPiMeLa.Types`）

`TSDLPoint`（`Int32` x2）、`TSDLFPoint`（`Single` x2）、`TSDLRect`（`Int32` x4）、`TSDLFRect`（`Single` x4）、`TSDLColor`（`UInt8` x4）、`TSDLFColor`（`Single` x4）は、**C 構造体と同一レイアウトの advanced record** とし、`PSDL_Rect(@R)` のように無変換で C 層へ渡せることを静的アサート（`{$if SizeOf(TSDLRect) <> SizeOf(SDL_Rect)} {$error} {$endif}`）で保証する。

| 演算子 | 対象 | 意味 |
|---|---|---|
| `=` / `<>` | 全型 | 要素比較（浮動小数は厳密比較。近似比較は `NearlyEquals(Eps)` メソッド） |
| `+` / `-` | Point + Point、Rect + Point（平行移動）、Color + Color（飽和加算） | ベクトル加減算 |
| `*` / `/` | Point * Single、FPoint * Single、Color * Single（各成分スケール、飽和） | スカラー倍 |
| `-`（単項） | Point、FPoint | 反転 |
| `in` | `Point in Rect`、`FPoint in FRect` | 包含判定（`SDL_PointInRect` 相当をインライン実装） |
| `*`（Rect * Rect） | Rect、FRect | 交差矩形（`SDL_GetRectIntersection`）。空なら `Empty` |
| `+`（Rect + Rect） | Rect、FRect | 包含矩形（`SDL_GetRectUnion`） |
| `:=`（`Implicit`） | `TSDLPoint → TSDLFPoint`、`TSDLRect → TSDLFRect`、`TSDLColor → TSDLFColor`（/255）、`TSDLFColor → TSDLColor`（×255 丸め、飽和） | 拡大方向は暗黙、縮小方向は `Explicit` に留める（精度損失を明示） |
| `Explicit` | `TSDLColor ↔ UInt32`（RGBA8888 パック）、`TSDLFPoint → TSDLPoint`（Trunc） | 明示変換 |

メソッド例: `TSDLRect.Create(X, Y, W, H)`、`FromLTRB`、`Empty`、`IsEmpty`、`Center`、`Inflate(dx, dy)`、`Offset`、`Intersects(R)`、`Contains(P)`、`Union(R)`、`Right`/`Bottom` プロパティ、`TSDLColor.FromHex($RRGGBBAA)`、`TSDLColor.Lerp(A, B, T)`、定数 `TSDLColor.White/Black/Transparent`（`class function` として実装。FPC の record 定数制約のため）。

`TSDLGUID` も `=` と `ToString/FromString`（`SDL_GUIDToString` / `SDL_StringToGUID`）を持つ record にする。

### 5.3 ジェネリクス

使う箇所は限定する（FPC のジェネリクスはコンパイルエラーの可読性が低く、Low 難易度担当の実装効率を下げるため）:

| 箇所 | 用途 |
|---|---|
| `TSDLHandleObject<THandle>` / `TSDLIDObject<TID>` | 基底クラスの重複排除（2.1）。派生クラスは `specialize` 済みの別名を経由する（`TSDLWindowBase = specialize TSDLHandleObject<PSDL_Window>;`）ので、ユーザーコードにジェネリクス構文は露出しない |
| `TSDLGPUMappedRange<T>` | 転送バッファのマップ領域を `^T` 配列として型安全に扱う record |
| `TSDLGPUCommandBuffer.PushVertexUniformData<T>(Slot; const Data: T)` | `SizeOf(T)` を自動で渡す。`generic` メソッドは FPC 3.2 で利用可 |
| `TSDLList<T>` = `Generics.Collections.TList<T>` の別名 | 子リストやリスナーリストの内部実装。ユーザーには `TArray<T>` を返す |
| `TSDLPool<T: TSDLObject>` | スワップチェーンテクスチャ等、借用ラッパーの再利用（内部用） |

`Generics.Collections`（FPC 3.2 標準の rtl-generics）に依存することを許容する。

### 5.4 インターフェース

- **CORBA インターフェース（非参照カウント）** — 既定（`{$interfaces corba}`）。用途: リスナー（`ISDL*Listener`）、イベントウォッチ/フィルタ、`ISDLIOStreamProvider`（`TSDLIOStreamFromStream` の抽象）、`ISDLStorageBackend`（カスタム Storage 実装）、`ISDLTrayHandler`。「オブジェクトの寿命は所有者が管理し、インターフェースはただの契約」という Pascal 的な使い方。GUID は `Supports` を使うために必ず付ける。
- **COM インターフェース（参照カウント）** — `IInterface` から派生し明示的に宣言。用途: `ISDLTexture` / `ISDLSurface`（2.3 の共有リソース）。`TSDLTexture` は `FRefCounted` フラグを持ち、`CreateShared` で生成した場合のみ `_Release` が `Free` を呼ぶ。
- インターフェースを「ラッパー API の抽象化」に使うこと（`ISDLWindow` を定義して `TSDLWindow` に実装させる等）は**しない**。モック用途はユーザーが継承で対応する。

### 5.5 コールバックの統一パターン（サンク）

SDL の C コールバックは `void *userdata` を伴う。papimela では以下を全ユニットで統一する:

```pascal
type
  TSDLTimerMethod = function(AInterval: UInt32): UInt32 of object;

  // ユニットローカル
  function TimerThunk(userdata: Pointer; timerID: SDL_TimerID; interval: UInt32): UInt32; cdecl;
  begin
    try
      Result := TSDLTimerBinding(userdata).Method(interval);
    except
      on E: Exception do begin TSDLLog.CallbackException('SDL_AddTimer', E); Result := 0; end;
    end;
  end;
```

- `of object` メソッドポインタと、FPC 3.2 の匿名関数非対応を踏まえて **`procedure ... is nested` は使わない**（コールバックの寿命がスコープを越えるため）。匿名メソッドは FPC 3.3 以降のため初版では対象外（第 7 章）。
- `userdata` にはメソッドポインタを保持する小さなバインディングオブジェクト（`TSDLTimerBinding`）を渡す。バインディングの寿命は登録元オブジェクト（`TSDLTimerHandle.Remove`、`TSDLAudioStream.Destroy` 等）が管理する。
- 例外は必ずサンクで止める（3.5）。

### 5.6 その他

- `class sealed` を静的クラス（`TSDLMouse`、`TSDLHints` 等）に付け、インスタンス化を防ぐため `constructor Create` を `private` に隠す。
- `strict private` / `strict protected` を既定にし、同一ユニット内からのフィールド直接参照を禁止する。
- `inline` はゲッター/セッター/`SDLCheck` に限定する。
- 列挙型は C 層の整数列挙をそのまま使うか、Pascal 側で `{$scopedenums}` 列挙に再定義するかは C 層の設計依存（未解決）。集合演算が有効なフラグ（`SDL_WindowFlags` は 64 ビット、`SDL_INIT_*` は 32 ビット）は、C 層のビットマスク定数を `set of TSDLWindowFlag` に変換するヘルパを Types に置く（ビット位置が 32 を超える `SDL_WindowFlags` は FPC の `set` で扱えないため **ビットフィールドのまま `TSDLWindowFlags = UInt64` とし、判定は `Has(Flag)` メソッド**にする方針。要検討）。

---

## 6. 命名規則

FPC / Lazarus コミュニティの慣習（FCL、LCL、Free Pascal Style Guide）に沿う。

| 対象 | 規則 | 例 |
|---|---|---|
| クラス | `T` + `SDL` + 概念名（PascalCase） | `TSDLWindow`、`TSDLGPUGraphicsPipeline` |
| レコード（値型） | `T` + `SDL` + 名 | `TSDLRect`、`TSDLEvent`、`TSDLGPUCommandBuffer` |
| ポインタ型 | `P` + レコード名から `T` を除いたもの | `PSDLRect`（C 層の `PSDL_Rect` とは別。相互変換は型キャスト） |
| インターフェース | `I` + `SDL` + 名。リスナーは `Listener` 接尾辞 | `ISDLKeyboardListener`、`ISDLTexture` |
| 例外 | `E` + `SDL` + 名 + `Error`（状態系は `Error` を付けない） | `ESDLRenderError`、`ESDLInvalidHandle` |
| 列挙型 | `T` + `SDL` + 名（単数形）。値は `{$scopedenums}` で修飾 | `TSDLGamepadButton.South` |
| 集合型 | 列挙名の複数形 | `TSDLSubsystems = set of TSDLSubsystem` |
| メソッドポインタ型 | `T` + `SDL` + 名 + `Event`（イベント）/ `Method`（コールバック）/ `Handler` | `TSDLKeyboardEventHandler`、`TSDLTimerMethod` |
| 静的（インスタンス化しない）クラス | `TSDL` + サブシステム名、`class sealed` | `TSDLMouse`、`TSDLHints`、`TSDLLog` |
| フィールド | `F` プレフィックス、`strict private` | `FHandle`、`FOwnsHandle` |
| 引数 | `A` プレフィックス | `AWindow`、`const AName: String` |
| ローカル変数 | プレフィックスなし、PascalCase。ループ変数は `I, J, K` | — |
| 定数 | PascalCase。C 層の `SDL_PROP_*` は C 名のまま | `DefaultWindowWidth`（ラッパー独自）、`SDL_PROP_WINDOW_TITLE_STRING`（C 層） |
| プロパティ / メソッド | PascalCase。SDL 関数名から `SDL_` と対象名を取った動詞または名詞 | `SDL_SetWindowTitle` → `Window.Title`、`SDL_RenderTexture` → `Renderer.RenderTexture`、`SDL_GetJoysticks` → `TSDLJoystick.Connected` |
| ゲッター/セッター | `Get` / `Set` + プロパティ名、`strict private` または `protected` | `GetTitle` / `SetTitle` |
| ユニット | `PaPiMeLa.` + PascalCase。サブ階層は `.` 区切り | `PaPiMeLa.Input.Keyboard` |
| SDL 名の踏襲 | SDL 側の用語（`Renderer`、`Gamepad`、`Playback/Recording`、`South/East/West/North`、`IOStream`）を優先し、SDL2 の旧名（`GameController`、`RWops`、`Capture`）は使わない | — |
| ブール | 状態は形容詞/受動態（`Paused`、`IsValid`、`Connected`）、能力は `Can*`/`Has*`/`Supports*` | `Window.Fullscreen`、`Renderer.CanRenderTarget` |
| `Try` 接頭辞 | 例外を投げず `Boolean` を返す版 | `TryRenderTexture`、`TryGetResult` |
| 破棄 | `Destroy`（デストラクタ）のみ。`Close`/`Release` は「ハンドルは維持して状態を変える」操作に限定 | `TSDLAudioDevice.Close` は例外的に SDL 用語に合わせる（未解決） |

補足:

- `TSDL` プレフィックスは冗長だが、ユーザーのプロジェクト内の `TWindow`、`TTexture` との衝突を避けるため必須とする。
- 単位（ミリ秒/ナノ秒）は名前に含める: `Ticks`（ms）、`TicksNS`、`DelayNS`、`Timestamp`（ns、SDL3 の既定に合わせて接尾辞なし）。
- 座標型の使い分け: SDL3 はマウス/タッチ/レンダラー座標が `float` になったので、`TSDLFPoint`/`TSDLFRect` を第一級とし、整数版は Surface やウィンドウ位置に限る。

---

## 7. 未解決事項・要検討事項

次フェーズで決めるべき事項を、影響の大きい順に列挙する。

1. **C バインディング層の調達**: 自作（`h2pas` + 手修正）か、既存の SDL3-for-Pascal 等を採用するか。採用する場合はライセンス（zlib/MPL）、ユニット名（`SDL3` 単一ユニットか分割か）、列挙の表現（整数定数か Pascal 列挙か）、`{$linklib}` か動的ロードか、を確認して OOP 層の前提に固定する必要がある。**OOP 層の Low 難易度作業の大半はこの決定待ち。**
2. **リンク方式**（静的 `{$linklib SDL3}` vs 実行時 `dlopen`）: 配布形態（Steam 等の同梱 DLL 差し替え）を考えると動的ロードが望ましいが、C 層の全関数に関数ポインタ変数が必要になる。
3. **文字列型**: `String`（UTF-8 前提）で行くか、`UTF8String` を明示するか、`RawByteString` を受け取り側に選ばせるか。Windows + 非 Lazarus 環境での既定コードページ問題。
4. **列挙・フラグの表現**: C 層の整数列挙をそのまま公開するか、`{$scopedenums}` の Pascal 列挙に再定義するか（再定義は型安全だが、C 層とのキャストが増え、SDL 側で列挙値が追加されたとき追従コストがある）。64 ビットの `SDL_WindowFlags` を `set` にできない問題。
5. **参照カウントの最終形**: 2.3 の「COM インターフェース opt-in」で十分か、FPC 3.2 の管理レコードによる `TSDLShared<T>` スマートポインタを導入するか。管理レコードは 3.2.0 以降で利用可能だが、デバッガ表示や `const` 引数まわりの挙動に癖がある。
6. **イベントレコードの型付きアクセサの実装方式**: `TSDLEvent` を `SDL_Event` の可変部レコードとして定義するか、`SDL_Event` へのポインタを持つ record helper にするか。前者は 128 バイトコピーが発生するが所有権が明確、後者はゼロコピーだが寿命の管理が必要。
7. **メインコールバックの実現可否**: `SDL_EnterAppMainCallbacks` を FPC の `program` から呼ぶ方式が iOS / Emscripten / Android で正しく動くか。それらのプラットフォームでは SDL 側の `main` 差し替え（`SDL_main_impl.h` 相当）が必要になる可能性がある。Windows で `SDL_RunApp` を使って UTF-8 引数を得るかどうか。**[要検証]**
8. **`SDL_PushEvent` がフィルタで落とされたときの扱い**（`false` だがエラーではない）: 例外にするか `Boolean` 戻りにするか。
9. **カメラフレーム取得 API の形**: `AcquireFrame/ReleaseFrame` のペアか、`for Frame in Camera.Frames` の列挙子 + 管理レコードによる自動 Release か。
10. **GPU の CreateInfo 構造体群**: レコード + `Default` 関数で行くか、ビルダクラスまで用意するか。ビルダは使い勝手が良いが GPU モジュールの実装規模を倍にする。
11. **オーディオコールバックの再入・ロック規約**: `TSDLAudioStream.Lock` を Pascal 側の `TSDLMutex` と統合するか、コールバック内で papimela オブジェクトに触ることを許すか。
12. **スレッド API を RTL `TThread` に寄せるか**: `TSDLThread` を提供するか、`TThread` + SDL の TLS/優先度 API だけをラップするかで `PaPiMeLa.Threading` の規模が変わる。Linux では `cthreads` を `uses` の先頭に置く必要があることをどう強制するか。
13. **匿名メソッド（FPC 3.3+）**: サポート対象を 3.2.2 にする限り使えない。将来 `{$ifdef}` で追加するための設計余地（メソッドポインタ型を `TSDL*Method` と `TSDL*Proc` の 2 系統にしておくか）。
14. **SDL 3.4 / 3.6 追加 API の扱い**（Notification、Pinch イベント、Gamepad CapSense、`SDL_openxr.h`、`SDL_UpdateTrays` 等）: ランタイムの `SDL_GetVersion` で分岐するか、コンパイル時 `{$define}` で切るか。**[要検証: 各 API の追加バージョン]**
15. **`TSDLAudioDevice.Close` などの SDL 用語との整合**: 6 章の「破棄は `Destroy` のみ」原則の例外をどこまで許すか。
16. **ハンドル逆引きに使うプロパティ名**（`papimela.wrapper`）の衝突回避と、C 層直生成ハンドルへの借用ラッパー生成ポリシー。
17. **Lazarus パッケージ (`.lpk`) / fpmake の構成**、テスト戦略（fpcunit + ヘッドレスビデオドライバ `SDL_VIDEO_DRIVER=dummy` / オーディオ `dummy` でどこまで CI できるか）。
18. **SDL_image / SDL_ttf / SDL_mixer** 系サテライトライブラリを papimela の名前空間（`PaPiMeLa.Image` 等）に含めるか、別プロジェクトにするか。

---

## 8. モジュール分割と実装優先度・難易度テーブル（実装担当割り当て一覧表）

### 8.1 難易度の定義と担当モデルの対応

| 難易度 | 判断基準 | 想定担当 |
|---|---|---|
| **Low** | 単純な関数ラップの繰り返しが中心。本文書で API の形（クラス名・メソッド名・例外クラス・`SDLCheck` の使い方）が確定しており、C 層の関数を 1 対 1 で包むだけで完成する。状態管理・スレッド・コールバックを含まない、または含んでも本文書の 5.5 パターンをそのまま適用できる | qwen2.5-coder:14b（ローカル軽量モデル） |
| **Medium** | 設計判断が残る。所有権の扱い（親子、借用）、プロパティ vs メソッドの選別、コールバックの寿命管理、レコード/クラスの選択などをモジュール内で決める必要がある。C 層の複数関数をまとめて 1 つの Pascal API に再構成する | Claude Sonnet 5 |
| **High** | 複雑な状態管理、スレッド安全性、GPU / AsyncIO のような新パラダイム、クロスプラットフォームのネイティブハンドル、他モジュールの土台となる基盤（設計ミスの影響範囲が大きい）を含む | Claude Opus 5 |

優先度: **P0** = 他のすべての前提、**P1** = 2D ゲーム/アプリの最小構成、**P2** = 入力・音声・ファイル、**P3** = 高度機能、**P4** = オプション/プラットフォーム固有。

### 8.2 一覧表

| # | ユニット | 対応 SDL3 ヘッダ | 主要クラス/型 | 規模（目安） | 依存 | 優先度 | 難易度 | 担当 | 難易度の根拠・注意点 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `PaPiMeLa.Errors` | SDL_error.h | `ESDLError` 階層、`SDLCheck*` | 小 | C 層 | P0 | **Medium** | Sonnet | 階層は確定済みだが、`inline` と例外生成の分離、スレッドローカル `SDL_GetError` の扱い、`SDL_ClearError` を呼ぶタイミングの判断が必要。最初に書かれ全モジュールが依存する |
| 2 | `PaPiMeLa.Core` | SDL_init.h, SDL_version.h, SDL_stdinc.h(一部) | `TSDLObject`、`TSDLHandleObject<T>`、`TSDLOwnerObject`、`TSDL`、`TSDLHandleRegistry`、`SDLAlloc/SDLFree`、文字列変換 | 中 | 1 | P0 | **High** | Opus | 基底クラスの設計（親子ツリー、`OwnsHandle`、逆引き、スレッド安全な子リスト）は全モジュールの土台。ジェネリック基底のコンパイル可否確認も含む |
| 3 | `PaPiMeLa.Types` | SDL_rect.h, SDL_pixels.h(色), SDL_guid.h | `TSDLPoint/FPoint/Rect/FRect/Color/FColor/GUID` と演算子 | 中 | 1 | P0 | **Low** | qwen | 5.2 の表に演算子とメソッドが列挙済み。レイアウト静的アサートを忘れないこと。`SDL_GetRectIntersection` 等の呼び出しは単純 |
| 4 | `PaPiMeLa.Properties` | SDL_properties.h | `TSDLProperties` | 小 | 2 | P0 | **Medium** | Sonnet | 所有/借用の 2 コンストラクタ、`SetPointerWithCleanup` のサンク寿命、`Enumerate` コールバック、`Lock/Unlock` の設計判断 |
| 5 | `PaPiMeLa.Hints` | SDL_hints.h | `TSDLHints` | 小 | 2 | P0 | **Low** | qwen | 静的関数の 1 対 1 ラップ。ヒントコールバックは 5.5 パターンをそのまま適用 |
| 6 | `PaPiMeLa.Log` | SDL_log.h | `TSDLLog` | 小 | 2 | P0 | **Low** | qwen | 可変引数は `Format` で Pascal 側で整形してから `SDL_LogMessage` に渡す。出力関数フックは 5.5 パターン |
| 7 | `PaPiMeLa.Time` | SDL_timer.h, SDL_time.h | `TSDLTimer`、`TSDLTimerHandle`、`TSDLDateTime` | 小 | 2 | P0 | **Low** | qwen | ほぼ 1 対 1。タイマーコールバックは 5.5 パターン。`SDL_Time` ↔ `TDateTime` 変換は単純算術 |
| 8 | `PaPiMeLa.Pixels` | SDL_pixels.h | `TSDLPixelFormatDetails`、`TSDLPalette`、色空間ヘルパ | 小 | 3 | P1 | **Low** | qwen | `SDL_GetPixelFormatDetails` はライブラリ所有ポインタなので借用。`TSDLPalette` は所有クラス。`MapRGBA`/`GetRGBA` の引数が SDL3 で増えた点に注意 |
| 9 | `PaPiMeLa.Surface` | SDL_surface.h, SDL_blendmode.h | `TSDLSurface`、`ISDLSurface` | 中 | 3, 4, 8 | P1 | **Medium** | Sonnet | `SDL_Surface` はフィールドが公開構造体なので `Pixels/Pitch/Format` の露出方法、`Lock` 必須判定、`MUSTLOCK` マクロ再現、参照カウント opt-in（2.3）、Blit 系の多数のオーバーロード整理 |
| 10 | `PaPiMeLa.Video` (Window/Display 部) | SDL_video.h | `TSDLWindow`、`TSDLWindowBuilder`、`TSDLDisplay`、`TSDLDisplayMode` | 大 | 2, 3, 4, 9 | P1 | **Medium** | Sonnet | 関数数が非常に多い（100 超）が大半は 1 対 1。ヒットテストコールバック、`FromID` 逆引き、Display を record にする判断、ウィンドウイベント自己登録（4.3）が判断点 |
| 11 | `PaPiMeLa.Video` (ネイティブハンドル / GL / EGL 部) | SDL_video.h, SDL_egl.h, SDL_opengl*.h | `TSDLWindow.NativeHandles`、`TSDLGLContext`、`TSDLGL` | 中 | 10 | P3 | **High** | Opus | プラットフォームごとのプロパティ名（HWND / NSWindow / X11 Display+Window / Wayland surface / Android / UIKit）を型付きで提供。`{$ifdef}` 分岐とテスト困難性 |
| 12 | `PaPiMeLa.Render` | SDL_render.h | `TSDLRenderer`、`TSDLTexture`、`ISDLTexture`、`TSDLVertex` | 大 | 3, 4, 9, 10 | P1 | **Medium** | Sonnet | 親子所有（Renderer → Texture）、`Target` 借用、`QueryTexture` 廃止に伴うプロパティ経由の情報取得、`Lock/LockToSurface` の借用 Surface、`RenderGeometryRaw` のポインタ引数、`Try` 版の選定 |
| 13 | `PaPiMeLa.Events` (基盤部) | SDL_events.h | `TSDLEvent`、`TSDLEventQueue`、`TSDLEventDispatcher`、リスナーインターフェース宣言、ウォッチ/フィルタ | 大 | 2, 3 | P1 | **High** | Opus | 128 バイト共用体との完全レイアウト一致、ゼロアロケーション配信、`Supports` による型別リスナー検出、配信中の Add/Remove、ウォッチが別スレッドで呼ばれる問題、ウィンドウ別振り分け |
| 14 | `PaPiMeLa.Events` (イベントレコード群) | SDL_events.h | 40 種の `TSDLXxxEvent` レコードと計算プロパティ、`Dispatch` 内 `case` 分岐の各枝 | 中 | 13 | P1 | **Low** | qwen | 13 の骨格が固まった後の機械的作業。C 構造体 1 つにつきレコード 1 つ + Dispatcher の `case` 1 枝 + リスナーメソッド 1 つ。`SDL_Event` メンバ名（`key`、`motion`、`gaxis`…）に忠実に |
| 15 | `PaPiMeLa.App` | SDL_main.h | `TSDLApplication`、サンク 4 本 | 小 | 2, 13 | P1 | **High** | Opus | `SDL_EnterAppMainCallbacks` を Pascal から呼ぶ方式のプラットフォーム検証、古典ループとの二重実装、`SDL_Quit` の責務、`appstate` 経由の例外伝播 |
| 16 | `PaPiMeLa.Input.Keyboard` | SDL_keyboard.h, SDL_keycode.h, SDL_scancode.h | `TSDLKeyboard`、キー名変換 | 小 | 2, 10(ID のみ) | P1 | **Low** | qwen | 静的関数 1 対 1。`SDL_GetKeyboardState` の配列ビューは `PBoolean` + 長さで返す |
| 17 | `PaPiMeLa.Input.Mouse` | SDL_mouse.h | `TSDLMouse`、`TSDLCursor` | 小 | 2, 3, 9 | P1 | **Low** | qwen | `TSDLCursor` の所有/借用（システムカーソルは借用）は本文書で確定済み。座標は float |
| 18 | `PaPiMeLa.Input.Touch` | SDL_touch.h | `TSDLTouchDevice`、`TSDLFinger` | 小 | 2 | P2 | **Low** | qwen | 列挙関数の `SDL_free` 込みラップのみ |
| 19 | `PaPiMeLa.Input.Pen` | SDL_pen.h | 列挙・フラグ定義のみ | 極小 | 2 | P2 | **Low** | qwen | ヘッダはほぼ型定義。イベント側（14）で消費 |
| 20 | `PaPiMeLa.Joystick` | SDL_joystick.h | `TSDLJoystick`、`TSDLVirtualJoystick` | 大 | 2, 3, 4 | P2 | **Medium** | Sonnet | ID 配列列挙 + Open の二段構造、`FromID` 逆引き、`Rumble` の時間管理、仮想ジョイスティック（`SDL_VirtualJoystickDesc` の多数のコールバック）の設計 |
| 21 | `PaPiMeLa.Gamepad` | SDL_gamepad.h | `TSDLGamepad`、`TSDLGamepadMapping`、`TSDLGamepadBinding` | 大 | 20 | P2 | **Medium** | Sonnet | 方角ボタン列挙と `Label` の関係、`SDL_GetGamepadBindings` の `SDL_free` が必要なポインタ配列、センサー有効化状態、タッチパッド多重インデックス |
| 22 | `PaPiMeLa.Haptic` | SDL_haptic.h | `TSDLHaptic`、`TSDLHapticEffect` | 中 | 20 | P3 | **Low** | qwen | `SDL_HapticEffect` 共用体をレコードで再現し、`CreateEffect/UpdateEffect/RunEffect/DestroyEffect` を 1 対 1 で包む |
| 23 | `PaPiMeLa.Sensor` | SDL_sensor.h | `TSDLSensor` | 小 | 2 | P3 | **Low** | qwen | 関数 15 個程度、すべて 1 対 1 |
| 24 | `PaPiMeLa.Camera` | SDL_camera.h | `TSDLCamera`、`TSDLCameraSpec` | 中 | 2, 9 | P3 | **Medium** | Sonnet | 許可状態（Approved/Denied）の非同期性、`AcquireFrame` が返す借用 Surface とタイムスタンプ、フレーム列挙 API の形（未解決 9）、スペック配列の `SDL_free` |
| 25 | `PaPiMeLa.Audio` (デバイス/ストリーム部) | SDL_audio.h | `TSDLAudioDeviceInfo`、`TSDLAudioDevice`、`TSDLAudioStream`、`TSDLAudioSpec`、`TSDLWavData` | 大 | 2, 4 | P2 | **Medium** | Sonnet | 物理/論理デバイスの分離、`OpenAudioDeviceStream` 簡易パスと通常パスの共存、bind の非所有性、`SDL_malloc` された WAV バッファの所有 |
| 26 | `PaPiMeLa.Audio` (コールバック部) | SDL_audio.h | `SetGetCallback/SetPutCallback`、`SetPostmixCallback`、`TSDLAudioStream.Lock` | 小 | 25 | P2 | **High** | Opus | オーディオスレッドからの呼び出し、ストリームロックとの整合、コールバック内での例外遮断、ストリーム破棄とコールバック実行の競合（`Destroy` 中に呼ばれる可能性） |
| 27 | `PaPiMeLa.GPU` (列挙・構造体・CreateInfo) | SDL_gpu.h | 60 超の列挙、`SDL_GPU*CreateInfo`/`*Binding`/`*TargetInfo` レコードと `Default` 関数 | 大 | 3 | P3 | **Low** | qwen | 大量だが完全に機械的な translate + 既定値関数。レイアウト静的アサートを各レコードに付ける。ビルダは含めない |
| 28 | `PaPiMeLa.GPU` (デバイス・リソース) | SDL_gpu.h | `TSDLGPUDevice`、`TSDLGPUResource` と 8 派生、`ClaimWindow`、スワップチェーン設定 | 大 | 2, 4, 10, 27 | P3 | **High** | Opus | デバイスがすべてを所有するモデルと親子ツリーの整合、`Release` の順序制約、シェーダフォーマットの選択、`TransferBuffer.Map` の型付きビュー、`WaitForIdle` と破棄タイミング |
| 29 | `PaPiMeLa.GPU` (コマンドバッファ・パス) | SDL_gpu.h | `TSDLGPUCommandBuffer`、`TSDLGPURenderPass/CopyPass/ComputePass`、`TSDLGPUFence` | 中 | 28 | P3 | **High** | Opus | 値型レコードでのライフサイクル表現、スワップチェーンテクスチャの借用プール、`Submit` 後の使用禁止、`Begin/End` 対応のデバッグ検出、Push uniform のジェネリックメソッド、複数スレッドからの Acquire |
| 30 | `PaPiMeLa.IO` | SDL_iostream.h | `TSDLIOStream`、`TSDLIOStreamFromStream`、`TSDLStreamOverIO` | 中 | 2, 4 | P2 | **Medium** | Sonnet | `SDL_IOStreamInterface` の 5 コールバックで `TStream` を包む双方向アダプタ、`Seek` の `whence` 変換、`Close` の所有権（`TStream` を誰が解放するか）、型付き Read/Write の生成 |
| 31 | `PaPiMeLa.AsyncIO` | SDL_asyncio.h | `TSDLAsyncIO`、`TSDLAsyncIOQueue`、`TSDLAsyncIOOutcome` | 小〜中 | 2, 30 | P3 | **High** | Opus | 非同期完了モデル（Close も非同期）、複数スレッドからのキュー共有、`Outcome.Buffer` の所有（`LoadFileAsync` は `SDL_free` 必要）、`UserData` の Pascal オブジェクト寿命、`Destroy` 時に未完了タスクがある場合の扱い |
| 32 | `PaPiMeLa.Storage` | SDL_storage.h | `TSDLStorage`、`ISDLStorageBackend` | 中 | 2, 4, 30 | P2 | **Medium** | Sonnet | Title/User/File/Custom の 4 経路、`Ready` ポーリング、`EnumerateDirectory` コールバック、`SDL_StorageInterface` によるカスタム実装の抽象化 |
| 33 | `PaPiMeLa.FileSystem` | SDL_filesystem.h | `TSDLFileSystem`、`TSDLPathInfo` | 小 | 2 | P2 | **Low** | qwen | `PrefPath` は `SDL_free`、`BasePath` は不要、という所有の違いを本文書通りに実装。`Glob` の結果配列は `SDL_free` 1 回で解放 |
| 34 | `PaPiMeLa.Threading` | SDL_thread.h, SDL_mutex.h | `TSDLThread`、`TSDLMutex`、`TSDLRWLock`、`TSDLSemaphore`、`TSDLCondition`、`TSDLInitState`、`TSDLTLS` | 中 | 2 | P2 | **High** | Opus | スレッドエントリのサンクと例外遮断、`Wait/Detach` 後のハンドル無効化、RTL `TThread`/`cthreads` との共存、TLS デストラクタコールバック、Lock 系が `void` になった SDL3 の仕様に合わせた例外なし API |
| 35 | `PaPiMeLa.Atomic` | SDL_atomic.h | `TSDLAtomicInt`、`TSDLAtomicU32`、`TSDLAtomicPointer`、`TSDLSpinLock`、メモリバリア | 小 | C 層 | P2 | **Medium** | Sonnet | レコード内に `SDL_AtomicInt` を持つ設計でアラインメントを保証、`CompareAndSwap` の戻り値と `out` 引数の整理、`SDL_CompilerBarrier` 等マクロの再現可否判断 |
| 36 | `PaPiMeLa.Dialog` | SDL_dialog.h | `TSDLFileDialog`、`TSDLDialogFileFilter` | 小 | 2, 4, 10(ID) | P3 | **Medium** | Sonnet | 結果コールバックの非同期性、`filelist` が `nil`（キャンセル）/ 空（エラー）の区別、フィルタ配列の寿命（コールバックまで保持が必要）、プロパティ版の統合 |
| 37 | `PaPiMeLa.MessageBox` | SDL_messagebox.h | `TSDLMessageBox`、ボタン/色スキームレコード | 小 | 2, 10(ID) | P1 | **Low** | qwen | 構造体組み立てと 2 関数のラップ。ボタン配列の `PChar` 寿命だけ注意 |
| 38 | `PaPiMeLa.Tray` | SDL_tray.h | `TSDLTray`、`TSDLTrayMenu`、`TSDLTrayEntry` | 中 | 2, 9 | P3 | **Medium** | Sonnet | 三層の所有ツリー（SDL 側がまとめて破棄する）とラッパーの親子整合、エントリコールバックの寿命、チェック/サブメニュー状態、`SDL_UpdateTrays` の要否 **[要検証]** |
| 39 | `PaPiMeLa.Process` | SDL_process.h | `TSDLProcess` | 小 | 2, 4, 30 | P3 | **Medium** | Sonnet | stdio 3 本の `IOStream` 借用、`ReadAll` の `SDL_free`、`Wait` のブロッキング/非ブロッキング、環境変数（`SDL_Environment`）の扱い |
| 40 | `PaPiMeLa.System` | SDL_power.h, SDL_locale.h, SDL_clipboard.h, SDL_cpuinfo.h, SDL_platform.h, SDL_misc.h | `TSDLPower`、`TSDLLocale`、`TSDLClipboard`、`TSDLCPUInfo`、`TSDLPlatform`、`OpenURL` | 小 | 2 | P2 | **Low** | qwen | 各ヘッダ数関数〜十数関数。`SDL_free` が必要な戻り（クリップボード文字列、ロケール配列）に注意。クリップボードのデータプロバイダコールバックは 5.5 パターン |
| 41 | `PaPiMeLa.System` (`SDL_system.h` 部) | SDL_system.h | `TSDLSystem`（Android JNI、iOS、Windows メッセージフック、X11 イベントフック、GDK 等） | 中 | 2 | P4 | **High** | Opus | プラットフォームごとの `{$ifdef}`、ネイティブ型（`JNIEnv`、`HWND`、`XEvent`）の前方宣言、メッセージフックコールバック、テストが実機依存 |
| 42 | `PaPiMeLa.LoadSO` | SDL_loadso.h | `TSDLSharedObject` | 極小 | 2 | P2 | **Low** | qwen | 3 関数 |
| 43 | `PaPiMeLa.Notification` | SDL_notification.h | `TSDLNotification`、`TSDLNotificationAction` | 小 | 2, 4, 9 | P4 | **Low** | qwen | **[要検証: SDL 3.6.0 新規]** 4 関数のラップ + プロパティ版。ランタイムバージョンチェックで `ESDLNotSupported` |
| 44 | `PaPiMeLa.Graphics.Vulkan` / `.Metal` | SDL_vulkan.h, SDL_metal.h | `TSDLVulkan`（インスタンス拡張列挙、サーフェス作成）、`TSDLMetalView` | 小 | 10 | P4 | **High** | Opus | Vulkan ヘッダ型（`VkInstance` 等）を papimela が定義するか外部バインディングに委ねるかの判断、Metal は macOS/iOS のみ、テスト困難 |
| 45 | `PaPiMeLa` (アンブレラ) | — | 型エイリアス再エクスポート | 小 | 全部 | P1 | **Low** | qwen | 各ユニットの public 型を `type TSDLWindow = PaPiMeLa.Video.TSDLWindow;` の形で並べるだけ。最後に実施 |

### 8.3 内訳サマリ

| 難易度 | モジュール数 | 担当 | 該当 # |
|---|---|---|---|
| Low | 19 | qwen2.5-coder:14b | 3, 5, 6, 7, 8, 14, 16, 17, 18, 19, 22, 23, 27, 33, 37, 40, 42, 43, 45 |
| Medium | 15 | Claude Sonnet 5 | 1, 4, 9, 10, 12, 20, 21, 24, 25, 30, 32, 35, 36, 38, 39 |
| High | 11 | Claude Opus 5 | 2, 11, 13, 15, 26, 28, 29, 31, 34, 41, 44 |

（合計 45 行。`Video`/`Events`/`Audio`/`GPU`/`System` は難易度の異なる部分に分割して複数行に分けているため、ユニット数としては 38 前後になる。）

### 8.4 推奨実装順序

```
フェーズ 0（基盤）:     #1 Errors → #2 Core → #3 Types → #4 Properties → #5 Hints → #6 Log → #7 Time
フェーズ 1（2D 最小）:  #13 Events 基盤 → #14 Events レコード → #8 Pixels → #9 Surface → #10 Video → #12 Render
                        → #16 Keyboard → #17 Mouse → #37 MessageBox → #15 App → #45 アンブレラ（初版）
フェーズ 2（入力・音・IO）: #35 Atomic → #34 Threading → #30 IO → #33 FileSystem → #40 System
                        → #20 Joystick → #21 Gamepad → #25 Audio → #26 Audio コールバック → #32 Storage
                        → #18 Touch → #19 Pen → #42 LoadSO
フェーズ 3（高度機能）:  #27 GPU 構造体 → #28 GPU デバイス → #29 GPU コマンド → #31 AsyncIO
                        → #24 Camera → #22 Haptic → #23 Sensor → #36 Dialog → #38 Tray → #39 Process → #11 Video ネイティブ
フェーズ 4（オプション）: #41 System 固有 → #44 Vulkan/Metal → #43 Notification
```

- Low 難易度モジュールは、依存先（Core/Errors/Types）が完成し、かつ「同じ形の Medium/High モジュールが 1 つ実装済みでお手本として参照できる」状態になってから着手させると、ローカルモデルの成功率が上がる。特に #14（イベントレコード群）は #13 の骨格に、#27（GPU 構造体）は #3（Types）のレイアウトアサート方式に、それぞれ倣わせる。
- 各 Low モジュールには、着手前に本文書の該当行と 5.5（サンク）・3.3（`SDLCheck`）・2.6（`SDL_free`）の 3 節を必読として渡す。
