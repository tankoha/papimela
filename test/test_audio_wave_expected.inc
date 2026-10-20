{ test_audio_wave の期待値。参照版の SDL（docs/ORIGIN.md の版。SDL_wave.c は 3.4.2 と同じ）に
  同じバイト列を SDL_LoadWAV_IO で読ませて取った（docs/TEST-LOG.md の使い捨て検証）。
  SDL の値を使わない行は注に D 番号と、papimela の期待値の出所を書いた。 }
const
  WaveExpected: array[0..123] of TWaveExpect = (
    (InHash: $12832299; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 101; Hash: $312FF0C2; EndPos: 146),
    (InHash: $B7F5CAA2; Ok: True; Format: $8010; Channels: 2; Freq: 44100; Len: 400; Hash: $DD1C9941; EndPos: 444),
    (InHash: $85AA7237; Ok: True; Format: $8020; Channels: 2; Freq: 48000; Len: 480; Hash: $75F5756F; EndPos: 404),
    (InHash: $1F2A5545; Ok: True; Format: $8020; Channels: 1; Freq: 96000; Len: 256; Hash: $849F7AB9; EndPos: 300),
    (InHash: $51CD02C7; Ok: True; Format: $8120; Channels: 2; Freq: 22050; Len: 320; Hash: $D3918F66; EndPos: 364),
    (InHash: $CA478CF0; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // 64-bit IEEE floating-point format not supported
    (InHash: $3A343D5D; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // 12-bit PCM format not supported
    (InHash: $47BADA9A; Ok: True; Format: $8010; Channels: 2; Freq: 44100; Len: 400; Hash: $DC282BD7; EndPos: 446),
    (InHash: $47BADA9A; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Truncated data chunk in WAVE file
    (InHash: $47BADA9A; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Truncated data chunk in WAVE file
    (InHash: $652A61A7; Ok: True; Format: $8010; Channels: 2; Freq: 44100; Len: 996; Hash: $C67F445D; EndPos: 1042),
    (InHash: $652A61A7; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Truncated data chunk in WAVE file
    (InHash: $652A61A7; Ok: True; Format: $8010; Channels: 2; Freq: 44100; Len: 996; Hash: $C67F445D; EndPos: 1042),
    (InHash: $ABB10D31; Ok: True; Format: $8010; Channels: 2; Freq: 32000; Len: 200; Hash: $9ABC488A; EndPos: 268),
    (InHash: $296064D9; Ok: True; Format: $8120; Channels: 1; Freq: 32000; Len: 200; Hash: $C24ABC37; EndPos: 268),
    (InHash: $98DD2189; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Unknown WAVE format GUID: 00000055-0000-0010-800000aa00389b71
    (InHash: $7CE97D83; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Extensible WAVE header too small
    (InHash: $85BED393; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 51; Hash: $A8047BC8; EndPos: 96),
    (InHash: $78FE4728; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid number of channels
    (InHash: $49B8D181; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid sample rate
    (InHash: $D37BF4D9; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Sample rate exceeds limit of 2147483647
    (InHash: $5A6DF9B2; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing wBitsPerSample field in WAVE fmt chunk
    (InHash: $52731411; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing wBitsPerSample field in WAVE fmt chunk
    (InHash: $6BF46AD5; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid WAVE fmt chunk length (too small)
    (InHash: $AF8482BB; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // MPEG formats not supported
    (InHash: $90F6AD9F; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Unknown WAVE format tag: 0x1234
    (InHash: $AC6765CD; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid bits per sample
    (InHash: $4ABC8B78; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // fmt chunk after data chunk in WAVE file
    (InHash: $280A7452; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing fmt chunk in WAVE file
    (InHash: $A20798D9; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing data chunk in WAVE file
    (InHash: $68695314; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 33; Hash: $98BE758A; EndPos: 124),
    (InHash: $9E1FB811; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 30; Hash: $72DCBC91; EndPos: 146),
    (InHash: $B01FBCFE; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 20; Hash: $349ECE8F; EndPos: 56),
    (InHash: $2B7A7E64; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Could not find RIFF or WAVE identifiers (not a Waveform file)
    (InHash: $38D047A3; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // RIFF form type is not WAVE (not a Waveform file)
    (InHash: $50E26264; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 21; Hash: $F0C11142; EndPos: 79),
    (InHash: $B6E2D83A; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 24; Hash: $D6656C37; EndPos: 68),
    (InHash: $CAA013B0; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing data chunk in WAVE file
    (InHash: $CAA013B0; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing data chunk in WAVE file
    (InHash: $CAA013B0; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing data chunk in WAVE file
    (InHash: $CAA013B0; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 48; Hash: $DD724267; EndPos: 164),
    (InHash: $CAA013B0; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 48; Hash: $DD724267; EndPos: 164),
    (InHash: $06304348; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 48; Hash: $DD724267; EndPos: 164),
    (InHash: $06304348; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing fmt chunk in WAVE file
    (InHash: $06304348; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 48; Hash: $DD724267; EndPos: 164),
    (InHash: $ED2906D2; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // RIFF size truncates chunk
    (InHash: $B4606BEC; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Chunk count in WAVE file exceeds limit of 2
    (InHash: $D7809F31; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 8; Hash: $2E7F086F; EndPos: 64),
    (InHash: $3743CF42; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 8; Hash: $7A715023; EndPos: 64),
    (InHash: $9815A2AE; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Chunk count in WAVE file exceeds limit of 2
    (InHash: $0CD07712; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 512; Hash: $12FB6645; EndPos: 300),
    (InHash: $CB83C45F; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 512; Hash: $715D95A8; EndPos: 300),
    (InHash: $1D142989; Ok: True; Format: $8010; Channels: 2; Freq: 8000; Len: 200; Hash: $99AA6716; EndPos: 146),
    (InHash: $9D452C15; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid companded bits per sample of 16
    (InHash: $E06FD147; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Unsupported block alignment
    (InHash: $9807DC19; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 62; Hash: $5FABF713; EndPos: 100),
    (InHash: $BA0678F7; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 200; Hash: $40A3AAB3; EndPos: 156),
    (InHash: $BA0678F7; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 120; Hash: $1BE950CB; EndPos: 156),
    (InHash: $BA0678F7; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 120; Hash: $1BE950CB; EndPos: 156),
    (InHash: $126563AD; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 200; Hash: $40A3AAB3; EndPos: 156),
    (InHash: $126563AD; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid number of sample frames in WAVE fact chunk (too many)
    (InHash: $C8DEDABB; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 200; Hash: $40A3AAB3; EndPos: 156),
    (InHash: $C8DEDABB; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 0; Hash: $811C9DC5; EndPos: 156),
    (InHash: $BA0678F7; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 200; Hash: $40A3AAB3; EndPos: 156),
    (InHash: $22C42FF1; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing fact chunk in WAVE file
    (InHash: $D901E51F; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid fact chunk in WAVE file
    (InHash: $FE23E5F3; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 80; Hash: $135EB2A5; EndPos: 156),
    (InHash: $FE23E5F3; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 200; Hash: $40A3AAB3; EndPos: 156),
    (InHash: $BEF4DCEF; Ok: True; Format: $8010; Channels: 1; Freq: 8000; Len: 20; Hash: $631DB1C8; EndPos: 156),
    (InHash: $B7438744; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 696; Hash: $7D1A288E; EndPos: 270),
    (InHash: $639CD33F; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 928; Hash: $8964A05F; EndPos: 334),
    (InHash: $2A7A56DB; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 928; Hash: $C49C1E48; EndPos: 376),
    (InHash: $2A7A56DB; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 1044; Hash: $31612EF9; EndPos: 376),
    (InHash: $2A7A56DB; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 928; Hash: $C49C1E48; EndPos: 376),
    (InHash: $2A7A56DB; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Truncated MS ADPCM block
    (InHash: $758A3676; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 928; Hash: $A2845494; EndPos: 344),
    (InHash: $4EFAD6D6; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 464; Hash: $8E98857B; EndPos: 206),
    (InHash: $0FD3364F; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 400; Hash: $B2162EA2; EndPos: 206),
    (InHash: $08FE8E3E; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid number of samples per MS ADPCM block (wSamplesPerBlock)
    (InHash: $8095C32B; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid number of samples per MS ADPCM block (wSamplesPerBlock)
    (InHash: $D028AD5B; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 928; Hash: $2F061704; EndPos: 342),
    (InHash: $F6E11F35; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Wrong preset coefficients in MS ADPCM format header
    (InHash: $772A5129; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Missing required coefficients in MS ADPCM format header
    (InHash: $0903E7A0; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid number of channels
    (InHash: $AFCB881F; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid MS ADPCM bits per sample of 3
    (InHash: $329C0C1B; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid MS ADPCM block size (nBlockAlign)
    (InHash: $F85F6F57; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // MS ADPCM with the extensible header is not supported
    (InHash: $DD69174C; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid MS ADPCM format header (too small)
    (InHash: $25A1ED49; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Could not read custom coefficients in MS ADPCM format header
    (InHash: $BD8B2BDE; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid MS ADPCM coefficient index in block header
    (InHash: $BA85B3EE; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // D-73: SDL は係数の表の外（初期化していない置き場）を読んで通す。papimela は断る
    (InHash: $ABC08485; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 466; Hash: $159B5929; EndPos: 282),  // D-74: SDL は出力の置き場の外へ書く（ASan）。範囲の中の値は全部の復号と同じ
    (InHash: $DCE82F8A; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 468; Hash: $313286BD; EndPos: 282),
    (InHash: $DD40C87D; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 2; Hash: $FF18F4DF; EndPos: 282),  // D-74: SDL は出力の置き場の外へ書く（ASan）。範囲の中の値は全部の復号と同じ
    (InHash: $BE0CE019; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 468; Hash: $74DDAE4C; EndPos: 346),  // D-74: SDL は出力の置き場の外へ書く（ASan）。範囲の中の値は全部の復号と同じ
    (InHash: $754E1F6E; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 300; Hash: $5225EF78; EndPos: 282),
    (InHash: $D8FBD5C4; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 968; Hash: $B50D6883; EndPos: 304),
    (InHash: $32762446; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 1452; Hash: $05188BAD; EndPos: 432),
    (InHash: $FCA64B4A; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 968; Hash: $ECBACEF7; EndPos: 334),
    (InHash: $FCA64B4A; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 1052; Hash: $90CB5889; EndPos: 334),  // D-75・D-76: SDL は 996 バイト。最後のブロックを埋めて SDL で全部復号し、263 フレームで切った値
    (InHash: $FCA64B4A; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Truncated IMA ADPCM block
    (InHash: $8B8DCD71; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 1036; Hash: $1C8E30FD; EndPos: 332),
    (InHash: $DE4C7CE5; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 968; Hash: $4C6994F2; EndPos: 312),  // D-78: SDL は 972 バイト（最後の 1 フレームは初期化していない置き場）。dropblock で SDL が返す値
    (InHash: $55941EE8; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 968; Hash: $C7EFC7C2; EndPos: 308),
    (InHash: $B3279225; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 504; Hash: $AD3A8333; EndPos: 316),  // D-76: SDL は 1f9b110f。fact を使わずに SDL で全部復号し、126 フレームで切った値
    (InHash: $7ABA0341; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 488; Hash: $7F7FF9B8; EndPos: 316),
    (InHash: $012EEB1E; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 252; Hash: $D11B2A32; EndPos: 188),
    (InHash: $10566B0F; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 968; Hash: $04A3FF18; EndPos: 324),
    (InHash: $D0BE5E31; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 484; Hash: $DB38699A; EndPos: 176),
    (InHash: $5CFF34B2; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 484; Hash: $C58D1893; EndPos: 172),
    (InHash: $60BA7674; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // 3-bit IMA ADPCM currently not supported
    (InHash: $7FF6BAB4; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid IMA ADPCM bits per sample of 5
    (InHash: $878F9AD8; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid IMA ADPCM block size (nBlockAlign)
    (InHash: $C0B15EEA; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid number of samples per IMA ADPCM block (wSamplesPerBlock)
    (InHash: $C4AF53C0; Ok: True; Format: $8010; Channels: 4; Freq: 22050; Len: 1936; Hash: $6959E7AD; EndPos: 560),
    (InHash: $12D15212; Ok: False; Format: $0; Channels: 0; Freq: 0; Len: 0; Hash: $0; EndPos: 0),  // Invalid IMA ADPCM block size (nBlockAlign)
    (InHash: $35FEDD1C; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 20; Hash: $349ECE8F; EndPos: 65),  // D-77: SDL は Missing fmt chunk（位置 4 から探す）。32 と同じ値で、位置だけ 9 進む
    (InHash: $CE590902; Ok: True; Format: $8020; Channels: 2; Freq: 48000; Len: 80; Hash: $66D57F64; EndPos: 104),  // D-79: SDL は data の後ろ（初期化していない置き場）まで読む。119（同じ中身の正しい nBlockAlign）を SDL で読んだ値
    (InHash: $0E1440B1; Ok: True; Format: $8020; Channels: 2; Freq: 48000; Len: 80; Hash: $66D57F64; EndPos: 104),  // D-79: SDL は data の後ろ（初期化していない置き場）まで読む。119（同じ中身の正しい nBlockAlign）を SDL で読んだ値
    (InHash: $B17D1784; Ok: True; Format: $8020; Channels: 2; Freq: 48000; Len: 80; Hash: $66D57F64; EndPos: 104),
    (InHash: $F99CFEFC; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 1008; Hash: $33C1CF4E; EndPos: 340),  // D-75: SDL は 1000 バイト。最後のブロックを埋めて SDL で全部復号し、252 フレームで切った値。数え直しを fact で抑える歯
    (InHash: $AD05D6C2; Ok: True; Format: $0008; Channels: 1; Freq: 8000; Len: 30; Hash: $A83D0E06; EndPos: 74),
    (InHash: $8BA1FC75; Ok: True; Format: $8010; Channels: 1; Freq: 22050; Len: 232; Hash: $785F3B8E; EndPos: 142),
    (InHash: $4E70046B; Ok: True; Format: $8010; Channels: 2; Freq: 22050; Len: 976; Hash: $E0E57247; EndPos: 332)  // D-80: SDL は置き場の外へ書き（ASan）、996 バイトを返す。最後のブロックを埋めて SDL で全部復号し、244 フレームで切った値
  );
