# examples

papimela の公開 API だけで書いたサンプル。

| サンプル | 内容 |
|---|---|
| [`pong.pas`](pong.pas) | Pong。1 人用（右はコンピュータ）と 2 人対戦。ウィンドウの大きさを変えると縦横比を保って拡大縮小する |

```bash
fpc -O1 -Fisrc -Fusrc -Fusrc/generated -FUlib -oexamples/pong examples/pong.pas
./examples/pong              # 遊ぶ（Wayland セッションが要る）
./examples/pong --selftest   # 表示サーバ無しで自己検査（CI が走らせる）
```

操作: W / S または ↑ / ↓ で左のパドル、2 で 2 人対戦（右は ↑ / ↓）、P で一時停止、
勝負がついたら Space で再開、Escape で終了。7 点先取。

## 書いてみて足りなかったもの

サンプルを書く目的は、ライブラリの中からは見えない不足を使う側から見つけることにある。
Pong 1 本で見つかったものを、影響の大きい順に並べる。**F-1〜F-3 は解決済み**で、
`pong.pas` も新しい API に書き換えた。残りの回避策は `pong.pas` の中にある。

| # | 足りないもの | Pong での回避策 | SDL での相当 | 担当（第 11 章） |
|---|---|---|---|---|
| F-1 | **キーの押下状態を問い合わせる API** | KeyDown / KeyUp から自分で組み立てる。フォーカスを失うと KeyUp が来ないので、WindowFocusLost で全部離す処理も自分で書く | `SDL_GetKeyboardState` | **解決済み**: `Ctx.Events.Keyboard.IsDown[TPMLScancode.W]`。フォーカスを失うと押されているキーを全部 KeyUp にしてから WindowFocusLost を積む（SDL と同じ） |
| F-2 | **スキャンコード**（キーの物理的な位置） | キーシムで判定している。キーシムは配列に従うので、AZERTY では W / S の位置が変わる。さらに `w` と `W` が別のキーシムなので両方書く（D-27 と同じ罠を、アプリを書く側が毎回踏む） | `SDL_Scancode` | **解決済み**: `Ev.Key.Scancode`（位置）と `Ev.Key.Key`（今の配列での意味。修飾なしなので `w` だけ見ればよい）。AZERTY でも W / S の位置で動く |
| F-3 | **アプリ向けのキー定数** | `XKB_KEY_Up` などをプラットフォーム層の `PaPiMeLa.Platform.XKB` から取っている。アプリがプラットフォームのユニットを `uses` しないと矢印キーも書けない | `SDLK_UP` など | **解決済み**: `PaPiMeLa.Keycodes`（`TPMLScancode.*`、`PMLK_*`。SDL と同じ値）。キーの名前は `TPMLScancode.UP.Name`、`PMLK_W.Name` |
| F-4 | **論理解像度**（LogicalPresentation） | 盤面 640x400 をウィンドウに収める倍率と余白を毎フレーム自分で計算し、全部の矩形を変換してから描く。検査でも同じ変換を使う | `SDL_SetRenderLogicalPresentation` | #41 Render の NOT RESOLVED |
| F-5 | **文字を描く API** | 得点を 7 セグメントの矩形で描いている | `SDL_RenderDebugText` | #41 Render の NOT RESOLVED |
| F-6 | **待つ API**（Delay） | VSync が効けば Present が待つので困らない。効かない環境ではループが CPU を使い切る | `SDL_Delay`、`SDL_DelayNS` | Timer（NOT RESOLVED に「TicksNS のみ」とある） |
| F-7 | `TPMLContextOptions` を呼び出し側が解放すること | `try` / `finally` で解放する。**papimela 自身のテスト 2 本（`test_dummy_video`、`test_render_window`）も解放し忘れていた**（今回あわせて直した） | 相当なし（SDL はプロパティ ID） | Core。値型（record）にすれば解放が要らなくなる |
| F-8 | 音 | 鳴らしていない | `SDL_OpenAudioDeviceStream` など | Audio（未着手） |

逆に、困らなかったもの:

- **ウィンドウへ描くレンダラ**。`CreateForWindow` の 1 行で描けて、ウィンドウの大きさを
  変えても何もしなくてよい。レンダラの解放も要らない（ウィンドウと一緒に消える）
- **半透明の合成**。`BlendMode := Blend` だけで、球の周りの光と一時停止の暗幕が描けた
- **ヘッドレスでの検査**。盤面の計算（`TPongGame`）を描画と入力から切り離し、ダミーの
  ビデオバックエンドで描いた画素を `ReadPixels` で読めば、ゲームの見た目まで CI で見られる
- **継承による差し替え**。パドルを動かすもの（`TController`）をキーボードとコンピュータの
  2 つの派生で書き、2 キーで入れ替えている。**やっぱり継承は必要では？**
