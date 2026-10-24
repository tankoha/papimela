{
  PaPiMeLa.Platform.GL — デスクトップ OpenGL（1.x〜2.1 の互換プロファイル）の型・定数・関数表

  Origin : partially ported from SDL (src/render/opengl/SDL_glfuncs.h, src/render/opengl/SDL_render_gl.c,
           src/render/opengl/SDL_shaders_gl.c)
           Scope: SDL の render/opengl が使う GL の定数と関数（SDL_glfuncs.h の有効な 48 行、シェーダの ARB 15、
           FBO の EXT 5、マルチテクスチャの ARB 1、デバッグ出力の ARB 1）。関数の取り方は PMLLoadGLFunctions と
           グループごとの PMLLoadGLExtFunctions。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9、§11 #17、#44

  WHAT:
    デスクトップ GL の型、定数（tools/gengl.bb が GL/gl.h と GL/glext.h から生成）、関数表
    （同じ生成器が SDL_glfuncs.h と glext.h の型から生成）と、その読み込み。

  WHY:
    GLES2（PaPiMeLa.Platform.GLES2）とは関数の集合も、シェーダの拡張（ARB）も違う。Render.GL が
    SDL の render/opengl と同じ関数だけを使うよう、SDL の表をそのまま持つ。

  RESOLVED:
    - 型名は PaPiMeLa.Platform.GLES2 と同じ。2 つのユニットは自己完結にしてある（Render.GL は GLES2 の
      ユニットを使わない。同じ名前の定数が両方にあるので、1 つのユニットから両方を使わない）
    - 関数の取り方は呼び出し側が渡す（AGetProc）。デスクトップ GL の本体の関数は libGL の dlsym で引く。
      eglGetProcAddress は存在しない gl* にも非 nil を返す（glvnd。スパイク 5）ので、存在の確認には使えない
    - コアの関数は全部あること。拡張はグループ（Shader・FBO・Multitexture・Debug）ごとに、
      全部あれば使える。無いグループは使わない（SDL と同じ）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.GL;

{$I papimela.inc}

interface

type
  GLenum      = LongWord;
  GLboolean   = Byte;
  GLbitfield  = LongWord;
  GLint       = LongInt;
  GLuint      = LongWord;
  GLsizei     = LongInt;
  GLfloat     = Single;
  GLclampf    = Single;
  GLdouble    = Double;
  GLclampd    = Double;
  GLubyte     = Byte;
  GLchar      = AnsiChar;
  GLintptr    = PtrInt;
  GLsizeiptr  = PtrInt;
  // ARB のシェーダのハンドル（GLhandleARB。Linux では unsigned int）
  GLhandleARB = LongWord;

  PGLenum   = ^GLenum;
  PGLint    = ^GLint;
  PGLuint   = ^GLuint;
  PGLsizei  = ^GLsizei;
  PGLfloat  = ^GLfloat;
  PGLdouble = ^GLdouble;
  PGLubyte  = ^GLubyte;
  PGLchar   = ^GLchar;
  PPGLchar  = ^PGLchar;

const
{$I generated/gl_constants.inc}

type
  { 名前から関数の番地を返す。見つからなければ nil。 }
  TPMLGLGetProc = function(AName: PAnsiChar): Pointer; cdecl;

  { 拡張のグループ。SDL は、グループの関数が 1 つでも欠けていればそのグループを使わない。 }
  TPMLGLExtGroup = (Shader, FBO, Multitexture, Debug);

  { デスクトップ GL の関数表。コア（SDL_glfuncs.h の順）と、拡張のグループ。 }
  TPMLGLFunctions = record
{$I generated/gl_functions.inc}
  end;

{ AGetProc でコアの関数表を埋める。見つからなかった関数の名前をカンマ区切りで返し、全部見つかれば空文字列。
  拡張の欄は nil にする（PMLLoadGLExtFunctions で埋める）。 }
function PMLLoadGLFunctions(AGetProc: TPMLGLGetProc; out AFuncs: TPMLGLFunctions): String;

{ 拡張のグループを埋める。見つからなかった関数の名前をカンマ区切りで返し、全部見つかれば空文字列。
  見つからなかった欄は nil のまま（呼ぶ側はグループが使えるかを、戻りが空かで決める）。 }
function PMLLoadGLExtFunctions(AGetProc: TPMLGLGetProc; var AFuncs: TPMLGLFunctions;
  AGroup: TPMLGLExtGroup): String;

implementation

function PMLLoadGLFunctions(AGetProc: TPMLGLGetProc; out AFuncs: TPMLGLFunctions): String;
var
  Missing: String;

  procedure Bind(out ATarget; const AName: String);
  begin
    Pointer(ATarget) := AGetProc(PAnsiChar(AName));
    if Pointer(ATarget) = nil then
    begin
      if Missing <> '' then
        Missing := Missing + ', ';
      Missing := Missing + AName;
    end;
  end;

begin
  FillChar(AFuncs, SizeOf(AFuncs), 0);
  Missing := '';
{$I generated/gl_bind_core.inc}
  Result := Missing;
end;

function PMLLoadGLExtFunctions(AGetProc: TPMLGLGetProc; var AFuncs: TPMLGLFunctions;
  AGroup: TPMLGLExtGroup): String;
var
  Missing: String;

  procedure Bind(out ATarget; const AName: String);
  begin
    Pointer(ATarget) := AGetProc(PAnsiChar(AName));
    if Pointer(ATarget) = nil then
    begin
      if Missing <> '' then
        Missing := Missing + ', ';
      Missing := Missing + AName;
    end;
  end;

begin
  Missing := '';
  case AGroup of
    TPMLGLExtGroup.Shader:
      begin
{$I generated/gl_bind_shader.inc}
      end;
    TPMLGLExtGroup.FBO:
      begin
{$I generated/gl_bind_fbo.inc}
      end;
    TPMLGLExtGroup.Multitexture:
      begin
{$I generated/gl_bind_multitexture.inc}
      end;
    TPMLGLExtGroup.Debug:
      begin
{$I generated/gl_bind_debug.inc}
      end;
  end;
  Result := Missing;
end;

end.
