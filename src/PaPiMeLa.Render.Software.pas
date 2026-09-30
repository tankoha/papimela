{
  PaPiMeLa.Render.Software — サーフェスへ描くレンダラドライバ

  Origin : ported from SDL (src/render/software/SDL_render_sw.c,
           SDL_drawline.c, SDL_drawpoint.c, SDL_blendfillrect.c)
           Scope: コマンドの実行順、ビューポートとクリップ矩形の重ね方、
           ブレゼンハムの線の端点の扱い、合成つきの矩形塗り、
           ウィンドウの大きさが変わったら描画先を取り直すこと。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.3、§11 #42

  WHAT:
    TPMLRenderDriver の最初の実装。描画先は TPMLSurface で、テクスチャの中身も
    TPMLSurface として持つ。TPMLWindowSoftwareRenderDriver はその派生で、
    ウィンドウのフレームバッファへ描いて Present で画面へ出す。

  WHY:
    GL が無くても描けるレンダラが 1 つ要る。ヘッドレスの検査はここで描いて
    画像を比べる。第 11 章 #43 の GLES2 ドライバを作るときの手本でもある。

  RESOLVED:
    - 矩形・転送・点・線は上書きして速い経路を持つ。三角形は Raster へ回す
    - 描画座標はビューポートの原点からの相対。クリップ矩形もビューポートからの
      相対で、実際に塗る範囲は「ビューポート ∩ クリップ矩形」になる（SDL と同じ）
    - 描画先サーフェスは借りるだけで、所有しない
    - ウィンドウへ描くときの描画先は、ウィンドウのフレームバッファを借りた
      サーフェス。VSync はウィンドウのフレームバッファの VSync に任せる
      （SDL の SW_SetVSync → SDL_SetWindowSurfaceVSync と同じ）

  NOT RESOLVED:
    - 回転転送（RenderTextureRotated）は未実装

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render.Software;

{$I papimela.inc}

interface

uses
  SysUtils, Math,
  PaPiMeLa.Types,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Pixels,
  PaPiMeLa.Surface,
  PaPiMeLa.Surface.Blit,
  PaPiMeLa.Video,
  PaPiMeLa.Render;

type
  TPMLSoftwareRenderDriver = class(TPMLRenderDriver)
  strict private
    FTarget  : TPMLSurface;      // 借りている
    FViewport: TPMLRect;
    FClip    : TPMLRect;
    FClipOn  : Boolean;
    procedure ApplyClip;
    procedure ExecClear(const ACmd: TPMLRenderCommand);
    procedure ExecFillRects(AQueue: TPMLRenderQueue; const ACmd: TPMLRenderCommand);
    procedure ExecPoints(AQueue: TPMLRenderQueue; const ACmd: TPMLRenderCommand);
    procedure ExecLines(AQueue: TPMLRenderQueue; const ACmd: TPMLRenderCommand);
    procedure ExecCopy(AQueue: TPMLRenderQueue; const ACmd: TPMLRenderCommand);
    procedure ExecGeometry(AQueue: TPMLRenderQueue; const ACmd: TPMLRenderCommand);
    procedure PutPixel(AX, AY: Integer; const AColor: TPMLColor; ABlend: TPMLBlendMode);
  protected
    { 描画先を差し替える。ウィンドウの大きさが変わったときに派生クラスが呼ぶ。
      ビューポートは次の実行で SetViewport コマンドが入れ直す。 }
    procedure SetTarget(ATarget: TPMLSurface);
  public
    constructor Create(ATarget: TPMLSurface);

    function  Name: String; override;
    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; override;

    function  CreateTexture(ATexture: TPMLTexture): Boolean; override;
    function  UpdateTexture(ATexture: TPMLTexture; const ARect: TPMLRect;
      APixels: Pointer; APitch: Integer): Boolean; override;
    procedure DestroyTexture(ATexture: TPMLTexture); override;

    procedure QueueGeometry(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const AVertices: array of TPMLVertex); override;
    procedure QueueFillRects(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const ARects: array of TPMLFRect); override;
    procedure QueueCopy(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      ATexture: TPMLTexture; const ASrc, ADst: TPMLFRect); override;
    procedure QueueDrawPoints(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); override;
    procedure QueueDrawLines(AQueue: TPMLRenderQueue; var ACmd: TPMLRenderCommand;
      const APoints: array of TPMLFPoint); override;

    procedure RunCommandQueue(AQueue: TPMLRenderQueue); override;
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface; override;
    procedure Present; override;

    property Target: TPMLSurface read FTarget;
  end;

  { ウィンドウのフレームバッファへ描くソフトウェアドライバ。

    PORT-NOTE: SDL_render_sw.c の SW_ActivateRenderer / SW_WindowEvent /
    SW_RenderPresent にあたる。SDL は PIXEL_SIZE_CHANGED のイベントで描画先を
    捨て、次の描画でウィンドウのサーフェスを取り直す。papimela は描くたびに
    フレームバッファを取り、領域か大きさが変わっていたら描画先を差し替える。
    イベントを見逃しても、アプリがイベントを回していなくても、古い領域へ
    描くことが起きない。

    描画そのものは基底クラスのまま。違うのは描画先の出どころと Present だけ
    なので、継承で足りる。 }
  TPMLWindowSoftwareRenderDriver = class(TPMLSoftwareRenderDriver)
  strict private
    FWindow: TPMLWindow;      // 借りている。レンダラはウィンドウより先に畳まれる
    FFrame : TPMLSurface;     // フレームバッファを借りたサーフェス。これは所有する
    class function WrapFramebuffer(AWindow: TPMLWindow): TPMLSurface; static;
    procedure Activate;
  public
    constructor Create(AWindow: TPMLWindow);
    destructor Destroy; override;

    function  GetOutputSize(out AWidth, AHeight: Integer): Boolean; override;
    procedure RunCommandQueue(AQueue: TPMLRenderQueue); override;
    function  ReadPixels(const ARect: TPMLRect): TPMLSurface; override;
    procedure Present; override;
    function  SetVSync(AInterval: Integer): Boolean; override;
  end;

implementation

uses
  PaPiMeLa.Render.Software.Raster;

function TextureSurface(ATexture: TPMLTexture): TPMLSurface; inline;
begin
  if (ATexture = nil) or not (ATexture.DriverData is TPMLSurface) then
    Result := nil
  else
    Result := TPMLSurface(ATexture.DriverData);
end;

{ TPMLSoftwareRenderDriver }

constructor TPMLSoftwareRenderDriver.Create(ATarget: TPMLSurface);
begin
  inherited Create(nil, nil);
  FTarget := ATarget;
  FViewport := TPMLRect.Make(0, 0, ATarget.Width, ATarget.Height);
end;

procedure TPMLSoftwareRenderDriver.SetTarget(ATarget: TPMLSurface);
begin
  FTarget := ATarget;
  FViewport := TPMLRect.Make(0, 0, ATarget.Width, ATarget.Height);
end;

function TPMLSoftwareRenderDriver.Name: String;
begin
  Result := 'software';
end;

function TPMLSoftwareRenderDriver.GetOutputSize(out AWidth, AHeight: Integer): Boolean;
begin
  AWidth := FTarget.Width;
  AHeight := FTarget.Height;
  Result := True;
end;

{ ---- テクスチャ。中身は TPMLSurface ---- }

function TPMLSoftwareRenderDriver.CreateTexture(ATexture: TPMLTexture): Boolean;
begin
  try
    ATexture.DriverData := TPMLSurface.Create(ATexture.Width, ATexture.Height,
      ATexture.Format);
    Result := True;
  except
    on E: EPMLError do
      Result := False;
  end;
end;

function TPMLSoftwareRenderDriver.UpdateTexture(ATexture: TPMLTexture;
  const ARect: TPMLRect; APixels: Pointer; APitch: Integer): Boolean;
var
  S: TPMLSurface;
  Y: Integer;
  RowBytes: PtrUInt;
  Src, Dst: PByte;
begin
  S := TextureSurface(ATexture);
  Result := False;
  if (S = nil) or (APixels = nil) then
    Exit;
  if (ARect.X < 0) or (ARect.Y < 0)
  or (ARect.X + ARect.W > S.Width) or (ARect.Y + ARect.H > S.Height) then
    Exit;
  RowBytes := PtrUInt(ARect.W) * PtrUInt(S.Details.BytesPerPixel);
  for Y := 0 to ARect.H - 1 do
  begin
    Src := PByte(APixels) + PtrUInt(Y) * PtrUInt(APitch);
    Dst := PByte(S.Pixels) + PtrUInt(ARect.Y + Y) * PtrUInt(S.Pitch)
         + PtrUInt(ARect.X) * PtrUInt(S.Details.BytesPerPixel);
    Move(Src^, Dst^, RowBytes);
  end;
  Result := True;
end;

{ 中身を解放する。DriverData を解放するのはここだけ（二重解放を避ける）。 }
procedure TPMLSoftwareRenderDriver.DestroyTexture(ATexture: TPMLTexture);
begin
  FreeAndNil(ATexture.DriverData);
end;

{ ---- 積み込み ---- }

procedure TPMLSoftwareRenderDriver.QueueGeometry(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const AVertices: array of TPMLVertex);
begin
  ACmd.First := AQueue.AddVertices(AVertices);
  ACmd.Count := Length(AVertices);
end;

// 矩形は矩形のまま積む。実行時に PMLFillRect の速い経路を使う。
procedure TPMLSoftwareRenderDriver.QueueFillRects(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const ARects: array of TPMLFRect);
begin
  ACmd.First := AQueue.AddRects(ARects);
  ACmd.Count := Length(ARects);
end;

// 転送元・転送先の 2 矩形で 1 回。実行時に PMLBlitScaled を使う。
procedure TPMLSoftwareRenderDriver.QueueCopy(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; ATexture: TPMLTexture; const ASrc, ADst: TPMLFRect);
begin
  ACmd.First := AQueue.AddRects([ASrc, ADst]);
  ACmd.Count := 2;
end;

// 点は矩形の X / Y だけを使う。
procedure TPMLSoftwareRenderDriver.QueueDrawPoints(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
var
  R: TPMLFRects;
  I: Integer;
begin
  SetLength(R, Length(APoints));
  for I := 0 to High(APoints) do
    R[I] := TPMLFRect.Make(APoints[I].X, APoints[I].Y, 0, 0);
  ACmd.First := AQueue.AddRects(R);
  ACmd.Count := Length(R);
end;

{ 折れ線を、線分ごとに 1 要素へ分けて積む。(X, Y) が始点、(W, H) が終点。

  線分に分けておくと、同じ状態の DrawLines が続いたときに結合しても
  折れ線どうしが勝手に繋がらない。 }
procedure TPMLSoftwareRenderDriver.QueueDrawLines(AQueue: TPMLRenderQueue;
  var ACmd: TPMLRenderCommand; const APoints: array of TPMLFPoint);
var
  R: TPMLFRects;
  I: Integer;
begin
  SetLength(R, Length(APoints) - 1);
  for I := 0 to High(APoints) - 1 do
    R[I] := TPMLFRect.Make(APoints[I].X, APoints[I].Y,
                           APoints[I + 1].X, APoints[I + 1].Y);
  ACmd.First := AQueue.AddRects(R);
  ACmd.Count := Length(R);
end;

{ ---- 実行 ---- }

{ 描画先のクリップ矩形を「ビューポート ∩ クリップ矩形」にする。
  クリップ矩形はビューポートの原点からの相対で与えられる。 }
procedure TPMLSoftwareRenderDriver.ApplyClip;
var
  X1, Y1, X2, Y2: Integer;
begin
  X1 := FViewport.X;
  Y1 := FViewport.Y;
  X2 := FViewport.X + FViewport.W;
  Y2 := FViewport.Y + FViewport.H;
  if FClipOn then
  begin
    if FViewport.X + FClip.X > X1 then X1 := FViewport.X + FClip.X;
    if FViewport.Y + FClip.Y > Y1 then Y1 := FViewport.Y + FClip.Y;
    if FViewport.X + FClip.X + FClip.W < X2 then X2 := FViewport.X + FClip.X + FClip.W;
    if FViewport.Y + FClip.Y + FClip.H < Y2 then Y2 := FViewport.Y + FClip.Y + FClip.H;
  end;
  if X2 < X1 then X2 := X1;
  if Y2 < Y1 then Y2 := Y1;
  // サーフェス側でさらにサーフェスの外が切られる。
  FTarget.ClipRect := TPMLRect.Make(X1, Y1, X2 - X1, Y2 - Y1);
end;

procedure TPMLSoftwareRenderDriver.PutPixel(AX, AY: Integer;
  const AColor: TPMLColor; ABlend: TPMLBlendMode);
var
  C: TPMLColor;
begin
  if (AX < FTarget.ClipRect.X) or (AY < FTarget.ClipRect.Y)
  or (AX >= FTarget.ClipRect.X + FTarget.ClipRect.W)
  or (AY >= FTarget.ClipRect.Y + FTarget.ClipRect.H) then
    Exit;
  if ABlend = TPMLBlendMode.None then
    C := AColor
  else
    C := PMLBlendColor(AColor, FTarget.ReadPixel(AX, AY), ABlend);
  FTarget.WritePixel(AX, AY, C);
end;

{ 画面全体を塗る。クリップ矩形は無視し、ビューポートだけに従う（SDL と同じ）。 }
{ 描画先の全体を塗る。ビューポートもクリップ矩形も無視する。

  PORT-NOTE: SDL_RenderClear の契約（SDL_render.h）で、SDL_render_sw.c も
  クリップを外して矩形 NULL（全体）で塗る。最初の版はビューポートの内側だけを
  塗っていた（D-35）。 }
procedure TPMLSoftwareRenderDriver.ExecClear(const ACmd: TPMLRenderCommand);
var
  Saved, Full: TPMLRect;
begin
  Saved := FTarget.ClipRect;
  Full := TPMLRect.Make(0, 0, FTarget.Width, FTarget.Height);
  FTarget.ClipRect := Full;
  PMLFillRect(FTarget, Full, ACmd.Color.ToColor);
  FTarget.ClipRect := Saved;
end;

{ 矩形の塗り。合成が無ければ PMLFillRect の速い経路、あれば 1 画素ずつ。

  座標は小数を持つので、塗る画素の範囲は「中心が矩形に入る画素」とする。
  整数の矩形ならそのまま [x, x + w) になり、三角形 2 枚で描いた結果と一致する。 }
procedure TPMLSoftwareRenderDriver.ExecFillRects(AQueue: TPMLRenderQueue;
  const ACmd: TPMLRenderCommand);
var
  I, X, Y, X1, Y1, X2, Y2: Integer;
  R: TPMLFRect;
  C: TPMLColor;
begin
  C := ACmd.Color.ToColor;
  for I := ACmd.First to ACmd.First + ACmd.Count - 1 do
  begin
    R := AQueue.RectAt(I);
    // 中心 (px + 0.5) が [x, x + w) に入る画素。
    X1 := Ceil(R.X - 0.5) + FViewport.X;
    Y1 := Ceil(R.Y - 0.5) + FViewport.Y;
    X2 := Ceil(R.X + R.W - 0.5) + FViewport.X;
    Y2 := Ceil(R.Y + R.H - 0.5) + FViewport.Y;
    if (X2 <= X1) or (Y2 <= Y1) then
      Continue;
    if ACmd.Blend = TPMLBlendMode.None then
      PMLFillRect(FTarget, TPMLRect.Make(X1, Y1, X2 - X1, Y2 - Y1), C)
    else
      for Y := Y1 to Y2 - 1 do
        for X := X1 to X2 - 1 do
          PutPixel(X, Y, C, ACmd.Blend);
  end;
end;

procedure TPMLSoftwareRenderDriver.ExecPoints(AQueue: TPMLRenderQueue;
  const ACmd: TPMLRenderCommand);
var
  I: Integer;
  R: TPMLFRect;
  C: TPMLColor;
begin
  C := ACmd.Color.ToColor;
  for I := ACmd.First to ACmd.First + ACmd.Count - 1 do
  begin
    R := AQueue.RectAt(I);
    PutPixel(Trunc(R.X) + FViewport.X, Trunc(R.Y) + FViewport.Y, C, ACmd.Blend);
  end;
end;

{ ブレゼンハムで線分を描く。両端の画素を含む。

  PORT-NOTE: SDL_drawline.c と同じく端点を両方塗る。折れ線の継ぎ目では同じ画素を
  2 回塗ることになり、合成つきの線では継ぎ目が濃くなる。SDL も同じ振る舞い。 }
procedure TPMLSoftwareRenderDriver.ExecLines(AQueue: TPMLRenderQueue;
  const ACmd: TPMLRenderCommand);
var
  I, X0, Y0, X1, Y1, DX, DY, SX, SY, Err, E2: Integer;
  R: TPMLFRect;
  C: TPMLColor;
begin
  C := ACmd.Color.ToColor;
  for I := ACmd.First to ACmd.First + ACmd.Count - 1 do
  begin
    R := AQueue.RectAt(I);
    X0 := Trunc(R.X) + FViewport.X;
    Y0 := Trunc(R.Y) + FViewport.Y;
    X1 := Trunc(R.W) + FViewport.X;
    Y1 := Trunc(R.H) + FViewport.Y;
    DX := Abs(X1 - X0);
    DY := -Abs(Y1 - Y0);
    if X0 < X1 then SX := 1 else SX := -1;
    if Y0 < Y1 then SY := 1 else SY := -1;
    Err := DX + DY;
    while True do
    begin
      PutPixel(X0, Y0, C, ACmd.Blend);
      if (X0 = X1) and (Y0 = Y1) then
        Break;
      E2 := 2 * Err;
      if E2 >= DY then
      begin
        Inc(Err, DY);
        Inc(X0, SX);
      end;
      if E2 <= DX then
      begin
        Inc(Err, DX);
        Inc(Y0, SY);
      end;
    end;
  end;
end;

{ テクスチャ転送。拡大縮小つきのブリットを使う。

  テクスチャの変調と合成モードは、ブリット元のサーフェスへ一時的に写して
  から転送する。PMLBlitScaled がそれらを読むため。 }
procedure TPMLSoftwareRenderDriver.ExecCopy(AQueue: TPMLRenderQueue;
  const ACmd: TPMLRenderCommand);
var
  S: TPMLSurface;
  Src, Dst: TPMLFRect;
begin
  S := TextureSurface(ACmd.Texture);
  if S = nil then
    Exit;
  Src := AQueue.RectAt(ACmd.First);
  Dst := AQueue.RectAt(ACmd.First + 1);
  S.BlendMode := ACmd.Texture.BlendMode;
  S.ColorMod := ACmd.Texture.ColorMod;
  S.AlphaMod := ACmd.Texture.AlphaMod;
  PMLBlitScaled(S,
    TPMLRect.Make(Trunc(Src.X), Trunc(Src.Y), Trunc(Src.W), Trunc(Src.H)),
    FTarget,
    TPMLRect.Make(Trunc(Dst.X) + FViewport.X, Trunc(Dst.Y) + FViewport.Y,
                  Trunc(Dst.W), Trunc(Dst.H)),
    ACmd.ScaleMode);
end;

procedure TPMLSoftwareRenderDriver.ExecGeometry(AQueue: TPMLRenderQueue;
  const ACmd: TPMLRenderCommand);
var
  I: Integer;
  Tex: TPMLSurface;
begin
  Tex := TextureSurface(ACmd.Texture);
  I := ACmd.First;
  while I + 2 < ACmd.First + ACmd.Count do
  begin
    PMLRasterTriangle(FTarget, AQueue.Vertex(I), AQueue.Vertex(I + 1),
      AQueue.Vertex(I + 2), Tex, ACmd.Blend, FViewport.X, FViewport.Y);
    Inc(I, 3);
  end;
end;

procedure TPMLSoftwareRenderDriver.RunCommandQueue(AQueue: TPMLRenderQueue);
var
  I: Integer;
  Cmd: TPMLRenderCommand;
  Saved: TPMLRect;
begin
  // 描画先のクリップ矩形を書き換えるので、終わったら戻す。
  Saved := FTarget.ClipRect;
  try
    ApplyClip;
    for I := 0 to AQueue.CommandCount - 1 do
    begin
      Cmd := AQueue.Commands[I];
      case Cmd.Kind of
        TPMLRenderCommandKind.SetViewport:
          begin
            FViewport := Cmd.Rect;
            ApplyClip;
          end;
        TPMLRenderCommandKind.SetClipRect:
          begin
            FClip := Cmd.Rect;
            FClipOn := Cmd.Enabled;
            ApplyClip;
          end;
        TPMLRenderCommandKind.Clear     : ExecClear(Cmd);
        TPMLRenderCommandKind.FillRects : ExecFillRects(AQueue, Cmd);
        TPMLRenderCommandKind.DrawPoints: ExecPoints(AQueue, Cmd);
        TPMLRenderCommandKind.DrawLines : ExecLines(AQueue, Cmd);
        TPMLRenderCommandKind.Copy      : ExecCopy(AQueue, Cmd);
        TPMLRenderCommandKind.Geometry  : ExecGeometry(AQueue, Cmd);
      end;
    end;
  finally
    FTarget.ClipRect := Saved;
  end;
end;

function TPMLSoftwareRenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
begin
  Result := TPMLSurface.Create(ARect.W, ARect.H, FTarget.Format);
  try
    PMLBlit(FTarget, ARect, Result, TPMLRect.Make(0, 0, 0, 0));
  except
    Result.Free;
    raise;
  end;
end;

// 描画先はサーフェスなので、見せる先が無い。
procedure TPMLSoftwareRenderDriver.Present;
begin
end;

{ TPMLWindowSoftwareRenderDriver }

class function TPMLWindowSoftwareRenderDriver.WrapFramebuffer(
  AWindow: TPMLWindow): TPMLSurface;
var
  P: Pointer;
  Pitch: Integer;
  Format: TPMLPixelFormat;
  Size: TPMLRect;
begin
  if not AWindow.LockFramebuffer(P, Pitch, Format) then
    raise EPMLRenderError.Create('the window framebuffer is not available');
  Size := AWindow.SizeInPixels;
  Result := TPMLSurface.CreateFrom(P, Size.W, Size.H, Pitch, Format);
end;

constructor TPMLWindowSoftwareRenderDriver.Create(AWindow: TPMLWindow);
begin
  FWindow := AWindow;
  FFrame := WrapFramebuffer(AWindow);
  inherited Create(FFrame);
end;

destructor TPMLWindowSoftwareRenderDriver.Destroy;
begin
  FreeAndNil(FFrame);
  inherited Destroy;
end;

{ 今のフレームバッファを描画先にする。領域・大きさ・行の幅のどれかが
  変わっていたら借り直す。変わっていなければ何もしない。 }
procedure TPMLWindowSoftwareRenderDriver.Activate;
var
  P: Pointer;
  Pitch: Integer;
  Format: TPMLPixelFormat;
  Size: TPMLRect;
  Fresh: TPMLSurface;
begin
  if not FWindow.LockFramebuffer(P, Pitch, Format) then
    raise EPMLRenderError.Create('the window framebuffer is not available');
  Size := FWindow.SizeInPixels;
  if (P = FFrame.Pixels) and (Pitch = FFrame.Pitch) and (Format = FFrame.Format)
  and (Size.W = FFrame.Width) and (Size.H = FFrame.Height) then
    Exit;
  Fresh := TPMLSurface.CreateFrom(P, Size.W, Size.H, Pitch, Format);
  SetTarget(Fresh);
  FFrame.Free;
  FFrame := Fresh;
end;

function TPMLWindowSoftwareRenderDriver.GetOutputSize(out AWidth,
  AHeight: Integer): Boolean;
begin
  Activate;
  Result := inherited GetOutputSize(AWidth, AHeight);
end;

procedure TPMLWindowSoftwareRenderDriver.RunCommandQueue(AQueue: TPMLRenderQueue);
begin
  Activate;
  inherited RunCommandQueue(AQueue);
end;

function TPMLWindowSoftwareRenderDriver.ReadPixels(const ARect: TPMLRect): TPMLSurface;
begin
  Activate;
  Result := inherited ReadPixels(ARect);
end;

procedure TPMLWindowSoftwareRenderDriver.Present;
begin
  FWindow.UpdateFramebuffer;
end;

function TPMLWindowSoftwareRenderDriver.SetVSync(AInterval: Integer): Boolean;
begin
  Result := FWindow.SetFramebufferVSync(AInterval);
end;

end.
