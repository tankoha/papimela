{
  PaPiMeLa.Platform.GLES2 — OpenGL ES 2.0 の型、定数、関数表

  Origin : partially ported from SDL (src/render/opengles2/SDL_gles2funcs.h)
           Scope: レンダラが使う関数の一覧（57 個）。型と読み込みの仕組みは本設計。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §9、§11 #17

  WHAT:
    GLES 2.0 の型、定数（tools/genkhronos.bb が gl2.h から生成）、関数ポインタを
    まとめた記録 TPMLGLES2Functions と、それを埋める PMLLoadGLES2Functions。

  WHY:
    GL の関数はコンテキストごとに取るもので、ライブラリを直接結合しない
    （SDL の GLES2_DriverContext と同じく、レンダラが自分の表を持つ）。
    khronos のヘッダ一式は使わず、必要なものだけを持つ（§9）。

  RESOLVED:
    - 記録のフィールド（57 個）は qwen2.5-coder が SDL_gles2funcs.h の C の宣言から
      書いた。型の対応表を渡し、戻り値と引数の型の並びを機械的に突き合わせて
      全件一致を確かめてから採用した（TEST-LOG の使い捨て検証）
    - 関数の取り方は呼び出し側が渡す（TPMLGLGetProc）。EGL では eglGetProcAddress、
      見つからなければ libGLESv2 から直接引く、という順序は PaPiMeLa.Video.EGL が決める

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Platform.GLES2;

{$I papimela.inc}

interface

type
  GLenum     = LongWord;
  GLboolean  = Byte;
  GLbitfield = LongWord;
  GLint      = LongInt;
  GLuint     = LongWord;
  GLsizei    = LongInt;
  GLfloat    = Single;
  GLclampf   = Single;
  GLubyte    = Byte;
  GLchar     = AnsiChar;
  GLintptr   = PtrInt;
  GLsizeiptr = PtrInt;

  PGLint   = ^GLint;
  PGLuint  = ^GLuint;
  PGLsizei = ^GLsizei;
  PGLfloat = ^GLfloat;
  PGLubyte = ^GLubyte;
  PGLchar  = ^GLchar;
  PPGLchar = ^PGLchar;

const
{$I generated/gles2_constants.inc}

type
  { 名前から関数の番地を返す。見つからなければ nil。eglGetProcAddress と同じ形。 }
  TPMLGLGetProc = function(AName: PAnsiChar): Pointer; cdecl;

  { GLES 2.0 の関数表。SDL_gles2funcs.h の順。 }
  TPMLGLES2Functions = record
    glActiveTexture: procedure(ATexture: GLenum); cdecl;
    glAttachShader: procedure(AProgram: GLuint; AShader: GLuint); cdecl;
    glBindAttribLocation: procedure(AProgram: GLuint; AIndex: GLuint; AName: PGLchar); cdecl;
    glBindTexture: procedure(ATarget: GLenum; ATexture: GLuint); cdecl;
    glBlendEquationSeparate: procedure(AModeRGB: GLenum; AModeAlpha: GLenum); cdecl;
    glBlendFuncSeparate: procedure(ASrcRGB: GLenum; ADstRGB: GLenum; ASrcAlpha: GLenum; ADstAlpha: GLenum); cdecl;
    glClear: procedure(AMask: GLbitfield); cdecl;
    glClearColor: procedure(ARed: GLclampf; AGreen: GLclampf; ABlue: GLclampf; AAlpha: GLclampf); cdecl;
    glCompileShader: procedure(AShader: GLuint); cdecl;
    glCreateProgram: function: GLuint; cdecl;
    glCreateShader: function(AType: GLenum): GLuint; cdecl;
    glDeleteProgram: procedure(AProgram: GLuint); cdecl;
    glDeleteShader: procedure(AShader: GLuint); cdecl;
    glDeleteTextures: procedure(AN: GLsizei; ATextures: PGLuint); cdecl;
    glDisable: procedure(ACap: GLenum); cdecl;
    glDisableVertexAttribArray: procedure(AIndex: GLuint); cdecl;
    glDrawArrays: procedure(AMode: GLenum; AFirst: GLint; ACount: GLsizei); cdecl;
    glEnable: procedure(ACap: GLenum); cdecl;
    glEnableVertexAttribArray: procedure(AIndex: GLuint); cdecl;
    glFinish: procedure; cdecl;
    glGenFramebuffers: procedure(AN: GLsizei; AFramebuffers: PGLuint); cdecl;
    glGenTextures: procedure(AN: GLsizei; ATextures: PGLuint); cdecl;
    glGetString: function(AName: GLenum): PGLubyte; cdecl;
    glGetError: function: GLenum; cdecl;
    glGetIntegerv: procedure(APname: GLenum; AParams: PGLint); cdecl;
    glGetProgramiv: procedure(AProgram: GLuint; APname: GLenum; AParams: PGLint); cdecl;
    glGetShaderInfoLog: procedure(AShader: GLuint; AMaxLength: GLsizei; ALength: PGLsizei; AInfoLog: PGLchar); cdecl;
    glGetShaderiv: procedure(AShader: GLuint; APname: GLenum; AParams: PGLint); cdecl;
    glGetUniformLocation: function(AProgram: GLuint; AName: PGLchar): GLint; cdecl;
    glLinkProgram: procedure(AProgram: GLuint); cdecl;
    glPixelStorei: procedure(APname: GLenum; AParam: GLint); cdecl;
    glReadPixels: procedure(AX: GLint; AY: GLint; AWidth: GLsizei; AHeight: GLsizei; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glScissor: procedure(AX: GLint; AY: GLint; AWidth: GLsizei; AHeight: GLsizei); cdecl;
    glShaderBinary: procedure(ACount: GLsizei; AShaders: PGLuint; ABinaryformat: GLenum; ABinary: Pointer; ALength: GLsizei); cdecl;
    glShaderSource: procedure(AShader: GLuint; ACount: GLsizei; AString: PPGLchar; ALength: PGLint); cdecl;
    glTexImage2D: procedure(ATarget: GLenum; ALevel: GLint; AInternalformat: GLint; AWidth: GLsizei; AHeight: GLsizei; ABorder: GLint; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glTexParameteri: procedure(ATarget: GLenum; APname: GLenum; AParam: GLint); cdecl;
    glTexSubImage2D: procedure(ATarget: GLenum; ALevel: GLint; AXoffset: GLint; AYoffset: GLint; AWidth: GLsizei; AHeight: GLsizei; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glUniform1i: procedure(ALocation: GLint; AValue: GLint); cdecl;
    glUniform3f: procedure(ALocation: GLint; AValue0: GLfloat; AValue1: GLfloat; AValue2: GLfloat); cdecl;
    glUniform4f: procedure(ALocation: GLint; AValue0: GLfloat; AValue1: GLfloat; AValue2: GLfloat; AValue3: GLfloat); cdecl;
    glUniformMatrix3fv: procedure(ALocation: GLint; ACount: GLsizei; ATranspose: GLboolean; AValue: PGLfloat); cdecl;
    glUniformMatrix4fv: procedure(ALocation: GLint; ACount: GLsizei; ATranspose: GLboolean; AValue: PGLfloat); cdecl;
    glUseProgram: procedure(AProgram: GLuint); cdecl;
    glVertexAttribPointer: procedure(AIndex: GLuint; ASize: GLint; AType: GLenum; ANormalized: GLboolean; AStride: GLsizei; APointer: Pointer); cdecl;
    glViewport: procedure(AX: GLint; AY: GLint; AWidth: GLsizei; AHeight: GLsizei); cdecl;
    glBindFramebuffer: procedure(ATarget: GLenum; AFramebuffer: GLuint); cdecl;
    glFramebufferTexture2D: procedure(ATarget: GLenum; AAttachment: GLenum; ATextarget: GLenum; ATexture: GLuint; ALevel: GLint); cdecl;
    glCheckFramebufferStatus: function(ATarget: GLenum): GLenum; cdecl;
    glDeleteFramebuffers: procedure(AN: GLsizei; AFramebuffers: PGLuint); cdecl;
    glGetAttribLocation: function(AProgram: GLuint; AName: PGLchar): GLint; cdecl;
    glGetProgramInfoLog: procedure(AProgram: GLuint; AMaxLength: GLsizei; ALength: PGLsizei; AInfoLog: PGLchar); cdecl;
    glGenBuffers: procedure(AN: GLsizei; ABuffers: PGLuint); cdecl;
    glDeleteBuffers: procedure(AN: GLsizei; ABuffers: PGLuint); cdecl;
    glBindBuffer: procedure(ATarget: GLenum; ABuffer: GLuint); cdecl;
    glBufferData: procedure(ATarget: GLenum; ASize: GLsizeiptr; AData: Pointer; AUsage: GLenum); cdecl;
    glBufferSubData: procedure(ATarget: GLenum; AOffset: GLintptr; ASize: GLsizeiptr; AData: Pointer); cdecl;
  end;

{ AGetProc で関数表を埋める。見つからなかった関数の名前をカンマ区切りで返し、
  全部見つかれば空文字列。見つからなかったフィールドは nil のまま。 }
function PMLLoadGLES2Functions(AGetProc: TPMLGLGetProc;
  out AFuncs: TPMLGLES2Functions): String;

implementation

function PMLLoadGLES2Functions(AGetProc: TPMLGLGetProc;
  out AFuncs: TPMLGLES2Functions): String;
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
  Bind(AFuncs.glActiveTexture, 'glActiveTexture');
  Bind(AFuncs.glAttachShader, 'glAttachShader');
  Bind(AFuncs.glBindAttribLocation, 'glBindAttribLocation');
  Bind(AFuncs.glBindTexture, 'glBindTexture');
  Bind(AFuncs.glBlendEquationSeparate, 'glBlendEquationSeparate');
  Bind(AFuncs.glBlendFuncSeparate, 'glBlendFuncSeparate');
  Bind(AFuncs.glClear, 'glClear');
  Bind(AFuncs.glClearColor, 'glClearColor');
  Bind(AFuncs.glCompileShader, 'glCompileShader');
  Bind(AFuncs.glCreateProgram, 'glCreateProgram');
  Bind(AFuncs.glCreateShader, 'glCreateShader');
  Bind(AFuncs.glDeleteProgram, 'glDeleteProgram');
  Bind(AFuncs.glDeleteShader, 'glDeleteShader');
  Bind(AFuncs.glDeleteTextures, 'glDeleteTextures');
  Bind(AFuncs.glDisable, 'glDisable');
  Bind(AFuncs.glDisableVertexAttribArray, 'glDisableVertexAttribArray');
  Bind(AFuncs.glDrawArrays, 'glDrawArrays');
  Bind(AFuncs.glEnable, 'glEnable');
  Bind(AFuncs.glEnableVertexAttribArray, 'glEnableVertexAttribArray');
  Bind(AFuncs.glFinish, 'glFinish');
  Bind(AFuncs.glGenFramebuffers, 'glGenFramebuffers');
  Bind(AFuncs.glGenTextures, 'glGenTextures');
  Bind(AFuncs.glGetString, 'glGetString');
  Bind(AFuncs.glGetError, 'glGetError');
  Bind(AFuncs.glGetIntegerv, 'glGetIntegerv');
  Bind(AFuncs.glGetProgramiv, 'glGetProgramiv');
  Bind(AFuncs.glGetShaderInfoLog, 'glGetShaderInfoLog');
  Bind(AFuncs.glGetShaderiv, 'glGetShaderiv');
  Bind(AFuncs.glGetUniformLocation, 'glGetUniformLocation');
  Bind(AFuncs.glLinkProgram, 'glLinkProgram');
  Bind(AFuncs.glPixelStorei, 'glPixelStorei');
  Bind(AFuncs.glReadPixels, 'glReadPixels');
  Bind(AFuncs.glScissor, 'glScissor');
  Bind(AFuncs.glShaderBinary, 'glShaderBinary');
  Bind(AFuncs.glShaderSource, 'glShaderSource');
  Bind(AFuncs.glTexImage2D, 'glTexImage2D');
  Bind(AFuncs.glTexParameteri, 'glTexParameteri');
  Bind(AFuncs.glTexSubImage2D, 'glTexSubImage2D');
  Bind(AFuncs.glUniform1i, 'glUniform1i');
  Bind(AFuncs.glUniform3f, 'glUniform3f');
  Bind(AFuncs.glUniform4f, 'glUniform4f');
  Bind(AFuncs.glUniformMatrix3fv, 'glUniformMatrix3fv');
  Bind(AFuncs.glUniformMatrix4fv, 'glUniformMatrix4fv');
  Bind(AFuncs.glUseProgram, 'glUseProgram');
  Bind(AFuncs.glVertexAttribPointer, 'glVertexAttribPointer');
  Bind(AFuncs.glViewport, 'glViewport');
  Bind(AFuncs.glBindFramebuffer, 'glBindFramebuffer');
  Bind(AFuncs.glFramebufferTexture2D, 'glFramebufferTexture2D');
  Bind(AFuncs.glCheckFramebufferStatus, 'glCheckFramebufferStatus');
  Bind(AFuncs.glDeleteFramebuffers, 'glDeleteFramebuffers');
  Bind(AFuncs.glGetAttribLocation, 'glGetAttribLocation');
  Bind(AFuncs.glGetProgramInfoLog, 'glGetProgramInfoLog');
  Bind(AFuncs.glGenBuffers, 'glGenBuffers');
  Bind(AFuncs.glDeleteBuffers, 'glDeleteBuffers');
  Bind(AFuncs.glBindBuffer, 'glBindBuffer');
  Bind(AFuncs.glBufferData, 'glBufferData');
  Bind(AFuncs.glBufferSubData, 'glBufferSubData');
  Result := Missing;
end;

end.
