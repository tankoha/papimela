{
  PaPiMeLa.Platform.Pulse — libpulse の実行時結合

  Origin : partially ported from SDL (src/audio/pulseaudio/SDL_pulseaudio.c, SDL_pulseaudio.h)
           Scope: 結合する関数の一覧（SDL_pulseaudio.c の冒頭の PULSEAUDIO_xxx と load_pulseaudio_syms）、
           PA_CONTEXT_IS_GOOD / PA_STREAM_IS_GOOD。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9.4、§11 #20

  WHAT:
    libpulse.so.0 を dlopen で結合し（TPMLPulse）、ヘッダの構造体を同じ並びのレコードに、
    定数を src/generated/pulse_consts.inc（tools/genpulse.bb が C で作る）にする。コールバックが
    ポインタで渡してくる構造体（pa_sink_info など）は、バックエンドが読む欄までの前半だけを写した。

  WHY:
    PulseAudio の C API は定数と構造体の並びに頼る。ライブラリからは取れないので写すしかない。
    写しの正しさは、本物のヘッダで動かした C の結果と比べて確かめる（test/test_pulse_abi.pas）。

  RESOLVED:
    - 浮動小数点の例外（FPC は有効、C は無効が前提）: pa_threaded_mainloop_start が作るスレッドは
      作った側の設定を受け継ぐ。PipeWire と同じく、呼んだスレッドの例外を PMLPulseMaskBegin / End で
      止める。念のため、コールバックの入口でも止める（PMLPulseCallbackEnter）
    - pa_operation_set_state_callback（PulseAudio 4.0 から）と pa_threaded_mainloop_set_name
      （5.0 から）は、無くても動く（SDL の optional と同じ）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Pulse;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils, Math, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

{$I generated/pulse_consts.inc}

const
  // SDL_pulseaudio.c が結合するライブラリ
  PML_PULSE_LIBRARY = 'libpulse.so.0';

type
  // ---- 不透明な型（空のレコードへの型付きポインタ。取り違えをコンパイラが見つける）
  TPAThreadedMainloop = record end;
  PPAThreadedMainloop = ^TPAThreadedMainloop;
  TPAMainloopAPI = record end;
  PPAMainloopAPI = ^TPAMainloopAPI;
  TPAContext = record end;
  PPAContext = ^TPAContext;
  TPAStream = record end;
  PPAStream = ^TPAStream;
  TPAOperation = record end;
  PPAOperation = ^TPAOperation;
  TPAProplist = record end;
  PPAProplist = ^TPAProplist;
  TPASpawnAPI = record end;
  PPASpawnAPI = ^TPASpawnAPI;

  // ---- sample.h・channelmap.h・def.h・volume.h
  PPASampleSpec = ^TPASampleSpec;
  TPASampleSpec = record
    Format  : cint;
    Rate    : cuint32;
    Channels: cuint8;
  end;

  PPAChannelMap = ^TPAChannelMap;
  TPAChannelMap = record
    Channels: cuint8;
    Map     : array[0..PA_CHANNELS_MAX - 1] of cint;
  end;

  PPABufferAttr = ^TPABufferAttr;
  TPABufferAttr = record
    MaxLength: cuint32;
    TLength  : cuint32;
    PreBuf   : cuint32;
    MinReq   : cuint32;
    FragSize : cuint32;
  end;

  PPACVolume = ^TPACVolume;
  TPACVolume = record
    Channels: cuint8;
    Values  : array[0..PA_CHANNELS_MAX - 1] of cuint32;
  end;

  { introspect.h。使う欄までの前半だけ（残りは書かない。バックエンドは渡されたポインタを読むだけで、
    大きさを当てにしない）。 }
  PPASinkInfo = ^TPASinkInfo;
  TPASinkInfo = record
    Name             : PChar;
    Index            : cuint32;
    Description      : PChar;
    SampleSpec       : TPASampleSpec;
    ChannelMap       : TPAChannelMap;
    OwnerModule      : cuint32;
    Volume           : TPACVolume;
    Mute             : cint;
    MonitorSource    : cuint32;
    MonitorSourceName: PChar;
  end;

  PPASourceInfo = ^TPASourceInfo;
  TPASourceInfo = record
    Name             : PChar;
    Index            : cuint32;
    Description      : PChar;
    SampleSpec       : TPASampleSpec;
    ChannelMap       : TPAChannelMap;
    OwnerModule      : cuint32;
    Volume           : TPACVolume;
    Mute             : cint;
    MonitorOfSink    : cuint32;
    MonitorOfSinkName: PChar;
  end;

  PPAServerInfo = ^TPAServerInfo;
  TPAServerInfo = record
    UserName         : PChar;
    HostName         : PChar;
    ServerVersion    : PChar;
    ServerName       : PChar;
    SampleSpec       : TPASampleSpec;
    DefaultSinkName  : PChar;
    DefaultSourceName: PChar;
    Cookie           : cuint32;
    ChannelMap       : TPAChannelMap;
  end;

  // ---- コールバック
  TPAContextNotifyCb  = procedure(AContext: PPAContext; AUserData: Pointer); cdecl;
  TPAContextSuccessCb = procedure(AContext: PPAContext; ASuccess: cint; AUserData: Pointer); cdecl;
  TPAContextSubscribeCb = procedure(AContext: PPAContext; AEvent: cint; AIndex: cuint32;
    AUserData: Pointer); cdecl;
  TPASinkInfoCb   = procedure(AContext: PPAContext; AInfo: PPASinkInfo; AEol: cint; AUserData: Pointer); cdecl;
  TPASourceInfoCb = procedure(AContext: PPAContext; AInfo: PPASourceInfo; AEol: cint; AUserData: Pointer); cdecl;
  TPAServerInfoCb = procedure(AContext: PPAContext; AInfo: PPAServerInfo; AUserData: Pointer); cdecl;
  TPAStreamNotifyCb  = procedure(AStream: PPAStream; AUserData: Pointer); cdecl;
  TPAStreamRequestCb = procedure(AStream: PPAStream; ANBytes: csize_t; AUserData: Pointer); cdecl;
  TPAStreamSuccessCb = procedure(AStream: PPAStream; ASuccess: cint; AUserData: Pointer); cdecl;
  TPAOperationNotifyCb = procedure(AOperation: PPAOperation; AUserData: Pointer); cdecl;
  TPAFreeCb = procedure(AData: Pointer); cdecl;

  { 結合する関数（SDL の PULSEAUDIO_xxx の一覧と同じ）。オプションの 2 つは無ければ nil。 }
  TPMLPulseAPI = record
    get_library_version             : function: PChar; cdecl;
    channel_map_init_auto           : function(AMap: PPAChannelMap; AChannels: cuint; ADef: cint): PPAChannelMap; cdecl;
    strerror                        : function(AError: cint): PChar; cdecl;
    proplist_new                    : function: PPAProplist; cdecl;
    proplist_free                   : procedure(AProplist: PPAProplist); cdecl;
    proplist_sets                   : function(AProplist: PPAProplist; AKey, AValue: PChar): cint; cdecl;

    threaded_mainloop_new           : function: PPAThreadedMainloop; cdecl;
    threaded_mainloop_set_name      : procedure(AM: PPAThreadedMainloop; AName: PChar); cdecl;  // 5.0 から。無ければ nil
    threaded_mainloop_get_api       : function(AM: PPAThreadedMainloop): PPAMainloopAPI; cdecl;
    threaded_mainloop_start         : function(AM: PPAThreadedMainloop): cint; cdecl;
    threaded_mainloop_stop          : procedure(AM: PPAThreadedMainloop); cdecl;
    threaded_mainloop_lock          : procedure(AM: PPAThreadedMainloop); cdecl;
    threaded_mainloop_unlock        : procedure(AM: PPAThreadedMainloop); cdecl;
    threaded_mainloop_wait          : procedure(AM: PPAThreadedMainloop); cdecl;
    threaded_mainloop_signal        : procedure(AM: PPAThreadedMainloop; AWaitForAccept: cint); cdecl;
    threaded_mainloop_free          : procedure(AM: PPAThreadedMainloop); cdecl;

    operation_get_state             : function(AOp: PPAOperation): cint; cdecl;
    operation_set_state_callback    : procedure(AOp: PPAOperation; ACb: TPAOperationNotifyCb; AUserData: Pointer); cdecl;  // 4.0 から。無ければ nil
    operation_cancel                : procedure(AOp: PPAOperation); cdecl;
    operation_unref                 : procedure(AOp: PPAOperation); cdecl;

    context_new_with_proplist       : function(AApi: PPAMainloopAPI; AName: PChar; AProplist: PPAProplist): PPAContext; cdecl;
    context_set_state_callback      : procedure(AC: PPAContext; ACb: TPAContextNotifyCb; AUserData: Pointer); cdecl;
    context_connect                 : function(AC: PPAContext; AServer: PChar; AFlags: cint; ASpawn: PPASpawnAPI): cint; cdecl;
    context_get_sink_info_list      : function(AC: PPAContext; ACb: TPASinkInfoCb; AUserData: Pointer): PPAOperation; cdecl;
    context_get_source_info_list    : function(AC: PPAContext; ACb: TPASourceInfoCb; AUserData: Pointer): PPAOperation; cdecl;
    context_get_sink_info_by_index  : function(AC: PPAContext; AIndex: cuint32; ACb: TPASinkInfoCb; AUserData: Pointer): PPAOperation; cdecl;
    context_get_source_info_by_index: function(AC: PPAContext; AIndex: cuint32; ACb: TPASourceInfoCb; AUserData: Pointer): PPAOperation; cdecl;
    context_get_state               : function(AC: PPAContext): cint; cdecl;
    context_subscribe               : function(AC: PPAContext; AMask: cint; ACb: TPAContextSuccessCb; AUserData: Pointer): PPAOperation; cdecl;
    context_set_subscribe_callback  : procedure(AC: PPAContext; ACb: TPAContextSubscribeCb; AUserData: Pointer); cdecl;
    context_disconnect              : procedure(AC: PPAContext); cdecl;
    context_unref                   : procedure(AC: PPAContext); cdecl;
    context_get_server_info         : function(AC: PPAContext; ACb: TPAServerInfoCb; AUserData: Pointer): PPAOperation; cdecl;

    stream_new                      : function(AC: PPAContext; AName: PChar; ASpec: PPASampleSpec; AMap: PPAChannelMap): PPAStream; cdecl;
    stream_set_state_callback       : procedure(AStr: PPAStream; ACb: TPAStreamNotifyCb; AUserData: Pointer); cdecl;
    stream_connect_playback         : function(AStr: PPAStream; ADev: PChar; AAttr: PPABufferAttr; AFlags: cint; AVolume: PPACVolume; ASync: PPAStream): cint; cdecl;
    stream_connect_record           : function(AStr: PPAStream; ADev: PChar; AAttr: PPABufferAttr; AFlags: cint): cint; cdecl;
    stream_get_buffer_attr          : function(AStr: PPAStream): PPABufferAttr; cdecl;
    stream_get_state                : function(AStr: PPAStream): cint; cdecl;
    stream_writable_size            : function(AStr: PPAStream): csize_t; cdecl;
    stream_readable_size            : function(AStr: PPAStream): csize_t; cdecl;
    stream_begin_write              : function(AStr: PPAStream; var AData: Pointer; var ANBytes: csize_t): cint; cdecl;
    stream_write                    : function(AStr: PPAStream; AData: Pointer; ANBytes: csize_t; AFree: TPAFreeCb; AOffset: cint64; ASeek: cint): cint; cdecl;
    stream_drain                    : function(AStr: PPAStream; ACb: TPAStreamSuccessCb; AUserData: Pointer): PPAOperation; cdecl;
    stream_disconnect               : function(AStr: PPAStream): cint; cdecl;
    stream_peek                     : function(AStr: PPAStream; var AData: Pointer; var ANBytes: csize_t): cint; cdecl;
    stream_drop                     : function(AStr: PPAStream): cint; cdecl;
    stream_flush                    : function(AStr: PPAStream; ACb: TPAStreamSuccessCb; AUserData: Pointer): PPAOperation; cdecl;
    stream_unref                    : procedure(AStr: PPAStream); cdecl;
    stream_set_write_callback       : procedure(AStr: PPAStream; ACb: TPAStreamRequestCb; AUserData: Pointer); cdecl;
    stream_set_read_callback        : procedure(AStr: PPAStream; ACb: TPAStreamRequestCb; AUserData: Pointer); cdecl;
  end;

  TPMLPulse = class
  strict private
    FLib: TPMLDynLib;
    procedure Bind(out ATarget; const ASymbol: String);
    procedure BindOptional(out ATarget; const ASymbol: String);
  public
    API: TPMLPulseAPI;
    // 開けなければ EPMLPlatformLibrary。
    constructor Create;
    destructor Destroy; override;
    class function IsAvailable: Boolean; static;
  end;

{ PA_CONTEXT_IS_GOOD / PA_STREAM_IS_GOOD（def.h のマクロ）。 }
function PMLPulseContextIsGood(AState: cint): Boolean; inline;
function PMLPulseStreamIsGood(AState: cint): Boolean; inline;

// 浮動小数点の例外（FPC は有効、C は無効が前提）。PMLPipeWireMaskBegin と同じ。
procedure PMLPulseCallbackEnter;
function  PMLPulseMaskBegin: TFPUExceptionMask;
procedure PMLPulseMaskEnd(const AOld: TFPUExceptionMask);
// 入口で例外が有効だった回数（0 のはず。PMLPulseMaskBegin が効いていれば）。
function  PMLPulseUnmaskedEntries: LongInt;

implementation

const
  AllMasked: TFPUExceptionMask = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow,
    exPrecision];

var
  UnmaskedEntries: LongInt = 0;

function PMLPulseContextIsGood(AState: cint): Boolean;
begin
  Result := (AState = PA_CONTEXT_CONNECTING) or (AState = PA_CONTEXT_AUTHORIZING)
    or (AState = PA_CONTEXT_SETTING_NAME) or (AState = PA_CONTEXT_READY);
end;

function PMLPulseStreamIsGood(AState: cint): Boolean;
begin
  Result := (AState = PA_STREAM_CREATING) or (AState = PA_STREAM_READY);
end;

procedure PMLPulseCallbackEnter;
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

function PMLPulseMaskBegin: TFPUExceptionMask;
begin
  // FPC 3.2.2 の aarch64 は SetExceptionMask が前の値でなく新しい値を返す。先に読んでおく
  Result := GetExceptionMask;
  SetExceptionMask(AllMasked);
end;

procedure PMLPulseMaskEnd(const AOld: TFPUExceptionMask);
begin
  SetExceptionMask(AOld);
end;

function PMLPulseUnmaskedEntries: LongInt;
begin
  Result := UnmaskedEntries;
end;

{ TPMLPulse }

procedure TPMLPulse.Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := FLib.Resolve(ASymbol);
end;

procedure TPMLPulse.BindOptional(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := FLib.TryResolve(ASymbol);
end;

constructor TPMLPulse.Create;
begin
  inherited Create;
  FLib := TPMLDynLib.Create([PML_PULSE_LIBRARY]);
  // SDL の load_pulseaudio_syms と同じ一覧。
  Bind(API.get_library_version, 'pa_get_library_version');
  Bind(API.threaded_mainloop_new, 'pa_threaded_mainloop_new');
  Bind(API.threaded_mainloop_get_api, 'pa_threaded_mainloop_get_api');
  Bind(API.threaded_mainloop_start, 'pa_threaded_mainloop_start');
  Bind(API.threaded_mainloop_stop, 'pa_threaded_mainloop_stop');
  Bind(API.threaded_mainloop_lock, 'pa_threaded_mainloop_lock');
  Bind(API.threaded_mainloop_unlock, 'pa_threaded_mainloop_unlock');
  Bind(API.threaded_mainloop_wait, 'pa_threaded_mainloop_wait');
  Bind(API.threaded_mainloop_signal, 'pa_threaded_mainloop_signal');
  Bind(API.threaded_mainloop_free, 'pa_threaded_mainloop_free');
  Bind(API.operation_get_state, 'pa_operation_get_state');
  Bind(API.operation_cancel, 'pa_operation_cancel');
  Bind(API.operation_unref, 'pa_operation_unref');
  Bind(API.context_new_with_proplist, 'pa_context_new_with_proplist');
  Bind(API.context_set_state_callback, 'pa_context_set_state_callback');
  Bind(API.context_connect, 'pa_context_connect');
  Bind(API.context_get_sink_info_list, 'pa_context_get_sink_info_list');
  Bind(API.context_get_source_info_list, 'pa_context_get_source_info_list');
  Bind(API.context_get_sink_info_by_index, 'pa_context_get_sink_info_by_index');
  Bind(API.context_get_source_info_by_index, 'pa_context_get_source_info_by_index');
  Bind(API.context_get_state, 'pa_context_get_state');
  Bind(API.context_subscribe, 'pa_context_subscribe');
  Bind(API.context_set_subscribe_callback, 'pa_context_set_subscribe_callback');
  Bind(API.context_disconnect, 'pa_context_disconnect');
  Bind(API.context_unref, 'pa_context_unref');
  Bind(API.stream_new, 'pa_stream_new');
  Bind(API.stream_set_state_callback, 'pa_stream_set_state_callback');
  Bind(API.stream_connect_playback, 'pa_stream_connect_playback');
  Bind(API.stream_connect_record, 'pa_stream_connect_record');
  Bind(API.stream_get_buffer_attr, 'pa_stream_get_buffer_attr');
  Bind(API.stream_get_state, 'pa_stream_get_state');
  Bind(API.stream_writable_size, 'pa_stream_writable_size');
  Bind(API.stream_readable_size, 'pa_stream_readable_size');
  Bind(API.stream_begin_write, 'pa_stream_begin_write');
  Bind(API.stream_write, 'pa_stream_write');
  Bind(API.stream_drain, 'pa_stream_drain');
  Bind(API.stream_disconnect, 'pa_stream_disconnect');
  Bind(API.stream_peek, 'pa_stream_peek');
  Bind(API.stream_drop, 'pa_stream_drop');
  Bind(API.stream_flush, 'pa_stream_flush');
  Bind(API.stream_unref, 'pa_stream_unref');
  Bind(API.channel_map_init_auto, 'pa_channel_map_init_auto');
  Bind(API.strerror, 'pa_strerror');
  Bind(API.stream_set_write_callback, 'pa_stream_set_write_callback');
  Bind(API.stream_set_read_callback, 'pa_stream_set_read_callback');
  Bind(API.context_get_server_info, 'pa_context_get_server_info');
  Bind(API.proplist_new, 'pa_proplist_new');
  Bind(API.proplist_free, 'pa_proplist_free');
  Bind(API.proplist_sets, 'pa_proplist_sets');
  // オプション（古い PulseAudio には無い）
  BindOptional(API.operation_set_state_callback, 'pa_operation_set_state_callback');
  BindOptional(API.threaded_mainloop_set_name, 'pa_threaded_mainloop_set_name');
end;

destructor TPMLPulse.Destroy;
begin
  FLib.Free;
  inherited Destroy;
end;

class function TPMLPulse.IsAvailable: Boolean;
begin
  Result := TPMLDynLib.IsAvailable([PML_PULSE_LIBRARY]);
end;

end.
