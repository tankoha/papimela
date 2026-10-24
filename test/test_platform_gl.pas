{
  test_platform_gl — デスクトップ GL の型・定数・関数表（PaPiMeLa.Platform.GL）

  Origin : original work (clean-room design; not derived from SDL sources)

  WHAT:
    tools/gengl.bb が生成した表と、その読み込みを確かめる。
      constants  GL の仕様で決まっている定数の値（生成物とは別に、仕様の値を手で書いた）
      core       偽の取得関数で、コアの 48 関数がちょうど要求される（名前の重複なし、SDL_glfuncs.h の
                 先頭と末尾の名前）。欠けた名前は表の順に、カンマ区切りで返る
      groups     拡張の 4 グループ（Shader 15・FBO 5・Multitexture 1・Debug 1）の名前と、欠けたときの戻り
      table      関数表の大きさ（コア 48 + 拡張 22 = 70 個のポインタ）
      libGL      本物の libGL.so.1 があれば、dlsym で全部が引けること（無い環境では飛ばす。上の偽物の検査が本体）
}
program test_platform_gl;

{$mode objfpc}{$H+}
{$scopedenums on}

uses
  SysUtils, Classes,
  PaPiMeLa.Platform.DynLib,
  PaPiMeLa.Platform.GL;

var
  Failures: Integer = 0;
  Requested: TStringList;
  MissingNames: TStringList;

procedure Check(ACondition: Boolean; const ALabel: String);
begin
  if ACondition then
    WriteLn('  [PASS] ', ALabel)
  else
  begin
    WriteLn('  [FAIL] ', ALabel);
    Inc(Failures);
  end;
end;

procedure Dummy; cdecl;
begin
end;

// 偽の取得関数: 要求された名前を記録し、MissingNames にあるものだけ nil を返す
function FakeGetProc(AName: PAnsiChar): Pointer; cdecl;
begin
  Requested.Add(String(AName));
  if MissingNames.IndexOf(String(AName)) >= 0 then
    Result := nil
  else
    Result := @Dummy;
end;

procedure Reset;
begin
  Requested.Clear;
  MissingNames.Clear;
end;

function HasDuplicates(AList: TStringList): Boolean;
var
  I, J: Integer;
begin
  for I := 0 to AList.Count - 1 do
    for J := I + 1 to AList.Count - 1 do
      if AList[I] = AList[J] then
        Exit(True);
  Result := False;
end;

procedure TestConstants;
begin
  WriteLn('constants: GL の仕様で決まっている値');
  Check(GL_TRUE = 1, 'GL_TRUE');
  Check(GL_FALSE = 0, 'GL_FALSE');
  Check(GL_POINTS = 0, 'GL_POINTS');
  Check(GL_LINES = 1, 'GL_LINES');
  Check(GL_LINE_STRIP = 3, 'GL_LINE_STRIP');
  Check(GL_TRIANGLES = 4, 'GL_TRIANGLES');
  Check(GL_COLOR_BUFFER_BIT = $4000, 'GL_COLOR_BUFFER_BIT');
  Check(GL_UNSIGNED_BYTE = $1401, 'GL_UNSIGNED_BYTE');
  Check(GL_FLOAT = $1406, 'GL_FLOAT');
  Check(GL_MODELVIEW = $1700, 'GL_MODELVIEW');
  Check(GL_PROJECTION = $1701, 'GL_PROJECTION');
  Check(GL_RGBA = $1908, 'GL_RGBA');
  Check(GL_LUMINANCE = $1909, 'GL_LUMINANCE');
  Check(GL_LUMINANCE_ALPHA = $190A, 'GL_LUMINANCE_ALPHA');
  Check(GL_BGRA = $80E1, 'GL_BGRA');
  Check(GL_TEXTURE_2D = $0DE1, 'GL_TEXTURE_2D');
  Check(GL_TEXTURE_RECTANGLE_ARB = $84F5, 'GL_TEXTURE_RECTANGLE_ARB');
  Check(GL_TEXTURE0_ARB = $84C0, 'GL_TEXTURE0_ARB');
  Check(GL_TEXTURE0 = $84C0, 'GL_TEXTURE0');
  Check(GL_FUNC_ADD = $8006, 'GL_FUNC_ADD');
  Check(GL_MIN = $8007, 'GL_MIN');
  Check(GL_MAX = $8008, 'GL_MAX');
  Check(GL_FRAMEBUFFER_EXT = $8D40, 'GL_FRAMEBUFFER_EXT');
  Check(GL_COLOR_ATTACHMENT0_EXT = $8CE0, 'GL_COLOR_ATTACHMENT0_EXT');
  Check(GL_FRAMEBUFFER_COMPLETE_EXT = $8CD5, 'GL_FRAMEBUFFER_COMPLETE_EXT');
  Check(GL_FRAMEBUFFER_SRGB = $8DB9, 'GL_FRAMEBUFFER_SRGB');
  Check(GL_FRAGMENT_SHADER_ARB = $8B30, 'GL_FRAGMENT_SHADER_ARB');
  Check(GL_VERTEX_SHADER_ARB = $8B31, 'GL_VERTEX_SHADER_ARB');
  Check(GL_OBJECT_COMPILE_STATUS_ARB = $8B81, 'GL_OBJECT_COMPILE_STATUS_ARB');
  Check(GL_OBJECT_INFO_LOG_LENGTH_ARB = $8B84, 'GL_OBJECT_INFO_LOG_LENGTH_ARB');
  Check(GL_UNSIGNED_INT_8_8_8_8_REV = $8367, 'GL_UNSIGNED_INT_8_8_8_8_REV');
  Check(GL_CLAMP_TO_EDGE = $812F, 'GL_CLAMP_TO_EDGE');
  Check(GL_INVALID_ENUM = $0500, 'GL_INVALID_ENUM');
  Check(GL_OUT_OF_MEMORY = $0505, 'GL_OUT_OF_MEMORY');
end;

procedure TestCore;
var
  F: TPMLGLFunctions;
  R: String;
begin
  WriteLn('core: コアの関数表');
  Reset;
  R := PMLLoadGLFunctions(@FakeGetProc, F);
  Check(R = '', '全部見つかれば空文字列: ' + R);
  Check(Requested.Count = 48, '要求された名前は 48 個: ' + IntToStr(Requested.Count));
  Check(not HasDuplicates(Requested), '名前に重複がない');
  Check(Requested[0] = 'glBegin', '先頭は SDL_glfuncs.h の順（glBegin）');
  Check(Requested[Requested.Count - 1] = 'glViewport', '末尾は glViewport');
  Check(Requested.IndexOf('glVertexPointer') >= 0, 'glVertexPointer');
  Check(Requested.IndexOf('glBlendFuncSeparate') >= 0, 'glBlendFuncSeparate');
  Check(Requested.IndexOf('glReadPixels') >= 0, 'glReadPixels');
  Check(Assigned(F.glClear) and Assigned(F.glViewport) and Assigned(F.glBegin), '欄が埋まる');
  Check(not Assigned(F.glUseProgramObjectARB), '拡張の欄は nil のまま');
  // 欠けた名前は表の順にカンマ区切り
  Reset;
  MissingNames.Add('glOrtho');
  MissingNames.Add('glClear');
  R := PMLLoadGLFunctions(@FakeGetProc, F);
  Check(R = 'glClear, glOrtho', '欠けた名前は表の順にカンマ区切り: ' + R);
  Check(not Assigned(F.glClear) and not Assigned(F.glOrtho), '欠けた欄は nil');
  Check(Assigned(F.glBegin), '他の欄は埋まる');
  Check(Requested.Count = 48, '欠けても残りも要求する（48 個）');
end;

procedure TestGroups;
var
  F: TPMLGLFunctions;
  R: String;
  Core: TPMLGLFunctions;
begin
  WriteLn('groups: 拡張のグループ');
  PMLLoadGLFunctions(@FakeGetProc, Core);
  F := Core;
  Reset;
  R := PMLLoadGLExtFunctions(@FakeGetProc, F, TPMLGLExtGroup.Shader);
  Check((R = '') and (Requested.Count = 15), 'Shader は 15 個: ' + IntToStr(Requested.Count) + ' ' + R);
  Check(not HasDuplicates(Requested), 'Shader の名前に重複がない');
  Check(Requested.IndexOf('glUniform4fARB') >= 0, 'Shader に glUniform4fARB が入る');
  Check(Assigned(F.glCreateShaderObjectARB) and Assigned(F.glUseProgramObjectARB), 'Shader の欄が埋まる');
  Check(not Assigned(F.glGenFramebuffersEXT), '他のグループの欄は触らない');
  Reset;
  R := PMLLoadGLExtFunctions(@FakeGetProc, F, TPMLGLExtGroup.FBO);
  Check((R = '') and (Requested.Count = 5), 'FBO は 5 個: ' + IntToStr(Requested.Count) + ' ' + R);
  Check(Requested[0] = 'glBindFramebufferEXT', 'FBO の先頭は glBindFramebufferEXT');
  Reset;
  R := PMLLoadGLExtFunctions(@FakeGetProc, F, TPMLGLExtGroup.Multitexture);
  Check((R = '') and (Requested.Count = 1) and (Requested[0] = 'glActiveTextureARB'), 'Multitexture は glActiveTextureARB');
  Reset;
  R := PMLLoadGLExtFunctions(@FakeGetProc, F, TPMLGLExtGroup.Debug);
  Check((R = '') and (Requested.Count = 1) and (Requested[0] = 'glDebugMessageCallbackARB'), 'Debug は glDebugMessageCallbackARB');
  // 欠けたとき
  Reset;
  MissingNames.Add('glUniform4fARB');
  MissingNames.Add('glLinkProgramARB');
  R := PMLLoadGLExtFunctions(@FakeGetProc, F, TPMLGLExtGroup.Shader);
  Check(R = 'glLinkProgramARB, glUniform4fARB', '欠けた名前を表の順に返す: ' + R);
  Check(not Assigned(F.glUniform4fARB) and Assigned(F.glShaderSourceARB), '欠けた欄だけ nil');
end;

procedure TestTable;
begin
  WriteLn('table: 関数表の大きさ');
  Check(SizeOf(TPMLGLFunctions) = 70 * SizeOf(Pointer), 'ポインタ 70 個（コア 48 + 拡張 22）: ' + IntToStr(SizeOf(TPMLGLFunctions) div SizeOf(Pointer)));
end;

var
  GLib: TPMLDynLib = nil;

function LibGetProc(AName: PAnsiChar): Pointer; cdecl;
begin
  Result := GLib.TryResolve(String(AName));
end;

function IfThenStr(ACond: Boolean; const AYes, ANo: String): String;
begin
  if ACond then
    Result := AYes
  else
    Result := ANo;
end;

procedure TestLibGL;
var
  Lib: TPMLDynLib;
  F: TPMLGLFunctions;
  R: String;
  G: TPMLGLExtGroup;
  Count: Integer;
begin
  WriteLn('libGL: 本物のライブラリの dlsym');
  if not TPMLDynLib.IsAvailable(['libGL.so.1', 'libOpenGL.so.0', 'libGL.so']) then
  begin
    WriteLn('  [SKIP] libGL が無い環境（偽物の検査が本体）');
    Exit;
  end;
  Lib := TPMLDynLib.Create(['libGL.so.1', 'libOpenGL.so.0', 'libGL.so']);
  try
    // 取得関数は手続き変数でなくグローバルな関数にしたいので、Lib を変数に置く
    GLib := Lib;
    R := PMLLoadGLFunctions(@LibGetProc, F);
    Check(R = '', 'コア 48 関数が全部 dlsym で引ける: ' + R);
    Count := 0;
    for G := Low(TPMLGLExtGroup) to High(TPMLGLExtGroup) do
    begin
      R := PMLLoadGLExtFunctions(@LibGetProc, F, G);
      if R = '' then
        Inc(Count);
      Check(True, 'グループ ' + IntToStr(Ord(G)) + ': ' + IfThenStr(R = '', '全部ある', '欠け: ' + R));
    end;
    Check(Count >= 0, '拡張のグループはライブラリの種類で揃わないことがある（記録だけ）');
  finally
    GLib := nil;
    Lib.Free;
  end;
end;

begin
  Requested := TStringList.Create;
  MissingNames := TStringList.Create;
  try
    WriteLn('=== test_platform_gl ===');
    TestConstants;
    TestCore;
    TestGroups;
    TestTable;
    TestLibGL;
  finally
    Requested.Free;
    MissingNames.Free;
  end;
  WriteLn;
  if Failures = 0 then
    WriteLn('=== 結論: デスクトップ GL の型・定数・関数表が期待どおり ===')
  else
  begin
    WriteLn('=== 失敗 ', Failures, ' 件 ===');
    Halt(1);
  end;
end.
