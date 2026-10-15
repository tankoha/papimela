// アンブレラ（PaPiMeLa.pas）の implementation 部に入る本体。
// tools/genumbrella.bb が次のユニットの interface 部から生成する。手で直さず、
// 生成器を直して作り直すこと（tools/genumbrella.bb --check が古さを調べる）。
//   PaPiMeLa.Types
//   PaPiMeLa.Errors
//   PaPiMeLa.Core
//   PaPiMeLa.Events
//   PaPiMeLa.Events.Drop
//   PaPiMeLa.Events.Keymap
//   PaPiMeLa.Keycodes
//   PaPiMeLa.Pixels
//   PaPiMeLa.Surface
//   PaPiMeLa.Surface.Blit
//   PaPiMeLa.Surface.BMP
//   PaPiMeLa.Surface.YUV
//   PaPiMeLa.IO
//   PaPiMeLa.Video
//   PaPiMeLa.Clipboard
//   PaPiMeLa.Render
//   PaPiMeLa.Audio.Convert
//   PaPiMeLa.Audio.Stream
//   PaPiMeLa.Audio.Mixer
//   PaPiMeLa.Audio.Wave
//   PaPiMeLa.Audio
//   PaPiMeLa.TextInput
//   PaPiMeLa.Time
//   PaPiMeLa.Atomic
//   PaPiMeLa.Threading
//   PaPiMeLa.Properties
//   PaPiMeLa.Log
//   PaPiMeLa.App
//   PaPiMeLa.Video.Backend
//   PaPiMeLa.TextInput.Backend
//   PaPiMeLa.Audio.Backend

// ---- PaPiMeLa.Events
function PMLEventDescription(const AEvent: TPMLEvent): String;
begin
  Result := PaPiMeLa.Events.PMLEventDescription(AEvent);
end;

function PMLNowNS: UInt64;
begin
  Result := PaPiMeLa.Events.PMLNowNS;
end;

// ---- PaPiMeLa.Events.Drop
function PMLURIToLocalPath(const AURI: String; out APath: String): Boolean;
begin
  Result := PaPiMeLa.Events.Drop.PMLURIToLocalPath(AURI, APath);
end;

function PMLURIListToLocalPaths(const AList: String): TStringArray;
begin
  Result := PaPiMeLa.Events.Drop.PMLURIListToLocalPaths(AList);
end;

// ---- PaPiMeLa.Events.Keymap
function PMLDefaultKeyFromScancode(AScancode: TPMLScancode; AShifted: Boolean): TPMLKeycode;
begin
  Result := PaPiMeLa.Events.Keymap.PMLDefaultKeyFromScancode(AScancode, AShifted);
end;

function PMLDefaultScancodeFromKey(AKey: TPMLKeycode; out AShifted: Boolean): TPMLScancode;
begin
  Result := PaPiMeLa.Events.Keymap.PMLDefaultScancodeFromKey(AKey, AShifted);
end;

function PMLScancodeFromName(const AName: String): TPMLScancode;
begin
  Result := PaPiMeLa.Events.Keymap.PMLScancodeFromName(AName);
end;

function PMLKeysymToUcs4(AKeysym: LongWord): LongWord;
begin
  Result := PaPiMeLa.Events.Keymap.PMLKeysymToUcs4(AKeysym);
end;

function PMLKeymapKeycode(
  AKeysym: LongWord;
  AScancode: TPMLScancode;
  AShifted: Boolean): TPMLKeycode;
begin
  Result := PaPiMeLa.Events.Keymap.PMLKeymapKeycode(AKeysym, AScancode, AShifted);
end;

function PMLScancodeFromEvdev(AEvdevCode: LongWord): TPMLScancode;
begin
  Result := PaPiMeLa.Events.Keymap.PMLScancodeFromEvdev(AEvdevCode);
end;

function PMLConvertNumpadKeycode(AKeycode: TPMLKeycode; ANumLock: Boolean): TPMLKeycode;
begin
  Result := PaPiMeLa.Events.Keymap.PMLConvertNumpadKeycode(AKeycode, ANumLock);
end;

function PMLParseKeycodeOptions(const AHint: String): TPMLKeycodeOptions;
begin
  Result := PaPiMeLa.Events.Keymap.PMLParseKeycodeOptions(AHint);
end;

// ---- PaPiMeLa.Pixels
function PMLPixelFlag(AFormat: TPMLPixelFormat): LongWord;
begin
  Result := PaPiMeLa.Pixels.PMLPixelFlag(AFormat);
end;

function PMLPixelType(AFormat: TPMLPixelFormat): TPMLPixelType;
begin
  Result := PaPiMeLa.Pixels.PMLPixelType(AFormat);
end;

function PMLPixelOrder(AFormat: TPMLPixelFormat): LongWord;
begin
  Result := PaPiMeLa.Pixels.PMLPixelOrder(AFormat);
end;

function PMLPixelLayout(AFormat: TPMLPixelFormat): TPMLPackedLayout;
begin
  Result := PaPiMeLa.Pixels.PMLPixelLayout(AFormat);
end;

function PMLBitsPerPixel(AFormat: TPMLPixelFormat): Integer;
begin
  Result := PaPiMeLa.Pixels.PMLBitsPerPixel(AFormat);
end;

function PMLBytesPerPixel(AFormat: TPMLPixelFormat): Integer;
begin
  Result := PaPiMeLa.Pixels.PMLBytesPerPixel(AFormat);
end;

function PMLIsPixelFormatIndexed(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormatIndexed(AFormat);
end;

function PMLIsPixelFormatPacked(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormatPacked(AFormat);
end;

function PMLIsPixelFormatArray(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormatArray(AFormat);
end;

function PMLIsPixelFormatAlpha(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormatAlpha(AFormat);
end;

function PMLIsPixelFormatFourCC(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormatFourCC(AFormat);
end;

function PMLIsPixelFormatFloat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormatFloat(AFormat);
end;

function PMLIsPixelFormat10Bit(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLIsPixelFormat10Bit(AFormat);
end;

function PMLDefaultColorspace(AFormat: TPMLPixelFormat): TPMLColorspace;
begin
  Result := PaPiMeLa.Pixels.PMLDefaultColorspace(AFormat);
end;

function PMLPixelFormatName(AFormat: TPMLPixelFormat): String;
begin
  Result := PaPiMeLa.Pixels.PMLPixelFormatName(AFormat);
end;

function PMLGetPixelFormatDetails(
  AFormat: TPMLPixelFormat;
  out ADetails: TPMLPixelFormatDetails): Boolean;
begin
  Result := PaPiMeLa.Pixels.PMLGetPixelFormatDetails(AFormat, ADetails);
end;

function PMLGetPixelFormatForMasks(
  ABitsPerPixel: Integer;
  ARMask, AGMask, ABMask, AAMask: LongWord): TPMLPixelFormat;
begin
  Result := PaPiMeLa.Pixels.PMLGetPixelFormatForMasks(ABitsPerPixel, ARMask, AGMask, ABMask, AAMask);
end;

function PMLMapRGB(
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  AR, AG, AB: Byte): LongWord;
begin
  Result := PaPiMeLa.Pixels.PMLMapRGB(ADetails, APalette, AR, AG, AB);
end;

function PMLMapRGBA(
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  AR, AG, AB, AA: Byte): LongWord;
begin
  Result := PaPiMeLa.Pixels.PMLMapRGBA(ADetails, APalette, AR, AG, AB, AA);
end;

function PMLMapColor(
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  const AColor: TPMLColor): LongWord;
begin
  Result := PaPiMeLa.Pixels.PMLMapColor(ADetails, APalette, AColor);
end;

procedure PMLGetRGB(
  APixel: LongWord;
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  out AR, AG, AB: Byte);
begin
  PaPiMeLa.Pixels.PMLGetRGB(APixel, ADetails, APalette, AR, AG, AB);
end;

procedure PMLGetRGBA(
  APixel: LongWord;
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette;
  out AR, AG, AB, AA: Byte);
begin
  PaPiMeLa.Pixels.PMLGetRGBA(APixel, ADetails, APalette, AR, AG, AB, AA);
end;

function PMLGetColor(
  APixel: LongWord;
  const ADetails: TPMLPixelFormatDetails;
  APalette: TPMLPalette): TPMLColor;
begin
  Result := PaPiMeLa.Pixels.PMLGetColor(APixel, ADetails, APalette);
end;

// ---- PaPiMeLa.Surface
function PMLPitchFor(AWidth: Integer; AFormat: TPMLPixelFormat): Integer;
begin
  Result := PaPiMeLa.Surface.PMLPitchFor(AWidth, AFormat);
end;

// ---- PaPiMeLa.Surface.Blit
function PMLBlit(
  ASrc: TPMLSurface;
  const ASrcRect: TPMLRect;
  ADst: TPMLSurface;
  const ADstRect: TPMLRect): Boolean;
begin
  Result := PaPiMeLa.Surface.Blit.PMLBlit(ASrc, ASrcRect, ADst, ADstRect);
end;

function PMLBlitScaled(
  ASrc: TPMLSurface;
  const ASrcRect: TPMLRect;
  ADst: TPMLSurface;
  const ADstRect: TPMLRect;
  AMode: TPMLScaleMode): Boolean;
begin
  Result := PaPiMeLa.Surface.Blit.PMLBlitScaled(ASrc, ASrcRect, ADst, ADstRect, AMode);
end;

function PMLFillRect(ADst: TPMLSurface; const ARect: TPMLRect; const AColor: TPMLColor): Boolean;
begin
  Result := PaPiMeLa.Surface.Blit.PMLFillRect(ADst, ARect, AColor);
end;

function PMLBlendColor(const ASrc, ADst: TPMLColor; AMode: TPMLBlendMode): TPMLColor;
begin
  Result := PaPiMeLa.Surface.Blit.PMLBlendColor(ASrc, ADst, AMode);
end;

// ---- PaPiMeLa.Surface.BMP
function PMLLoadBMP(AStream: TStream): TPMLSurface;
begin
  Result := PaPiMeLa.Surface.BMP.PMLLoadBMP(AStream);
end;

function PMLLoadBMPFile(const APath: String): TPMLSurface;
begin
  Result := PaPiMeLa.Surface.BMP.PMLLoadBMPFile(APath);
end;

procedure PMLSaveBMP(AStream: TStream; ASurface: TPMLSurface);
begin
  PaPiMeLa.Surface.BMP.PMLSaveBMP(AStream, ASurface);
end;

procedure PMLSaveBMPFile(const APath: String; ASurface: TPMLSurface);
begin
  PaPiMeLa.Surface.BMP.PMLSaveBMPFile(APath, ASurface);
end;

// ---- PaPiMeLa.Surface.YUV
function PMLIsYUVFormat(AFormat: TPMLPixelFormat): Boolean;
begin
  Result := PaPiMeLa.Surface.YUV.PMLIsYUVFormat(AFormat);
end;

function PMLYCbCrTypeOf(AColorspace: TPMLColorspace; out AType: TPMLYCbCrType): Boolean;
begin
  Result := PaPiMeLa.Surface.YUV.PMLYCbCrTypeOf(AColorspace, AType);
end;

function PMLCalculateYUVSize(
  AFormat: TPMLPixelFormat;
  AWidth, AHeight: Integer;
  out ASize: PtrUInt;
  out APitch: Integer): Boolean;
begin
  Result := PaPiMeLa.Surface.YUV.PMLCalculateYUVSize(AFormat, AWidth, AHeight, ASize, APitch);
end;

procedure PMLConvertYUVToARGB8888(
  AWidth, AHeight: Integer;
  AFormat: TPMLPixelFormat;
  AColorspace: TPMLColorspace;
  ASrc: Pointer;
  ASrcPitch: Integer;
  ADst: Pointer;
  ADstPitch: Integer);
begin
  PaPiMeLa.Surface.YUV.PMLConvertYUVToARGB8888(AWidth, AHeight, AFormat, AColorspace, ASrc, ASrcPitch, ADst, ADstPitch);
end;

// ---- PaPiMeLa.IO
function PMLReadU8(AStream: TStream): Byte;
begin
  Result := PaPiMeLa.IO.PMLReadU8(AStream);
end;

function PMLReadU16LE(AStream: TStream): Word;
begin
  Result := PaPiMeLa.IO.PMLReadU16LE(AStream);
end;

function PMLReadU32LE(AStream: TStream): LongWord;
begin
  Result := PaPiMeLa.IO.PMLReadU32LE(AStream);
end;

function PMLReadU16BE(AStream: TStream): Word;
begin
  Result := PaPiMeLa.IO.PMLReadU16BE(AStream);
end;

function PMLReadU32BE(AStream: TStream): LongWord;
begin
  Result := PaPiMeLa.IO.PMLReadU32BE(AStream);
end;

function PMLReadS16LE(AStream: TStream): SmallInt;
begin
  Result := PaPiMeLa.IO.PMLReadS16LE(AStream);
end;

function PMLReadS32LE(AStream: TStream): LongInt;
begin
  Result := PaPiMeLa.IO.PMLReadS32LE(AStream);
end;

procedure PMLWriteU8(AStream: TStream; AValue: Byte);
begin
  PaPiMeLa.IO.PMLWriteU8(AStream, AValue);
end;

procedure PMLWriteU16LE(AStream: TStream; AValue: Word);
begin
  PaPiMeLa.IO.PMLWriteU16LE(AStream, AValue);
end;

procedure PMLWriteU32LE(AStream: TStream; AValue: LongWord);
begin
  PaPiMeLa.IO.PMLWriteU32LE(AStream, AValue);
end;

procedure PMLWriteU16BE(AStream: TStream; AValue: Word);
begin
  PaPiMeLa.IO.PMLWriteU16BE(AStream, AValue);
end;

procedure PMLWriteU32BE(AStream: TStream; AValue: LongWord);
begin
  PaPiMeLa.IO.PMLWriteU32BE(AStream, AValue);
end;

procedure PMLReadExactly(AStream: TStream; var ABuffer; ACount: LongInt);
begin
  PaPiMeLa.IO.PMLReadExactly(AStream, ABuffer, ACount);
end;

procedure PMLWriteExactly(AStream: TStream; const ABuffer; ACount: LongInt);
begin
  PaPiMeLa.IO.PMLWriteExactly(AStream, ABuffer, ACount);
end;

function PMLReadAll(AStream: TStream): TBytes;
begin
  Result := PaPiMeLa.IO.PMLReadAll(AStream);
end;

function PMLLoadFile(const APath: String): TBytes;
begin
  Result := PaPiMeLa.IO.PMLLoadFile(APath);
end;

procedure PMLSaveFile(const APath: String; const AData: TBytes);
begin
  PaPiMeLa.IO.PMLSaveFile(APath, AData);
end;

function PMLLoadTextFile(const APath: String): String;
begin
  Result := PaPiMeLa.IO.PMLLoadTextFile(APath);
end;

// ---- PaPiMeLa.Render
function PMLSameDrawState(const A, B: TPMLRenderCommand): Boolean;
begin
  Result := PaPiMeLa.Render.PMLSameDrawState(A, B);
end;

function PMLRenderDriverNames: TStringArray;
begin
  Result := PaPiMeLa.Render.PMLRenderDriverNames;
end;

// ---- PaPiMeLa.Audio.Convert
function PMLAudioBitSize(AFormat: TPMLAudioFormat): Integer;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioBitSize(AFormat);
end;

function PMLAudioByteSize(AFormat: TPMLAudioFormat): Integer;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioByteSize(AFormat);
end;

function PMLAudioIsFloat(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioIsFloat(AFormat);
end;

function PMLAudioIsBigEndian(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioIsBigEndian(AFormat);
end;

function PMLAudioIsSigned(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioIsSigned(AFormat);
end;

function PMLIsSupportedAudioFormat(AFormat: TPMLAudioFormat): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLIsSupportedAudioFormat(AFormat);
end;

function PMLIsSupportedChannelCount(AChannels: Integer): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLIsSupportedChannelCount(AChannels);
end;

function PMLAudioFormatName(AFormat: TPMLAudioFormat): String;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioFormatName(AFormat);
end;

function PMLAudioSilenceValue(AFormat: TPMLAudioFormat): Byte;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioSilenceValue(AFormat);
end;

function PMLClosestAudioFormats(AFormat: TPMLAudioFormat): TPMLAudioFormats;
begin
  Result := PaPiMeLa.Audio.Convert.PMLClosestAudioFormats(AFormat);
end;

function PMLChannelMapIsBogus(const AMap: TPMLChannelMap; AChannels: Integer): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLChannelMapIsBogus(AMap, AChannels);
end;

function PMLChannelMapIsDefault(const AMap: TPMLChannelMap; AChannels: Integer): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLChannelMapIsDefault(AMap, AChannels);
end;

function PMLChannelMapsEqual(AChannels: Integer; const A, B: TPMLChannelMap): Boolean;
begin
  Result := PaPiMeLa.Audio.Convert.PMLChannelMapsEqual(AChannels, A, B);
end;

procedure PMLConvertAudioToFloat(
  ADst: PSingle;
  ASrc: Pointer;
  ANumSamples: Integer;
  ASrcFormat: TPMLAudioFormat);
begin
  PaPiMeLa.Audio.Convert.PMLConvertAudioToFloat(ADst, ASrc, ANumSamples, ASrcFormat);
end;

procedure PMLConvertAudioFromFloat(
  ADst: Pointer;
  ASrc: PSingle;
  ANumSamples: Integer;
  ADstFormat: TPMLAudioFormat);
begin
  PaPiMeLa.Audio.Convert.PMLConvertAudioFromFloat(ADst, ASrc, ANumSamples, ADstFormat);
end;

procedure PMLConvertAudioSwapEndian(ADst, ASrc: Pointer; ANumSamples, ABitSize: Integer);
begin
  PaPiMeLa.Audio.Convert.PMLConvertAudioSwapEndian(ADst, ASrc, ANumSamples, ABitSize);
end;

procedure PMLConvertAudio(
  ANumFrames: Integer;
  ASrc: Pointer;
  ASrcFormat: TPMLAudioFormat;
  ASrcChannels: Integer;
  const ASrcMap: TPMLChannelMap;
  ADst: Pointer;
  ADstFormat: TPMLAudioFormat;
  ADstChannels: Integer;
  const ADstMap: TPMLChannelMap;
  AScratch: Pointer;
  AGain: Single);
begin
  PaPiMeLa.Audio.Convert.PMLConvertAudio(ANumFrames, ASrc, ASrcFormat, ASrcChannels, ASrcMap, ADst, ADstFormat, ADstChannels, ADstMap, AScratch, AGain);
end;

function PMLAudioMaxFrameSize(
  ASrcFormat: TPMLAudioFormat;
  ASrcChannels: Integer;
  ADstFormat: TPMLAudioFormat;
  ADstChannels: Integer): Integer;
begin
  Result := PaPiMeLa.Audio.Convert.PMLAudioMaxFrameSize(ASrcFormat, ASrcChannels, ADstFormat, ADstChannels);
end;

function PMLGetResampleRate(ASrcRate, ADstRate: Integer): Int64;
begin
  Result := PaPiMeLa.Audio.Convert.PMLGetResampleRate(ASrcRate, ADstRate);
end;

function PMLResamplerHistoryFrames: Integer;
begin
  Result := PaPiMeLa.Audio.Convert.PMLResamplerHistoryFrames;
end;

function PMLResamplerPaddingFrames(ARate: Int64): Integer;
begin
  Result := PaPiMeLa.Audio.Convert.PMLResamplerPaddingFrames(ARate);
end;

function PMLResamplerInputFrames(AOutputFrames, ARate, AOffset: Int64): Int64;
begin
  Result := PaPiMeLa.Audio.Convert.PMLResamplerInputFrames(AOutputFrames, ARate, AOffset);
end;

function PMLResamplerOutputFrames(AInputFrames, ARate: Int64; var AOffset: Int64): Int64;
begin
  Result := PaPiMeLa.Audio.Convert.PMLResamplerOutputFrames(AInputFrames, ARate, AOffset);
end;

procedure PMLResampleAudio(
  AChannels: Integer;
  ASrc: PSingle;
  AInFrames: Integer;
  ADst: PSingle;
  AOutFrames: Integer;
  ARate: Int64;
  var AOffset: Int64);
begin
  PaPiMeLa.Audio.Convert.PMLResampleAudio(AChannels, ASrc, AInFrames, ADst, AOutFrames, ARate, AOffset);
end;

// ---- PaPiMeLa.Audio.Stream
function PMLConvertAudioSamples(
  const ASrcSpec: TPMLAudioSpec;
  ASrc: Pointer;
  ALen: Integer;
  const ADstSpec: TPMLAudioSpec): TBytes;
begin
  Result := PaPiMeLa.Audio.Stream.PMLConvertAudioSamples(ASrcSpec, ASrc, ALen, ADstSpec);
end;

// ---- PaPiMeLa.Audio.Mixer
procedure PMLMixAudio(
  ADst, ASrc: Pointer;
  AFormat: TPMLAudioFormat;
  ALen: Integer;
  AVolume: Single);
begin
  PaPiMeLa.Audio.Mixer.PMLMixAudio(ADst, ASrc, AFormat, ALen, AVolume);
end;

// ---- PaPiMeLa.Audio.Wave
function PMLLoadWAV(
  AStream: TStream;
  const AOptions: TPMLWaveOptions;
  out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PaPiMeLa.Audio.Wave.PMLLoadWAV(AStream, AOptions, ASpec);
end;

function PMLLoadWAV(AStream: TStream; out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PaPiMeLa.Audio.Wave.PMLLoadWAV(AStream, ASpec);
end;

function PMLLoadWAVFile(
  const APath: String;
  const AOptions: TPMLWaveOptions;
  out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PaPiMeLa.Audio.Wave.PMLLoadWAVFile(APath, AOptions, ASpec);
end;

function PMLLoadWAVFile(const APath: String; out ASpec: TPMLAudioSpec): TBytes;
begin
  Result := PaPiMeLa.Audio.Wave.PMLLoadWAVFile(APath, ASpec);
end;

// ---- PaPiMeLa.Audio
procedure PMLMixFloat32Audio(ADst, ASrc: PSingle; ALen: Integer);
begin
  PaPiMeLa.Audio.PMLMixFloat32Audio(ADst, ASrc, ALen);
end;

// ---- PaPiMeLa.Time
procedure PMLDelay(AMs: LongWord);
begin
  PaPiMeLa.Time.PMLDelay(AMs);
end;

procedure PMLDelayNS(ANs: UInt64);
begin
  PaPiMeLa.Time.PMLDelayNS(ANs);
end;

procedure PMLDelayPrecise(ANs: UInt64);
begin
  PaPiMeLa.Time.PMLDelayPrecise(ANs);
end;

procedure PMLDelayPreciseWith(
  ANs: UInt64;
  ANow: TPMLNowFunc;
  ASleep: TPMLSleepProc;
  APause: TPMLPauseProc);
begin
  PaPiMeLa.Time.PMLDelayPreciseWith(ANs, ANow, ASleep, APause);
end;

// ---- PaPiMeLa.Atomic
procedure PMLMemoryBarrierRelease;
begin
  PaPiMeLa.Atomic.PMLMemoryBarrierRelease;
end;

procedure PMLMemoryBarrierAcquire;
begin
  PaPiMeLa.Atomic.PMLMemoryBarrierAcquire;
end;

procedure PMLCPUPause;
begin
  PaPiMeLa.Atomic.PMLCPUPause;
end;

// ---- PaPiMeLa.Threading
function PMLThreadSchedPolicy(
  APriority: TPMLThreadPriority;
  const APolicyHint: String;
  AForceRealtimeTimeCritical: Boolean;
  ACurrent: TPMLSchedPolicy): TPMLSchedPolicy;
begin
  Result := PaPiMeLa.Threading.PMLThreadSchedPolicy(APriority, APolicyHint, AForceRealtimeTimeCritical, ACurrent);
end;

function PMLRealtimePriority(APriority: TPMLThreadPriority; AMaxRealtime: Integer): Integer;
begin
  Result := PaPiMeLa.Threading.PMLRealtimePriority(APriority, AMaxRealtime);
end;

function PMLRealtimeKitMaxPriority: Integer;
begin
  Result := PaPiMeLa.Threading.PMLRealtimeKitMaxPriority;
end;

// ---- PaPiMeLa.Properties
function PMLGetEnvironment(const AName: String; out AValue: String): Boolean;
begin
  Result := PaPiMeLa.Properties.PMLGetEnvironment(AName, AValue);
end;

function PMLStringBoolean(const AValue: String; ADefault: Boolean): Boolean;
begin
  Result := PaPiMeLa.Properties.PMLStringBoolean(AValue, ADefault);
end;

function PMLStringInteger(const AValue: String; ADefault: Integer): Integer;
begin
  Result := PaPiMeLa.Properties.PMLStringInteger(AValue, ADefault);
end;

function PMLStrToInt64C(const AValue: String): Int64;
begin
  Result := PaPiMeLa.Properties.PMLStrToInt64C(AValue);
end;

function PMLStrToFloatC(const AValue: String): Double;
begin
  Result := PaPiMeLa.Properties.PMLStrToFloatC(AValue);
end;

// ---- PaPiMeLa.Video.Backend
function PMLVideoBackendNames: TStringArray;
begin
  Result := PaPiMeLa.Video.Backend.PMLVideoBackendNames;
end;

// ---- PaPiMeLa.TextInput.Backend
function PMLTextInputBackendNames: TStringArray;
begin
  Result := PaPiMeLa.TextInput.Backend.PMLTextInputBackendNames;
end;

// ---- PaPiMeLa.Audio.Backend
function PMLAudioBackendNames: TStringArray;
begin
  Result := PaPiMeLa.Audio.Backend.PMLAudioBackendNames;
end;

