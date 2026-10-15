{
  PaPiMeLa.Platform.Alsa — libasound（ALSA）の実行時結合

  Origin : partially ported from SDL (src/audio/alsa/SDL_alsa_audio.c, SDL_alsa_audio.h)
           Scope: 結合する関数の一覧（SDL_alsa_audio.c の冒頭の ALSA_xxx と load_alsa_syms）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9.4、§11 #20

  WHAT:
    libasound.so.2 を dlopen で結合し（TPMLAlsa）、ヘッダの定数を src/generated/alsa_consts.inc
    （tools/genalsa.bb が C で作る）に、チャンネルの並びの問い合わせが返す構造体を同じ並びの
    レコードにする。hw_params・sw_params・ctl・pcm_info などは不透明な型で、大きさは
    xxx_sizeof() で問い合わせて自分で確保する（SDL の snd_pcm_hw_params_alloca と同じ）。

  WHY:
    ALSA の C API は定数と構造体の並びに頼る。ライブラリからは取れないので写すしかない。
    写しの正しさは、本物のヘッダで動かした C の結果と比べて確かめる（test/test_alsa_abi.pas）。

  RESOLVED:
    - snd_device_name_get_hint が返す文字列は malloc で確保されている。libc の free で解放する
      （SDL のコメントのとおり、SDL_free ではない）
    - snd_pcm_avail_delay（QNX 向け）は結合しない（初回のスコープは Linux だけ）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.Alsa;

{$I papimela.inc}
{$packrecords c}

interface

uses
  SysUtils, ctypes,
  PaPiMeLa.Errors,
  PaPiMeLa.Platform.DynLib;

{$I generated/alsa_consts.inc}

const
  // SDL_alsa_audio.c が結合するライブラリ
  PML_ALSA_LIBRARY = 'libasound.so.2';

type
  // ---- 不透明な型（空のレコードへの型付きポインタ。取り違えをコンパイラが見つける）
  TSndPcm = record end;
  PSndPcm = ^TSndPcm;
  PPSndPcm = ^PSndPcm;
  TSndPcmHwParams = record end;
  PSndPcmHwParams = ^TSndPcmHwParams;
  TSndPcmSwParams = record end;
  PSndPcmSwParams = ^TSndPcmSwParams;
  TSndCtl = record end;
  PSndCtl = ^TSndCtl;
  PPSndCtl = ^PSndCtl;
  TSndCtlCardInfo = record end;
  PSndCtlCardInfo = ^TSndCtlCardInfo;
  TSndPcmInfo = record end;
  PSndPcmInfo = ^TSndPcmInfo;

  // ---- チャンネルの並び（pcm.h の snd_pcm_chmap_t と snd_pcm_chmap_query_t）
  PSndPcmChmap = ^TSndPcmChmap;
  TSndPcmChmap = record
    Channels: cuint;
    // 後ろに Channels 個の位置（cuint）が続く（pos[0]）。Pos[I] で読む
  end;

  PSndPcmChmapQuery = ^TSndPcmChmapQuery;
  PPSndPcmChmapQuery = ^PSndPcmChmapQuery;
  TSndPcmChmapQuery = record
    ChmapType: cint;       // enum snd_pcm_chmap_type
    Map      : TSndPcmChmap;
  end;

  PCUInt = ^cuint;
  PCULong = ^culong;

  { 結合する関数（SDL の ALSA_xxx の一覧と同じ）。 }
  TPMLAlsaAPI = record
    pcm_open                       : function(var APcm: PSndPcm; AName: PChar; AStream: cint; AMode: cint): cint; cdecl;
    pcm_close                      : function(APcm: PSndPcm): cint; cdecl;
    pcm_start                      : function(APcm: PSndPcm): cint; cdecl;
    pcm_writei                     : function(APcm: PSndPcm; ABuf: Pointer; AFrames: culong): clong; cdecl;
    pcm_readi                      : function(APcm: PSndPcm; ABuf: Pointer; AFrames: culong): clong; cdecl;
    pcm_recover                    : function(APcm: PSndPcm; AErr: cint; ASilent: cint): cint; cdecl;
    pcm_prepare                    : function(APcm: PSndPcm): cint; cdecl;
    pcm_drain                      : function(APcm: PSndPcm): cint; cdecl;
    strerror                       : function(AErr: cint): PChar; cdecl;
    pcm_hw_params_sizeof           : function: csize_t; cdecl;
    pcm_sw_params_sizeof           : function: csize_t; cdecl;
    pcm_hw_params_copy             : procedure(ADst, ASrc: PSndPcmHwParams); cdecl;
    pcm_hw_params_any              : function(APcm: PSndPcm; AParams: PSndPcmHwParams): cint; cdecl;
    pcm_hw_params_set_access       : function(APcm: PSndPcm; AParams: PSndPcmHwParams; AAccess: cint): cint; cdecl;
    pcm_hw_params_set_format       : function(APcm: PSndPcm; AParams: PSndPcmHwParams; AFormat: cint): cint; cdecl;
    pcm_hw_params_set_channels     : function(APcm: PSndPcm; AParams: PSndPcmHwParams; AVal: cuint): cint; cdecl;
    pcm_hw_params_get_channels     : function(AParams: PSndPcmHwParams; var AVal: cuint): cint; cdecl;
    pcm_hw_params_set_rate_near    : function(APcm: PSndPcm; AParams: PSndPcmHwParams; var AVal: cuint; ADir: Pcint): cint; cdecl;
    pcm_hw_params_set_period_size_near: function(APcm: PSndPcm; AParams: PSndPcmHwParams; var AVal: culong; ADir: Pcint): cint; cdecl;
    pcm_hw_params_get_period_size  : function(AParams: PSndPcmHwParams; var AVal: culong; ADir: Pcint): cint; cdecl;
    pcm_hw_params_set_periods_min  : function(APcm: PSndPcm; AParams: PSndPcmHwParams; var AVal: cuint; ADir: Pcint): cint; cdecl;
    pcm_hw_params_set_periods_first: function(APcm: PSndPcm; AParams: PSndPcmHwParams; var AVal: cuint; ADir: Pcint): cint; cdecl;
    pcm_hw_params_get_periods      : function(AParams: PSndPcmHwParams; var AVal: cuint; ADir: Pcint): cint; cdecl;
    pcm_hw_params_set_buffer_size_near: function(APcm: PSndPcm; AParams: PSndPcmHwParams; var AVal: culong): cint; cdecl;
    pcm_hw_params_get_buffer_size  : function(AParams: PSndPcmHwParams; var AVal: culong): cint; cdecl;
    pcm_hw_params                  : function(APcm: PSndPcm; AParams: PSndPcmHwParams): cint; cdecl;
    pcm_sw_params_current          : function(APcm: PSndPcm; AParams: PSndPcmSwParams): cint; cdecl;
    pcm_sw_params_set_start_threshold: function(APcm: PSndPcm; AParams: PSndPcmSwParams; AVal: culong): cint; cdecl;
    pcm_sw_params                  : function(APcm: PSndPcm; AParams: PSndPcmSwParams): cint; cdecl;
    pcm_nonblock                   : function(APcm: PSndPcm; ANonBlock: cint): cint; cdecl;
    pcm_wait                       : function(APcm: PSndPcm; ATimeout: cint): cint; cdecl;
    pcm_sw_params_set_avail_min    : function(APcm: PSndPcm; AParams: PSndPcmSwParams; AVal: culong): cint; cdecl;
    pcm_reset                      : function(APcm: PSndPcm): cint; cdecl;
    pcm_state                      : function(APcm: PSndPcm): cint; cdecl;
    device_name_hint               : function(ACard: cint; AIface: PChar; var AHints: PPointer): cint; cdecl;
    device_name_get_hint           : function(AHint: Pointer; AId: PChar): PChar; cdecl;
    device_name_free_hint          : function(AHints: PPointer): cint; cdecl;
    pcm_avail                      : function(APcm: PSndPcm): clong; cdecl;
    ctl_card_info_sizeof           : function: csize_t; cdecl;
    pcm_info_sizeof                : function: csize_t; cdecl;
    card_next                      : function(var ACard: cint): cint; cdecl;
    ctl_open                       : function(var ACtl: PSndCtl; AName: PChar; AMode: cint): cint; cdecl;
    ctl_close                      : function(ACtl: PSndCtl): cint; cdecl;
    ctl_card_info                  : function(ACtl: PSndCtl; AInfo: PSndCtlCardInfo): cint; cdecl;
    ctl_pcm_next_device            : function(ACtl: PSndCtl; var ADevice: cint): cint; cdecl;
    pcm_info_get_subdevices_count  : function(AInfo: PSndPcmInfo): cuint; cdecl;
    pcm_info_set_device            : procedure(AInfo: PSndPcmInfo; ADev: cuint); cdecl;
    pcm_info_set_subdevice         : procedure(AInfo: PSndPcmInfo; ASubdev: cuint); cdecl;
    pcm_info_set_stream            : procedure(AInfo: PSndPcmInfo; AStream: cint); cdecl;
    ctl_pcm_info                   : function(ACtl: PSndCtl; AInfo: PSndPcmInfo): cint; cdecl;
    ctl_card_info_get_id           : function(AInfo: PSndCtlCardInfo): PChar; cdecl;
    pcm_info_get_name              : function(AInfo: PSndPcmInfo): PChar; cdecl;
    pcm_info_get_subdevice_name    : function(AInfo: PSndPcmInfo): PChar; cdecl;
    ctl_card_info_get_name         : function(AInfo: PSndCtlCardInfo): PChar; cdecl;
    ctl_card_info_clear            : procedure(AInfo: PSndCtlCardInfo); cdecl;
    pcm_hw_free                    : function(APcm: PSndPcm): cint; cdecl;
    pcm_hw_params_set_channels_near: function(APcm: PSndPcm; AParams: PSndPcmHwParams; var AVal: cuint): cint; cdecl;
    pcm_query_chmaps               : function(APcm: PSndPcm): PPSndPcmChmapQuery; cdecl;
    pcm_free_chmaps                : procedure(AMaps: PPSndPcmChmapQuery); cdecl;
    pcm_set_chmap                  : function(APcm: PSndPcm; AMap: PSndPcmChmap): cint; cdecl;
    pcm_chmap_print                : function(AMap: PSndPcmChmap; AMaxLen: csize_t; ABuf: PChar): cint; cdecl;
  end;

  TPMLAlsa = class
  strict private
    FLib: TPMLDynLib;
    procedure Bind(out ATarget; const ASymbol: String);
  public
    API: TPMLAlsaAPI;
    // 開けなければ EPMLPlatformLibrary。
    constructor Create;
    destructor Destroy; override;
    class function IsAvailable: Boolean; static;
  end;

// snd_pcm_chmap_t の後ろの位置の配列の I 番目（pos[I]）。
function PMLAlsaChmapPos(AMap: PSndPcmChmap; AIndex: Integer): cuint; inline;
procedure PMLAlsaChmapSetPos(AMap: PSndPcmChmap; AIndex: Integer; AValue: cuint); inline;

implementation

function PMLAlsaChmapPos(AMap: PSndPcmChmap; AIndex: Integer): cuint;
begin
  Result := PCUInt(PtrUInt(AMap) + SizeOf(TSndPcmChmap))[AIndex];
end;

procedure PMLAlsaChmapSetPos(AMap: PSndPcmChmap; AIndex: Integer; AValue: cuint);
begin
  PCUInt(PtrUInt(AMap) + SizeOf(TSndPcmChmap))[AIndex] := AValue;
end;

procedure TPMLAlsa.Bind(out ATarget; const ASymbol: String);
begin
  Pointer(ATarget) := FLib.Resolve(ASymbol);
end;

constructor TPMLAlsa.Create;
begin
  inherited Create;
  FLib := TPMLDynLib.Create([PML_ALSA_LIBRARY]);
  // SDL の load_alsa_syms と同じ一覧。
  Bind(API.pcm_open, 'snd_pcm_open');
  Bind(API.pcm_close, 'snd_pcm_close');
  Bind(API.pcm_start, 'snd_pcm_start');
  Bind(API.pcm_writei, 'snd_pcm_writei');
  Bind(API.pcm_readi, 'snd_pcm_readi');
  Bind(API.pcm_recover, 'snd_pcm_recover');
  Bind(API.pcm_prepare, 'snd_pcm_prepare');
  Bind(API.pcm_drain, 'snd_pcm_drain');
  Bind(API.strerror, 'snd_strerror');
  Bind(API.pcm_hw_params_sizeof, 'snd_pcm_hw_params_sizeof');
  Bind(API.pcm_sw_params_sizeof, 'snd_pcm_sw_params_sizeof');
  Bind(API.pcm_hw_params_copy, 'snd_pcm_hw_params_copy');
  Bind(API.pcm_hw_params_any, 'snd_pcm_hw_params_any');
  Bind(API.pcm_hw_params_set_access, 'snd_pcm_hw_params_set_access');
  Bind(API.pcm_hw_params_set_format, 'snd_pcm_hw_params_set_format');
  Bind(API.pcm_hw_params_set_channels, 'snd_pcm_hw_params_set_channels');
  Bind(API.pcm_hw_params_get_channels, 'snd_pcm_hw_params_get_channels');
  Bind(API.pcm_hw_params_set_rate_near, 'snd_pcm_hw_params_set_rate_near');
  Bind(API.pcm_hw_params_set_period_size_near, 'snd_pcm_hw_params_set_period_size_near');
  Bind(API.pcm_hw_params_get_period_size, 'snd_pcm_hw_params_get_period_size');
  Bind(API.pcm_hw_params_set_periods_min, 'snd_pcm_hw_params_set_periods_min');
  Bind(API.pcm_hw_params_set_periods_first, 'snd_pcm_hw_params_set_periods_first');
  Bind(API.pcm_hw_params_get_periods, 'snd_pcm_hw_params_get_periods');
  Bind(API.pcm_hw_params_set_buffer_size_near, 'snd_pcm_hw_params_set_buffer_size_near');
  Bind(API.pcm_hw_params_get_buffer_size, 'snd_pcm_hw_params_get_buffer_size');
  Bind(API.pcm_hw_params, 'snd_pcm_hw_params');
  Bind(API.pcm_sw_params_current, 'snd_pcm_sw_params_current');
  Bind(API.pcm_sw_params_set_start_threshold, 'snd_pcm_sw_params_set_start_threshold');
  Bind(API.pcm_sw_params, 'snd_pcm_sw_params');
  Bind(API.pcm_nonblock, 'snd_pcm_nonblock');
  Bind(API.pcm_wait, 'snd_pcm_wait');
  Bind(API.pcm_sw_params_set_avail_min, 'snd_pcm_sw_params_set_avail_min');
  Bind(API.pcm_reset, 'snd_pcm_reset');
  Bind(API.pcm_state, 'snd_pcm_state');
  Bind(API.device_name_hint, 'snd_device_name_hint');
  Bind(API.device_name_get_hint, 'snd_device_name_get_hint');
  Bind(API.device_name_free_hint, 'snd_device_name_free_hint');
  Bind(API.pcm_avail, 'snd_pcm_avail');
  Bind(API.ctl_card_info_sizeof, 'snd_ctl_card_info_sizeof');
  Bind(API.pcm_info_sizeof, 'snd_pcm_info_sizeof');
  Bind(API.card_next, 'snd_card_next');
  Bind(API.ctl_open, 'snd_ctl_open');
  Bind(API.ctl_close, 'snd_ctl_close');
  Bind(API.ctl_card_info, 'snd_ctl_card_info');
  Bind(API.ctl_pcm_next_device, 'snd_ctl_pcm_next_device');
  Bind(API.pcm_info_get_subdevices_count, 'snd_pcm_info_get_subdevices_count');
  Bind(API.pcm_info_set_device, 'snd_pcm_info_set_device');
  Bind(API.pcm_info_set_subdevice, 'snd_pcm_info_set_subdevice');
  Bind(API.pcm_info_set_stream, 'snd_pcm_info_set_stream');
  Bind(API.ctl_pcm_info, 'snd_ctl_pcm_info');
  Bind(API.ctl_card_info_get_id, 'snd_ctl_card_info_get_id');
  Bind(API.pcm_info_get_name, 'snd_pcm_info_get_name');
  Bind(API.pcm_info_get_subdevice_name, 'snd_pcm_info_get_subdevice_name');
  Bind(API.ctl_card_info_get_name, 'snd_ctl_card_info_get_name');
  Bind(API.ctl_card_info_clear, 'snd_ctl_card_info_clear');
  Bind(API.pcm_hw_free, 'snd_pcm_hw_free');
  Bind(API.pcm_hw_params_set_channels_near, 'snd_pcm_hw_params_set_channels_near');
  Bind(API.pcm_query_chmaps, 'snd_pcm_query_chmaps');
  Bind(API.pcm_free_chmaps, 'snd_pcm_free_chmaps');
  Bind(API.pcm_set_chmap, 'snd_pcm_set_chmap');
  Bind(API.pcm_chmap_print, 'snd_pcm_chmap_print');
end;

destructor TPMLAlsa.Destroy;
begin
  FLib.Free;
  inherited Destroy;
end;

class function TPMLAlsa.IsAvailable: Boolean;
begin
  Result := TPMLDynLib.IsAvailable([PML_ALSA_LIBRARY]);
end;

end.
