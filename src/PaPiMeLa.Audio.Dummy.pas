{
  PaPiMeLa.Audio.Dummy — 音をどこにも出さないオーディオバックエンド

  Origin : ported from SDL (src/audio/dummy/SDL_dummyaudio.c)
           Scope: SDL_dummyaudio.c の全体（Emscripten の部分を除く）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #55

  WHAT:
    既定の再生と録音のデバイスを 1 台ずつ持つ。再生は 1 回分の時間だけ待って捨て、録音は
    いつも無音を返す。

  WHY:
    テストと CI のため。音の出るサーバが無くても、デバイスのスレッド・混ぜる・結び付けを
    本物と同じ道筋で動かせる。

  RESOLVED:
    - 「求められたときだけ」のバックエンド（SDL の demand_only）。ヒント
      PAPIMELA_AUDIO_DRIVER=dummy で選ぶ。既定では試さない
    - 待ち時間は 1 回分のフレーム数 / 周波数（ミリ秒、切り捨て）。ヒント
      PAPIMELA_AUDIO_DUMMY_TIMESCALE を掛けられる（0 以上。四捨五入）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Dummy;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Time,
  PaPiMeLa.Properties,
  PaPiMeLa.Audio.Backend;

type
  TPMLDummyAudioBackend = class(TPMLAudioBackend)
  public
    constructor Create(ACore: TPMLAudioCore); override;
    function  Name: String; override;
    function  OpenDevice(ADevice: TPMLAudioDevice): Boolean; override;
    procedure CloseDevice(ADevice: TPMLAudioDevice); override;
    function  WaitDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte; override;
    function  WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean; override;
    function  RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer; ALen: Integer): Integer; override;
  end;

implementation

type
  // SDL_PrivateAudioData。
  TDummyDeviceData = class
  public
    MixBuf : PByte;      // 再生の置き場（捨てるだけ）
    IODelay: LongWord;   // WaitDevice で寝るミリ秒
    destructor Destroy; override;
  end;

destructor TDummyDeviceData.Destroy;
begin
  if MixBuf <> nil then
    FreeMem(MixBuf);
  inherited Destroy;
end;

constructor TPMLDummyAudioBackend.Create(ACore: TPMLAudioCore);
begin
  inherited Create(ACore);
  FCapabilities := [TPMLAudioBackendCapability.OnlyHasDefaultPlaybackDevice,
    TPMLAudioBackendCapability.OnlyHasDefaultRecordingDevice,
    TPMLAudioBackendCapability.HasRecordingSupport];
end;

function TPMLDummyAudioBackend.Name: String;
begin
  Result := 'dummy';
end;

{ DUMMYAUDIO_OpenDevice。デバイスの形式は変えない。 }
function TPMLDummyAudioBackend.OpenDevice(ADevice: TPMLAudioDevice): Boolean;
var
  Data: TDummyDeviceData;
  HintText: String;
  Scale: Double;
begin
  Data := TDummyDeviceData.Create;
  ADevice.Hidden := Data;
  if not ADevice.Recording then
    Data.MixBuf := GetMem(ADevice.BufferSize);
  Data.IODelay := LongWord((ADevice.SampleFrames * 1000) div ADevice.Spec.Freq);

  HintText := Trim(FCore.Hint(PML_HINT_AUDIO_DUMMY_TIMESCALE));
  // SDL_atof は読めなければ 0（待たない）。
  if HintText <> '' then
  begin
    if not TryStrToFloat(HintText, Scale, DefaultFormatSettings) then
      Scale := 0;
    if Scale >= 0 then
      // SDL_round は 0.5 を 0 から遠い方へ丸める（Pascal の Round は偶数へ）。
      Data.IODelay := LongWord(Trunc(Data.IODelay * Scale + 0.5));
  end;
  Result := True;
end;

procedure TPMLDummyAudioBackend.CloseDevice(ADevice: TPMLAudioDevice);
begin
  ADevice.Hidden.Free;
  ADevice.Hidden := nil;
end;

function TPMLDummyAudioBackend.WaitDevice(ADevice: TPMLAudioDevice): Boolean;
begin
  PMLDelay(TDummyDeviceData(ADevice.Hidden).IODelay);
  Result := True;
end;

function TPMLDummyAudioBackend.GetDeviceBuf(ADevice: TPMLAudioDevice; var ASize: Integer): PByte;
begin
  Result := TDummyDeviceData(ADevice.Hidden).MixBuf;
end;

function TPMLDummyAudioBackend.WaitRecordingDevice(ADevice: TPMLAudioDevice): Boolean;
begin
  Result := WaitDevice(ADevice);
end;

{ いつも無音で満たす。 }
function TPMLDummyAudioBackend.RecordDevice(ADevice: TPMLAudioDevice; ABuffer: Pointer;
  ALen: Integer): Integer;
begin
  FillChar(ABuffer^, ALen, ADevice.SilenceValue);
  Result := ALen;
end;

function CreateDummyAudioBackend(ACore: TPMLAudioCore): TPMLAudioBackend;
begin
  Result := TPMLDummyAudioBackend.Create(ACore);
end;

initialization
  // 優先度は 0（ビデオの dummy と同じ）。求められたときだけ使う。
  PMLRegisterAudioBackend('dummy', 0, @CreateDummyAudioBackend, True);

end.
