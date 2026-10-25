{
  PaPiMeLa.Video.Wayland.LibDecor — libdecor の文脈（クライアントサイド装飾）

  Origin : partially ported from SDL (src/video/wayland/SDL_waylandvideo.c)
           Scope: should_use_libdecor（使うかどうかの判断）、libdecor_interface の error、LibdecorNew、
           Wayland_LoadLibdecor の読み込みと、SDL_waylandevents.c の libdecor_dispatch の呼び方、
           SDL_waylandvideo.c の終了処理の libdecor_unref。
           移植しないもの: GTK を避けるために libdecor を別スレッドで作る回避策（CanUseGtk /
           LibdecorNewInThread。papimela は GTK のプラグインがあれば素直に使わせる。NOT RESOLVED を見る）。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §3.4、§11 #69

  WHAT:
    libdecor の文脈（struct libdecor）を、Wayland の接続の上に 1 つ持つ。ウィンドウ（フレーム）は
    TPMLWaylandWindowBackend が、この文脈から作る。

  WHY:
    GNOME のように xdg-decoration を持たないコンポジタは、クライアントが枠を描く（クライアントサイド装飾）。
    libdecor がそれを肩代わりする。

  RESOLVED:
    - 使う条件は SDL と同じ: ヒント PAPIMELA_WAYLAND_PREFER_LIBDECOR が真なら使う。そうでなければ
      xdg-decoration があるコンポジタでは使わず（サーバが枠を描く）、無ければ使う。libdecor が無い、
      または文脈を作れなければ、枠なしのまま動く（libdecor を無かったことにする）
    - イベントは libdecor_dispatch(文脈, 0) で配る。接続の読み込みの後に呼ぶ（SDL の Wayland_PumpEvents）
    - libdecor の error は、直近のものを覚える（LastError）。接続を切るほどの失敗ではない

  NOT RESOLVED:
    - SDL は、GTK を使わないアプリで GTK のプラグインを避けるため、libdecor の文脈を別スレッドで作る
      （プラグインはメインスレッドで作られたときだけ GTK を選ぶ）。papimela は避けない。GTK のプラグインしか
      無い環境では、GTK が読み込まれる

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Video.Wayland.LibDecor;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Errors,
  PaPiMeLa.Core.Base,
  PaPiMeLa.Properties,
  PaPiMeLa.Platform.LibDecor,
  PaPiMeLa.Platform.Wayland.Client,
  PaPiMeLa.Video.Wayland.Types;

type
  TPMLWaylandLibDecor = class(TPMLSystemObject)
  strict private
    FContext: Plibdecor;
    FIface  : TLibDecorInterface;
    FLoaded : Boolean;
  public
    { SDL の should_use_libdecor。ライブラリが読めるかも見る。 }
    class function ShouldUse(AServices: TPMLContextBase; AConn: TPMLWaylandConnection): Boolean;
    { libdecor を読み込み、文脈を作る。できなければ EPMLUnsupported（読み込みは元に戻す）。 }
    constructor Create(AContextRef: TObject; AOwner: TPMLObject; AConn: TPMLWaylandConnection);
    destructor Destroy; override;

    { libdecor に溜まったイベントを配る（待たない）。 }
    procedure Dispatch;

    property Context: Plibdecor read FContext;
  end;

{ 直近の libdecor のエラーの説明（無ければ空）。検査用。 }
function PMLLibDecorLastError: String;

implementation

var
  GLastError: String = '';

function PMLLibDecorLastError: String;
begin
  Result := GLastError;
end;

procedure LibDecorError(AContext: Plibdecor; AError: LongInt; AMessage: PAnsiChar); cdecl;
begin
  GLastError := Format('libdecor error (%d): %s', [AError, String(AMessage)]);
end;

class function TPMLWaylandLibDecor.ShouldUse(AServices: TPMLContextBase; AConn: TPMLWaylandConnection): Boolean;
var
  Prefer: Boolean;
begin
  // ライブラリがあるか（読み込みは文脈を作るときまで遅らせる）
  if not PMLLibDecorAvailable then
    Exit(False);
  Prefer := (AServices <> nil) and (AServices.Hints <> nil)
    and AServices.Hints.GetBoolean(PML_HINT_WAYLAND_PREFER_LIBDECOR, False);
  if Prefer then
    Exit(True);
  // xdg-decoration があれば、サーバが枠を描く
  Result := AConn.DecorationMgr = nil;
end;

constructor TPMLWaylandLibDecor.Create(AContextRef: TObject; AOwner: TPMLObject; AConn: TPMLWaylandConnection);
begin
  inherited Create(AContextRef, AOwner);
  if not PMLLibDecorLoad then
    raise EPMLUnsupported.Create('libdecor is not available');
  FLoaded := True;
  FillChar(FIface, SizeOf(FIface), 0);
  FIface.error := @LibDecorError;
  GLastError := '';
  FContext := libdecor_new(AConn.Display, @FIface);
  if FContext = nil then
  begin
    PMLLibDecorUnload;
    FLoaded := False;
    raise EPMLUnsupported.Create('libdecor_new failed' + ' ' + GLastError);
  end;
end;

destructor TPMLWaylandLibDecor.Destroy;
begin
  if FContext <> nil then
    libdecor_unref(FContext);
  FContext := nil;
  if FLoaded then
    PMLLibDecorUnload;
  inherited Destroy;
end;

procedure TPMLWaylandLibDecor.Dispatch;
begin
  if FContext <> nil then
    libdecor_dispatch(FContext, 0);
end;

end.
