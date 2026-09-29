# イベントモデル

Design: `docs/DESIGN.md` §6 — 正は英語版 [`event-model.md`](event-model.md)

**実装済みの型だけを描いてある。**

---

## 1. 何を解決しているか

SDL はイベント構造体の中に `const char *text` を持ち、後から `SDL_PollEvent` の内部
（`SDL_CleanupEvent`）で解放している。動くには動くが、寿命の規約が型ではなく
ポーリング関数の側にある。

papimela は C との共用体互換が不要なので、`TPMLEvent` は**管理型フィールドを可変部の前に
置いた**素のレコードにした。FPC は可変部（`case`）の中に管理型を置けないが、その前になら置ける。
これで参照カウントがテキスト・文節配列・候補一覧の寿命を引き受け、リングバッファの上書きで
自動的に解放される。

`SizeOf(TPMLEvent)` は x86_64 で**72 バイト**（実測。`test/test_fcitx_textinput` が毎回報告する）。
キーイベントとウィンドウイベントはヒープ確保が発生しない。

---

## 2. 構造

```mermaid
classDiagram
    class TPMLEvent {
        +Kind TPMLEventKind
        +Timestamp UInt64
        +WindowID TPMLWindowID
        +Text String
        +Segments TPMLCompositionSegments
        +Strings TPMLStringArray
        +Key TPMLKeyEventData
        +Edit TPMLTextEditingData
        +DeleteSurrounding TPMLDeleteSurroundingData
        +Window TPMLWindowEventData
        +UserData TPMLUserEventData
    }
    class TPMLKeyEventData {
        +Keysym LongWord
        +Keycode LongWord
        +Modifiers TPMLKeyModifiers
        +IsRepeat Boolean
        +KeyboardID LongWord
    }
    class TPMLTextEditingData {
        +CursorByte Integer
        +CursorChar Integer
        +SelectionStartChar Integer
        +SelectionLengthChars Integer
        +FocusedSegment Integer
        +SegmentsReliable Boolean
    }
    class TPMLDeleteSurroundingData {
        +BeforeBytes Integer
        +AfterBytes Integer
        +BeforeChars Integer
        +AfterChars Integer
    }
    class TPMLWindowEventData {
        +Data1 Int32
        +Data2 Int32
    }
    class TPMLUserEventData {
        +Code Int32
        +Data1 Pointer
        +Data2 Pointer
    }

    TPMLEvent *-- TPMLKeyEventData : variant 0
    TPMLEvent *-- TPMLTextEditingData : variant 1
    TPMLEvent *-- TPMLDeleteSurroundingData : variant 2
    TPMLEvent *-- TPMLWindowEventData : variant 3
    TPMLEvent *-- TPMLUserEventData : variant 4
```

先頭 6 フィールドは全イベント共通、残り 5 つは記憶域を共有する選択肢である。
`TPMLEventKind` は現在 85 個あるが、ペイロードの形は上の 5 種類しかない。
各サブシステムが実装されるにつれて可変部が増えるが、**可変部への追加は既存コードに影響しない**。

---

## 3. キューと協調相手

```mermaid
classDiagram
    class TPMLEventQueue {
        +Poll()
        +Wait()
        +WaitTimeout()
        +Pump()
        +Push()
        +PushSimple()
        +Peek()
        +Flush()
        +FlushAll()
        +RegisterUserEvents()
        +RegisterPumpSource()
        +UnregisterPumpSource()
        +AddWatch()
        +RemoveWatch()
        +WakeUp()
        +Enabled
        +PendingCount
        +DroppedCount
    }
    class IPMLEventPumpSource {
        <<interface>>
        +PumpSourceName()
        +PumpEvents()
    }
    class IPMLEventWatch {
        <<interface>>
        +OnEventPushed()
    }
    class TPMLVideoSystem
    class TPMLTextInputSystem
    class TPMLContext

    TPMLContext *-- TPMLEventQueue : owns
    TPMLEventQueue o-- IPMLEventPumpSource : pumps in registration order
    TPMLEventQueue o-- IPMLEventWatch : filters on push
    IPMLEventPumpSource <|.. TPMLVideoSystem
    IPMLEventPumpSource <|.. TPMLTextInputSystem
    TPMLVideoSystem ..> TPMLEventQueue : Push
    TPMLTextInputSystem ..> TPMLEventQueue : Push
```

**規約。**

- `Push` は任意のスレッドから呼べる。リングが満杯なら最古のイベントを捨て、`DroppedCount` が
  増える。テストはこれが 0 のままであることを検査している。
- `Poll` と `Wait` はメインスレッド専用（`CheckMainThread`）。
- `Pump` は登録されたソースを登録順にたどるが、タイムアウト分ブロックしてよいのは
  **最初のソースだけ**である。両方が揃った時点でビデオバックエンドを IME より先に
  登録すべきなのはこのため。ファイルディスクリプタで待てる側を先頭に置く。
- `IPMLEventWatch.OnEventPushed` は Push したスレッドで実行され、`False` を返すとイベントを落とす。

---

## 4. 既知の未整備

| 項目 | 状態 |
|---|---|
| 複数 fd をまとめた `poll(2)` | 未実装。現状 fd を出すのは D-Bus と Wayland だけで各自が待っている。§6.3 はこれで足りなくなった時点で 1 つの poll セットに統合することを求めている |
| `eventfd` による `WakeUp` | 現在は待ちループが見るフラグ |
| 排他 | `SyncObjs.TCriticalSection`。`PaPiMeLa.Threading`（#8）ができたら `TPMLMutex` へ移す |
| `TPMLKeyboardState` / `TPMLMouseState` / `TPMLTouchState` | 未実装。シート（#37）と同時に入る |
| nil の管理型に対する `Finalize` コスト測定 | サイズは実測済み。ベンチマークは未実施（§10 項目 9） |
