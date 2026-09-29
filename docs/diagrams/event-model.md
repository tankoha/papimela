# Event Model

Design: `docs/DESIGN.md` §6 — Japanese version: [`event-model_jp.md`](event-model_jp.md)

**Only implemented types are drawn.**

---

## 1. The problem this solves

SDL stores a `const char *text` inside the event struct and frees it later from inside
`SDL_PollEvent` (`SDL_CleanupEvent`). That works, but the lifetime rule lives in the polling
function rather than in the type.

Since papimela needs no C union compatibility, `TPMLEvent` is a plain record with **managed
fields in front of the variant part**. FPC cannot place managed types inside a `case`, but it can
place them before it. Ref-counting then handles text, clause arrays and candidate lists; ring
buffer overwrite releases them automatically.

`SizeOf(TPMLEvent)` is **72 bytes** on x86_64 (measured; `test/test_fcitx_textinput` reports it on
every run). Key and window events allocate nothing.

---

## 2. Structure

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

The first six fields are common to every event; the last five are alternatives sharing storage.
`TPMLEventKind` currently has 85 members, but only the five payload shapes above exist — the rest
of the subsystems will add variants as they land, and adding a variant does not disturb existing
code.

---

## 3. Queue and its collaborators

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
    class IPMLKeyFilter {
        <<interface>>
        +KeyFilterActive()
        +FilterKey()
    }
    class TPMLKeyboardState {
        +SendKey()
        +SendModifiers()
        +SendFocus()
        +Modifiers
        +FocusedWindow
        +ConsumedCount
    }
    class TPMLMouseState {
        +SendMotion()
        +SendButton()
        +SendWheel()
        +SendFocus()
        +ButtonState
    }
    class TPMLVideoSystem
    class TPMLTextInputSystem
    class TPMLContext
    class TPMLWaylandSeat

    TPMLContext *-- TPMLEventQueue : owns
    TPMLEventQueue *-- TPMLKeyboardState : owns
    TPMLEventQueue *-- TPMLMouseState : owns
    TPMLEventQueue o-- IPMLEventPumpSource : pumps in registration order
    TPMLEventQueue o-- IPMLEventWatch : filters on push
    TPMLEventQueue o-- IPMLKeyFilter : routes keys to the IME
    IPMLEventPumpSource <|.. TPMLVideoSystem
    IPMLEventPumpSource <|.. TPMLTextInputSystem
    IPMLKeyFilter <|.. TPMLTextInputSystem
    TPMLWaylandSeat ..> TPMLKeyboardState : SendKey
    TPMLWaylandSeat ..> TPMLMouseState : SendMotion
    TPMLKeyboardState ..> IPMLKeyFilter : asks first
    TPMLKeyboardState ..> TPMLEventQueue : Push
    TPMLVideoSystem ..> TPMLEventQueue : Push
    TPMLTextInputSystem ..> TPMLEventQueue : Push
```

**The key path (§7.5).** A backend never calls `Push` for keys. `TPMLWaylandSeat` hands every key —
press *and* release, modifiers included — to `TPMLKeyboardState.SendKey`, which asks the IME first.
If the IME answers `Consumed`, no `KeyDown` and no `TextInput` is emitted at all; the text will
arrive later as `TextEditing` / `TextInput` from the IME's own path. If it answers `PassThrough`,
the key becomes a normal `KeyDown`, plus a `TextInput` when xkb produced printable text.
`Deferred` (awaiting an async IME reply) is defined but no backend returns it yet.

**Rules.**

- `Push` is callable from any thread. When the ring is full the oldest event is dropped and
  `DroppedCount` increments — tests assert it stays at zero.
- `Poll` and `Wait` are main-thread only (`CheckMainThread`).
- `Pump` walks every registered source in registration order, and only the **first** source is
  allowed to block for the timeout. That is why the video backend must be registered before the
  IME backend once both exist: the one that can wait on a file descriptor should go first.
- `IPMLEventWatch.OnEventPushed` runs on the pushing thread and can drop the event by returning
  `False`.

---

## 4. Known gaps

| Item | State |
|---|---|
| unified `poll(2)` over several file descriptors | not built. Only D-Bus and Wayland contribute descriptors today and each waits on its own; §6.3 wants one `poll` set once that stops being enough |
| `WakeUp` via `eventfd` | currently a flag checked by the wait loop |
| mutex | `SyncObjs.TCriticalSection`; will move to `TPMLMutex` when `PaPiMeLa.Threading` (#8) exists |
| `TPMLKeyboardState` / `TPMLMouseState` / `TPMLTouchState` | not implemented; they arrive with seats (#37) |
| `Finalize` cost measurement for nil managed fields | size measured, benchmark not run (§10 item 9) |
