{
  PaPiMeLa.Platform.XKB — libxkbcommon の実行時結合

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §11 #37

  WHAT:
    Wayland のコンポジタが送ってくるキーマップ（XKB テキスト形式）を解釈し、
    キーコードからキーシムと UTF-8 文字列を得る。修飾キーの状態も追う。

  WHY:
    Wayland はキーコードしか送らない。キーシムも文字も、クライアントが
    キーマップを解釈して自分で求める。この変換を持たないと「A キーが押された」
    までしか分からず、IME にも渡せない。

  RESOLVED:
    - Wayland のキーコードは evdev 値。XKB は evdev + 8 を要求するので変換する
    - キーマップは fd で渡ってくる。mmap してヌル終端文字列として読む

  NOT RESOLVED:
    - コンポーズキー（xkb_compose_*）は未対応
    - キーマップのレイアウト切替（group）は update_mask に渡してはいるが、
      複数レイアウトの検証はしていない

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.XKB;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

const
  XKB_KEYMAP_FORMAT_TEXT_V1 = 1;

  // xkb_state_component
  XKB_STATE_MODS_DEPRESSED = 1 shl 0;
  XKB_STATE_MODS_LATCHED   = 1 shl 1;
  XKB_STATE_MODS_LOCKED    = 1 shl 2;
  XKB_STATE_MODS_EFFECTIVE = 1 shl 3;

  // Wayland のキーコードは evdev 値。XKB は evdev + 8 を使う。
  XKB_EVDEV_OFFSET = 8;

  // よく使うキーシム（X11 keysymdef.h より）
  XKB_KEY_BackSpace = $FF08;
  XKB_KEY_Tab       = $FF09;
  XKB_KEY_Return    = $FF0D;
  XKB_KEY_Escape    = $FF1B;
  XKB_KEY_Delete    = $FFFF;
  XKB_KEY_Home      = $FF50;
  XKB_KEY_Left      = $FF51;
  XKB_KEY_Up        = $FF52;
  XKB_KEY_Right     = $FF53;
  XKB_KEY_Down      = $FF54;
  XKB_KEY_End       = $FF57;
  XKB_KEY_space     = $0020;

type
  Pxkb_context = Pointer;
  Pxkb_keymap  = Pointer;
  Pxkb_state   = Pointer;
  xkb_keysym_t = LongWord;

  { キーマップと状態をまとめて持つ。1 つのシートに 1 つ。 }
  TPMLXKBState = class
  strict private
    FKeymap  : Pxkb_keymap;
    FState   : Pxkb_state;
    FModShift, FModCtrl, FModAlt, FModSuper, FModCaps, FModNum: LongWord;
    procedure LookupModIndices;
    function  GetLoaded: Boolean;
  public
    destructor Destroy; override;

    // コンポジタから受け取ったキーマップ文字列を読み込む。失敗なら False。
    function LoadKeymap(const AText: String): Boolean;
    procedure UpdateMask(ADepressed, ALatched, ALocked, AGroup: LongWord);

    // AEvdevCode は Wayland がそのまま送ってくる値（+8 は内部で行う）。
    function KeysymOf(AEvdevCode: LongWord): xkb_keysym_t;
    function TextOf(AEvdevCode: LongWord): String;
    function Repeats(AEvdevCode: LongWord): Boolean;
    function Modifiers: TPMLKeyModifiers;

    property Loaded: Boolean read GetLoaded;
  end;

function PMLXKBLoad: Boolean;
procedure PMLXKBUnload;

implementation

const
  LIBXKB_NAMES: array[0..1] of String = ('libxkbcommon.so.0', 'libxkbcommon.so');

var
  GLib     : TPMLDynLib = nil;
  GRefCount: Integer = 0;
  GContext : Pxkb_context = nil;

  xkb_context_new   : function(flags: LongWord): Pxkb_context; cdecl = nil;
  xkb_context_unref : procedure(ctx: Pxkb_context); cdecl = nil;
  xkb_keymap_new_from_string: function(ctx: Pxkb_context; s: PAnsiChar;
    format: LongWord; flags: LongWord): Pxkb_keymap; cdecl = nil;
  xkb_keymap_unref  : procedure(keymap: Pxkb_keymap); cdecl = nil;
  xkb_keymap_key_repeats: function(keymap: Pxkb_keymap; key: LongWord): LongInt; cdecl = nil;
  xkb_keymap_mod_get_index: function(keymap: Pxkb_keymap; name: PAnsiChar): LongWord; cdecl = nil;
  xkb_state_new     : function(keymap: Pxkb_keymap): Pxkb_state; cdecl = nil;
  xkb_state_unref   : procedure(state: Pxkb_state); cdecl = nil;
  xkb_state_update_mask: function(state: Pxkb_state;
    depressed, latched, locked, depressed_layout, latched_layout, locked_layout: LongWord): LongWord; cdecl = nil;
  xkb_state_key_get_one_sym: function(state: Pxkb_state; key: LongWord): xkb_keysym_t; cdecl = nil;
  xkb_state_key_get_utf8: function(state: Pxkb_state; key: LongWord;
    buffer: PAnsiChar; size: PtrUInt): LongInt; cdecl = nil;
  xkb_state_mod_index_is_active: function(state: Pxkb_state; idx: LongWord;
    componentType: LongWord): LongInt; cdecl = nil;

procedure Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := GLib.Resolve(ASymbol);
end;

function PMLXKBLoad: Boolean;
begin
  if GRefCount > 0 then
  begin
    Inc(GRefCount);
    Exit(True);
  end;
  try
    GLib := TPMLDynLib.Create(LIBXKB_NAMES);
  except
    on E: EPMLPlatformLibrary do
    begin
      GLib := nil;
      Exit(False);
    end;
  end;

  Bind(xkb_context_new,            'xkb_context_new');
  Bind(xkb_context_unref,          'xkb_context_unref');
  Bind(xkb_keymap_new_from_string, 'xkb_keymap_new_from_string');
  Bind(xkb_keymap_unref,           'xkb_keymap_unref');
  Bind(xkb_keymap_key_repeats,     'xkb_keymap_key_repeats');
  Bind(xkb_keymap_mod_get_index,   'xkb_keymap_mod_get_index');
  Bind(xkb_state_new,              'xkb_state_new');
  Bind(xkb_state_unref,            'xkb_state_unref');
  Bind(xkb_state_update_mask,      'xkb_state_update_mask');
  Bind(xkb_state_key_get_one_sym,  'xkb_state_key_get_one_sym');
  Bind(xkb_state_key_get_utf8,     'xkb_state_key_get_utf8');
  Bind(xkb_state_mod_index_is_active, 'xkb_state_mod_index_is_active');

  GContext := xkb_context_new(0);
  if GContext = nil then
  begin
    FreeAndNil(GLib);
    Exit(False);
  end;
  GRefCount := 1;
  Result := True;
end;

procedure PMLXKBUnload;
begin
  if GRefCount = 0 then
    Exit;
  Dec(GRefCount);
  if GRefCount > 0 then
    Exit;
  if GContext <> nil then
  begin
    xkb_context_unref(GContext);
    GContext := nil;
  end;
  FreeAndNil(GLib);
end;

{ TPMLXKBState }

destructor TPMLXKBState.Destroy;
begin
  if FState <> nil then
    xkb_state_unref(FState);
  if FKeymap <> nil then
    xkb_keymap_unref(FKeymap);
  inherited Destroy;
end;

function TPMLXKBState.GetLoaded: Boolean;
begin
  Result := (FKeymap <> nil) and (FState <> nil);
end;

procedure TPMLXKBState.LookupModIndices;
begin
  FModShift := xkb_keymap_mod_get_index(FKeymap, 'Shift');
  FModCtrl  := xkb_keymap_mod_get_index(FKeymap, 'Control');
  FModAlt   := xkb_keymap_mod_get_index(FKeymap, 'Mod1');
  FModSuper := xkb_keymap_mod_get_index(FKeymap, 'Mod4');
  FModCaps  := xkb_keymap_mod_get_index(FKeymap, 'Lock');
  FModNum   := xkb_keymap_mod_get_index(FKeymap, 'Mod2');
end;

function TPMLXKBState.LoadKeymap(const AText: String): Boolean;
var
  NewKeymap: Pxkb_keymap;
  NewState : Pxkb_state;
begin
  Result := False;
  if GContext = nil then
    Exit;
  NewKeymap := xkb_keymap_new_from_string(GContext, PAnsiChar(AText),
    XKB_KEYMAP_FORMAT_TEXT_V1, 0);
  if NewKeymap = nil then
    Exit;
  NewState := xkb_state_new(NewKeymap);
  if NewState = nil then
  begin
    xkb_keymap_unref(NewKeymap);
    Exit;
  end;

  if FState <> nil then
    xkb_state_unref(FState);
  if FKeymap <> nil then
    xkb_keymap_unref(FKeymap);
  FKeymap := NewKeymap;
  FState := NewState;
  LookupModIndices;
  Result := True;
end;

procedure TPMLXKBState.UpdateMask(ADepressed, ALatched, ALocked, AGroup: LongWord);
begin
  if FState = nil then
    Exit;
  xkb_state_update_mask(FState, ADepressed, ALatched, ALocked, 0, 0, AGroup);
end;

function TPMLXKBState.KeysymOf(AEvdevCode: LongWord): xkb_keysym_t;
begin
  if FState = nil then
    Exit(0);
  Result := xkb_state_key_get_one_sym(FState, AEvdevCode + XKB_EVDEV_OFFSET);
end;

function TPMLXKBState.TextOf(AEvdevCode: LongWord): String;
var
  Buf: array[0..63] of AnsiChar;
  N  : LongInt;
begin
  Result := '';
  if FState = nil then
    Exit;
  N := xkb_state_key_get_utf8(FState, AEvdevCode + XKB_EVDEV_OFFSET,
    @Buf[0], SizeOf(Buf));
  if N <= 0 then
    Exit;
  if N > SizeOf(Buf) - 1 then
    N := SizeOf(Buf) - 1;
  SetString(Result, PAnsiChar(@Buf[0]), N);
end;

function TPMLXKBState.Repeats(AEvdevCode: LongWord): Boolean;
begin
  if FKeymap = nil then
    Exit(False);
  Result := xkb_keymap_key_repeats(FKeymap, AEvdevCode + XKB_EVDEV_OFFSET) <> 0;
end;

function TPMLXKBState.Modifiers: TPMLKeyModifiers;

  function Active(AIndex: LongWord): Boolean;
  begin
    Result := (AIndex <> LongWord(-1))
      and (xkb_state_mod_index_is_active(FState, AIndex, XKB_STATE_MODS_EFFECTIVE) > 0);
  end;

begin
  Result := [];
  if FState = nil then
    Exit;
  if Active(FModShift) then Include(Result, TPMLKeyModifier.Shift);
  if Active(FModCtrl)  then Include(Result, TPMLKeyModifier.Ctrl);
  if Active(FModAlt)   then Include(Result, TPMLKeyModifier.Alt);
  if Active(FModSuper) then Include(Result, TPMLKeyModifier.Super);
  if Active(FModCaps)  then Include(Result, TPMLKeyModifier.CapsLock);
  if Active(FModNum)   then Include(Result, TPMLKeyModifier.NumLock);
end;

end.
