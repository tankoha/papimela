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
    - papimela のキーマップ（TPMLKeymap）はここで作る。押されている修飾に
      左右されないよう、本物とは別の作業用の状態で「修飾なし」と「Shift」の段を引く

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
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Keycodes,
  PaPiMeLa.Events.Keymap;

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

  // struct xkb_rule_names。配列を名前で指定してキーマップを作る（検査用）。
  Txkb_rule_names = record
    rules, model, layout, variant, options: PAnsiChar;
  end;
  Pxkb_rule_names = ^Txkb_rule_names;

  { キーマップと状態をまとめて持つ。1 つのシートに 1 つ。 }
  TPMLXKBState = class
  strict private
    FKeymap  : Pxkb_keymap;
    FState   : Pxkb_state;
    FScratch : Pxkb_state;     // キーマップ作成用。修飾を自由に設定して段を引く
    FGroup   : LongWord;
    FModShift, FModCtrl, FModAlt, FModSuper, FModCaps, FModNum: LongWord;
    procedure LookupModIndices;
    function  GetLoaded: Boolean;
    function  Install(ANewKeymap: Pxkb_keymap): Boolean;
  public
    destructor Destroy; override;

    // コンポジタから受け取ったキーマップ文字列を読み込む。失敗なら False。
    function LoadKeymap(const AText: String): Boolean;
    // 配列を名前で指定して読み込む（"fr"、"de" など）。コンポジタ無しで配列ごとの
    // 振る舞いを検査するために使う。xkeyboard-config が無ければ False。
    function LoadKeymapFromNames(const ALayout: String; const AVariant: String = ''): Boolean;
    procedure UpdateMask(ADepressed, ALatched, ALocked, AGroup: LongWord);

    // AEvdevCode は Wayland がそのまま送ってくる値（+8 は内部で行う）。
    function KeysymOf(AEvdevCode: LongWord): xkb_keysym_t;
    function TextOf(AEvdevCode: LongWord): String;
    function Repeats(AEvdevCode: LongWord): Boolean;
    function Modifiers: TPMLKeyModifiers;

    // 今の配列（Group）で、修飾なし（AShifted = False）または Shift のときのキーシム。
    // 押されている修飾キーには左右されない。
    function KeysymAtLevel(AEvdevCode: LongWord; AShifted: Boolean): xkb_keysym_t;
    // 今の配列から papimela のキーマップを作る。呼び出し側が所有する。
    function BuildKeymap: TPMLKeymap;

    property Loaded: Boolean read GetLoaded;
    property Group : LongWord read FGroup;
  end;

function PMLXKBLoad: Boolean;
procedure PMLXKBUnload;

implementation

uses
  PaPiMeLa.Keycodes.Tables;

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
  xkb_keymap_new_from_names: function(ctx: Pxkb_context; names: Pxkb_rule_names;
    flags: LongWord): Pxkb_keymap; cdecl = nil;
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
  Bind(xkb_keymap_new_from_names,  'xkb_keymap_new_from_names');
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
  if FScratch <> nil then
    xkb_state_unref(FScratch);
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

{ 新しいキーマップを据える。状態を 2 つ（本物と作業用）作れなければ何も変えない。 }
function TPMLXKBState.Install(ANewKeymap: Pxkb_keymap): Boolean;
var
  NewState, NewScratch: Pxkb_state;
begin
  Result := False;
  if ANewKeymap = nil then
    Exit;
  NewState := xkb_state_new(ANewKeymap);
  NewScratch := xkb_state_new(ANewKeymap);
  if (NewState = nil) or (NewScratch = nil) then
  begin
    if NewState <> nil then
      xkb_state_unref(NewState);
    if NewScratch <> nil then
      xkb_state_unref(NewScratch);
    xkb_keymap_unref(ANewKeymap);
    Exit;
  end;

  if FScratch <> nil then
    xkb_state_unref(FScratch);
  if FState <> nil then
    xkb_state_unref(FState);
  if FKeymap <> nil then
    xkb_keymap_unref(FKeymap);
  FKeymap := ANewKeymap;
  FState := NewState;
  FScratch := NewScratch;
  FGroup := 0;
  LookupModIndices;
  Result := True;
end;

function TPMLXKBState.LoadKeymap(const AText: String): Boolean;
begin
  if GContext = nil then
    Exit(False);
  Result := Install(xkb_keymap_new_from_string(GContext, PAnsiChar(AText),
    XKB_KEYMAP_FORMAT_TEXT_V1, 0));
end;

function TPMLXKBState.LoadKeymapFromNames(const ALayout, AVariant: String): Boolean;
var
  Names: Txkb_rule_names;
begin
  if GContext = nil then
    Exit(False);
  FillChar(Names, SizeOf(Names), 0);
  Names.rules := 'evdev';
  Names.model := 'pc105';
  Names.layout := PAnsiChar(ALayout);
  if AVariant <> '' then
    Names.variant := PAnsiChar(AVariant);
  Result := Install(xkb_keymap_new_from_names(GContext, @Names, 0));
end;

procedure TPMLXKBState.UpdateMask(ADepressed, ALatched, ALocked, AGroup: LongWord);
begin
  if FState = nil then
    Exit;
  FGroup := AGroup;
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


function TPMLXKBState.KeysymAtLevel(AEvdevCode: LongWord; AShifted: Boolean): xkb_keysym_t;
var
  Mask: LongWord;
begin
  if FScratch = nil then
    Exit(0);
  Mask := 0;
  if AShifted and (FModShift <> LongWord(-1)) then
    Mask := LongWord(1) shl FModShift;
  xkb_state_update_mask(FScratch, Mask, 0, 0, 0, 0, FGroup);
  Result := xkb_state_key_get_one_sym(FScratch, AEvdevCode + XKB_EVDEV_OFFSET);
end;

{ PORT-NOTE: SDL の Wayland_KeymapIterator にあたる。SDL は xkb のキーマップの
  段（level）を全部たどり、段ごとの修飾の組み合わせで登録する。ここでは作業用の
  状態に「修飾なし」と「Shift」を設定して 2 段だけ引く（PaPiMeLa.Events.Keymap の
  RESOLVED を参照）。スキャンコードは evdev の表から決まる。 }
function TPMLXKBState.BuildKeymap: TPMLKeymap;
var
  Evdev: LongWord;
  Scancode: TPMLScancode;
  Shifted: Boolean;
  Sym: xkb_keysym_t;
begin
  Result := TPMLKeymap.Create;
  if FKeymap = nil then
    Exit;
  for Evdev := 0 to High(PML_LINUX_SCANCODES) do
  begin
    Scancode := PMLScancodeFromEvdev(Evdev);
    if Scancode = TPMLScancode.UNKNOWN then
      Continue;
    for Shifted := False to True do
    begin
      Sym := KeysymAtLevel(Evdev, Shifted);
      if Sym <> 0 then
        Result.SetEntry(Scancode, Shifted, PMLKeymapKeycode(Sym, Scancode, Shifted));
    end;
  end;
end;

end.
