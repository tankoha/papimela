{
  PaPiMeLa.Audio.Stream — 音声のストリーム（形式・チャンネル数・周波数の変換つきの待ち行列）

  Origin : ported from SDL (src/audio/SDL_audiocvt.c)
           Scope: SDL_AudioStream の作成と形式の変更、チャンネルの並び、周波数の比、音量、
           入力（PutData・PutDataNoCopy・PutPlanarData。大きな入力はロックの外で写す）、
           出力（GetData。トラックごとに、周波数を変えるなら余白つきで読んで変換し、
           チャンネルを増やすときは変換の後、減らすときは前）、Available・Queued・Flush・Clear、
           呼び出し（OnGet・OnPut と、その量の計算）、SDL_ConvertAudioSamples。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #52

  WHAT:
    アプリが Create する TPMLAudioStream。入力の形式（SrcSpec）で PutData し、出力の形式
    （DstSpec）で GetData する。オーディオのデバイスに結び付けると（2 段目）、デバイスの
    スレッドが GetData で取り出して鳴らす。

  WHY:
    SDL3 の音声の中心はストリーム。デバイスの層（SDL_audio.c）はストリームを混ぜるだけ。

  PORT-NOTE:
    - SDL の bool の失敗（SDL_SetError）は例外にした。引数の誤りは EPMLArgument、内部の失敗は
      EPMLAudioError。GetData は何も出せないうちに内部で失敗したときだけ EPMLAudioError
      （SDL は -1。出せたあとの失敗は SDL と同じく出せた量を返す）
    - PutPlanarData の置き場の数が入力のチャンネル数と違えば EPMLArgument（SDL は足りなければ
      nil で埋め、多ければ無視する）。入力が 1 チャンネルで nil の置き場は、SDL と同じく誤り
    - CheckAudioStreamIsFullySetup は要らない（作るときに両方の形式を持つ）

  NOT RESOLVED:
    - デバイスへの結び付け（bind）は 2 段目（#51）。BoundDevice と、結び付いた側の形式を
      変えさせない規則はそのときに足す

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Stream;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Threading,
  PaPiMeLa.Audio.Convert,
  PaPiMeLa.Audio.Queue;

type
  TPMLAudioStream = class;

  { 入力・出力の呼び出し（SDL_AudioStreamCallback）。ストリームのロックを持ったまま、
    呼んだスレッド（デバイスに結び付いていればデバイスのスレッド）から来る。
    AAdditionalAmount は足りない分、ATotalAmount は今回求められた分（どちらもバイト）。
    OnGet では入力の形式のバイト数、OnPut では増えた出力のバイト数（SDL と同じ）。 }
  TPMLAudioStreamCallback = procedure(AStream: TPMLAudioStream;
    AAdditionalAmount, ATotalAmount: Integer) of object;

  { PutDataNoCopy の置き場を使い終えた知らせ（SDL_AudioStreamDataCompleteCallback）。 }
  TPMLAudioStreamDataComplete = TPMLReleaseAudioBufferCallback;

  { 音声のストリーム（SDL_AudioStream）。どのメソッドもスレッド安全（内部でロックする）。
    引数の誤り（形式・チャンネル数・周波数・長さ・並び）は EPMLArgument。 }
  TPMLAudioStream = class(TPMLOwnedObject)
  strict private
    FOnGet: TPMLAudioStreamCallback;
    FOnPut: TPMLAudioStreamCallback;
    // SDL_AudioStream の中身。bound_device・simplified・全ストリームの連なり・props は 2 段目（デバイス）。
    FLock: TPMLMutex;
    FSrcSpec: TPMLAudioSpec;
    FDstSpec: TPMLAudioSpec;
    FSrcMap: TPMLChannelMap;
    FDstMap: TPMLChannelMap;
    FFreqRatio: Single;
    FGain: Single;
    FQueue: TPMLAudioQueue;
    // 今処理している入力の形式と並び、周波数の変換の位置（32.32）。
    FInputSpec: TPMLAudioSpec;
    FInputMap: TPMLChannelMap;
    FResampleOffset: Int64;
    // 変換の作業の置き場（SIMD の整列は値に影響しないので、整列は求めない）。
    FWorkBuffer: PByte;
    FWorkBufferSize: PtrUInt;
    procedure ApplyFormat(AChangeSrc: Boolean; const ASrcSpec: TPMLAudioSpec;
      AChangeDst: Boolean; const ADstSpec: TPMLAudioSpec);
    procedure ApplyChannelMap(AIsInput: Boolean; const AMap: TPMLChannelMap);
    function  ResampleRate(ASrcFreq: Integer; AResampleOffset: Int64): Int64;
    function  UpdateInputSpec(const ASpec: TPMLAudioSpec; const AMap: TPMLChannelMap): Boolean;
    procedure PutBufferInternal(const ASpec: TPMLAudioSpec; const AMap: TPMLChannelMap;
      ABuf: Pointer; ALen: Integer; ACallback: TPMLReleaseAudioBufferCallback;
      AUserData: Pointer; out ATaken: Boolean);
    procedure PutBuffer(ABuf: Pointer; ALen: Integer; ACallback: TPMLReleaseAudioBufferCallback;
      AUserData: Pointer; out ATaken: Boolean);
    function  EnsureWorkBuffer(ANewLen: PtrUInt): PByte;
    function  NextAudioIter(var AIter: Pointer; var AResampleOffset: Int64;
      out ASpec: TPMLAudioSpec; out AMap: TPMLChannelMap; out AFlushed: Boolean): Int64;
    function  AvailableFrames(AOutResampleOffset: PInt64): Int64;
    function  HeadFrames(out ASpec: TPMLAudioSpec; out AMap: TPMLChannelMap;
      out AFlushed: Boolean): Int64;
    function  GetDataInternal(ABuf: PByte; AOutputFrames: Integer; AGain: Single): Boolean;
    function  GetOnGet: TPMLAudioStreamCallback;
    procedure SetOnGet(AValue: TPMLAudioStreamCallback);
    function  GetOnPut: TPMLAudioStreamCallback;
    procedure SetOnPut(AValue: TPMLAudioStreamCallback);
  public
    { SDL_CreateAudioStream。形式・チャンネル数（1〜8）・周波数（1 以上）を確かめる。 }
    constructor Create(const ASrcSpec, ADstSpec: TPMLAudioSpec);
    destructor Destroy; override;

    { SDL_SetAudioStreamFormat。チャンネル数が変わった側の並びは消える。 }
    procedure SetFormat(const ASrcSpec, ADstSpec: TPMLAudioSpec);
    // 片側だけ変える（SDL で他方に NULL を渡すのと同じ）。
    procedure SetSrcFormat(const ASpec: TPMLAudioSpec);
    procedure SetDstFormat(const ASpec: TPMLAudioSpec);
    function  SrcSpec: TPMLAudioSpec;
    function  DstSpec: TPMLAudioSpec;

    { SDL_SetAudioStreamInputChannelMap / OutputChannelMap。長さはその側のチャンネル数
      （違えば EPMLArgument）。空の配列か恒等の並びで既定に戻す。値が -1..チャンネル数-1 の
      外なら EPMLArgument。読むと写しを返す（既定なら空）。 }
    procedure SetInputChannelMap(const AMap: TPMLChannelMap);
    procedure SetOutputChannelMap(const AMap: TPMLChannelMap);
    function  InputChannelMap: TPMLChannelMap;
    function  OutputChannelMap: TPMLChannelMap;

    { 入力の周波数に掛ける比（SDL_SetAudioStreamFrequencyRatio）。0.01〜100 の外は EPMLArgument。 }
    function  GetFrequencyRatio: Single;
    procedure SetFrequencyRatio(AValue: Single);
    { 音量（SDL_SetAudioStreamGain）。負なら EPMLArgument。 }
    function  GetGain: Single;
    procedure SetGain(AValue: Single);

    { 入力を足す（SDL_PutAudioStreamData）。ALen は入力の 1 フレームの倍数（違えば EPMLArgument）。
      写すので、戻ったら ABuf は再利用してよい。 }
    procedure PutData(ABuf: Pointer; ALen: Integer);
    { 写さずに足す（SDL_PutAudioStreamDataNoCopy）。使い終えたら ACallback を呼ぶ（nil でもよい）。 }
    procedure PutDataNoCopy(ABuf: Pointer; ALen: Integer;
      ACallback: TPMLAudioStreamDataComplete; AUserData: Pointer);
    { チャンネルごとの置き場から足す（SDL_PutAudioStreamPlanarData）。ANumSamples はチャンネル
      あたりの標本の数。AChannelBuffers の数は入力のチャンネル数（違えば EPMLArgument）。
      nil の置き場は無音。 }
    procedure PutPlanarData(const AChannelBuffers: array of Pointer; ANumSamples: Integer);

    { 出力を取り出す（SDL_GetAudioStreamData）。ALen は出力の 1 フレームの倍数に切り捨てる。
      取り出したバイト数を返す。 }
    function  GetData(ABuf: Pointer; ALen: Integer): Integer;
    { デバイスの層向け（SDL_GetAudioStreamDataAdjustGain）。音量に AExtraGain も掛ける。 }
    function  GetDataAdjustGain(ABuf: Pointer; ALen: Integer; AExtraGain: Single): Integer;

    // 今取り出せる出力のバイト数（SDL_GetAudioStreamAvailable）。
    function  Available: Integer;
    // 溜まっている入力のバイト数（SDL_GetAudioStreamQueued。SDL の説明は「フレーム」だが、実際はバイト）。
    function  Queued: Integer;
    // 入力の終わりの印（SDL_FlushAudioStream）。周波数を変えているとき、最後の余白まで出せるようにする。
    procedure Flush;
    // 全部捨てる（SDL_ClearAudioStream）。
    procedure Clear;
    // 複数の操作をまとめて行うときに（SDL_LockAudioStream）。再入できる。
    procedure Lock;
    procedure Unlock;

    property FrequencyRatio: Single read GetFrequencyRatio write SetFrequencyRatio;
    property Gain: Single read GetGain write SetGain;
    // 設定はロックの下で（SDL_SetAudioStreamGetCallback / PutCallback）。
    property OnGet: TPMLAudioStreamCallback read GetOnGet write SetOnGet;
    property OnPut: TPMLAudioStreamCallback read GetOnPut write SetOnPut;
  end;

{ 一度に変換する（SDL_ConvertAudioSamples）。ストリームを作って、入れて、流し切って、
  全部取り出す。引数の誤りは EPMLArgument。 }
function PMLConvertAudioSamples(const ASrcSpec: TPMLAudioSpec; ASrc: Pointer; ALen: Integer;
  const ADstSpec: TPMLAudioSpec): TBytes;

implementation

const
  // SDL_PutAudioStreamData: これ以上の入力は、ロックの外で写してからトラックとして足す。
  LargeInputThreshold = 64 * 1024;
  // SDL_PutAudioStreamPlanarData: これ以下なら積み上げ（スタック）の上で並べる。
  InterleaveStackSize = 1024;
  // GetData は 4096 フレームずつ処理する（確保が大きくなりすぎないように）。
  GetChunkFrames = 4096;
  // SDL_MAX_SINT32
  MaxSint32 = $7FFFFFFF;
  // SDL_GetSIMDAlignment の代わり。整列は値に影響しないので 16 にしておく。
  SimdAlignment = 16;

{ FreeAllocatedAudioBuffer: ストリームが確保した置き場の解放。 }
procedure FreeAllocatedAudioBuffer(AUserData: Pointer; ABuf: Pointer; ALen: Integer);
begin
  FreeMem(ABuf);
end;

{ DontFreeThisAudioBuffer: 呼び出し側の置き場で、ストリームより長生きすると約束されている。 }
procedure DontFreeThisAudioBuffer(AUserData: Pointer; ABuf: Pointer; ALen: Integer);
begin
end;

{ ---- 作る・壊す ---- }

constructor TPMLAudioStream.Create(const ASrcSpec, ADstSpec: TPMLAudioSpec);
begin
  inherited Create(nil, nil);
  FFreqRatio := 1.0;
  FGain := 1.0;
  FQueue := TPMLAudioQueue.Create(8192);
  FLock := TPMLMutex.Create;
  // OnAudioStreamCreated（全ストリームの連なりへの登録）は 2 段目。
  // 途中で EPMLArgument になると、Destroy が作った分だけ片付ける。
  SetFormat(ASrcSpec, ADstSpec);
end;

destructor TPMLAudioStream.Destroy;
begin
  // SDL_DestroyAudioStream: プロパティの破棄・全ストリームの連なりからの削除・
  // デバイスからの unbind は 2 段目。
  // 写さない入力の置き場の解放の知らせは、キューを壊すときに来る。
  FQueue.Free;
  FQueue := nil;
  if FWorkBuffer <> nil then
    FreeMem(FWorkBuffer);
  FWorkBuffer := nil;
  FLock.Free;
  FLock := nil;
  inherited Destroy;
end;

{ ---- 呼び出しの登録 ---- }

function TPMLAudioStream.GetOnGet: TPMLAudioStreamCallback;
begin
  FLock.Lock;
  try
    Result := FOnGet;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.SetOnGet(AValue: TPMLAudioStreamCallback);
begin
  FLock.Lock;
  try
    FOnGet := AValue;
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioStream.GetOnPut: TPMLAudioStreamCallback;
begin
  FLock.Lock;
  try
    Result := FOnPut;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.SetOnPut(AValue: TPMLAudioStreamCallback);
begin
  FLock.Lock;
  try
    FOnPut := AValue;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.Lock;
begin
  FLock.Lock;
end;

procedure TPMLAudioStream.Unlock;
begin
  FLock.Unlock;
end;

{ ---- 形式 ---- }

{ 形式・チャンネル数・周波数を確かめる（SDL_SetAudioStreamFormat の CHECK_PARAM）。 }
procedure CheckSpec(const ASpec: TPMLAudioSpec; const AWhat: String);
begin
  if not PMLIsSupportedAudioFormat(ASpec.Format) then
    raise EPMLArgument.Create('Parameter ''' + AWhat + '.Format'' is invalid');
  if not PMLIsSupportedChannelCount(ASpec.Channels) then
    raise EPMLArgument.Create('Parameter ''' + AWhat + '.Channels'' is invalid');
  if ASpec.Freq <= 0 then
    raise EPMLArgument.Create('Parameter ''' + AWhat + '.Freq'' is invalid');
end;

{ SDL_SetAudioStreamFormat。SDL は NULL で「そちらは変えない」。 }
procedure TPMLAudioStream.ApplyFormat(AChangeSrc: Boolean; const ASrcSpec: TPMLAudioSpec;
  AChangeDst: Boolean; const ADstSpec: TPMLAudioSpec);
begin
  // 周波数の上限の確かめは SDL も外している。
  if AChangeSrc then
    CheckSpec(ASrcSpec, 'SrcSpec');
  if AChangeDst then
    CheckSpec(ADstSpec, 'DstSpec');

  FLock.Lock;
  try
    // 2 段目: デバイスに結び付いている側の形式は黙って変えない（bound_device）。
    if AChangeSrc then
    begin
      // チャンネル数が変わったら、その側の並びは意味を失う。
      if ASrcSpec.Channels <> FSrcSpec.Channels then
        FSrcMap := nil;
      FSrcSpec := ASrcSpec;
    end;
    if AChangeDst then
    begin
      if ADstSpec.Channels <> FDstSpec.Channels then
        FDstMap := nil;
      FDstSpec := ADstSpec;
    end;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.SetFormat(const ASrcSpec, ADstSpec: TPMLAudioSpec);
begin
  ApplyFormat(True, ASrcSpec, True, ADstSpec);
end;

procedure TPMLAudioStream.SetSrcFormat(const ASpec: TPMLAudioSpec);
begin
  ApplyFormat(True, ASpec, False, ASpec);
end;

procedure TPMLAudioStream.SetDstFormat(const ASpec: TPMLAudioSpec);
begin
  ApplyFormat(False, ASpec, True, ASpec);
end;

function TPMLAudioStream.SrcSpec: TPMLAudioSpec;
begin
  FLock.Lock;
  try
    Result := FSrcSpec;
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioStream.DstSpec: TPMLAudioSpec;
begin
  FLock.Lock;
  try
    Result := FDstSpec;
  finally
    FLock.Unlock;
  end;
end;

{ ---- チャンネルの並び ---- }

{ SetAudioStreamChannelMap。AMap が空なら既定へ戻す。AIsInput は入力側か出力側か。 }
procedure TPMLAudioStream.ApplyChannelMap(AIsInput: Boolean; const AMap: TPMLChannelMap);
var
  Channels: Integer;
  Current, NewMap: TPMLChannelMap;
begin
  FLock.Lock;
  try
    if AIsInput then
    begin
      Channels := FSrcSpec.Channels;
      Current := FSrcMap;
    end
    else
    begin
      Channels := FDstSpec.Channels;
      Current := FDstMap;
    end;

    if (Length(AMap) > 0) and (Length(AMap) <> Channels) then
      raise EPMLArgument.Create('Wrong number of channels');
    // もう既定になっている。
    if (Length(Current) = 0) and (Length(AMap) = 0) then
      Exit;
    // 同じ並びを持っている。写し直さない。
    if (Length(Current) > 0) and (Length(AMap) > 0)
      and CompareMem(@Current[0], @AMap[0], SizeOf(Integer) * Channels) then
      Exit;
    if PMLChannelMapIsBogus(AMap, Channels) then
      raise EPMLArgument.Create('Invalid channel mapping');

    // 恒等の並びは既定（空）にする。呼び出し側の配列と共有しないよう写す。
    if PMLChannelMapIsDefault(AMap, Channels) then
      NewMap := nil
    else
      NewMap := Copy(AMap, 0, Channels);
    if AIsInput then
      FSrcMap := NewMap
    else
      FDstMap := NewMap;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.SetInputChannelMap(const AMap: TPMLChannelMap);
begin
  ApplyChannelMap(True, AMap);
end;

procedure TPMLAudioStream.SetOutputChannelMap(const AMap: TPMLChannelMap);
begin
  ApplyChannelMap(False, AMap);
end;

function TPMLAudioStream.InputChannelMap: TPMLChannelMap;
begin
  FLock.Lock;
  try
    Result := Copy(FSrcMap, 0, Length(FSrcMap));
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioStream.OutputChannelMap: TPMLChannelMap;
begin
  FLock.Lock;
  try
    Result := Copy(FDstMap, 0, Length(FDstMap));
  finally
    FLock.Unlock;
  end;
end;

{ ---- 周波数の比・音量 ---- }

function TPMLAudioStream.GetFrequencyRatio: Single;
begin
  FLock.Lock;
  try
    Result := FFreqRatio;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.SetFrequencyRatio(AValue: Single);
begin
  // 「ほぼ恣意的に選んだ」範囲（SDL のコメント）。
  if AValue < Single(0.01) then
    raise EPMLArgument.Create('Frequency ratio is too low');
  if AValue > Single(100.0) then
    raise EPMLArgument.Create('Frequency ratio is too high');
  FLock.Lock;
  try
    FFreqRatio := AValue;
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioStream.GetGain: Single;
begin
  FLock.Lock;
  try
    Result := FGain;
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.SetGain(AValue: Single);
begin
  if AValue < Single(0.0) then
    raise EPMLArgument.Create('Parameter ''Gain'' is invalid');
  FLock.Lock;
  try
    FGain := AValue;
  finally
    FLock.Unlock;
  end;
end;

{ GetAudioStreamResampleRate。入力の周波数に比を掛けて（単精度で）切り捨て、変換の速さにする。
  周波数が同じで、フレームの間に居ないなら 0（変換しない）。 }
function TPMLAudioStream.ResampleRate(ASrcFreq: Integer; AResampleOffset: Int64): Int64;
var
  Scaled: Single;
begin
  Scaled := Single(ASrcFreq) * FFreqRatio;
  ASrcFreq := Integer(Trunc(Scaled));
  Result := PMLGetResampleRate(ASrcFreq, FDstSpec.Freq);
  if (Result = Int64($100000000)) and (AResampleOffset = 0) then
    Result := 0;
end;

{ UpdateAudioStreamInputSpec: 処理するトラックの形式が変わったら、履歴を無音にして覚え直す。 }
function TPMLAudioStream.UpdateInputSpec(const ASpec: TPMLAudioSpec;
  const AMap: TPMLChannelMap): Boolean;
begin
  if (FInputSpec.Format = ASpec.Format) and (FInputSpec.Channels = ASpec.Channels)
    and (FInputSpec.Freq = ASpec.Freq) and PMLChannelMapsEqual(ASpec.Channels, FInputMap, AMap) then
    Exit(True);

  if not FQueue.ResetHistory(PMLResamplerHistoryFrames) then
    Exit(False);

  if Length(AMap) > 0 then
    FInputMap := Copy(AMap, 0, ASpec.Channels)
  else
    FInputMap := nil;
  FInputSpec := ASpec;
  Result := True;
end;

{ ---- 入力 ---- }

{ PutAudioStreamBufferInternal。ロックを持って呼ぶこと。引数は確かめ済みであること。
  ACallback があれば ABuf をそのままトラックにする（キューが持ち主になり、使い終えたら ACallback）。
  ATaken は、キューが ABuf の持ち主になったか（例外のとき、呼び出し側が解放するかの判断用）。 }
procedure TPMLAudioStream.PutBufferInternal(const ASpec: TPMLAudioSpec;
  const AMap: TPMLChannelMap; ABuf: Pointer; ALen: Integer;
  ACallback: TPMLReleaseAudioBufferCallback; AUserData: Pointer; out ATaken: Boolean);
var
  Track: TPMLAudioTrack;
  PrevAvailable, NewAvailable: Integer;
begin
  ATaken := False;
  Track := nil;
  if Assigned(ACallback) then
    Track := FQueue.CreateTrack(ASpec, AMap, PByte(ABuf), ALen, ALen, ACallback, AUserData);

  if Assigned(FOnPut) then
    PrevAvailable := Available
  else
    PrevAvailable := 0;

  if Track <> nil then
  begin
    FQueue.AddTrack(Track);
    ATaken := True;
  end
  else if not FQueue.Write(ASpec, AMap, PByte(ABuf), PtrUInt(ALen)) then
    raise EPMLAudioError.Create('Could not write to the audio queue');

  if Assigned(FOnPut) then
  begin
    NewAvailable := Available - PrevAvailable;
    FOnPut(Self, NewAvailable, NewAvailable);
  end;
end;

{ PutAudioStreamBuffer。 }
procedure TPMLAudioStream.PutBuffer(ABuf: Pointer; ALen: Integer;
  ACallback: TPMLReleaseAudioBufferCallback; AUserData: Pointer; out ATaken: Boolean);
begin
  ATaken := False;
  FLock.Lock;
  try
    // CheckAudioStreamIsFullySetup: このクラスは作るときに両方の形式を持つので要らない。
    if (ALen mod FSrcSpec.FrameSize) <> 0 then
      raise EPMLArgument.Create('Can''t add partial sample frames');
    PutBufferInternal(FSrcSpec, FSrcMap, ABuf, ALen, ACallback, AUserData, ATaken);
  finally
    FLock.Unlock;
  end;
end;

procedure TPMLAudioStream.PutData(ABuf: Pointer; ALen: Integer);
var
  Data: Pointer;
  Taken: Boolean;
begin
  if ABuf = nil then
    raise EPMLArgument.Create('Parameter ''ABuf'' is invalid');
  if ALen < 0 then
    raise EPMLArgument.Create('Parameter ''ALen'' is invalid');
  if ALen = 0 then
    Exit;

  // 大きな入力は、ロックの外でできるだけ仕事をする（出力の側を待たせないため）。
  if ALen >= LargeInputThreshold then
  begin
    GetMem(Data, ALen);
    Move(ABuf^, Data^, ALen);
    Taken := False;
    try
      PutBuffer(Data, ALen, @FreeAllocatedAudioBuffer, nil, Taken);
    except
      if not Taken then
        FreeMem(Data);
      raise;
    end;
    Exit;
  end;

  PutBuffer(ABuf, ALen, nil, nil, Taken);
end;

procedure TPMLAudioStream.PutDataNoCopy(ABuf: Pointer; ALen: Integer;
  ACallback: TPMLAudioStreamDataComplete; AUserData: Pointer);
var
  Taken: Boolean;
begin
  if ABuf = nil then
    raise EPMLArgument.Create('Parameter ''ABuf'' is invalid');
  if ALen < 0 then
    raise EPMLArgument.Create('Parameter ''ALen'' is invalid');
  if ALen = 0 then
  begin
    if Assigned(ACallback) then
      ACallback(AUserData, ABuf, ALen);
    Exit;
  end;
  if Assigned(ACallback) then
    PutBuffer(ABuf, ALen, ACallback, AUserData, Taken)
  else
    PutBuffer(ABuf, ALen, @DontFreeThisAudioBuffer, AUserData, Taken);
end;

{ InterleaveAudioChannels。nil のチャンネルは無音にする。
  SDL は 8 / 16 / 32 ビットの 3 つの関数に分けているが、標本をそのまま写すだけなので 1 つにまとめた
  （無音の標本は、U8 だけ $80、ほかは全ビット 0。PMLAudioSilenceValue が U8 以外で 0 を返すので、
  標本の大きさぶんそのバイトを並べればよい）。 }
procedure InterleaveChannels(AOutput: PByte; const ABuffers: array of Pointer;
  AChannels, ANumSamples: Integer; const ASpec: TPMLAudioSpec);
var
  SampleSize, Frame, Channel: Integer;
  Silence: Byte;
  Src: PByte;
begin
  SampleSize := PMLAudioByteSize(ASpec.Format);
  Silence := PMLAudioSilenceValue(ASpec.Format);
  for Frame := 0 to ANumSamples - 1 do
    for Channel := 0 to AChannels - 1 do
    begin
      if ABuffers[Channel] = nil then
        FillChar(AOutput^, SampleSize, Silence)
      else
      begin
        Src := PByte(ABuffers[Channel]) + (Int64(Frame) * SampleSize);
        Move(Src^, AOutput^, SampleSize);
      end;
      Inc(AOutput, SampleSize);
    end;
end;

{ PORT-NOTE: SDL は渡されたチャンネルの数が入力のチャンネル数より少なければ nil で埋め、
  多ければ余りを無視する。ここでは数が違えば EPMLArgument にする（インターフェースの約束）。
  PORT-NOTE: 入力が 1 チャンネルのとき、SDL は SDL_PutAudioStreamData に渡すので、nil の置き場は
  「buf が無効」の誤りになる（nil は無音、という説明と食い違う）。ここでも同じく EPMLArgument。 }
procedure TPMLAudioStream.PutPlanarData(const AChannelBuffers: array of Pointer;
  ANumSamples: Integer);
var
  Spec: TPMLAudioSpec;
  Map: TPMLChannelMap;
  Len: Integer;
  Stack: array[0..InterleaveStackSize - 1] of Byte;
  Data: Pointer;
  Taken: Boolean;
begin
  if ANumSamples < 0 then
    raise EPMLArgument.Create('Parameter ''ANumSamples'' is invalid');
  if ANumSamples = 0 then
    Exit;

  // 並べるのはロックの外で（出力の側を待たせない）。ただし今の入力の形式は要る。
  FLock.Lock;
  try
    Spec := FSrcSpec;
    Map := Copy(FSrcMap, 0, Length(FSrcMap));
  finally
    FLock.Unlock;
  end;

  if Length(AChannelBuffers) <> Spec.Channels then
    raise EPMLArgument.Create('Wrong number of channel buffers');

  // 並べるものが無いとき（1 チャンネル）は普通の入力と同じ。
  if Spec.Channels = 1 then
  begin
    PutData(AChannelBuffers[0], Spec.FrameSize * ANumSamples);
    Exit;
  end;

  if Int64(Spec.FrameSize) * ANumSamples > High(Integer) then
    raise EPMLArgument.Create('Parameter ''ANumSamples'' is invalid');
  Len := Spec.FrameSize * ANumSamples;

  // 小さければ積み上げの上で並べて普通の入力に。大きければ確保した置き場に並べ、
  // 写さずにトラックにする（持ち主はキュー）。
  if Len <= InterleaveStackSize then
  begin
    InterleaveChannels(@Stack[0], AChannelBuffers, Spec.Channels, ANumSamples, Spec);
    FLock.Lock;
    try
      PutBufferInternal(Spec, Map, @Stack[0], Len, nil, nil, Taken);
    finally
      FLock.Unlock;
    end;
    Exit;
  end;

  GetMem(Data, Len);
  Taken := False;
  try
    InterleaveChannels(PByte(Data), AChannelBuffers, Spec.Channels, ANumSamples, Spec);
    // 並べている間に別のスレッドが形式を変えても、PutBufferInternal は並べたときの形式で
    // トラックを作る。次の入力は新しい形式で別のトラックになる（SDL と同じ）。
    FLock.Lock;
    try
      PutBufferInternal(Spec, Map, Data, Len, @FreeAllocatedAudioBuffer, nil, Taken);
    finally
      FLock.Unlock;
    end;
  except
    if not Taken then
      FreeMem(Data);
    raise;
  end;
end;

procedure TPMLAudioStream.Flush;
begin
  FLock.Lock;
  try
    FQueue.Flush;
  finally
    FLock.Unlock;
  end;
end;

{ ---- 出力 ---- }

{ EnsureAudioStreamWorkBufferSize。中身は残らない（作業の置き場）。 }
function TPMLAudioStream.EnsureWorkBuffer(ANewLen: PtrUInt): PByte;
var
  Ptr: PByte;
begin
  if FWorkBufferSize >= ANewLen then
    Exit(FWorkBuffer);
  GetMem(Ptr, ANewLen);
  if FWorkBuffer <> nil then
    FreeMem(FWorkBuffer);
  FWorkBuffer := Ptr;
  FWorkBufferSize := ANewLen;
  Result := Ptr;
end;

{ NextAudioStreamIter: 次の「流し切るまでのひとまとまり」から出せるフレーム数。
  変換するなら余白（流し切っていなければ右側の余白の分は出せない）を引き、位置を進める。 }
function TPMLAudioStream.NextAudioIter(var AIter: Pointer; var AResampleOffset: Int64;
  out ASpec: TPMLAudioSpec; out AMap: TPMLChannelMap; out AFlushed: Boolean): Int64;
var
  QueuedBytes: PtrUInt;
  Flushed: Boolean;
  Offset, Rate, OutputFrames: Int64;
begin
  QueuedBytes := FQueue.NextIter(AIter, ASpec, AMap, Flushed);

  // 無限に読める。変換するかどうかに関係なく、無限に出せる。
  if QueuedBytes = High(PtrUInt) then
  begin
    AResampleOffset := 0;
    AFlushed := False;
    Exit(MaxSint32);
  end;

  Offset := AResampleOffset;
  Rate := ResampleRate(ASpec.Freq, Offset);
  OutputFrames := Int64(QueuedBytes div PtrUInt(ASpec.FrameSize));

  if Rate <> 0 then
  begin
    // 変換には現在位置の左右の余白が要る。右側は、トラックが流し切られていれば無音で埋めるが、
    // そうでなければ（続きが来るかもしれないので）その分は出せない。
    if not Flushed then
      Dec(OutputFrames, PMLResamplerPaddingFrames(Rate));
    OutputFrames := PMLResamplerOutputFrames(OutputFrames, Rate, Offset);
  end;

  if Flushed then
    Offset := 0;

  AResampleOffset := Offset;
  AFlushed := Flushed;
  Result := OutputFrames;
end;

{ GetAudioStreamAvailableFrames。 }
function TPMLAudioStream.AvailableFrames(AOutResampleOffset: PInt64): Int64;
var
  Iter: Pointer;
  ResampleOffset: Int64;
  Spec: TPMLAudioSpec;
  Map: TPMLChannelMap;
  Flushed: Boolean;
begin
  Iter := FQueue.BeginIter;
  ResampleOffset := FResampleOffset;
  Result := 0;
  while Iter <> nil do
  begin
    Inc(Result, NextAudioIter(Iter, ResampleOffset, Spec, Map, Flushed));
    // もう十分ある。扱いやすい大きさに抑える。
    if Result >= MaxSint32 then
    begin
      Result := MaxSint32;
      Break;
    end;
  end;
  if AOutResampleOffset <> nil then
    AOutResampleOffset^ := ResampleOffset;
end;

{ GetAudioStreamHead。 }
function TPMLAudioStream.HeadFrames(out ASpec: TPMLAudioSpec; out AMap: TPMLChannelMap;
  out AFlushed: Boolean): Int64;
var
  Iter: Pointer;
  ResampleOffset: Int64;
begin
  Iter := FQueue.BeginIter;
  if Iter = nil then
  begin
    ASpec := TPMLAudioSpec.Make(0, 0, 0);
    AMap := nil;
    AFlushed := False;
    Exit(0);
  end;
  ResampleOffset := FResampleOffset;
  Result := NextAudioIter(Iter, ResampleOffset, ASpec, AMap, AFlushed);
end;

{ GetAudioStreamDataInternal。ロックを持って呼ぶ。入力が足りていること。
  False は、キューから読めなかった（数え間違い）。 }
function TPMLAudioStream.GetDataInternal(ABuf: PByte; AOutputFrames: Integer;
  AGain: Single): Boolean;
var
  SrcFormat, DstFormat, ResampleFormat: TPMLAudioFormat;
  SrcChannels, DstChannels, ResampleChannels: Integer;
  MaxFrameSize, ResampleFrameSize: Integer;
  InputFrames, PaddingFrames, WorkBufferFrames, WorkBufferCapacity: Integer;
  ResampleBufferOffset, ResampleConvertBytes: Integer;
  ResampleRateValue: Int64;
  WorkBuffer, InputBuffer: PByte;
  ResampleBuffer: Pointer;
  PreGain, PostGain: Single;
begin
  SrcFormat := FInputSpec.Format;
  SrcChannels := FInputSpec.Channels;
  DstFormat := FDstSpec.Format;
  DstChannels := FDstSpec.Channels;

  MaxFrameSize := PMLAudioMaxFrameSize(SrcFormat, SrcChannels, DstFormat, DstChannels);
  ResampleRateValue := ResampleRate(FInputSpec.Freq, FResampleOffset);

  // 変換しないなら簡単（形式の変換も要らないかもしれない）。
  if ResampleRateValue = 0 then
  begin
    WorkBuffer := nil;
    if (SrcFormat <> DstFormat) or (SrcChannels <> DstChannels) or (AGain <> Single(1.0)) then
      WorkBuffer := EnsureWorkBuffer(PtrUInt(AOutputFrames) * PtrUInt(MaxFrameSize));
    Result := (FQueue.Read(ABuf, DstFormat, DstChannels, FDstMap, 0, AOutputFrames, 0,
      WorkBuffer, AGain) = ABuf);
    Exit;
  end;

  // 周波数を変える。出力のフレーム数に要る入力のフレーム数は、位置によって変わる
  // （上げるときは 0 になることもある）。
  InputFrames := Integer(PMLResamplerInputFrames(AOutputFrames, ResampleRateValue, FResampleOffset));
  PaddingFrames := PMLResamplerPaddingFrames(ResampleRateValue);
  ResampleFormat := PML_AUDIO_F32;

  // チャンネルを増やすなら変換の後（複製を変換する無駄を避ける）。減らすなら前
  // （補間した値を変換するほうが、変換した値を補間するよりよい）。
  ResampleChannels := SrcChannels;
  if DstChannels < ResampleChannels then
    ResampleChannels := DstChannels;
  ResampleFrameSize := PMLAudioByteSize(ResampleFormat) * ResampleChannels;

  // 作業の置き場の主な部分は 3 つのどれかに使う:
  //   入力の形式の 1 フレーム x （左の余白 + 入力 + 右の余白）
  //   変換用の 1 フレーム       x （左の余白 + 入力 + 右の余白）
  //   出力の形式の 1 フレーム   x 出力のフレーム数
  // 直接出力へ変換できないときは、その後ろに変換の出力（変換用の 1 フレーム x 出力のフレーム数）。
  WorkBufferFrames := InputFrames + (PaddingFrames * 2);
  WorkBufferCapacity := WorkBufferFrames * MaxFrameSize;
  ResampleBufferOffset := -1;

  if (DstFormat <> ResampleFormat) or (DstChannels <> ResampleChannels) then
  begin
    ResampleConvertBytes := AOutputFrames * MaxFrameSize;
    if ResampleConvertBytes > WorkBufferCapacity then
      WorkBufferCapacity := ResampleConvertBytes;
    // 整列（値には影響しない）
    Inc(WorkBufferCapacity, SimdAlignment - 1);
    Dec(WorkBufferCapacity, WorkBufferCapacity mod SimdAlignment);
    ResampleBufferOffset := WorkBufferCapacity;
    Inc(WorkBufferCapacity, AOutputFrames * ResampleFrameSize);
  end;

  WorkBuffer := EnsureWorkBuffer(PtrUInt(WorkBufferCapacity));

  // 音量は、処理する標本が少ないほう（変換の前か後）で掛ける。
  if InputFrames > AOutputFrames then
  begin
    PreGain := 1.0;
    PostGain := AGain;
  end
  else
  begin
    PreGain := AGain;
    PostGain := 1.0;
  end;

  // 出力の並びは変換の後で掛けるので、ここでは nil。
  InputBuffer := FQueue.Read(nil, ResampleFormat, ResampleChannels, nil,
    PaddingFrames, InputFrames, PaddingFrames, WorkBuffer, PreGain);
  if InputBuffer = nil then
    Exit(False);
  Inc(InputBuffer, PaddingFrames * ResampleFrameSize);

  if ResampleBufferOffset <> -1 then
    ResampleBuffer := WorkBuffer + ResampleBufferOffset
  else
    ResampleBuffer := ABuf;

  PMLResampleAudio(ResampleChannels, PSingle(InputBuffer), InputFrames,
    PSingle(ResampleBuffer), AOutputFrames, ResampleRateValue, FResampleOffset);

  // 最後の形式へ（入力の並びは、キューから読むときに済んでいるので nil）。
  PMLConvertAudio(AOutputFrames, ResampleBuffer, ResampleFormat, ResampleChannels, nil,
    ABuf, DstFormat, DstChannels, FDstMap, WorkBuffer, PostGain);

  Result := True;
end;

function TPMLAudioStream.GetData(ABuf: Pointer; ALen: Integer): Integer;
begin
  Result := GetDataAdjustGain(ABuf, ALen, Single(1.0));
end;

function TPMLAudioStream.GetDataAdjustGain(ABuf: Pointer; ALen: Integer;
  AExtraGain: Single): Integer;
var
  Buf, Dst: PByte;
  TotalGain: Single;
  DstFrameSize, OutputFrames, Total: Integer;
  TotalRequest, AdditionalRequest, ResampleOffset, Available0, Rate: Int64;
  InputSpec: TPMLAudioSpec;
  InputMap: TPMLChannelMap;
  Flushed: Boolean;
  AvailableInFrames: Int64;
begin
  if ABuf = nil then
    raise EPMLArgument.Create('Parameter ''ABuf'' is invalid');
  if ALen < 0 then
    raise EPMLArgument.Create('Parameter ''ALen'' is invalid');
  if ALen = 0 then
    Exit(0);

  Buf := PByte(ABuf);
  FLock.Lock;
  try
    TotalGain := FGain * AExtraGain;
    DstFrameSize := FDstSpec.FrameSize;

    Dec(ALen, ALen mod DstFrameSize);  // 半端なフレームは切り捨てる。

    // 呼び出しに、入力を足す機会を与える。
    if Assigned(FOnGet) then
    begin
      TotalRequest := ALen div DstFrameSize;  // まず欲しいフレーム数
      AdditionalRequest := TotalRequest;

      ResampleOffset := 0;
      Available0 := AvailableFrames(@ResampleOffset);

      if Available0 < AdditionalRequest then
        Dec(AdditionalRequest, Available0)
      else
        AdditionalRequest := 0;

      Rate := ResampleRate(FSrcSpec.Freq, ResampleOffset);
      if Rate <> 0 then
      begin
        TotalRequest := PMLResamplerInputFrames(TotalRequest, Rate, ResampleOffset);
        AdditionalRequest := PMLResamplerInputFrames(AdditionalRequest, Rate, ResampleOffset);
      end;

      TotalRequest := TotalRequest * FSrcSpec.FrameSize;  // フレーム数をバイト数へ
      AdditionalRequest := AdditionalRequest * FSrcSpec.FrameSize;
      if AdditionalRequest > High(Integer) then
        AdditionalRequest := High(Integer);
      if TotalRequest > High(Integer) then
        TotalRequest := High(Integer);
      FOnGet(Self, Integer(AdditionalRequest), Integer(TotalRequest));
    end;

    // 確保が大きくなりすぎない（整数が溢れない）よう、少しずつ処理する。
    Total := 0;
    while Total < ALen do
    begin
      // 処理はトラック 1 つずつ。
      AvailableInFrames := HeadFrames(InputSpec, InputMap, Flushed);

      if AvailableInFrames = 0 then
      begin
        if Flushed then
        begin
          FQueue.PopHead;
          FInputSpec := TPMLAudioSpec.Make(0, 0, 0);
          FResampleOffset := 0;
          FInputMap := nil;
          Continue;
        end;
        // 今は出せるフレームが無いが、流し切っていないので、あとで入るかもしれない。
        Break;
      end;

      if not UpdateInputSpec(InputSpec, InputMap) then
      begin
        if Total = 0 then
          raise EPMLAudioError.Create('Could not reset the audio queue history');
        Break;
      end;

      // 出力の長さを、今出せる分までに抑える（GetDataInternal は入力が足りていることを求める）。
      OutputFrames := (ALen - Total) div DstFrameSize;
      if OutputFrames > GetChunkFrames then
        OutputFrames := GetChunkFrames;
      if AvailableInFrames < OutputFrames then
        OutputFrames := Integer(AvailableInFrames);

      Dst := Buf + Total;
      if not GetDataInternal(Dst, OutputFrames, TotalGain) then
      begin
        // PORT-NOTE: SDL は何も出せていなければ -1、出せていればそこまでの量を返す。
        // ここでは何も出せていなければ EPMLAudioError にする。
        if Total = 0 then
          raise EPMLAudioError.Create('Not enough data in queue');
        Break;
      end;

      Inc(Total, OutputFrames * DstFrameSize);
    end;

    Result := Total;
  finally
    FLock.Unlock;
  end;
end;

function TPMLAudioStream.Available: Integer;
var
  Count: Int64;
begin
  FLock.Lock;
  try
    Count := AvailableFrames(nil);
    // 出力の形式のバイト数へ。
    Count := Count * FDstSpec.FrameSize;
  finally
    FLock.Unlock;
  end;
  // 整数に収まらなければ上限に抑える。
  if Count > High(Integer) then
    Count := High(Integer);
  Result := Integer(Count);
end;

function TPMLAudioStream.Queued: Integer;
var
  Total: PtrUInt;
begin
  FLock.Lock;
  try
    Total := FQueue.Queued;
  finally
    FLock.Unlock;
  end;
  if Total > PtrUInt(High(Integer)) then
    Total := PtrUInt(High(Integer));
  Result := Integer(Total);
end;

procedure TPMLAudioStream.Clear;
begin
  FLock.Lock;
  try
    FQueue.Clear;
    FInputSpec := TPMLAudioSpec.Make(0, 0, 0);
    FInputMap := nil;
    FResampleOffset := 0;
  finally
    FLock.Unlock;
  end;
end;

{ ---- 一度に変換する ---- }

function PMLConvertAudioSamples(const ASrcSpec: TPMLAudioSpec; ASrc: Pointer; ALen: Integer;
  const ADstSpec: TPMLAudioSpec): TBytes;
var
  Stream: TPMLAudioStream;
  DstLen: Integer;
begin
  Result := nil;
  if ASrc = nil then
    raise EPMLArgument.Create('Parameter ''ASrc'' is invalid');
  if ALen < 0 then
    raise EPMLArgument.Create('Parameter ''ALen'' is invalid');

  Stream := TPMLAudioStream.Create(ASrcSpec, ADstSpec);
  try
    Stream.PutDataNoCopy(ASrc, ALen, nil, nil);
    Stream.Flush;
    DstLen := Stream.Available;
    SetLength(Result, DstLen);
    if DstLen > 0 then
      if Stream.GetData(@Result[0], DstLen) <> DstLen then
      begin
        Result := nil;
        raise EPMLAudioError.Create('Could not convert all of the audio samples');
      end;
  finally
    Stream.Free;
  end;
end;

end.
