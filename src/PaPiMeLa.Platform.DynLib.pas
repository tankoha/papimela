{
  PaPiMeLa.Platform.DynLib — 共有ライブラリの実行時ロード

  Origin : original work (clean-room design; not derived from SDL sources)
  Design : docs/DESIGN.md §2.5（#ifdef を dlopen 成否に置き換える方針）

  WHAT:
    FPC の dynlibs を包み、シンボル解決の失敗を EPMLPlatformLibrary にする。

  WHY:
    IME・オーディオ・Wayland の各バックエンドは任意機能なので、ライブラリの
    不在はリンクエラーではなく実行時の能力判定でなければならない。
    設計方針「Linux 内の分岐は実行時の dlopen 成否に置き換える」の土台。

  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.DynLib;

{$I papimela.inc}

interface

uses
  SysUtils, DynLibs,
  PaPiMeLa.Errors;

type
  TPMLDynLib = class
  strict private
    FHandle: TLibHandle;
    FName  : String;
  public
    // ANames は候補。順に試して最初に開けたものを使う（'libdbus-1.so.3' → 'libdbus-1.so'）。
    constructor Create(const ANames: array of String);
    destructor Destroy; override;

    // 解決できなければ EPMLPlatformLibrary を投げる。
    function Resolve(const ASymbol: String): Pointer;
    // 解決できなければ nil を返す。バージョン差で存在しない関数に使う。
    function TryResolve(const ASymbol: String): Pointer;

    class function IsAvailable(const ANames: array of String): Boolean;

    property Name: String read FName;
  end;

implementation

constructor TPMLDynLib.Create(const ANames: array of String);
var
  I: Integer;
begin
  inherited Create;
  FHandle := NilHandle;
  for I := Low(ANames) to High(ANames) do
  begin
    FHandle := LoadLibrary(ANames[I]);
    if FHandle <> NilHandle then
    begin
      FName := ANames[I];
      Exit;
    end;
  end;
  if Length(ANames) > 0 then
    FName := ANames[Low(ANames)];
  raise EPMLPlatformLibrary.CreateNative('failed to load shared library', 0,
    FName, GetLoadErrorStr);
end;

destructor TPMLDynLib.Destroy;
begin
  if FHandle <> NilHandle then
    UnloadLibrary(FHandle);
  inherited Destroy;
end;

function TPMLDynLib.TryResolve(const ASymbol: String): Pointer;
begin
  Result := GetProcedureAddress(FHandle, ASymbol);
end;

function TPMLDynLib.Resolve(const ASymbol: String): Pointer;
begin
  Result := TryResolve(ASymbol);
  if Result = nil then
    raise EPMLPlatformLibrary.CreateNative(
      Format('symbol "%s" not found', [ASymbol]), 0, FName);
end;

class function TPMLDynLib.IsAvailable(const ANames: array of String): Boolean;
var
  I: Integer;
  H: TLibHandle;
begin
  for I := Low(ANames) to High(ANames) do
  begin
    H := LoadLibrary(ANames[I]);
    if H <> NilHandle then
    begin
      UnloadLibrary(H);
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
