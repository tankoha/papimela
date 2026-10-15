{
  PaPiMeLa.Platform.PipeWire — libpipewire-0.3 の実行時結合と、SPA のインライン関数の写し

  Origin : partially ported from SDL (src/audio/pipewire/SDL_pipewire.c)
           Scope: 結合する関数の一覧（SDL_pipewire.c の冒頭の PIPEWIRE_xxx）だけ。
           SDL revision: see docs/ORIGIN.md
           インライン関数は PipeWire のヘッダ（MIT。下の告知）から写した:
           spa/utils/list.h（spa_list_init・spa_list_remove）、spa/utils/hook.h（spa_hook_remove と
           メソッドの呼び出し方 spa_api_method_r）、spa/utils/dict.h（spa_dict_lookup）、
           pipewire/core.h・node.h（pw_core_add_listener・pw_core_sync・pw_core_get_registry・
           pw_registry_add_listener・pw_registry_bind・pw_node_enum_params）、
           spa/pod/builder.h と spa/param/audio/raw-utils.h（spa_format_audio_raw_build の組み立て）、
           spa/pod/iter.h・body.h（spa_pod_find_prop・spa_pod_get_values・spa_pod_get_int）、
           spa/utils/json-core.h・json.h（spa_json_next・spa_json_parse_stringn・
           spa_json_enter_object / array・spa_json_get_string）。PipeWire 1.6.2。
  Design : docs/DESIGN.md §9.4、§11 #21

  WHAT:
    libpipewire-0.3.so.0 を dlopen で結合し（TPMLPipeWire）、ヘッダの構造体を同じ並びのレコードに、
    定数を src/generated/pipewire_consts.inc（tools/genpipewire.bb が C で作る）にする。ヘッダの
    インライン関数で SDL の PipeWire のバックエンドが使うものを Pascal に写す。

  WHY:
    PipeWire の API の半分はヘッダの中にある（メソッドの呼び出し、pod の組み立て、JSON）。
    ライブラリからは取れないので写すしかない。写しの正しさは、本物のヘッダで動かした C の結果と
    比べて確かめる（test/test_pipewire_abi.pas）。

  RESOLVED:
    - 構造体の大きさと欄の位置、pod のバイト列、pod と JSON の読み取りの結果は、
      test/pipewire_abi_expected.inc（同じ生成器が作る）と比べる
    - 浮動小数点の例外（FPC は有効、C は無効が前提）: C のスレッドは作ったスレッドの設定を受け継ぎ、
      PipeWire のスレッドは papimela のメインスレッドから作られる（spikes/RESULTS.md のスパイク 4）。
      PipeWire の関数を呼ぶ間は PMLPipeWireMaskBegin / End で呼んだスレッドの例外を止め、作られる
      スレッドが止めた設定を受け継ぐようにする（PipeWire の中の計算、変換のデータのスレッドを含む）。
      念のため、呼び出しの入口でも止める（PMLPipeWireCallbackEnter。入口で有効だった回数を数える）
    - spa_dict_lookup は並べ替えの印があっても前から探す（同じ鍵が 2 つ無ければ結果は同じ）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）

  PipeWire のヘッダから写した部分:
  Copyright © 2018 Wim Taymans（json-core.h・json.h は © 2020 Wim Taymans）。SPDX-License-Identifier: MIT
  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
  associated documentation files (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute,
  sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions: The above copyright notice and this
  permission notice shall be included in all copies or substantial portions of the Software.
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
  OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}
unit PaPiMeLa.Platform.PipeWire;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils, Math, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

{$I generated/pipewire_consts.inc}

const
  // spa/utils/dict.h
  SPA_DICT_FLAG_SORTED = 1;
  // SDL_pipewire.c が結合するライブラリ
  PML_PIPEWIRE_LIBRARY = 'libpipewire-0.3.so.0';

type
  // ---- 不透明な型（空のレコードへの型付きポインタ。取り違えをコンパイラが見つける）
  TPWThreadLoop = record end;
  PPWThreadLoop = ^TPWThreadLoop;
  TPWMainLoop = record end;
  PPWMainLoop = ^TPWMainLoop;
  TPWLoop = record end;
  PPWLoop = ^TPWLoop;
  TPWContext = record end;
  PPWContext = ^TPWContext;
  TPWCore = record end;
  PPWCore = ^TPWCore;
  TPWRegistry = record end;
  PPWRegistry = ^TPWRegistry;
  TPWProxy = record end;
  PPWProxy = ^TPWProxy;
  TPWStream = record end;
  PPWStream = ^TPWStream;
  TPWProperties = record end;
  PPWProperties = ^TPWProperties;

  // ---- spa/utils
  PSpaList = ^TSpaList;
  TSpaList = record
    Next, Prev: PSpaList;
  end;

  TSpaCallbacks = record
    Funcs: Pointer;
    Data : Pointer;
  end;

  // pw_core・pw_registry・pw_proxy の先頭はこれ（メソッドの表とその相手）。
  PSpaInterface = ^TSpaInterface;
  TSpaInterface = record
    TypeName: PChar;
    Version : LongWord;
    Cb      : TSpaCallbacks;
  end;

  PSpaHook = ^TSpaHook;
  TSpaHookRemoved = procedure(AHook: PSpaHook); cdecl;
  TSpaHook = record
    Link   : TSpaList;
    Cb     : TSpaCallbacks;
    Removed: TSpaHookRemoved;
    Priv   : Pointer;
  end;

  PSpaDictItem = ^TSpaDictItem;
  TSpaDictItem = record
    Key, Value: PChar;
  end;

  PSpaDict = ^TSpaDict;
  TSpaDict = record
    Flags : LongWord;
    NItems: LongWord;
    Items : PSpaDictItem;
  end;

  // ---- spa/pod
  PSpaPod = ^TSpaPod;
  TSpaPod = record
    Size   : LongWord;   // 本体のバイト数（頭の 8 バイトを含まない）
    PodType: LongWord;
  end;

  PSpaPodProp = ^TSpaPodProp;
  TSpaPodProp = record
    Key  : LongWord;
    Flags: LongWord;
    Value: TSpaPod;
  end;

  TSpaPodObjectBody = record
    ObjType: LongWord;
    Id     : LongWord;
  end;

  PSpaPodObject = ^TSpaPodObject;
  TSpaPodObject = record
    Pod : TSpaPod;
    Body: TSpaPodObjectBody;
  end;

  TSpaPodChoiceBody = record
    ChoiceType: LongWord;
    Flags     : LongWord;
    Child     : TSpaPod;
  end;

  PSpaPodChoice = ^TSpaPodChoice;
  TSpaPodChoice = record
    Pod : TSpaPod;
    Body: TSpaPodChoiceBody;
  end;

  TSpaPodArrayBody = record
    Child: TSpaPod;
  end;

  // ---- spa/param、spa/buffer
  PSpaParamInfo = ^TSpaParamInfo;
  TSpaParamInfo = record
    Id     : LongWord;
    Flags  : LongWord;
    User   : LongWord;
    Seq    : LongInt;
    Padding: array[0..3] of LongWord;
  end;

  PSpaChunk = ^TSpaChunk;
  TSpaChunk = record
    Offset: LongWord;
    Size  : LongWord;
    Stride: LongInt;
    Flags : LongInt;
  end;

  PSpaData = ^TSpaData;
  TSpaData = record
    DataType : LongWord;
    Flags    : LongWord;
    Fd       : Int64;
    MapOffset: LongWord;
    MaxSize  : LongWord;
    Data     : Pointer;
    Chunk    : PSpaChunk;
  end;

  PSpaBuffer = ^TSpaBuffer;
  TSpaBuffer = record
    NMetas: LongWord;
    NDatas: LongWord;
    Metas : Pointer;
    Datas : PSpaData;
  end;

  // ---- pipewire の情報
  PPWBuffer = ^TPWBuffer;
  TPWBuffer = record
    Buffer   : PSpaBuffer;
    UserData : Pointer;
    Size     : QWord;
    Requested: QWord;
    Time     : QWord;
  end;

  PPWCoreInfo = ^TPWCoreInfo;
  TPWCoreInfo = record
    Id        : LongWord;
    Cookie    : LongWord;
    UserName  : PChar;
    HostName  : PChar;
    Version   : PChar;
    Name      : PChar;
    ChangeMask: QWord;
    Props     : PSpaDict;
  end;

  PPWNodeInfo = ^TPWNodeInfo;
  TPWNodeInfo = record
    Id            : LongWord;
    MaxInputPorts : LongWord;
    MaxOutputPorts: LongWord;
    ChangeMask    : QWord;
    NInputPorts   : LongWord;
    NOutputPorts  : LongWord;
    State         : LongInt;
    Error         : PChar;
    Props         : PSpaDict;
    Params        : PSpaParamInfo;
    NParams       : LongWord;
  end;

  PPWClientInfo = ^TPWClientInfo;
  TPWClientInfo = record
    Id        : LongWord;
    ChangeMask: QWord;
    Props     : PSpaDict;
  end;

  // ---- 知らせの表（使わない欄は Pointer）。どれも AData が先頭（SDL の void *data）。
  PPWCoreEvents = ^TPWCoreEvents;
  TPWCoreEvents = record
    Version   : LongWord;
    Info      : procedure(AData: Pointer; AInfo: PPWCoreInfo); cdecl;
    Done      : procedure(AData: Pointer; AId: LongWord; ASeq: cint); cdecl;
    Ping      : Pointer;
    Error     : Pointer;
    RemoveId  : Pointer;
    BoundId   : Pointer;
    AddMem    : Pointer;
    RemoveMem : Pointer;
    BoundProps: Pointer;
  end;

  PPWCoreMethods = ^TPWCoreMethods;
  TPWCoreMethods = record
    Version     : LongWord;
    AddListener : function(AObject: Pointer; AListener: PSpaHook; AEvents: PPWCoreEvents;
                    AData: Pointer): cint; cdecl;
    Hello       : Pointer;
    Sync        : function(AObject: Pointer; AId: LongWord; ASeq: cint): cint; cdecl;
    Pong        : Pointer;
    Error       : Pointer;
    GetRegistry : function(AObject: Pointer; AVersion: LongWord; AUserDataSize: csize_t): PPWRegistry; cdecl;
    CreateObject: Pointer;
    Destroy     : Pointer;
  end;

  PPWRegistryEvents = ^TPWRegistryEvents;
  TPWRegistryEvents = record
    Version     : LongWord;
    Global      : procedure(AData: Pointer; AId, APermissions: LongWord; AType: PChar;
                    AVersion: LongWord; AProps: PSpaDict); cdecl;
    GlobalRemove: procedure(AData: Pointer; AId: LongWord); cdecl;
  end;

  PPWRegistryMethods = ^TPWRegistryMethods;
  TPWRegistryMethods = record
    Version    : LongWord;
    AddListener: function(AObject: Pointer; AListener: PSpaHook; AEvents: PPWRegistryEvents;
                   AData: Pointer): cint; cdecl;
    Bind       : function(AObject: Pointer; AId: LongWord; AType: PChar; AVersion: LongWord;
                   AUserDataSize: csize_t): Pointer; cdecl;
    Destroy    : Pointer;
  end;

  PPWNodeEvents = ^TPWNodeEvents;
  TPWNodeEvents = record
    Version: LongWord;
    Info   : procedure(AData: Pointer; AInfo: PPWNodeInfo); cdecl;
    Param  : procedure(AData: Pointer; ASeq: cint; AId, AIndex, ANext: LongWord; AParam: PSpaPod); cdecl;
  end;

  PPWNodeMethods = ^TPWNodeMethods;
  TPWNodeMethods = record
    Version        : LongWord;
    AddListener    : Pointer;
    SubscribeParams: Pointer;
    EnumParams     : function(AObject: Pointer; ASeq: cint; AId, AStart, ANum: LongWord;
                       AFilter: PSpaPod): cint; cdecl;
    SetParam       : Pointer;
    SendCommand    : Pointer;
  end;

  PPWMetadataEvents = ^TPWMetadataEvents;
  TPWMetadataEvents = record
    Version : LongWord;
    Property_: function(AData: Pointer; ASubject: LongWord; AKey, AType, AValue: PChar): cint; cdecl;
  end;

  PPWClientEvents = ^TPWClientEvents;
  TPWClientEvents = record
    Version    : LongWord;
    Info       : procedure(AData: Pointer; AInfo: PPWClientInfo); cdecl;
    Permissions: Pointer;
  end;

  PPWStreamEvents = ^TPWStreamEvents;
  TPWStreamEvents = record
    Version     : LongWord;
    Destroy     : Pointer;
    StateChanged: procedure(AData: Pointer; AOld, AState: cint; AError: PChar); cdecl;
    ControlInfo : Pointer;
    IoChanged   : Pointer;
    ParamChanged: Pointer;
    AddBuffer   : procedure(AData: Pointer; ABuffer: PPWBuffer); cdecl;
    RemoveBuffer: Pointer;
    Process     : procedure(AData: Pointer); cdecl;
    Drained     : Pointer;
    Command     : Pointer;
    TriggerDone : Pointer;
  end;

  { 結合する関数（SDL_pipewire.c の PIPEWIRE_xxx と同じ一覧）。 }
  TPMLPipeWireAPI = record
    get_library_version: function: PChar; cdecl;
    init               : procedure(AArgc: Pcint; AArgv: Pointer); cdecl;
    deinit             : procedure; cdecl;
    main_loop_new      : function(AProps: PSpaDict): PPWMainLoop; cdecl;
    main_loop_get_loop : function(ALoop: PPWMainLoop): PPWLoop; cdecl;
    main_loop_run      : function(ALoop: PPWMainLoop): cint; cdecl;
    main_loop_quit     : function(ALoop: PPWMainLoop): cint; cdecl;
    main_loop_destroy  : procedure(ALoop: PPWMainLoop); cdecl;
    thread_loop_new       : function(AName: PChar; AProps: PSpaDict): PPWThreadLoop; cdecl;
    thread_loop_destroy   : procedure(ALoop: PPWThreadLoop); cdecl;
    thread_loop_stop      : procedure(ALoop: PPWThreadLoop); cdecl;
    thread_loop_get_loop  : function(ALoop: PPWThreadLoop): PPWLoop; cdecl;
    thread_loop_lock      : procedure(ALoop: PPWThreadLoop); cdecl;
    thread_loop_unlock    : procedure(ALoop: PPWThreadLoop); cdecl;
    thread_loop_signal    : procedure(ALoop: PPWThreadLoop; AWaitForAccept: cbool); cdecl;
    thread_loop_wait      : procedure(ALoop: PPWThreadLoop); cdecl;
    thread_loop_timed_wait: function(ALoop: PPWThreadLoop; AWaitMaxSec: cint): cint; cdecl;
    thread_loop_start     : function(ALoop: PPWThreadLoop): cint; cdecl;
    context_new           : function(ALoop: PPWLoop; AProps: PPWProperties; AUserDataSize: csize_t): PPWContext; cdecl;
    context_destroy       : procedure(AContext: PPWContext); cdecl;
    context_connect       : function(AContext: PPWContext; AProps: PPWProperties; AUserDataSize: csize_t): PPWCore; cdecl;
    proxy_add_object_listener: procedure(AProxy: PPWProxy; AListener: PSpaHook; AFuncs: Pointer; AData: Pointer); cdecl;
    proxy_get_user_data   : function(AProxy: PPWProxy): Pointer; cdecl;
    proxy_destroy         : procedure(AProxy: PPWProxy); cdecl;
    core_disconnect       : function(ACore: PPWCore): cint; cdecl;
    stream_new_simple     : function(ALoop: PPWLoop; AName: PChar; AProps: PPWProperties;
                              AEvents: PPWStreamEvents; AData: Pointer): PPWStream; cdecl;
    stream_destroy        : procedure(AStream: PPWStream); cdecl;
    stream_connect        : function(AStream: PPWStream; ADirection: cint; ATargetId: LongWord;
                              AFlags: LongWord; AParams: Pointer; ANParams: LongWord): cint; cdecl;
    stream_get_state      : function(AStream: PPWStream; AError: PPChar): cint; cdecl;
    stream_dequeue_buffer : function(AStream: PPWStream): PPWBuffer; cdecl;
    stream_queue_buffer   : function(AStream: PPWStream; ABuffer: PPWBuffer): cint; cdecl;
    // 可変長の引数（NULL で終わる鍵と値の並び）。papimela は nil だけを渡す。
    properties_new        : function(AKey: PChar): PPWProperties; cdecl; varargs;
    properties_set        : function(AProps: PPWProperties; AKey, AValue: PChar): cint; cdecl;
    stream_update_properties: function(AStream: PPWStream; ADict: PSpaDict): cint; cdecl;
  end;

  { libpipewire-0.3 を開いて関数を結合する。開けない・関数が足りないなら EPMLPlatformLibrary。
    pw_init / pw_deinit は呼ばない（呼ぶのは使う側。SDL の init_pipewire_library と同じ）。 }
  TPMLPipeWire = class
  strict private
    FLib: TPMLDynLib;
    procedure Bind(out ATarget; const ASymbol: String);
  public
    API: TPMLPipeWireAPI;
    constructor Create;
    destructor Destroy; override;
    class function IsAvailable: Boolean; static;
  end;

{ PipeWire のスレッドから来る呼び出しの入口で最初に呼ぶ（浮動小数点の例外を止める。C と同じ）。
  入口で例外が有効だったら数える（PMLPipeWireUnmaskedEntries）。 }
procedure PMLPipeWireCallbackEnter;
// 入口で浮動小数点の例外が有効だった回数（0 のはず。PMLPipeWireMaskBegin が効いていれば）。
function  PMLPipeWireUnmaskedEntries: LongInt;
{ PipeWire の関数（スレッドを作るもの）を呼ぶ前に呼び、呼んだスレッドの浮動小数点の例外を止める。
  前の設定を返す。呼んだ後に PMLPipeWireMaskEnd で戻す。 }
function  PMLPipeWireMaskBegin: TFPUExceptionMask;
procedure PMLPipeWireMaskEnd(const AOld: TFPUExceptionMask);

// ---- spa/utils/list.h・hook.h・dict.h
procedure PMLSpaListInit(var AList: TSpaList);
procedure PMLSpaListRemove(AElem: PSpaList);
procedure PMLSpaHookRemove(AHook: PSpaHook);
// spa_dict_lookup。無ければ nil。
function  PMLSpaDictLookup(ADict: PSpaDict; AKey: PChar): PChar;

// ---- pipewire/core.h・node.h（spa_api_method_r。表が無い・版が足りない・関数が無いなら既定の値）
function  PMLPWCoreAddListener(ACore: PPWCore; AListener: PSpaHook; AEvents: PPWCoreEvents;
  AData: Pointer): cint;
function  PMLPWCoreSync(ACore: PPWCore; AId: LongWord; ASeq: cint): cint;
function  PMLPWCoreGetRegistry(ACore: PPWCore; AVersion: LongWord; AUserDataSize: csize_t): PPWRegistry;
function  PMLPWRegistryAddListener(ARegistry: PPWRegistry; AListener: PSpaHook;
  AEvents: PPWRegistryEvents; AData: Pointer): cint;
function  PMLPWRegistryBind(ARegistry: PPWRegistry; AId: LongWord; AType: PChar; AVersion: LongWord;
  AUserDataSize: csize_t): PPWProxy;
function  PMLPWNodeEnumParams(ANode: PPWProxy; ASeq: cint; AId, AStart, ANum: LongWord;
  AFilter: PSpaPod): cint;

// ---- spa/pod
{ spa_format_audio_raw_build。AFormat が SPA_AUDIO_FORMAT_UNKNOWN なら形式を、ARate が 0 なら周波数を、
  チャンネル数が 0 なら数と並びを省く。並びは APositions のはじめのチャンネル数ぶん
  （足りなければ並びを省く。SPA の SPA_AUDIO_FLAG_UNPOSITIONED にあたる）。pod のバイト列を返す。 }
function  PMLSpaFormatAudioRawBuild(AParamId, AFormat, ARate, AChannels: LongWord;
  const APositions: array of LongWord): TBytes;
// spa_pod_find_prop（AStart は nil か、前に見つけたもの）。オブジェクトでなければ nil。
function  PMLSpaPodFindProp(APod: PSpaPod; AStart: PSpaPodProp; AKey: LongWord): PSpaPodProp;
// spa_pod_get_values。Choice なら子と値の数と種類、そうでなければ自分（数は 1 か 0）と None。
function  PMLSpaPodGetValues(APod: PSpaPod; out ANValues, AChoice: LongWord): PSpaPod;
// spa_pod_get_int。0 か -EINVAL。
function  PMLSpaPodGetInt(APod: PSpaPod; out AValue: LongInt): cint;
// SPA_POD_BODY。
function  PMLSpaPodBody(APod: PSpaPod): Pointer; inline;

// ---- spa/utils/json
type
  PSpaJson = ^TSpaJson;
  TSpaJson = record
    Cur, EndP: PChar;
    Parent   : PSpaJson;
    State    : LongWord;
    Depth    : LongWord;
  end;

procedure PMLSpaJsonInit(out AIter: TSpaJson; AData: PChar; ASize: SizeInt);
// spa_json_next。トークンの長さ、終わりなら 0、誤りなら -1。
function  PMLSpaJsonNext(var AIter: TSpaJson; out AValue: PChar): cint;
function  PMLSpaJsonEnterObject(var AIter: TSpaJson; out ASub: TSpaJson): cint;
function  PMLSpaJsonEnterArray(var AIter: TSpaJson; out ASub: TSpaJson): cint;
{ spa_json_get_string。AMaxLen は C の置き場の大きさ（終わりの NUL を含む）。トークンの長さが
  AMaxLen 以上なら -ENOSPC。値は AValue に。 }
function  PMLSpaJsonGetString(var AIter: TSpaJson; out AValue: String; AMaxLen: cint): cint;

implementation

const
  AllMasked: TFPUExceptionMask = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow,
    exPrecision];

var
  UnmaskedEntries: LongInt = 0;

procedure PMLPipeWireCallbackEnter;
var
  Mask: TFPUExceptionMask;
begin
  Mask := GetExceptionMask;
  if Mask <> AllMasked then
  begin
    InterLockedIncrement(UnmaskedEntries);
    SetExceptionMask(AllMasked);
  end;
end;

function PMLPipeWireUnmaskedEntries: LongInt;
begin
  Result := UnmaskedEntries;
end;

function PMLPipeWireMaskBegin: TFPUExceptionMask;
begin
  // FPC 3.2.2 の aarch64 は SetExceptionMask が前の値でなく新しい値を返す。先に読んでおく
  Result := GetExceptionMask;
  SetExceptionMask(AllMasked);
end;

procedure PMLPipeWireMaskEnd(const AOld: TFPUExceptionMask);
begin
  SetExceptionMask(AOld);
end;

{ ---- TPMLPipeWire ---- }

constructor TPMLPipeWire.Create;
begin
  inherited Create;
  FLib := TPMLDynLib.Create([PML_PIPEWIRE_LIBRARY]);
  // SDL の load_pipewire_syms と同じ一覧（pw_properties_setf は使わない。値は Pascal で作る）。
  Bind(API.get_library_version, 'pw_get_library_version');
  Bind(API.init, 'pw_init');
  Bind(API.deinit, 'pw_deinit');
  Bind(API.main_loop_new, 'pw_main_loop_new');
  Bind(API.main_loop_get_loop, 'pw_main_loop_get_loop');
  Bind(API.main_loop_run, 'pw_main_loop_run');
  Bind(API.main_loop_quit, 'pw_main_loop_quit');
  Bind(API.main_loop_destroy, 'pw_main_loop_destroy');
  Bind(API.thread_loop_new, 'pw_thread_loop_new');
  Bind(API.thread_loop_destroy, 'pw_thread_loop_destroy');
  Bind(API.thread_loop_stop, 'pw_thread_loop_stop');
  Bind(API.thread_loop_get_loop, 'pw_thread_loop_get_loop');
  Bind(API.thread_loop_lock, 'pw_thread_loop_lock');
  Bind(API.thread_loop_unlock, 'pw_thread_loop_unlock');
  Bind(API.thread_loop_signal, 'pw_thread_loop_signal');
  Bind(API.thread_loop_wait, 'pw_thread_loop_wait');
  Bind(API.thread_loop_timed_wait, 'pw_thread_loop_timed_wait');
  Bind(API.thread_loop_start, 'pw_thread_loop_start');
  Bind(API.context_new, 'pw_context_new');
  Bind(API.context_destroy, 'pw_context_destroy');
  Bind(API.context_connect, 'pw_context_connect');
  Bind(API.proxy_add_object_listener, 'pw_proxy_add_object_listener');
  Bind(API.proxy_get_user_data, 'pw_proxy_get_user_data');
  Bind(API.proxy_destroy, 'pw_proxy_destroy');
  Bind(API.core_disconnect, 'pw_core_disconnect');
  Bind(API.stream_new_simple, 'pw_stream_new_simple');
  Bind(API.stream_destroy, 'pw_stream_destroy');
  Bind(API.stream_connect, 'pw_stream_connect');
  Bind(API.stream_get_state, 'pw_stream_get_state');
  Bind(API.stream_dequeue_buffer, 'pw_stream_dequeue_buffer');
  Bind(API.stream_queue_buffer, 'pw_stream_queue_buffer');
  Bind(API.properties_new, 'pw_properties_new');
  Bind(API.properties_set, 'pw_properties_set');
  Bind(API.stream_update_properties, 'pw_stream_update_properties');
end;

destructor TPMLPipeWire.Destroy;
begin
  FLib.Free;
  inherited Destroy;
end;

procedure TPMLPipeWire.Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := FLib.Resolve(ASymbol);
end;

class function TPMLPipeWire.IsAvailable: Boolean;
begin
  Result := TPMLDynLib.IsAvailable([PML_PIPEWIRE_LIBRARY]);
end;

{ ---- spa/utils/list.h・hook.h・dict.h ---- }

procedure PMLSpaListInit(var AList: TSpaList);
begin
  AList.Next := @AList;
  AList.Prev := @AList;
end;

procedure PMLSpaListRemove(AElem: PSpaList);
begin
  AElem^.Prev^.Next := AElem^.Next;
  AElem^.Next^.Prev := AElem^.Prev;
end;

{ spa_hook_remove。つながっていなければ（prev が nil）外さない。 }
procedure PMLSpaHookRemove(AHook: PSpaHook);
begin
  if AHook^.Link.Prev <> nil then
    PMLSpaListRemove(@AHook^.Link);
  if Assigned(AHook^.Removed) then
    AHook^.Removed(AHook);
end;

function PMLSpaDictLookup(ADict: PSpaDict; AKey: PChar): PChar;
var
  I: LongWord;
  Item: PSpaDictItem;
begin
  Result := nil;
  if ADict = nil then
    Exit;
  Item := ADict^.Items;
  for I := 1 to ADict^.NItems do
  begin
    if StrComp(Item^.Key, AKey) = 0 then
      Exit(Item^.Value);
    Inc(Item);
  end;
end;

{ ---- pipewire/core.h・node.h ---- }

{ spa_api_method_r の前半: 相手（spa_interface）の表を返す。版の確かめ（SPA_CALLBACK_VERSION_MIN）は、
  ここで使う関数がどれも版 0 を求めるので、表があることだけになる。 }
function MethodTable(AObject: Pointer): Pointer; inline;
begin
  Result := PSpaInterface(AObject)^.Cb.Funcs;
end;

function MethodData(AObject: Pointer): Pointer; inline;
begin
  Result := PSpaInterface(AObject)^.Cb.Data;
end;

function PMLPWCoreAddListener(ACore: PPWCore; AListener: PSpaHook; AEvents: PPWCoreEvents;
  AData: Pointer): cint;
var
  M: PPWCoreMethods;
begin
  M := MethodTable(ACore);
  if (M = nil) or not Assigned(M^.AddListener) then
    Exit(-ENOTSUP);
  Result := M^.AddListener(MethodData(ACore), AListener, AEvents, AData);
end;

function PMLPWCoreSync(ACore: PPWCore; AId: LongWord; ASeq: cint): cint;
var
  M: PPWCoreMethods;
begin
  M := MethodTable(ACore);
  if (M = nil) or not Assigned(M^.Sync) then
    Exit(-ENOTSUP);
  Result := M^.Sync(MethodData(ACore), AId, ASeq);
end;

function PMLPWCoreGetRegistry(ACore: PPWCore; AVersion: LongWord; AUserDataSize: csize_t): PPWRegistry;
var
  M: PPWCoreMethods;
begin
  M := MethodTable(ACore);
  if (M = nil) or not Assigned(M^.GetRegistry) then
    Exit(nil);
  Result := M^.GetRegistry(MethodData(ACore), AVersion, AUserDataSize);
end;

function PMLPWRegistryAddListener(ARegistry: PPWRegistry; AListener: PSpaHook;
  AEvents: PPWRegistryEvents; AData: Pointer): cint;
var
  M: PPWRegistryMethods;
begin
  M := MethodTable(ARegistry);
  if (M = nil) or not Assigned(M^.AddListener) then
    Exit(-ENOTSUP);
  Result := M^.AddListener(MethodData(ARegistry), AListener, AEvents, AData);
end;

function PMLPWRegistryBind(ARegistry: PPWRegistry; AId: LongWord; AType: PChar; AVersion: LongWord;
  AUserDataSize: csize_t): PPWProxy;
var
  M: PPWRegistryMethods;
begin
  M := MethodTable(ARegistry);
  if (M = nil) or not Assigned(M^.Bind) then
    Exit(nil);
  Result := PPWProxy(M^.Bind(MethodData(ARegistry), AId, AType, AVersion, AUserDataSize));
end;

function PMLPWNodeEnumParams(ANode: PPWProxy; ASeq: cint; AId, AStart, ANum: LongWord;
  AFilter: PSpaPod): cint;
var
  M: PPWNodeMethods;
begin
  M := MethodTable(ANode);
  if (M = nil) or not Assigned(M^.EnumParams) then
    Exit(-ENOTSUP);
  Result := M^.EnumParams(MethodData(ANode), ASeq, AId, AStart, ANum, AFilter);
end;

{ ---- spa/pod の組み立て（spa_format_audio_raw_build。spa_pod_builder の該当部分） ---- }

function PMLSpaFormatAudioRawBuild(AParamId, AFormat, ARate, AChannels: LongWord;
  const APositions: array of LongWord): TBytes;
var
  Buf: TBytes;
  Len: Integer;
  I: Integer;

  procedure Put32(AValue: LongWord);
  begin
    if Len + 4 > Length(Buf) then
      SetLength(Buf, (Len + 4) * 2);
    PLongWord(@Buf[Len])^ := NtoLE(AValue);
    Inc(Len, 4);
  end;

  // SPA_POD_ALIGN（8）に揃える（足りない分は 0）。
  procedure Pad;
  begin
    while Len mod SPA_POD_ALIGN <> 0 do
    begin
      if Len + 1 > Length(Buf) then
        SetLength(Buf, (Len + 1) * 2);
      Buf[Len] := 0;
      Inc(Len);
    end;
  end;

  // プロパティ（鍵、旗 0）と、1 つの 32 ビットの値の pod。
  procedure Prop32(AKey, AType, AValue: LongWord);
  begin
    Put32(AKey);
    Put32(0);
    Put32(4);
    Put32(AType);
    Put32(AValue);
    Pad;
  end;

begin
  Buf := nil;
  SetLength(Buf, 256);
  Len := 0;
  // spa_pod_builder_push_object: 大きさは pop で入れる。
  Put32(0);
  Put32(SPA_TYPE_Object);
  Put32(SPA_TYPE_OBJECT_Format);
  Put32(AParamId);
  Prop32(SPA_FORMAT_mediaType, SPA_TYPE_Id, SPA_MEDIA_TYPE_audio);
  Prop32(SPA_FORMAT_mediaSubtype, SPA_TYPE_Id, SPA_MEDIA_SUBTYPE_raw);
  if AFormat <> SPA_AUDIO_FORMAT_UNKNOWN then
    Prop32(SPA_FORMAT_AUDIO_format, SPA_TYPE_Id, AFormat);
  if ARate <> 0 then
    Prop32(SPA_FORMAT_AUDIO_rate, SPA_TYPE_Int, ARate);
  if AChannels <> 0 then
  begin
    Prop32(SPA_FORMAT_AUDIO_channels, SPA_TYPE_Int, AChannels);
    // 並びを読めないなら省く（SPA の SPA_AUDIO_FLAG_UNPOSITIONED と、置き場より多いチャンネル数）。
    if (LongWord(Length(APositions)) >= AChannels) and (AChannels <= SPA_AUDIO_MAX_CHANNELS) then
    begin
      Put32(SPA_FORMAT_AUDIO_position);
      Put32(0);
      // SPA_POD_Array: 本体は子の頭（大きさ 4、Id）と値の並び。
      Put32(SizeOf(TSpaPodArrayBody) + 4 * AChannels);
      Put32(SPA_TYPE_Array);
      Put32(4);
      Put32(SPA_TYPE_Id);
      for I := 0 to Integer(AChannels) - 1 do
        Put32(APositions[I]);
      Pad;
    end;
  end;
  // spa_pod_builder_pop: 頭の 8 バイトを除いた大きさ。
  PLongWord(@Buf[0])^ := NtoLE(LongWord(Len - SizeOf(TSpaPod)));
  SetLength(Buf, Len);
  Result := Buf;
end;

{ ---- spa/pod の読み取り（iter.h・body.h） ---- }

function PMLSpaPodBody(APod: PSpaPod): Pointer;
begin
  Result := Pointer(PByte(APod) + SizeOf(TSpaPod));
end;

// SPA_POD_CHECK(pod, type, size)。
function PodCheck(APod: PSpaPod; AType, AMinSize: LongWord): Boolean;
begin
  Result := (APod^.Size < SPA_POD_MAX_SIZE) and (APod^.PodType = AType) and (APod^.Size >= AMinSize);
end;

{ spa_pod_prop_is_inside: AIter が本体（ABody から ASize バイト）の中にあり、4 バイトに揃い、
  値の本体まで入りきる。 }
function PropIsInside(ABody: Pointer; ASize: LongWord; AIter: PSpaPodProp): Boolean;
var
  Remaining: PtrUInt;
begin
  Result := False;
  if (PtrUInt(AIter) mod 4) <> 0 then
    Exit;
  if (PtrUInt(ABody) <= PtrUInt(AIter)) and (SizeOf(TSpaPodProp) <= ASize)
    and (PtrUInt(AIter) - PtrUInt(ABody) <= ASize - SizeOf(TSpaPodProp)) then
  begin
    Remaining := (PtrUInt(ABody) + ASize) - (PtrUInt(AIter) + SizeOf(TSpaPodProp));
    Result := Remaining >= AIter^.Value.Size;
  end;
end;

// spa_pod_prop_next: 鍵と値の 8 バイト境界に揃えた大きさだけ進む。
function PropNext(AIter: PSpaPodProp): PSpaPodProp;
var
  N: QWord;
begin
  N := SizeOf(TSpaPodProp) + QWord(AIter^.Value.Size);
  N := (N + SPA_POD_ALIGN - 1) and not QWord(SPA_POD_ALIGN - 1);
  Result := PSpaPodProp(PByte(AIter) + N);
end;

function PMLSpaPodFindProp(APod: PSpaPod; AStart: PSpaPodProp; AKey: LongWord): PSpaPodProp;
var
  Obj: PSpaPodObject;
  Body: Pointer;
  First, Start, Res: PSpaPodProp;
begin
  Result := nil;
  if not PodCheck(APod, SPA_TYPE_Object, SizeOf(TSpaPodObjectBody)) then
    Exit;
  Obj := PSpaPodObject(APod);
  Body := @Obj^.Body;
  First := PSpaPodProp(PByte(Body) + SizeOf(TSpaPodObjectBody));
  if AStart <> nil then
    Start := PropNext(AStart)
  else
    Start := First;
  Res := Start;
  while PropIsInside(Body, Obj^.Pod.Size, Res) do
  begin
    if Res^.Key = AKey then
      Exit(Res);
    Res := PropNext(Res);
  end;
  // 始めから、AStart の次の手前まで見直す。
  Res := First;
  while Res <> Start do
  begin
    if Res^.Key = AKey then
      Exit(Res);
    Res := PropNext(Res);
  end;
end;

// spa_pod_type_size。
function PodTypeSize(AType: LongWord): LongWord;
begin
  case AType of
    SPA_TYPE_None, SPA_TYPE_Bytes, SPA_TYPE_Struct, SPA_TYPE_Pod: Result := 0;
    SPA_TYPE_String, SPA_TYPE_Bitmap: Result := 1;
    SPA_TYPE_Bool, SPA_TYPE_Int, SPA_TYPE_Id, SPA_TYPE_Float: Result := 4;
    SPA_TYPE_Long, SPA_TYPE_Double, SPA_TYPE_Fd, SPA_TYPE_Rectangle, SPA_TYPE_Fraction: Result := 8;
    SPA_TYPE_Array, SPA_TYPE_Object: Result := 8;
    SPA_TYPE_Sequence: Result := 8;     // spa_pod_sequence_body（unit・pad）
    SPA_TYPE_Pointer: Result := 16;     // spa_pod_pointer_body（type・pad・value）
    SPA_TYPE_Choice: Result := SizeOf(TSpaPodChoiceBody);
  else
    Result := 0;
  end;
end;

// spa_pod_choice_n_values。
procedure ChoiceNValues(AChoice: LongWord; out AMin, AMax: LongWord);
begin
  case AChoice of
    SPA_CHOICE_Enum:
    begin
      AMin := 2;
      AMax := High(LongWord);
    end;
    SPA_CHOICE_Range:
    begin
      AMin := 3;
      AMax := 3;
    end;
    SPA_CHOICE_Step:
    begin
      AMin := 4;
      AMax := 4;
    end;
    SPA_CHOICE_None, SPA_CHOICE_Flags:
    begin
      AMin := 1;
      AMax := 1;
    end;
  else
    AMin := 1;
    AMax := High(LongWord);
  end;
end;

function PMLSpaPodGetValues(APod: PSpaPod; out ANValues, AChoice: LongWord): PSpaPod;
var
  C: PSpaPodChoice;
  ChildSize, MinN, MaxN: LongWord;
begin
  if PodCheck(APod, SPA_TYPE_Choice, SizeOf(TSpaPodChoiceBody)) then
  begin
    // spa_pod_choice_body_get_values
    C := PSpaPodChoice(APod);
    ChildSize := C^.Body.Child.Size;
    if ChildSize <> 0 then
      ANValues := (C^.Pod.Size - SizeOf(TSpaPodChoiceBody)) div ChildSize
    else
      ANValues := 0;
    AChoice := C^.Body.ChoiceType;
    ChoiceNValues(AChoice, MinN, MaxN);
    if (ANValues < MinN) or (ChildSize < PodTypeSize(C^.Body.Child.PodType)) then
      ANValues := 0
    else if ANValues > MaxN then
      ANValues := MaxN;
    Result := @C^.Body.Child;
  end
  else
  begin
    if APod^.Size < PodTypeSize(APod^.PodType) then
      ANValues := 0
    else
      ANValues := 1;
    AChoice := SPA_CHOICE_None;
    Result := APod;
  end;
end;

function PMLSpaPodGetInt(APod: PSpaPod; out AValue: LongInt): cint;
begin
  AValue := 0;
  if not PodCheck(APod, SPA_TYPE_Int, 4) then
    Exit(-EINVAL);
  AValue := PLongInt(PMLSpaPodBody(APod))^;
  Result := 0;
end;

{ ---- spa/utils/json-core.h・json.h ---- }

const
  // spa_json_next の状態（下の 4 ビット）と旗。
  JS_NONE = 0;
  JS_STRUCT = 1;
  JS_BARE = 2;
  JS_STRING = 3;
  JS_UTF8 = 4;
  JS_ESC = 5;
  JS_COMMENT = 6;
  JS_ARRAY_FLAG = $10;       // 配列の中
  JS_PREV_ARRAY_FLAG = $20;  // 深さ 0 の配列の印
  JS_KEY_FLAG = $40;         // オブジェクトの鍵の中
  JS_SUB_FLAG = $80;         // 最上位ではない
  JS_FLAGS = $ff0;
  SPA_JSON_ERROR_FLAG = $100;
  // 誤りの種類（SPA_JSON_ERROR_FLAG から順に）
  JE_INVALID_ARRAY_SEPARATOR = SPA_JSON_ERROR_FLAG + 1;
  JE_EXPECTED_OBJECT_KEY = SPA_JSON_ERROR_FLAG + 2;
  JE_EXPECTED_OBJECT_VALUE = SPA_JSON_ERROR_FLAG + 3;
  JE_TOO_DEEP_NESTING = SPA_JSON_ERROR_FLAG + 4;
  JE_EXPECTED_ARRAY_CLOSE = SPA_JSON_ERROR_FLAG + 5;
  JE_EXPECTED_OBJECT_CLOSE = SPA_JSON_ERROR_FLAG + 6;
  JE_MISMATCHED_BRACKET = SPA_JSON_ERROR_FLAG + 7;
  JE_ESCAPE_NOT_ALLOWED = SPA_JSON_ERROR_FLAG + 8;
  JE_CHARACTERS_NOT_ALLOWED = SPA_JSON_ERROR_FLAG + 9;
  JE_INVALID_ESCAPE = SPA_JSON_ERROR_FLAG + 10;
  JE_INVALID_STATE = SPA_JSON_ERROR_FLAG + 11;
  JE_UNFINISHED_STRING = SPA_JSON_ERROR_FLAG + 12;

procedure PMLSpaJsonInit(out AIter: TSpaJson; AData: PChar; ASize: SizeInt);
begin
  AIter.Cur := AData;
  AIter.EndP := AData + ASize;
  AIter.Parent := nil;
  AIter.State := 0;
  AIter.Depth := 0;
end;

// SPA_FLAG_UPDATE(field, flag, val)
procedure FlagUpdate(var AField: LongWord; AFlag: LongWord; AValue: Boolean); inline;
begin
  if AValue then
    AField := AField or AFlag
  else
    AField := AField and not AFlag;
end;

procedure FlagUpdate64(var AField: QWord; AFlag: QWord; AValue: Boolean); inline;
begin
  if AValue then
    AField := AField or AFlag
  else
    AField := AField and not AFlag;
end;

{ spa_json_next。C の goto again はループの頭へ戻る Continue の代わりに、同じ文字で状態を
  もう一度見る（Again）。 }
function PMLSpaJsonNext(var AIter: TSpaJson; out AValue: PChar): cint;
var
  Utf8Remain: Integer;
  Err: LongWord;
  ArrayStack: array[0..7] of QWord;
  Cur: Byte;
  Flag: LongWord;
  Again: Boolean;
  Mask: QWord;
  Iter: PSpaJson;

  procedure Fail(AReason: LongWord);
  begin
    Err := AReason;
  end;

begin
  Utf8Remain := 0;
  Err := 0;
  FillChar(ArrayStack, SizeOf(ArrayStack), 0);
  AValue := AIter.Cur;

  if (AIter.State and SPA_JSON_ERROR_FLAG) <> 0 then
    Exit(-1);

  while AIter.Cur < AIter.EndP do
  begin
    Cur := Byte(AIter.Cur^);
    repeat
      Again := False;
      Flag := AIter.State and JS_FLAGS;
      case AIter.State and not JS_FLAGS of
        JS_NONE:
        begin
          Flag := Flag and not (JS_KEY_FLAG or JS_PREV_ARRAY_FLAG);
          AIter.State := JS_STRUCT or Flag;
          AIter.Depth := 0;
          Again := True;
        end;
        JS_STRUCT:
          case Cur of
            0, 9, 32, 13, 10, Ord(','):
              ;
            Ord(':'), Ord('='):
            begin
              if (Flag and JS_ARRAY_FLAG) <> 0 then
                Fail(JE_INVALID_ARRAY_SEPARATOR)
              else if (Flag and JS_KEY_FLAG) = 0 then
                Fail(JE_EXPECTED_OBJECT_KEY)
              else
                AIter.State := AIter.State or JS_SUB_FLAG;
            end;
            Ord('#'):
              AIter.State := JS_COMMENT or Flag;
            Ord('"'):
            begin
              if (Flag and JS_KEY_FLAG) <> 0 then
                Flag := Flag or JS_SUB_FLAG;
              if (Flag and JS_ARRAY_FLAG) = 0 then
                FlagUpdate(Flag, JS_KEY_FLAG, (Flag and JS_KEY_FLAG) = 0);
              AValue := AIter.Cur;
              AIter.State := JS_STRING or Flag;
            end;
            Ord('['), Ord('{'):
            begin
              if (Flag and JS_ARRAY_FLAG) = 0 then
              begin
                // 最上位はオブジェクトの中か、値 1 つの中。どちらでも配列・オブジェクトを受ける。
                if ((AIter.State and JS_SUB_FLAG) <> 0) and ((Flag and JS_KEY_FLAG) = 0) then
                begin
                  Fail(JE_EXPECTED_OBJECT_KEY);
                  Break;
                end;
                Flag := Flag and not JS_KEY_FLAG;
              end;
              AIter.State := JS_STRUCT or JS_SUB_FLAG or Flag;
              FlagUpdate(AIter.State, JS_ARRAY_FLAG, Cur = Ord('['));
              // 深さ 0 の配列の印は状態に、それより深いものは一時の積み上げに覚える。
              if AIter.Depth = 0 then
                FlagUpdate(AIter.State, JS_PREV_ARRAY_FLAG, (Flag and JS_ARRAY_FLAG) <> 0)
              else if ((AIter.Depth - 1) shr 6) < Length(ArrayStack) then
              begin
                Mask := QWord(1) shl ((AIter.Depth - 1) and $3f);
                FlagUpdate64(ArrayStack[(AIter.Depth - 1) shr 6], Mask, (Flag and JS_ARRAY_FLAG) <> 0);
              end
              else
              begin
                Fail(JE_TOO_DEEP_NESTING);
                Break;
              end;
              AValue := AIter.Cur;
              Inc(AIter.Depth);
              if AIter.Depth <= 1 then
              begin
                Inc(AIter.Cur);
                Exit(1);
              end;
            end;
            Ord('}'), Ord(']'):
            begin
              if ((Flag and JS_ARRAY_FLAG) <> 0) and (Cur <> Ord(']')) then
                Fail(JE_EXPECTED_ARRAY_CLOSE)
              else if ((Flag and JS_ARRAY_FLAG) = 0) and (Cur <> Ord('}')) then
                Fail(JE_EXPECTED_OBJECT_CLOSE)
              else if (Flag and JS_KEY_FLAG) <> 0 then
                Fail(JE_EXPECTED_OBJECT_VALUE)   // 鍵と値の組が途中
              else
              begin
                AIter.State := JS_STRUCT or JS_SUB_FLAG or Flag;
                if AIter.Depth = 0 then
                begin
                  if AIter.Parent <> nil then
                  begin
                    AIter.Parent^.Cur := AIter.Cur;
                    Exit(0);
                  end;
                  Fail(JE_MISMATCHED_BRACKET);
                end
                else
                begin
                  Dec(AIter.Depth);
                  if AIter.Depth = 0 then
                    FlagUpdate(AIter.State, JS_ARRAY_FLAG, (Flag and JS_PREV_ARRAY_FLAG) <> 0)
                  else if ((AIter.Depth - 1) shr 6) < Length(ArrayStack) then
                  begin
                    Mask := QWord(1) shl ((AIter.Depth - 1) and $3f);
                    FlagUpdate(AIter.State, JS_ARRAY_FLAG,
                      (ArrayStack[(AIter.Depth - 1) shr 6] and Mask) <> 0);
                  end
                  else
                    Fail(JE_TOO_DEEP_NESTING);
                end;
              end;
            end;
            Ord('\'):
              Fail(JE_ESCAPE_NOT_ALLOWED);   // 裸の逃がしは許さない
          else
            // 裸の ASCII は許す
            if not ((Cur >= 32) and (Cur <= 126)) then
              Fail(JE_CHARACTERS_NOT_ALLOWED)
            else
            begin
              if (Flag and JS_KEY_FLAG) <> 0 then
                Flag := Flag or JS_SUB_FLAG;
              if (Flag and JS_ARRAY_FLAG) = 0 then
                FlagUpdate(Flag, JS_KEY_FLAG, (Flag and JS_KEY_FLAG) = 0);
              AValue := AIter.Cur;
              AIter.State := JS_BARE or Flag;
            end;
          end;
        JS_BARE:
          case Cur of
            0, 9, 32, 13, 10, Ord('"'), Ord('#'), Ord(':'), Ord(','), Ord('='), Ord(']'), Ord('}'):
            begin
              AIter.State := JS_STRUCT or Flag;
              if AIter.Depth > 0 then
                Again := True
              else
                Exit(cint(AIter.Cur - AValue));
            end;
            Ord('\'):
              Fail(JE_ESCAPE_NOT_ALLOWED);
          else
            if not ((Cur >= 32) and (Cur <= 126)) then
              Fail(JE_CHARACTERS_NOT_ALLOWED);
          end;
        JS_STRING:
          case Cur of
            Ord('\'):
              AIter.State := JS_ESC or Flag;
            Ord('"'):
            begin
              AIter.State := JS_STRUCT or Flag;
              if AIter.Depth = 0 then
              begin
                Inc(AIter.Cur);
                Exit(cint(AIter.Cur - AValue));
              end;
            end;
            240..247:
            begin
              Inc(Utf8Remain, 3);
              AIter.State := JS_UTF8 or Flag;
            end;
            224..239:
            begin
              Inc(Utf8Remain, 2);
              AIter.State := JS_UTF8 or Flag;
            end;
            192..223:
            begin
              Inc(Utf8Remain);
              AIter.State := JS_UTF8 or Flag;
            end;
          else
            if not ((Cur >= 32) and (Cur <= 127)) then
              Fail(JE_CHARACTERS_NOT_ALLOWED);
          end;
        JS_UTF8:
          if (Cur >= 128) and (Cur <= 191) then
          begin
            Dec(Utf8Remain);
            if Utf8Remain = 0 then
              AIter.State := JS_STRING or Flag;
          end
          else
            Fail(JE_CHARACTERS_NOT_ALLOWED);
        JS_ESC:
          case Cur of
            Ord('"'), Ord('\'), Ord('/'), Ord('b'), Ord('f'), Ord('n'), Ord('r'), Ord('t'), Ord('u'):
              AIter.State := JS_STRING or Flag;
          else
            Fail(JE_INVALID_ESCAPE);
          end;
        JS_COMMENT:
          if (Cur = 10) or (Cur = 13) then
            AIter.State := JS_STRUCT or Flag;
      else
        Fail(JE_INVALID_STATE);
      end;
    until (not Again) or (Err <> 0);
    if Err <> 0 then
      Break;
    Inc(AIter.Cur);
  end;

  if Err = 0 then
  begin
    if (AIter.Depth <> 0) or (AIter.Parent <> nil) then
      Err := JE_MISMATCHED_BRACKET
    else
      case AIter.State and not JS_FLAGS of
        JS_STRING, JS_UTF8, JS_ESC:
          Err := JE_UNFINISHED_STRING;   // 文字列か逃がしが閉じていない
        JS_COMMENT:
          Exit(0);                       // 最後の注釈
      end;
  end;
  if Err = 0 then
  begin
    if ((AIter.State and JS_SUB_FLAG) <> 0) and ((AIter.State and JS_KEY_FLAG) <> 0) then
      Err := JE_EXPECTED_OBJECT_VALUE
    else if (AIter.State and not JS_FLAGS) <> JS_STRUCT then
    begin
      AIter.State := JS_STRUCT or (AIter.State and JS_FLAGS);
      Exit(cint(AIter.Cur - AValue));
    end
    else
      Exit(0);
  end;

  // error: 誤りを親へ伝える。
  AIter.State := Err;
  Iter := @AIter;
  while Iter^.Parent <> nil do
  begin
    if (Iter^.Parent^.State and SPA_JSON_ERROR_FLAG) <> 0 then
      Break;
    Iter^.Parent^.State := Err;
    Iter^.Parent^.Cur := Iter^.Cur;
    Iter := Iter^.Parent;
  end;
  Result := -1;
end;

// spa_json_enter_container。
function EnterContainer(var AIter: TSpaJson; out ASub: TSpaJson; AType: Char): cint;
var
  Value: PChar;
  Len: cint;
begin
  ASub := Default(TSpaJson);
  Len := PMLSpaJsonNext(AIter, Value);
  if Len <= 0 then
    Exit(Len);
  if not ((Len > 0) and ((Value^ = '{') or (Value^ = '['))) then
    Exit(-EPROTO);
  if Value^ <> AType then
    Exit(-EINVAL);
  // SPA_JSON_ENTER
  ASub.Cur := AIter.Cur;
  ASub.EndP := AIter.EndP;
  ASub.Parent := @AIter;
  ASub.State := AIter.State and $ff0;
  ASub.Depth := 0;
  Result := 1;
end;

function PMLSpaJsonEnterObject(var AIter: TSpaJson; out ASub: TSpaJson): cint;
begin
  Result := EnterContainer(AIter, ASub, '{');
end;

function PMLSpaJsonEnterArray(var AIter: TSpaJson; out ASub: TSpaJson): cint;
begin
  Result := EnterContainer(AIter, ASub, '[');
end;

// spa_json_parse_hex。
function ParseHex(P: PChar; ANum: Integer; out AValue: LongWord): Boolean;
var
  I: Integer;
  V: LongWord;
begin
  AValue := 0;
  for I := 0 to ANum - 1 do
  begin
    case P[I] of
      '0'..'9': V := Ord(P[I]) - Ord('0');
      'a'..'f': V := Ord(P[I]) - Ord('a') + 10;
      'A'..'F': V := Ord(P[I]) - Ord('A') + 10;
    else
      Exit(False);
    end;
    AValue := (AValue shl 4) or V;
  end;
  Result := True;
end;

{ spa_json_parse_stringn。結果を String に作る（C の置き場の大きさの確かめは同じ）。 }
function ParseStringN(AVal: PChar; ALen: cint; out AResult: String; AMaxLen: cint): cint;
var
  P, Last: PChar;
  Cp, V, N, Idx: LongWord;
  Enc: array[0..2] of LongWord = ($80, $800, $10000);
  Prefix: array[0..3] of Byte = (0, $c0, $e0, $f0);
  Bytes: array[0..3] of Byte;
  K: Integer;
begin
  AResult := '';
  if AMaxLen <= ALen then
    Exit(-ENOSPC);
  // spa_json_is_string: 2 文字以上で " から始まる
  if not ((ALen > 1) and (AVal^ = '"')) then
  begin
    SetString(AResult, AVal, ALen);
    Exit(1);
  end;
  Last := AVal + ALen;
  P := AVal + 1;
  while P < Last do
  begin
    if P^ = '\' then
    begin
      Inc(P);
      case P^ of
        'n': AResult := AResult + #10;
        'r': AResult := AResult + #13;
        'b': AResult := AResult + #8;
        't': AResult := AResult + #9;
        'f': AResult := AResult + #12;
        'u':
        begin
          if (Last - P < 5) or not ParseHex(P + 1, 4, Cp) then
          begin
            AResult := AResult + P^;
            Inc(P);
            Continue;
          end;
          Inc(P, 4);
          if (Cp >= $d800) and (Cp <= $dbff) then
          begin
            if (Last - P < 7) or (P[1] <> '\') or (P[2] <> 'u') or not ParseHex(P + 3, 4, V)
              or (V < $dc00) or (V > $dfff) then
            begin
              Inc(P);
              Continue;
            end;
            Inc(P, 6);
            Cp := $010000 + (((Cp and $3ff) shl 10) or (V and $3ff));
          end
          else if (Cp >= $dc00) and (Cp <= $dfff) then
          begin
            Inc(P);
            Continue;
          end;
          Idx := 0;
          while (Idx < 3) and not (Cp < Enc[Idx]) do
            Inc(Idx);
          N := Idx;
          while N > 0 do
          begin
            Bytes[N] := (Cp or $80) and $bf;
            Dec(N);
            Cp := Cp shr 6;
          end;
          Bytes[0] := (Cp or Prefix[Idx]) and $ff;
          for K := 0 to Integer(Idx) do
            AResult := AResult + Char(Bytes[K]);
        end;
      else
        AResult := AResult + P^;
      end;
    end
    else if P^ = '"' then
      Break
    else
      AResult := AResult + P^;
    Inc(P);
  end;
  Result := 1;
end;

function PMLSpaJsonGetString(var AIter: TSpaJson; out AValue: String; AMaxLen: cint): cint;
var
  Value: PChar;
  Len: cint;
begin
  AValue := '';
  Len := PMLSpaJsonNext(AIter, Value);
  if Len <= 0 then
    Exit(Len);
  Result := ParseStringN(Value, Len, AValue, AMaxLen);
end;

end.
