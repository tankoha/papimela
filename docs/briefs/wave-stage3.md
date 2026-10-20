<!--
  WAV の 3 段目（MS-ADPCM / IMA-ADPCM、#54）の依頼文。qwen（手元の ollama / Bedrock の Qwen3-Coder）に
  1 回の補完で書かせるためのもの。2026-10-20 に Haiku に任せた 3 段目の再演（Haiku に渡した依頼文は
  残っていなかったので、最終版の PORT-NOTE と docs/DEFECTS.md の D-73〜D-80 から同じ粒度で作り直した）。

  組み立て方（このファイルは指示と仕様だけ。プロンプトの全体は組み立てて作る）:
    docs/briefs/wave-stage3.sh > <作業用>/prompt.txt
    PAPIMELA_QWEN_BACKEND=bedrock tools/qwen-gen.bb <作業用>/prompt.txt <作業用>/stage3.pas

  組み立てたプロンプトは、この下の「TASK」、docs/CODING-STYLE.md、出発点のユニット（コミット 0a1515f の
  src/PaPiMeLa.Audio.Wave.pas）、移植元の C（reference/SDL/src/audio/SDL_wave.c の該当部分）の順に並ぶ。
  最終版のコードは入れない。
-->
# TASK

You are writing part of papimela, a re-implementation of SDL3 in Free Pascal (FPC 3.2.2, `{$mode objfpc}{$H+}`,
`{$scopedenums on}`, `{$modeswitch advancedrecords}`). Not a binding: the C code below is the *source to port*, and
you write Pascal that behaves the same (with the listed deviations).

The unit `PaPiMeLa.Audio.Wave` (given in full below, section STARTING UNIT) already has stages 1 and 2 implemented.
Stage 3 is 12 empty functions between the line

    { ---- 3 段目: MS-ADPCM と IMA-ADPCM ---- }

and the line

    { ---- 形式ごとへの振り分け（1 段目） ---- }

**Output exactly one thing: the Pascal source that replaces everything from the first of those two lines up to (not
including) the second.** Start your output with the `{ ---- 3 段目: MS-ADPCM と IMA-ADPCM ---- }` line. No
explanation before or after, no Markdown fences. Do not output any other part of the unit.

## Rules

1. Keep the 12 declarations exactly as they are (names, parameter names, modifiers, types, return types). You may add
   small helper routines inside the stage-3 region, before their first use (for example a reader for a signed
   little-endian 16-bit value).
2. Port the C functions in section SDL SOURCE one-to-one, in the same order of checks, with the **same error strings**.
   Where C does `return SDL_SetError("...")`, call `Fail('...')` (it raises; stages 1 and 2 do the same). Where C
   formats with `%u`, use `Fail(Format('...%u...', [value]))`. There is no allocation failure path in Pascal.
3. Types: `Sint64` → `Int64`, `size_t` → `SizeInt`, `Sint32` → `LongInt`, `Uint32` → `LongWord`, `Sint16` →
   `SmallInt`, `Uint16` → `Word`, `Uint8` → `Byte`, `Sint8` → `ShortInt`. Compute sizes and counts that can exceed
   2^31 in `Int64`. Where C compares unsigned values that could go below zero in Pascal (for example
   `blockdatasamples < samplesperblock - 2`), compute both sides in `Int64`.
4. The decoder state is the record `TADPCMState` (C's `ADPCM_DecoderState`). Its `Block`/`BlockLen`/`BlockPos` are
   C's `block.data`/`block.size`/`block.pos`; `Input`/`InputSize`/`InputPos` are `input.*`; `Output` (a dynamic
   array of `SmallInt`) and `OutputPos` are `output.data`/`output.pos`, and `Length(Output)` is `output.size`.
   MS channel state is `AState.MS[0..1]` (`TMSChannelState`), IMA step indices are `AState.IMA[0..Channels-1]`
   (`ShortInt`). The MS coefficient pairs are `AFile.Coeffs` (2 values per pair; the pair count is
   `Length(AFile.Coeffs) div 2`).
5. Style (the full style guide is in section CODING STYLE): comments in Japanese; no `for var` (declare loop
   variables in the `var` section); qualify enum values with their type (`TTruncationHint.Strict`, never bare
   `Strict`); **put every comparison in parentheses** in boolean expressions (in Pascal `and` binds tighter than
   `or`, and `or` binds tighter than comparisons: write `(A < B) or (C > 0)`). `div` and `mod` truncate towards zero
   like C's `/` and `%`. Do not rely on integer overflow wrapping.
6. Every place that deliberately differs from SDL gets a comment `// PORT-NOTE(bug): <what differs and why> (D-xx)`.

## The 12 functions (one line each, plus the deviations)

- `MSCalculateSampleFrames(AFile, ADataLength)`: port `MS_ADPCM_CalculateSampleFrames`. HeaderSize =
  `Channels * 7`, available blocks = `ADataLength div BlockAlign`, trailing = `ADataLength mod BlockAlign`, frame
  bits = `BitsPerSample * Channels`. The final `WaveAdjustToFactValue` is the existing `AdjustToFactValue`
  (it raises by itself, so there is no `< 0` check).
- `MSInit(AFile, ADataLength)`: port `MS_ADPCM_Init`. `AFile.Chunk.Data` is the fmt chunk (`AFile.Chunk.Size` bytes).
  Store the coefficients in `AFile.Coeffs` (`SetLength(AFile.Coeffs, CoeffCount * 2)`), each a signed LE 16-bit value
  at `22 + I * 2`, checking the first 14 against the preset table. Ends by calling `MSCalculateSampleFrames`.
- `MSProcessNibble(AState, ASample1, ASample2, ANybble)`: port `MS_ADPCM_ProcessNibble`. **Deviation**: compute
  `(ASample1 * Coeff1) + (ASample2 * Coeff2)` in `Int64` before `div 256` (the coefficients come from the file, and
  the sum can exceed `LongInt`; in C it overflows). The new delta is `(LongWord(Delta) * ADAPTIVE[ANybble]) div 256`,
  clamped to `[16, 65535]`.
- `MSDecodeBlockHeader(AState, AFile)`: port `MS_ADPCM_DecodeBlockHeader`. Offsets are from `AState.Block` (the block
  start). **Deviation (D-73)**: reject the coefficient index when `(Idx >= (Length(AFile.Coeffs) div 2))`; SDL
  compares with `>` and reads one pair past the table. Same error string.
- `MSDecodeBlockData(AState)`: port `MS_ADPCM_DecodeBlockData` exactly (the nybble is a `Word` with the `$4000`
  marker bit; shifting it left by 4 must stay within 16 bits). Returns False when the input runs out, after setting
  `OutputPos` so that the incomplete frame is dropped.
- `MSDecode(AFile)`: port `MS_ADPCM_Decode`; the result is the decoded samples as bytes (S16, as they lie in memory),
  `nil` when there are no frames. Output byte count = `FramesTotal * Channels * 2`, fail with `'WAVE file too big'`
  when it exceeds `$FFFFFFFF`. **Deviation (D-74)**: allocate `Output` with **2 extra frames**
  (`(FramesTotal + 2) * Channels` samples). The block header always writes 2 frames, so when the fact chunk cuts
  the frame count to less than that, SDL writes past its buffer. The returned byte count is still based on
  `FramesTotal` (or on the truncation, as in SDL). Copy into the result with `Move`.
- `IMACalculateSampleFrames(AFile, ADataLength)`: port `IMA_ADPCM_CalculateSampleFrames`. HeaderSize and sub-block
  frame size are both `Channels * 4`. **Deviation (D-78)**: count the trailing partial block only when
  `(Trailing >= HeaderSize)`; SDL uses `trailingdata > blockheadersize - 2` and counts one frame for a block whose
  header is incomplete, but the decoder never decodes such a block (it needs `BytesLeft >= BlockHeaderSize`), so SDL
  returns a frame it never writes.
- `IMAInit(AFile, ADataLength)`: port `IMA_ADPCM_Init`. For the extensible header, `SamplesPerBlock` was already set
  by stage 1 (do nothing); otherwise read it from fmt bytes 18..19 when `(AFile.Chunk.Size >= 20) and
  (AFile.Format.ExtSize >= 2)`. Ends by calling `IMACalculateSampleFrames`.
- `IMAProcessNibble(AIndex, ALastSample, ANybble)`: port `IMA_ADPCM_ProcessNibble` (clamp the index to `0..88` before
  using it, store `index + INDEX_TABLE[ANybble]` back into `AIndex`, build the delta with shifts exactly as C does).
- `IMADecodeBlockHeader(AState)`: port `IMA_ADPCM_DecodeBlockHeader`. Offsets are `BlockPos + Chan * 4`. The step
  index byte is signed 8-bit; the reserved 4th byte is not checked.
- `IMADecodeBlockData(AState)`: port `IMA_ADPCM_DecodeBlockData`, with three **deviations**:
  - (D-75) when the data is truncated, the number of frames that can still be decoded is
    `((BlockLeft div SubFrame) * 8)` plus `((Remain mod 4) * 2)` when `(Remain > (SubFrame - 4))`. SDL forgets the
    `* 8` and counts sub-blocks as frames.
  - (D-80) never decode more frames than were requested: if that count is larger than the frames left for this
    block, keep the smaller one. SDL has no such cap and writes past its buffer when the fact chunk leaves few frames.
  - (D-76) each channel reads **its own 4 bytes** of the sub-block: channel `Chan` starts at `BlockPos + Chan * 4`,
    and after each sub-block `BlockPos` advances by `SubFrame`. SDL reads the bytes continuously, so in a partial
    sub-block (fewer than 8 frames) the second and later channels read bytes that belong to the previous channel.
  Returns False when it was truncated (after decoding what it could).
- `IMADecode(AFile)`: port `IMA_ADPCM_Decode` like `MSDecode` above (no extra frames needed here; allocate
  `FramesTotal * Channels` samples, `SetLength(St.IMA, Channels)`).

## Known traps from earlier ports in this project

- Pascal identifiers are case-insensitive: `ms` and `MS` are the same name. `AState.MS` is a field; don't name a
  local `Ms`.
- `Nybble shl 4` on a `Word` is computed in a wider type; take `Word(...)` of the result.
- `SetLength` zero-fills, so you don't need `FillChar`.
