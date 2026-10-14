{ src/generated/audio_channel_converters.inc — tools/genchannelconv.bb が
  reference/SDL/src/audio/SDL_audio_channel_converters.h から生成する。手で直さない。
  56 個のチャンネル数の変換と、その表 ChannelConverters[元][先]（1..8。同じ数は nil）。 }

procedure ConvMonoToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 2);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 2);
  end;
end;

procedure ConvMonoTo21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 3);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[2] := Single(0.0);
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 3);
  end;
end;

procedure ConvMonoToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 4);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 4);
  end;
end;

procedure ConvMonoTo41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 5);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 5);
  end;
end;

procedure ConvMonoTo51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 6);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 6);
  end;
end;

procedure ConvMonoTo61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 7);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[6] := Single(0.0);
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 7);
  end;
end;

procedure ConvMonoTo71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 1);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[0];
    ADst[7] := Single(0.0);
    ADst[6] := Single(0.0);
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := SrcFC;
    ADst[0] := SrcFC;
    Dec(ASrc, 1);
    Dec(ADst, 8);
  end;
end;

procedure ConvStereoToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.500000000)) + (ASrc[1] * Single(0.500000000));
    Inc(ASrc, 2);
    Inc(ADst, 1);
  end;
end;

procedure ConvStereoTo21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 2);
  Inc(ADst, (ANumFrames - 1) * 3);
  for I := ANumFrames downto 1 do
  begin
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 2);
    Dec(ADst, 3);
  end;
end;

procedure ConvStereoToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 2);
  Inc(ADst, (ANumFrames - 1) * 4);
  for I := ANumFrames downto 1 do
  begin
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 2);
    Dec(ADst, 4);
  end;
end;

procedure ConvStereoTo41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 2);
  Inc(ADst, (ANumFrames - 1) * 5);
  for I := ANumFrames downto 1 do
  begin
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 2);
    Dec(ADst, 5);
  end;
end;

procedure ConvStereoTo51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 2);
  Inc(ADst, (ANumFrames - 1) * 6);
  for I := ANumFrames downto 1 do
  begin
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 2);
    Dec(ADst, 6);
  end;
end;

procedure ConvStereoTo61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 2);
  Inc(ADst, (ANumFrames - 1) * 7);
  for I := ANumFrames downto 1 do
  begin
    ADst[6] := Single(0.0);
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 2);
    Dec(ADst, 7);
  end;
end;

procedure ConvStereoTo71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 2);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    ADst[7] := Single(0.0);
    ADst[6] := Single(0.0);
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 2);
    Dec(ADst, 8);
  end;
end;

procedure Conv21ToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.333333343)) + (ASrc[1] * Single(0.333333343)) + (ASrc[2] * Single(0.333333343));
    Inc(ASrc, 3);
    Inc(ADst, 1);
  end;
end;

procedure Conv21ToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcLFE: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcLFE := ASrc[2];
    ADst[0] := (ASrc[0] * Single(0.800000012)) + (SrcLFE * Single(0.200000003));
    ADst[1] := (ASrc[1] * Single(0.800000012)) + (SrcLFE * Single(0.200000003));
    Inc(ASrc, 3);
    Inc(ADst, 2);
  end;
end;

procedure Conv21ToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcLFE: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 3);
  Inc(ADst, (ANumFrames - 1) * 4);
  for I := ANumFrames downto 1 do
  begin
    SrcLFE := ASrc[2];
    ADst[3] := (SrcLFE * Single(0.111111112));
    ADst[2] := (SrcLFE * Single(0.111111112));
    ADst[1] := (SrcLFE * Single(0.111111112)) + (ASrc[1] * Single(0.888888896));
    ADst[0] := (SrcLFE * Single(0.111111112)) + (ASrc[0] * Single(0.888888896));
    Dec(ASrc, 3);
    Dec(ADst, 4);
  end;
end;

procedure Conv21To41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 3);
  Inc(ADst, (ANumFrames - 1) * 5);
  for I := ANumFrames downto 1 do
  begin
    ADst[4] := Single(0.0);
    ADst[3] := Single(0.0);
    ADst[2] := ASrc[2];
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 3);
    Dec(ADst, 5);
  end;
end;

procedure Conv21To51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 3);
  Inc(ADst, (ANumFrames - 1) * 6);
  for I := ANumFrames downto 1 do
  begin
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 3);
    Dec(ADst, 6);
  end;
end;

procedure Conv21To61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 3);
  Inc(ADst, (ANumFrames - 1) * 7);
  for I := ANumFrames downto 1 do
  begin
    ADst[6] := Single(0.0);
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 3);
    Dec(ADst, 7);
  end;
end;

procedure Conv21To71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 3);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    ADst[7] := Single(0.0);
    ADst[6] := Single(0.0);
    ADst[5] := Single(0.0);
    ADst[4] := Single(0.0);
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 3);
    Dec(ADst, 8);
  end;
end;

procedure ConvQuadToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.250000000)) + (ASrc[1] * Single(0.250000000)) + (ASrc[2] * Single(0.250000000)) + (ASrc[3] * Single(0.250000000));
    Inc(ASrc, 4);
    Inc(ADst, 1);
  end;
end;

procedure ConvQuadToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[2];
    SrcBR := ASrc[3];
    ADst[0] := (ASrc[0] * Single(0.421000004)) + (SrcBL * Single(0.358999997)) + (SrcBR * Single(0.219999999));
    ADst[1] := (ASrc[1] * Single(0.421000004)) + (SrcBL * Single(0.219999999)) + (SrcBR * Single(0.358999997));
    Inc(ASrc, 4);
    Inc(ADst, 2);
  end;
end;

procedure ConvQuadTo21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[2];
    SrcBR := ASrc[3];
    ADst[0] := (ASrc[0] * Single(0.421000004)) + (SrcBL * Single(0.358999997)) + (SrcBR * Single(0.219999999));
    ADst[1] := (ASrc[1] * Single(0.421000004)) + (SrcBL * Single(0.219999999)) + (SrcBR * Single(0.358999997));
    ADst[2] := Single(0.0);
    Inc(ASrc, 4);
    Inc(ADst, 3);
  end;
end;

procedure ConvQuadTo41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 4);
  Inc(ADst, (ANumFrames - 1) * 5);
  for I := ANumFrames downto 1 do
  begin
    ADst[4] := ASrc[3];
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 4);
    Dec(ADst, 5);
  end;
end;

procedure ConvQuadTo51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 4);
  Inc(ADst, (ANumFrames - 1) * 6);
  for I := ANumFrames downto 1 do
  begin
    ADst[5] := ASrc[3];
    ADst[4] := ASrc[2];
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 4);
    Dec(ADst, 6);
  end;
end;

procedure ConvQuadTo61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 4);
  Inc(ADst, (ANumFrames - 1) * 7);
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[2];
    SrcBR := ASrc[3];
    ADst[6] := (SrcBR * Single(0.796000004));
    ADst[5] := (SrcBL * Single(0.796000004));
    ADst[4] := (SrcBR * Single(0.500000000)) + (SrcBL * Single(0.500000000));
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := (ASrc[1] * Single(0.939999998));
    ADst[0] := (ASrc[0] * Single(0.939999998));
    Dec(ASrc, 4);
    Dec(ADst, 7);
  end;
end;

procedure ConvQuadTo71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 4);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    ADst[7] := Single(0.0);
    ADst[6] := Single(0.0);
    ADst[5] := ASrc[3];
    ADst[4] := ASrc[2];
    ADst[3] := Single(0.0);
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 4);
    Dec(ADst, 8);
  end;
end;

procedure Conv41ToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.200000003)) + (ASrc[1] * Single(0.200000003)) + (ASrc[2] * Single(0.200000003)) + (ASrc[3] * Single(0.200000003)) + (ASrc[4] * Single(0.200000003));
    Inc(ASrc, 5);
    Inc(ADst, 1);
  end;
end;

procedure Conv41ToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcLFE, SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcLFE := ASrc[2];
    SrcBL := ASrc[3];
    SrcBR := ASrc[4];
    ADst[0] := (ASrc[0] * Single(0.374222219)) + (SrcLFE * Single(0.111111112)) + (SrcBL * Single(0.319111109)) + (SrcBR * Single(0.195555553));
    ADst[1] := (ASrc[1] * Single(0.374222219)) + (SrcLFE * Single(0.111111112)) + (SrcBL * Single(0.195555553)) + (SrcBR * Single(0.319111109));
    Inc(ASrc, 5);
    Inc(ADst, 2);
  end;
end;

procedure Conv41To21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[3];
    SrcBR := ASrc[4];
    ADst[0] := (ASrc[0] * Single(0.421000004)) + (SrcBL * Single(0.358999997)) + (SrcBR * Single(0.219999999));
    ADst[1] := (ASrc[1] * Single(0.421000004)) + (SrcBL * Single(0.219999999)) + (SrcBR * Single(0.358999997));
    ADst[2] := ASrc[2];
    Inc(ASrc, 5);
    Inc(ADst, 3);
  end;
end;

procedure Conv41ToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcLFE: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcLFE := ASrc[2];
    ADst[0] := (ASrc[0] * Single(0.941176474)) + (SrcLFE * Single(0.058823530));
    ADst[1] := (ASrc[1] * Single(0.941176474)) + (SrcLFE * Single(0.058823530));
    ADst[2] := (SrcLFE * Single(0.058823530)) + (ASrc[3] * Single(0.941176474));
    ADst[3] := (SrcLFE * Single(0.058823530)) + (ASrc[4] * Single(0.941176474));
    Inc(ASrc, 5);
    Inc(ADst, 4);
  end;
end;

procedure Conv41To51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 5);
  Inc(ADst, (ANumFrames - 1) * 6);
  for I := ANumFrames downto 1 do
  begin
    ADst[5] := ASrc[4];
    ADst[4] := ASrc[3];
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 5);
    Dec(ADst, 6);
  end;
end;

procedure Conv41To61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 5);
  Inc(ADst, (ANumFrames - 1) * 7);
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[3];
    SrcBR := ASrc[4];
    ADst[6] := (SrcBR * Single(0.796000004));
    ADst[5] := (SrcBL * Single(0.796000004));
    ADst[4] := (SrcBR * Single(0.500000000)) + (SrcBL * Single(0.500000000));
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := (ASrc[1] * Single(0.939999998));
    ADst[0] := (ASrc[0] * Single(0.939999998));
    Dec(ASrc, 5);
    Dec(ADst, 7);
  end;
end;

procedure Conv41To71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 5);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    ADst[7] := Single(0.0);
    ADst[6] := Single(0.0);
    ADst[5] := ASrc[4];
    ADst[4] := ASrc[3];
    ADst[3] := ASrc[2];
    ADst[2] := Single(0.0);
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 5);
    Dec(ADst, 8);
  end;
end;

procedure Conv51ToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.166666672)) + (ASrc[1] * Single(0.166666672)) + (ASrc[2] * Single(0.166666672)) + (ASrc[3] * Single(0.166666672)) + (ASrc[4] * Single(0.166666672)) + (ASrc[5] * Single(0.166666672));
    Inc(ASrc, 6);
    Inc(ADst, 1);
  end;
end;

procedure Conv51ToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcLFE, SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcLFE := ASrc[3];
    SrcBL := ASrc[4];
    SrcBR := ASrc[5];
    ADst[0] := (ASrc[0] * Single(0.294545442)) + (SrcFC * Single(0.208181813)) + (SrcLFE * Single(0.090909094)) + (SrcBL * Single(0.251818180)) + (SrcBR * Single(0.154545456));
    ADst[1] := (ASrc[1] * Single(0.294545442)) + (SrcFC * Single(0.208181813)) + (SrcLFE * Single(0.090909094)) + (SrcBL * Single(0.154545456)) + (SrcBR * Single(0.251818180));
    Inc(ASrc, 6);
    Inc(ADst, 2);
  end;
end;

procedure Conv51To21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcBL := ASrc[4];
    SrcBR := ASrc[5];
    ADst[0] := (ASrc[0] * Single(0.324000001)) + (SrcFC * Single(0.229000002)) + (SrcBL * Single(0.277000010)) + (SrcBR * Single(0.170000002));
    ADst[1] := (ASrc[1] * Single(0.324000001)) + (SrcFC * Single(0.229000002)) + (SrcBL * Single(0.170000002)) + (SrcBR * Single(0.277000010));
    ADst[2] := ASrc[3];
    Inc(ASrc, 6);
    Inc(ADst, 3);
  end;
end;

procedure Conv51ToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcLFE: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcLFE := ASrc[3];
    ADst[0] := (ASrc[0] * Single(0.558095276)) + (SrcFC * Single(0.394285709)) + (SrcLFE * Single(0.047619049));
    ADst[1] := (ASrc[1] * Single(0.558095276)) + (SrcFC * Single(0.394285709)) + (SrcLFE * Single(0.047619049));
    ADst[2] := (SrcLFE * Single(0.047619049)) + (ASrc[4] * Single(0.558095276));
    ADst[3] := (SrcLFE * Single(0.047619049)) + (ASrc[5] * Single(0.558095276));
    Inc(ASrc, 6);
    Inc(ADst, 4);
  end;
end;

procedure Conv51To41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    ADst[0] := (ASrc[0] * Single(0.586000025)) + (SrcFC * Single(0.414000005));
    ADst[1] := (ASrc[1] * Single(0.586000025)) + (SrcFC * Single(0.414000005));
    ADst[2] := ASrc[3];
    ADst[3] := (ASrc[4] * Single(0.586000025));
    ADst[4] := (ASrc[5] * Single(0.586000025));
    Inc(ASrc, 6);
    Inc(ADst, 5);
  end;
end;

procedure Conv51To61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 6);
  Inc(ADst, (ANumFrames - 1) * 7);
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[4];
    SrcBR := ASrc[5];
    ADst[6] := (SrcBR * Single(0.796000004));
    ADst[5] := (SrcBL * Single(0.796000004));
    ADst[4] := (SrcBR * Single(0.500000000)) + (SrcBL * Single(0.500000000));
    ADst[3] := ASrc[3];
    ADst[2] := (ASrc[2] * Single(0.939999998));
    ADst[1] := (ASrc[1] * Single(0.939999998));
    ADst[0] := (ASrc[0] * Single(0.939999998));
    Dec(ASrc, 6);
    Dec(ADst, 7);
  end;
end;

procedure Conv51To71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 6);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    ADst[7] := Single(0.0);
    ADst[6] := Single(0.0);
    ADst[5] := ASrc[5];
    ADst[4] := ASrc[4];
    ADst[3] := ASrc[3];
    ADst[2] := ASrc[2];
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 6);
    Dec(ADst, 8);
  end;
end;

procedure Conv61ToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.143142849)) + (ASrc[1] * Single(0.143142849)) + (ASrc[2] * Single(0.143142849)) + (ASrc[3] * Single(0.142857149)) + (ASrc[4] * Single(0.143142849)) + (ASrc[5] * Single(0.143142849)) + (ASrc[6] * Single(0.143142849));
    Inc(ASrc, 7);
    Inc(ADst, 1);
  end;
end;

procedure Conv61ToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcLFE, SrcBC, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcLFE := ASrc[3];
    SrcBC := ASrc[4];
    SrcSL := ASrc[5];
    SrcSR := ASrc[6];
    ADst[0] := (ASrc[0] * Single(0.247384623)) + (SrcFC * Single(0.174461529)) + (SrcLFE * Single(0.076923080)) + (SrcBC * Single(0.174461529)) + (SrcSL * Single(0.226153851)) + (SrcSR * Single(0.100615382));
    ADst[1] := (ASrc[1] * Single(0.247384623)) + (SrcFC * Single(0.174461529)) + (SrcLFE * Single(0.076923080)) + (SrcBC * Single(0.174461529)) + (SrcSL * Single(0.100615382)) + (SrcSR * Single(0.226153851));
    Inc(ASrc, 7);
    Inc(ADst, 2);
  end;
end;

procedure Conv61To21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcBC, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcBC := ASrc[4];
    SrcSL := ASrc[5];
    SrcSR := ASrc[6];
    ADst[0] := (ASrc[0] * Single(0.268000007)) + (SrcFC * Single(0.188999996)) + (SrcBC * Single(0.188999996)) + (SrcSL * Single(0.245000005)) + (SrcSR * Single(0.108999997));
    ADst[1] := (ASrc[1] * Single(0.268000007)) + (SrcFC * Single(0.188999996)) + (SrcBC * Single(0.188999996)) + (SrcSL * Single(0.108999997)) + (SrcSR * Single(0.245000005));
    ADst[2] := ASrc[3];
    Inc(ASrc, 7);
    Inc(ADst, 3);
  end;
end;

procedure Conv61ToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcLFE, SrcBC, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcLFE := ASrc[3];
    SrcBC := ASrc[4];
    SrcSL := ASrc[5];
    SrcSR := ASrc[6];
    ADst[0] := (ASrc[0] * Single(0.463679999)) + (SrcFC * Single(0.327360004)) + (SrcLFE * Single(0.040000003)) + (SrcSL * Single(0.168960005));
    ADst[1] := (ASrc[1] * Single(0.463679999)) + (SrcFC * Single(0.327360004)) + (SrcLFE * Single(0.040000003)) + (SrcSR * Single(0.168960005));
    ADst[2] := (SrcLFE * Single(0.040000003)) + (SrcBC * Single(0.327360004)) + (SrcSL * Single(0.431039989));
    ADst[3] := (SrcLFE * Single(0.040000003)) + (SrcBC * Single(0.327360004)) + (SrcSR * Single(0.431039989));
    Inc(ASrc, 7);
    Inc(ADst, 4);
  end;
end;

procedure Conv61To41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcBC, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcBC := ASrc[4];
    SrcSL := ASrc[5];
    SrcSR := ASrc[6];
    ADst[0] := (ASrc[0] * Single(0.483000010)) + (SrcFC * Single(0.340999991)) + (SrcSL * Single(0.175999999));
    ADst[1] := (ASrc[1] * Single(0.483000010)) + (SrcFC * Single(0.340999991)) + (SrcSR * Single(0.175999999));
    ADst[2] := ASrc[3];
    ADst[3] := (SrcBC * Single(0.340999991)) + (SrcSL * Single(0.449000001));
    ADst[4] := (SrcBC * Single(0.340999991)) + (SrcSR * Single(0.449000001));
    Inc(ASrc, 7);
    Inc(ADst, 5);
  end;
end;

procedure Conv61To51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBC, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcBC := ASrc[4];
    SrcSL := ASrc[5];
    SrcSR := ASrc[6];
    ADst[0] := (ASrc[0] * Single(0.611000001)) + (SrcSL * Single(0.223000005));
    ADst[1] := (ASrc[1] * Single(0.611000001)) + (SrcSR * Single(0.223000005));
    ADst[2] := (ASrc[2] * Single(0.611000001));
    ADst[3] := ASrc[3];
    ADst[4] := (SrcBC * Single(0.432000011)) + (SrcSL * Single(0.568000019));
    ADst[5] := (SrcBC * Single(0.432000011)) + (SrcSR * Single(0.568000019));
    Inc(ASrc, 7);
    Inc(ADst, 6);
  end;
end;

procedure Conv61To71(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBC: Single;
begin
  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。
  Inc(ASrc, (ANumFrames - 1) * 7);
  Inc(ADst, (ANumFrames - 1) * 8);
  for I := ANumFrames downto 1 do
  begin
    SrcBC := ASrc[4];
    ADst[7] := ASrc[6];
    ADst[6] := ASrc[5];
    ADst[5] := (SrcBC * Single(0.707000017));
    ADst[4] := (SrcBC * Single(0.707000017));
    ADst[3] := ASrc[3];
    ADst[2] := ASrc[2];
    ADst[1] := ASrc[1];
    ADst[0] := ASrc[0];
    Dec(ASrc, 7);
    Dec(ADst, 8);
  end;
end;

procedure Conv71ToMono(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
begin
  for I := ANumFrames downto 1 do
  begin
    ADst[0] := (ASrc[0] * Single(0.125125006)) + (ASrc[1] * Single(0.125125006)) + (ASrc[2] * Single(0.125125006)) + (ASrc[3] * Single(0.125000000)) + (ASrc[4] * Single(0.125125006)) + (ASrc[5] * Single(0.125125006)) + (ASrc[6] * Single(0.125125006)) + (ASrc[7] * Single(0.125125006));
    Inc(ASrc, 8);
    Inc(ADst, 1);
  end;
end;

procedure Conv71ToStereo(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcLFE, SrcBL, SrcBR, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcLFE := ASrc[3];
    SrcBL := ASrc[4];
    SrcBR := ASrc[5];
    SrcSL := ASrc[6];
    SrcSR := ASrc[7];
    ADst[0] := (ASrc[0] * Single(0.211866662)) + (SrcFC * Single(0.150266662)) + (SrcLFE * Single(0.066666670)) + (SrcBL * Single(0.181066677)) + (SrcBR * Single(0.111066669)) + (SrcSL * Single(0.194133341)) + (SrcSR * Single(0.085866667));
    ADst[1] := (ASrc[1] * Single(0.211866662)) + (SrcFC * Single(0.150266662)) + (SrcLFE * Single(0.066666670)) + (SrcBL * Single(0.111066669)) + (SrcBR * Single(0.181066677)) + (SrcSL * Single(0.085866667)) + (SrcSR * Single(0.194133341));
    Inc(ASrc, 8);
    Inc(ADst, 2);
  end;
end;

procedure Conv71To21(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcBL, SrcBR, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcBL := ASrc[4];
    SrcBR := ASrc[5];
    SrcSL := ASrc[6];
    SrcSR := ASrc[7];
    ADst[0] := (ASrc[0] * Single(0.226999998)) + (SrcFC * Single(0.160999998)) + (SrcBL * Single(0.194000006)) + (SrcBR * Single(0.119000003)) + (SrcSL * Single(0.208000004)) + (SrcSR * Single(0.092000000));
    ADst[1] := (ASrc[1] * Single(0.226999998)) + (SrcFC * Single(0.160999998)) + (SrcBL * Single(0.119000003)) + (SrcBR * Single(0.194000006)) + (SrcSL * Single(0.092000000)) + (SrcSR * Single(0.208000004));
    ADst[2] := ASrc[3];
    Inc(ASrc, 8);
    Inc(ADst, 3);
  end;
end;

procedure Conv71ToQuad(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcLFE, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcLFE := ASrc[3];
    SrcSL := ASrc[6];
    SrcSR := ASrc[7];
    ADst[0] := (ASrc[0] * Single(0.466344833)) + (SrcFC * Single(0.329241365)) + (SrcLFE * Single(0.034482758)) + (SrcSL * Single(0.169931039));
    ADst[1] := (ASrc[1] * Single(0.466344833)) + (SrcFC * Single(0.329241365)) + (SrcLFE * Single(0.034482758)) + (SrcSR * Single(0.169931039));
    ADst[2] := (SrcLFE * Single(0.034482758)) + (ASrc[4] * Single(0.466344833)) + (SrcSL * Single(0.433517247));
    ADst[3] := (SrcLFE * Single(0.034482758)) + (ASrc[5] * Single(0.466344833)) + (SrcSR * Single(0.433517247));
    Inc(ASrc, 8);
    Inc(ADst, 4);
  end;
end;

procedure Conv71To41(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcFC, SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcFC := ASrc[2];
    SrcSL := ASrc[6];
    SrcSR := ASrc[7];
    ADst[0] := (ASrc[0] * Single(0.483000010)) + (SrcFC * Single(0.340999991)) + (SrcSL * Single(0.175999999));
    ADst[1] := (ASrc[1] * Single(0.483000010)) + (SrcFC * Single(0.340999991)) + (SrcSR * Single(0.175999999));
    ADst[2] := ASrc[3];
    ADst[3] := (ASrc[4] * Single(0.483000010)) + (SrcSL * Single(0.449000001));
    ADst[4] := (ASrc[5] * Single(0.483000010)) + (SrcSR * Single(0.449000001));
    Inc(ASrc, 8);
    Inc(ADst, 5);
  end;
end;

procedure Conv71To51(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcSL, SrcSR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcSL := ASrc[6];
    SrcSR := ASrc[7];
    ADst[0] := (ASrc[0] * Single(0.518000007)) + (SrcSL * Single(0.188999996));
    ADst[1] := (ASrc[1] * Single(0.518000007)) + (SrcSR * Single(0.188999996));
    ADst[2] := (ASrc[2] * Single(0.518000007));
    ADst[3] := ASrc[3];
    ADst[4] := (ASrc[4] * Single(0.518000007)) + (SrcSL * Single(0.481999993));
    ADst[5] := (ASrc[5] * Single(0.518000007)) + (SrcSR * Single(0.481999993));
    Inc(ASrc, 8);
    Inc(ADst, 6);
  end;
end;

procedure Conv71To61(ADst, ASrc: PSingle; ANumFrames: Integer);
var
  I: Integer;
  SrcBL, SrcBR: Single;
begin
  for I := ANumFrames downto 1 do
  begin
    SrcBL := ASrc[4];
    SrcBR := ASrc[5];
    ADst[0] := (ASrc[0] * Single(0.541000009));
    ADst[1] := (ASrc[1] * Single(0.541000009));
    ADst[2] := (ASrc[2] * Single(0.541000009));
    ADst[3] := ASrc[3];
    ADst[4] := (SrcBL * Single(0.287999988)) + (SrcBR * Single(0.287999988));
    ADst[5] := (SrcBL * Single(0.458999991)) + (ASrc[6] * Single(0.541000009));
    ADst[6] := (SrcBR * Single(0.458999991)) + (ASrc[7] * Single(0.541000009));
    Inc(ASrc, 8);
    Inc(ADst, 7);
  end;
end;

const
  ChannelConverters: array[1..8, 1..8] of TPMLChannelConverter = (
    (nil, @ConvMonoToStereo, @ConvMonoTo21, @ConvMonoToQuad, @ConvMonoTo41, @ConvMonoTo51, @ConvMonoTo61, @ConvMonoTo71),
    (@ConvStereoToMono, nil, @ConvStereoTo21, @ConvStereoToQuad, @ConvStereoTo41, @ConvStereoTo51, @ConvStereoTo61, @ConvStereoTo71),
    (@Conv21ToMono, @Conv21ToStereo, nil, @Conv21ToQuad, @Conv21To41, @Conv21To51, @Conv21To61, @Conv21To71),
    (@ConvQuadToMono, @ConvQuadToStereo, @ConvQuadTo21, nil, @ConvQuadTo41, @ConvQuadTo51, @ConvQuadTo61, @ConvQuadTo71),
    (@Conv41ToMono, @Conv41ToStereo, @Conv41To21, @Conv41ToQuad, nil, @Conv41To51, @Conv41To61, @Conv41To71),
    (@Conv51ToMono, @Conv51ToStereo, @Conv51To21, @Conv51ToQuad, @Conv51To41, nil, @Conv51To61, @Conv51To71),
    (@Conv61ToMono, @Conv61ToStereo, @Conv61To21, @Conv61ToQuad, @Conv61To41, @Conv61To51, nil, @Conv61To71),
    (@Conv71ToMono, @Conv71ToStereo, @Conv71To21, @Conv71ToQuad, @Conv71To41, @Conv71To51, @Conv71To61, nil));
