// アンブレラ（PaPiMeLa.pas）の implementation 部に入る本体。
// tools/genumbrella.bb が次のユニットの interface 部から生成する。手で直さず、
// 生成器を直して作り直すこと（tools/genumbrella.bb --check が古さを調べる）。
//   PaPiMeLa.Types
//   PaPiMeLa.Errors
//   PaPiMeLa.Core
//   PaPiMeLa.Events
//   PaPiMeLa.Events.Keymap
//   PaPiMeLa.Keycodes
//   PaPiMeLa.Pixels
//   PaPiMeLa.Surface
//   PaPiMeLa.Surface.Blit
//   PaPiMeLa.Surface.BMP
//   PaPiMeLa.IO
//   PaPiMeLa.Video
//   PaPiMeLa.Render
//   PaPiMeLa.TextInput
//   PaPiMeLa.Time
//   PaPiMeLa.App
//   PaPiMeLa.Video.Backend
//   PaPiMeLa.TextInput.Backend

// ---- PaPiMeLa.Events
function PMLNowNS: UInt64;
begin
  Result := PaPiMeLa.Events.PMLNowNS;
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

