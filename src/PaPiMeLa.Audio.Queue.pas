{
  PaPiMeLa.Audio.Queue — 音声のストリームの入力を溜めるキュー

  Origin : ported from SDL (src/audio/SDL_audioqueue.c, src/audio/SDL_audioqueue.h)
           Scope: トラック（同じ形式・並びの入力のひと続き）の連なり、トラックごとの
           「流し切った」印、チャンク単位の確保と使い回し（メモリのプール）、呼び出し側が
           持つ置き場をそのまま使うトラック（解放の呼び出しつき）、トラックをまたぐ走査、
           周波数の変換のための過去・未来の余白つきの読み出し（履歴の置き場と、流し切った
           後の無音）、溜まっているバイト数。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.5、§11 #53

  WHAT:
    TPMLAudioStream の入力側。PutData で書いたものをトラックに溜め、GetData のときに
    形式を変えながら読み出す。

  WHY:
    入力の形式は途中で変えられる（SetFormat）。形式ごとにトラックを分けて溜め、
    先頭のトラックから順に変換する（SDL と同じ）。

  NOT RESOLVED:
    - TPMLRingBuffer<T> の適用は見送った（設計書 #53 の検討事項）。SDL のチャンクの連なりのまま

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Audio.Queue;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Audio.Convert;

type
  { 呼び出し側が持つ置き場を使い終えたときの知らせ（SDL_ReleaseAudioBufferCallback）。 }
  TPMLReleaseAudioBufferCallback = procedure(AUserData: Pointer; ABuf: Pointer; ALen: Integer);

  { 同じ形式・並びの入力のひと続き（SDL_AudioTrack）。中身はキューの実装が決める。 }
  TPMLAudioTrack = class;

  { 音声のキュー（SDL_AudioQueue）。ロックしない（ストリームのロックの下で使う）。 }
  TPMLAudioQueue = class
  private
    // トラックの連なり（SDL_AudioQueue.head / tail）。
    FHead: TPMLAudioTrack;
    FTail: TPMLAudioTrack;
    // 履歴（周波数の変換のための、先頭のトラックより前のフレーム）。
    FHistoryBuffer: PByte;
    FHistoryLength: PtrUInt;
    FHistoryCapacity: PtrUInt;
    // メモリのプール（SDL_MemoryPool）。トラックは空きのオブジェクトの連なり、
    // チャンクは先頭に次の空きの番地を書き込む生のブロック（どちらも SDL と同じ上限）。
    FTrackFree: TPMLAudioTrack;
    FTrackNumFree: PtrUInt;
    FChunkFree: Pointer;
    FChunkNumFree: PtrUInt;
    FChunkSize: PtrUInt;
    function  AllocTrack: TPMLAudioTrack;
    procedure FreeTrack(ATrack: TPMLAudioTrack);
    function  AllocChunk: Pointer;
    procedure FreeChunk(ABlock: Pointer);
    procedure DestroyTrack(ATrack: TPMLAudioTrack);
    function  CreateChunkedTrack(const ASpec: TPMLAudioSpec;
      const AChannelMap: TPMLChannelMap): TPMLAudioTrack;
    function  PeekPast(AData: PByte; ALen: PtrUInt): PByte;
    procedure UpdateHistory(AData: PByte; ALen: PtrUInt);
    function  ReadPresent(AData: PByte; ALen: PtrUInt): PByte;
    function  PeekFuture(AData: PByte; ALen: PtrUInt): PByte;
  public
    // AChunkSize はキューが自分で確保するチャンクの大きさ（SDL は 8192）。
    constructor Create(AChunkSize: PtrUInt);
    destructor Destroy; override;
    // 全部捨てる（SDL_ClearAudioQueue）。呼び出し側の置き場のトラックは解放を知らせる。
    procedure Clear;
    // 最後のトラックに「流し切った」の印を付ける（SDL_FlushAudioQueue）。
    procedure Flush;
    // 先頭のトラックを捨てる（SDL_PopAudioQueueHead）。先頭は流し切ったものであること。
    procedure PopHead;
    // 末尾に書く（SDL_WriteToAudioQueue）。形式か並びが変わったら、前のトラックは流し切ってあること。
    function  Write(const ASpec: TPMLAudioSpec; const AChannelMap: TPMLChannelMap;
      AData: PByte; ALen: PtrUInt): Boolean;
    // 呼び出し側が持つ置き場のトラックを作る（SDL_CreateAudioTrack）。
    function  CreateTrack(const ASpec: TPMLAudioSpec; const AChannelMap: TPMLChannelMap;
      AData: PByte; ALen, ACapacity: PtrUInt; ACallback: TPMLReleaseAudioBufferCallback;
      AUserData: Pointer): TPMLAudioTrack;
    // トラックを末尾に足す（SDL_AddTrackToAudioQueue）。前のトラックは流し切る。
    procedure AddTrack(ATrack: TPMLAudioTrack);
    // トラックの走査（SDL_BeginAudioQueueIter / SDL_NextAudioQueueIter）。走査の終わりは nil。
    // 戻り値はそのトラックのバイト数。無限に読めるとき（SDL の SDL_SIZE_MAX）は High(PtrUInt)。
    function  BeginIter: Pointer;
    function  NextIter(var AIter: Pointer; out ASpec: TPMLAudioSpec;
      out AChannelMap: TPMLChannelMap; out AFlushed: Boolean): PtrUInt;
    { 先頭のトラックから、過去 APastFrames・今 APresentFrames・未来 AFutureFrames のフレームを
      ADstFormat / ADstChannels / ADstMap へ変換して読む（SDL_ReadFromAudioQueue）。今の分だけ
      キューから取り除き、過去の分は履歴から、未来の分は覗くだけ（足りなければ流し切った後は無音）。
      戻り値は結果の置き場（ADst か AScratch の中）。足りなければ nil。 }
    function  Read(ADst: PByte; ADstFormat: TPMLAudioFormat; ADstChannels: Integer;
      const ADstMap: TPMLChannelMap; APastFrames, APresentFrames, AFutureFrames: Integer;
      AScratch: PByte; AGain: Single): PByte;
    // 溜まっているバイト数（SDL_GetAudioQueueQueued）。
    function  Queued: PtrUInt;
    // 履歴を ANumFrames フレームの無音にする（SDL_ResetAudioQueueHistory）。
    function  ResetHistory(ANumFrames: Integer): Boolean;
  end;

  TPMLAudioTrack = class
  private
    FSpec: TPMLAudioSpec;
    FChannelMap: TPMLChannelMap;
    FFlushed: Boolean;
    FNext: TPMLAudioTrack;
    FUserData: Pointer;
    FCallback: TPMLReleaseAudioBufferCallback;
    FData: PByte;
    FHead: PtrUInt;
    FTail: PtrUInt;
    FCapacity: PtrUInt;
  end;

implementation

uses
  PaPiMeLa.Errors;

const
  // 空きを溜めておく上限（SDL の InitMemoryPool の max_free）。
  TrackPoolMaxFree = 8;
  ChunkPoolMaxFree = 4;
  // キューを作るとき、先に用意しておくトラックの数（SDL の ReserveMemoryPoolBlocks）。
  TrackPoolReserve = 2;

{ チャンクの解放の知らせ（FreeChunkedAudioBuffer）。AUserData はキュー。 }
procedure FreeChunkedAudioBuffer(AUserData: Pointer; ABuf: Pointer; ALen: Integer);
begin
  TPMLAudioQueue(AUserData).FreeChunk(ABuf);
end;

{ ---- メモリのプール（AllocMemoryPoolBlock / FreeMemoryPoolBlock） ---- }

{ トラック: 空きがあれば使い回し、無ければ作る。 }
function TPMLAudioQueue.AllocTrack: TPMLAudioTrack;
begin
  if FTrackNumFree = 0 then
    Exit(TPMLAudioTrack.Create);
  Result := FTrackFree;
  FTrackFree := Result.FNext;
  Dec(FTrackNumFree);
end;

{ トラックを空きに戻す（上限を超えるなら捨てる）。次に使うとき SDL_zerop 相当に初期化される。 }
procedure TPMLAudioQueue.FreeTrack(ATrack: TPMLAudioTrack);
begin
  if FTrackNumFree < TrackPoolMaxFree then
  begin
    ATrack.FChannelMap := nil;
    ATrack.FNext := FTrackFree;
    FTrackFree := ATrack;
    Inc(FTrackNumFree);
  end
  else
    ATrack.Free;
end;

{ チャンク: 空きの先頭の 8 バイトに次の空きの番地が入っている。 }
function TPMLAudioQueue.AllocChunk: Pointer;
begin
  if FChunkNumFree = 0 then
  begin
    GetMem(Result, FChunkSize);
    Exit;
  end;
  Result := FChunkFree;
  FChunkFree := PPointer(Result)^;
  Dec(FChunkNumFree);
end;

procedure TPMLAudioQueue.FreeChunk(ABlock: Pointer);
begin
  if FChunkNumFree < ChunkPoolMaxFree then
  begin
    PPointer(ABlock)^ := FChunkFree;
    FChunkFree := ABlock;
    Inc(FChunkNumFree);
  end
  else
    FreeMem(ABlock);
end;

{ ---- キュー本体 ---- }

constructor TPMLAudioQueue.Create(AChunkSize: PtrUInt);
var
  I: Integer;
  Track: TPMLAudioTrack;
begin
  inherited Create;
  // SDL は assert(block_size >= sizeof(void *))。空きの先頭に次の番地を書くので要る。
  if AChunkSize < SizeOf(Pointer) then
    raise EPMLArgument.Create('audio queue chunk size is too small');
  FChunkSize := AChunkSize;
  // ReserveMemoryPoolBlocks(track_pool, 2)
  for I := 1 to TrackPoolReserve do
  begin
    Track := TPMLAudioTrack.Create;
    Track.FNext := FTrackFree;
    FTrackFree := Track;
    Inc(FTrackNumFree);
  end;
end;

destructor TPMLAudioQueue.Destroy;
var
  Track, NextTrack: TPMLAudioTrack;
  Block, NextBlock: Pointer;
begin
  Clear;
  // DestroyMemoryPool(track_pool / chunk_pool)
  Track := FTrackFree;
  FTrackFree := nil;
  FTrackNumFree := 0;
  while Track <> nil do
  begin
    NextTrack := Track.FNext;
    Track.Free;
    Track := NextTrack;
  end;
  Block := FChunkFree;
  FChunkFree := nil;
  FChunkNumFree := 0;
  while Block <> nil do
  begin
    NextBlock := PPointer(Block)^;
    FreeMem(Block);
    Block := NextBlock;
  end;
  if FHistoryBuffer <> nil then
    FreeMem(FHistoryBuffer);
  inherited Destroy;
end;

{ DestroyAudioTrack: 持ち主に返し、トラックを空きに戻す。 }
procedure TPMLAudioQueue.DestroyTrack(ATrack: TPMLAudioTrack);
begin
  if Assigned(ATrack.FCallback) then
    ATrack.FCallback(ATrack.FUserData, ATrack.FData, Integer(ATrack.FCapacity));
  FreeTrack(ATrack);
end;

procedure TPMLAudioQueue.Clear;
var
  Track, NextTrack: TPMLAudioTrack;
begin
  Track := FHead;
  FHead := nil;
  FTail := nil;
  FHistoryLength := 0;
  while Track <> nil do
  begin
    NextTrack := Track.FNext;
    DestroyTrack(Track);
    Track := NextTrack;
  end;
end;

procedure TPMLAudioQueue.Flush;
begin
  if FTail <> nil then
    FTail.FFlushed := True;
end;

procedure TPMLAudioQueue.PopHead;
var
  Track, NextTrack: TPMLAudioTrack;
  Flushed: Boolean;
begin
  Track := FHead;
  repeat
    Flushed := Track.FFlushed;
    NextTrack := Track.FNext;
    DestroyTrack(Track);
    Track := NextTrack;
  until Flushed;
  FHead := Track;
  FHistoryLength := 0;
  if Track = nil then
    FTail := nil;
end;

function TPMLAudioQueue.CreateTrack(const ASpec: TPMLAudioSpec; const AChannelMap: TPMLChannelMap;
  AData: PByte; ALen, ACapacity: PtrUInt; ACallback: TPMLReleaseAudioBufferCallback;
  AUserData: Pointer): TPMLAudioTrack;
begin
  Result := AllocTrack;
  // SDL_zerop(track)。プールから戻ったものは FreeTrack で並びを消してあるが、全部を初期化し直す。
  Result.FFlushed := False;
  Result.FNext := nil;
  if Length(AChannelMap) > 0 then
    Result.FChannelMap := Copy(AChannelMap, 0, ASpec.Channels)
  else
    Result.FChannelMap := nil;
  Result.FSpec := ASpec;
  Result.FUserData := AUserData;
  Result.FCallback := ACallback;
  Result.FData := AData;
  Result.FHead := 0;
  Result.FTail := ALen;
  Result.FCapacity := ACapacity;
end;

{ CreateChunkedAudioTrack: キューが確保したチャンクを置き場にした、空のトラック。 }
function TPMLAudioQueue.CreateChunkedTrack(const ASpec: TPMLAudioSpec;
  const AChannelMap: TPMLChannelMap): TPMLAudioTrack;
var
  Chunk: Pointer;
  Capacity: PtrUInt;
begin
  Chunk := AllocChunk;
  Capacity := FChunkSize;
  Capacity := Capacity - (Capacity mod PtrUInt(ASpec.FrameSize));
  try
    Result := CreateTrack(ASpec, AChannelMap, PByte(Chunk), 0, Capacity,
      @FreeChunkedAudioBuffer, Self);
  except
    FreeChunk(Chunk);
    raise;
  end;
end;

procedure TPMLAudioQueue.AddTrack(ATrack: TPMLAudioTrack);
begin
  if FTail <> nil then
  begin
    // 形式が変わっていたら、前のトラックを流し切る。
    if not ((FTail.FSpec.Format = ATrack.FSpec.Format)
      and (FTail.FSpec.Channels = ATrack.FSpec.Channels)
      and (FTail.FSpec.Freq = ATrack.FSpec.Freq)
      and PMLChannelMapsEqual(FTail.FSpec.Channels, FTail.FChannelMap, ATrack.FChannelMap)) then
      FTail.FFlushed := True;
    FTail.FNext := ATrack;
  end
  else
    FHead := ATrack;
  FTail := ATrack;
end;

{ ---- 書く ---- }

{ WriteToAudioTrack。 }
function WriteToTrack(ATrack: TPMLAudioTrack; AData: PByte; ALen: PtrUInt): PtrUInt;
begin
  if ATrack.FFlushed or (ATrack.FTail >= ATrack.FCapacity) then
    Exit(0);
  if ALen > ATrack.FCapacity - ATrack.FTail then
    ALen := ATrack.FCapacity - ATrack.FTail;
  Move(AData^, ATrack.FData[ATrack.FTail], ALen);
  Inc(ATrack.FTail, ALen);
  Result := ALen;
end;

function TPMLAudioQueue.Write(const ASpec: TPMLAudioSpec; const AChannelMap: TPMLChannelMap;
  AData: PByte; ALen: PtrUInt): Boolean;
var
  Track, NewTrack: TPMLAudioTrack;
  Written: PtrUInt;
begin
  if ALen = 0 then
    Exit(True);
  Track := FTail;
  if Track <> nil then
  begin
    if not ((Track.FSpec.Format = ASpec.Format) and (Track.FSpec.Channels = ASpec.Channels)
      and (Track.FSpec.Freq = ASpec.Freq)
      and PMLChannelMapsEqual(Track.FSpec.Channels, Track.FChannelMap, AChannelMap)) then
      Track.FFlushed := True;
  end
  else
  begin
    Track := CreateChunkedTrack(ASpec, AChannelMap);
    FHead := Track;
    FTail := Track;
  end;
  repeat
    Written := WriteToTrack(Track, AData, ALen);
    Inc(AData, Written);
    Dec(ALen, Written);
    if ALen = 0 then
      Break;
    NewTrack := CreateChunkedTrack(ASpec, AChannelMap);
    Track.FNext := NewTrack;
    FTail := NewTrack;
    Track := NewTrack;
  until False;
  Result := True;
end;

{ ---- 走査 ---- }

function TPMLAudioQueue.BeginIter: Pointer;
begin
  Result := FHead;
end;

function TPMLAudioQueue.NextIter(var AIter: Pointer; out ASpec: TPMLAudioSpec;
  out AChannelMap: TPMLChannelMap; out AFlushed: Boolean): PtrUInt;
var
  Iter, Track: TPMLAudioTrack;
  Avail: PtrUInt;
  Flushed: Boolean;
begin
  Iter := TPMLAudioTrack(AIter);
  ASpec := Iter.FSpec;
  AChannelMap := Iter.FChannelMap;
  Flushed := False;
  Result := 0;
  while Iter <> nil do
  begin
    Track := Iter;
    Iter := Iter.FNext;
    Avail := Track.FTail - Track.FHead;
    // 足すと溢れるなら、無限に読めることにする。
    if Avail >= High(PtrUInt) - Result then
    begin
      Result := High(PtrUInt);
      Flushed := False;
      Break;
    end;
    Inc(Result, Avail);
    Flushed := Track.FFlushed;
    if Flushed then
      Break;
  end;
  AIter := Iter;
  AFlushed := Flushed;
end;

{ ---- 読む ---- }

{ PeekIntoAudioQueuePast: 先頭のトラックの手前の ALen バイト。足りない分は履歴から。 }
function TPMLAudioQueue.PeekPast(AData: PByte; ALen: PtrUInt): PByte;
var
  Track: TPMLAudioTrack;
  Past: PtrUInt;
begin
  Track := FHead;
  if Track.FHead >= ALen then
    Exit(@Track.FData[Track.FHead - ALen]);
  Past := ALen - Track.FHead;
  if Past > FHistoryLength then
    Exit(nil);
  Move(FHistoryBuffer[FHistoryLength - Past], AData^, Past);
  Move(Track.FData^, AData[Past], Track.FHead);
  Result := AData;
end;

{ UpdateAudioQueueHistory: 読み終えたトラックの末尾を履歴の後ろに足す。 }
procedure TPMLAudioQueue.UpdateHistory(AData: PByte; ALen: PtrUInt);
var
  HistoryBytes, Preserve: PtrUInt;
begin
  HistoryBytes := FHistoryLength;
  if ALen >= HistoryBytes then
    Move(AData[ALen - HistoryBytes], FHistoryBuffer^, HistoryBytes)
  else
  begin
    Preserve := HistoryBytes - ALen;
    Move(FHistoryBuffer[ALen], FHistoryBuffer^, Preserve);
    Move(AData^, FHistoryBuffer[Preserve], ALen);
  end;
end;

{ ReadFromAudioQueue: ALen バイトを取り除いて返す。足りなければ nil。 }
function TPMLAudioQueue.ReadPresent(AData: PByte; ALen: PtrUInt): PByte;
var
  Track, NextTrack: TPMLAudioTrack;
  Total, Avail: PtrUInt;
begin
  Track := FHead;
  if Track.FTail - Track.FHead >= ALen then
  begin
    Result := @Track.FData[Track.FHead];
    Inc(Track.FHead, ALen);
    Exit;
  end;
  Total := 0;
  repeat
    Avail := Track.FTail - Track.FHead;
    if Avail > ALen - Total then
      Avail := ALen - Total;
    Move(Track.FData[Track.FHead], AData[Total], Avail);
    Inc(Track.FHead, Avail);
    Inc(Total, Avail);
    if Total = ALen then
      Break;
    // 流し切ったトラックの先、まだ続きが来ていないトラックの先は読めない。
    if Track.FFlushed then
      Exit(nil);
    NextTrack := Track.FNext;
    if NextTrack = nil then
      Exit(nil);
    UpdateHistory(Track.FData, Track.FTail);
    FHead := NextTrack;
    DestroyTrack(Track);
    Track := NextTrack;
  until False;
  Result := AData;
end;

{ PeekIntoAudioQueueFuture: 取り除かずに ALen バイト。流し切った後で足りなければ無音で埋める。 }
function TPMLAudioQueue.PeekFuture(AData: PByte; ALen: PtrUInt): PByte;
var
  Track: TPMLAudioTrack;
  Total, Avail: PtrUInt;
begin
  Track := FHead;
  if Track.FTail - Track.FHead >= ALen then
    Exit(@Track.FData[Track.FHead]);
  Total := 0;
  repeat
    Avail := Track.FTail - Track.FHead;
    if Avail > ALen - Total then
      Avail := ALen - Total;
    Move(Track.FData[Track.FHead], AData[Total], Avail);
    Inc(Total, Avail);
    if Total = ALen then
      Break;
    if Track.FFlushed then
    begin
      FillChar(AData[Total], ALen - Total, PMLAudioSilenceValue(Track.FSpec.Format));
      Break;
    end;
    Track := Track.FNext;
    if Track = nil then
      Exit(nil);
  until False;
  Result := AData;
end;

function TPMLAudioQueue.Read(ADst: PByte; ADstFormat: TPMLAudioFormat; ADstChannels: Integer;
  const ADstMap: TPMLChannelMap; APastFrames, APresentFrames, AFutureFrames: Integer;
  AScratch: PByte; AGain: Single): PByte;
var
  Track: TPMLAudioTrack;
  SrcFormat: TPMLAudioFormat;
  SrcChannels: Integer;
  SrcMap: TPMLChannelMap;
  SrcFrameSize, DstFrameSize: PtrUInt;
  SrcPastBytes, SrcPresentBytes, SrcFutureBytes: PtrUInt;
  DstPastBytes, DstPresentBytes, DstFutureBytes: PtrUInt;
  Convert: Boolean;
  Ptr, Src: PByte;
begin
  Track := FHead;
  if Track = nil then
    Exit(nil);

  SrcFormat := Track.FSpec.Format;
  SrcChannels := Track.FSpec.Channels;
  SrcMap := Track.FChannelMap;

  SrcFrameSize := PtrUInt(PMLAudioByteSize(SrcFormat)) * PtrUInt(SrcChannels);
  DstFrameSize := PtrUInt(PMLAudioByteSize(ADstFormat)) * PtrUInt(ADstChannels);

  SrcPastBytes := PtrUInt(APastFrames) * SrcFrameSize;
  SrcPresentBytes := PtrUInt(APresentFrames) * SrcFrameSize;
  SrcFutureBytes := PtrUInt(AFutureFrames) * SrcFrameSize;

  DstPastBytes := PtrUInt(APastFrames) * DstFrameSize;
  DstPresentBytes := PtrUInt(APresentFrames) * DstFrameSize;
  DstFutureBytes := PtrUInt(AFutureFrames) * DstFrameSize;

  Convert := (SrcFormat <> ADstFormat) or (SrcChannels <> ADstChannels) or (AGain <> Single(1.0));

  // 写してほしいと言われていないが、変換が要るなら作業用の置き場に出す。
  if Convert and (ADst = nil) then
    ADst := AScratch;

  // 先頭のトラックだけで全部まかなえるか。
  if (Track.FHead >= SrcPastBytes)
    and ((Track.FTail - Track.FHead) >= (SrcPresentBytes + SrcFutureBytes)) then
  begin
    Ptr := @Track.FData[Track.FHead - SrcPastBytes];
    Inc(Track.FHead, SrcPresentBytes);
    // 写すか変換する必要があるか。
    if ADst <> nil then
    begin
      PMLConvertAudio(APastFrames + APresentFrames + AFutureFrames, Ptr,
        SrcFormat, SrcChannels, SrcMap, ADst, ADstFormat, ADstChannels, ADstMap, AScratch, AGain);
      Ptr := ADst;
    end;
    Exit(Ptr);
  end;

  if ADst = nil then
    // 写してほしいと言われていないが、写さないと渡せないので作業用の置き場に出す。
    ADst := AScratch
  else if not Convert then
    // 写すだけなので、作業用の置き場を使わず ADst へ直接写す。
    AScratch := ADst;

  Ptr := ADst;

  if SrcPastBytes <> 0 then
  begin
    Src := PeekPast(AScratch, SrcPastBytes);
    // PORT-NOTE: SDL は NULL のまま ConvertAudio に渡す（履歴が無いときは未定義）。ここでは nil を返す。
    if Src = nil then
      Exit(nil);
    PMLConvertAudio(APastFrames, Src, SrcFormat, SrcChannels, SrcMap,
      ADst, ADstFormat, ADstChannels, ADstMap, AScratch, AGain);
    Inc(ADst, DstPastBytes);
    Inc(AScratch, DstPastBytes);
  end;

  if SrcPresentBytes <> 0 then
  begin
    Src := ReadPresent(AScratch, SrcPresentBytes);
    if Src = nil then
      Exit(nil);
    PMLConvertAudio(APresentFrames, Src, SrcFormat, SrcChannels, SrcMap,
      ADst, ADstFormat, ADstChannels, ADstMap, AScratch, AGain);
    Inc(ADst, DstPresentBytes);
    Inc(AScratch, DstPresentBytes);
  end;

  if SrcFutureBytes <> 0 then
  begin
    Src := PeekFuture(AScratch, SrcFutureBytes);
    if Src = nil then
      Exit(nil);
    PMLConvertAudio(AFutureFrames, Src, SrcFormat, SrcChannels, SrcMap,
      ADst, ADstFormat, ADstChannels, ADstMap, AScratch, AGain);
    Inc(ADst, DstFutureBytes);
    Inc(AScratch, DstFutureBytes);
  end;

  Result := Ptr;
end;

function TPMLAudioQueue.Queued: PtrUInt;
var
  Iter: Pointer;
  Spec: TPMLAudioSpec;
  Map: TPMLChannelMap;
  Flushed: Boolean;
  Avail: PtrUInt;
begin
  Result := 0;
  Iter := BeginIter;
  while Iter <> nil do
  begin
    Avail := NextIter(Iter, Spec, Map, Flushed);
    if Avail >= High(PtrUInt) - Result then
    begin
      Result := High(PtrUInt);
      Break;
    end;
    Inc(Result, Avail);
  end;
end;

function TPMLAudioQueue.ResetHistory(ANumFrames: Integer): Boolean;
var
  Track: TPMLAudioTrack;
  Len: PtrUInt;
  NewBuffer: PByte;
begin
  Track := FHead;
  if Track = nil then
    Exit(False);
  Len := PtrUInt(ANumFrames) * PtrUInt(Track.FSpec.FrameSize);
  if FHistoryCapacity < Len then
  begin
    // 先に新しい置き場を確保する。失敗したら（例外）前の履歴はそのまま残る。
    GetMem(NewBuffer, Len);
    if FHistoryBuffer <> nil then
      FreeMem(FHistoryBuffer);
    FHistoryBuffer := NewBuffer;
    FHistoryCapacity := Len;
  end;
  FHistoryLength := Len;
  if Len > 0 then
    FillChar(FHistoryBuffer^, Len, PMLAudioSilenceValue(Track.FSpec.Format));
  Result := True;
end;

end.
