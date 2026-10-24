{ src/generated/gl_functions.inc — tools/gengl.bb が作る。手で直さない。
  デスクトップ OpenGL の関数表のフィールド。コアは SDL_glfuncs.h の有効な行（48 件）、
  拡張は SDL が使う ARB / EXT の関数（22 件）。 }
    // ---- コア（全部あること）
    glBegin: procedure(A1: GLenum); cdecl;
    glBindTexture: procedure(A1: GLenum; A2: GLuint); cdecl;
    glBlendEquation: procedure(A1: GLenum); cdecl;
    glBlendFuncSeparate: procedure(A1: GLenum; A2: GLenum; A3: GLenum; A4: GLenum); cdecl;
    glClear: procedure(A1: GLbitfield); cdecl;
    glClearColor: procedure(A1: GLclampf; A2: GLclampf; A3: GLclampf; A4: GLclampf); cdecl;
    glColor3fv: procedure(A1: PGLfloat); cdecl;
    glColor4f: procedure(A1: GLfloat; A2: GLfloat; A3: GLfloat; A4: GLfloat); cdecl;
    glColor4ub: procedure(ARed: GLubyte; AGreen: GLubyte; ABlue: GLubyte; AAlpha: GLubyte); cdecl;
    glColorPointer: procedure(ASize: GLint; AType: GLenum; AStride: GLsizei; APointer: Pointer); cdecl;
    glDeleteTextures: procedure(A1: GLsizei; ATextures: PGLuint); cdecl;
    glDepthFunc: procedure(AFunc: GLenum); cdecl;
    glDisable: procedure(ACap: GLenum); cdecl;
    glDisableClientState: procedure(AArray: GLenum); cdecl;
    glDrawArrays: procedure(AMode: GLenum; AFirst: GLint; ACount: GLsizei); cdecl;
    glDrawPixels: procedure(AWidth: GLsizei; AHeight: GLsizei; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glEnable: procedure(ACap: GLenum); cdecl;
    glEnableClientState: procedure(AArray: GLenum); cdecl;
    glEnd: procedure; cdecl;
    glGenTextures: procedure(A1: GLsizei; ATextures: PGLuint); cdecl;
    glGetError: function: GLenum; cdecl;
    glGetFloatv: procedure(APname: GLenum; AParams: PGLfloat); cdecl;
    glGetIntegerv: procedure(APname: GLenum; AParams: PGLint); cdecl;
    glGetPointerv: procedure(APname: GLenum; AParams: Pointer); cdecl;
    glGetString: function(AName: GLenum): PGLubyte; cdecl;
    glLineWidth: procedure(AWidth: GLfloat); cdecl;
    glLoadIdentity: procedure; cdecl;
    glMatrixMode: procedure(AMode: GLenum); cdecl;
    glOrtho: procedure(ALeft: GLdouble; ARight: GLdouble; ABottom: GLdouble; ATop: GLdouble; AZNear: GLdouble; AZFar: GLdouble); cdecl;
    glPixelStorei: procedure(APname: GLenum; AParam: GLint); cdecl;
    glPointSize: procedure(ASize: GLfloat); cdecl;
    glRasterPos2i: procedure(A1: GLint; A2: GLint); cdecl;
    glReadBuffer: procedure(AMode: GLenum); cdecl;
    glReadPixels: procedure(A1: GLint; A2: GLint; AWidth: GLsizei; AHeight: GLsizei; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glRectf: procedure(A1: GLfloat; A2: GLfloat; A3: GLfloat; A4: GLfloat); cdecl;
    glRotatef: procedure(AAngle: GLfloat; A2: GLfloat; A3: GLfloat; A4: GLfloat); cdecl;
    glScissor: procedure(A1: GLint; A2: GLint; AWidth: GLsizei; AHeight: GLsizei); cdecl;
    glShadeModel: procedure(AMode: GLenum); cdecl;
    glTexCoord2f: procedure(A1: GLfloat; A2: GLfloat); cdecl;
    glTexCoordPointer: procedure(ASize: GLint; AType: GLenum; AStride: GLsizei; APointer: Pointer); cdecl;
    glTexEnvf: procedure(ATarget: GLenum; APname: GLenum; AParam: GLfloat); cdecl;
    glTexImage2D: procedure(ATarget: GLenum; ALevel: GLint; AInternalformat: GLint; AWidth: GLsizei; AHeight: GLsizei; ABorder: GLint; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glTexParameteri: procedure(ATarget: GLenum; APname: GLenum; AParam: GLint); cdecl;
    glTexSubImage2D: procedure(ATarget: GLenum; ALevel: GLint; AXoffset: GLint; AYoffset: GLint; AWidth: GLsizei; AHeight: GLsizei; AFormat: GLenum; AType: GLenum; APixels: Pointer); cdecl;
    glVertex2f: procedure(A1: GLfloat; A2: GLfloat); cdecl;
    glVertex3fv: procedure(A1: PGLfloat); cdecl;
    glVertexPointer: procedure(ASize: GLint; AType: GLenum; AStride: GLsizei; APointer: Pointer); cdecl;
    glViewport: procedure(A1: GLint; A2: GLint; AWidth: GLsizei; AHeight: GLsizei); cdecl;
    // ---- 拡張: Shader（グループ全部あること）
    glAttachObjectARB: procedure(AContainerObj: GLhandleARB; AObj: GLhandleARB); cdecl;
    glCompileShaderARB: procedure(AShaderObj: GLhandleARB); cdecl;
    glCreateProgramObjectARB: function: GLhandleARB; cdecl;
    glCreateShaderObjectARB: function(AShaderType: GLenum): GLhandleARB; cdecl;
    glDeleteObjectARB: procedure(AObj: GLhandleARB); cdecl;
    glGetInfoLogARB: procedure(AObj: GLhandleARB; AMaxLength: GLsizei; ALength: PGLsizei; AInfoLog: PGLchar); cdecl;
    glGetObjectParameterivARB: procedure(AObj: GLhandleARB; APname: GLenum; AParams: PGLint); cdecl;
    glGetUniformLocationARB: function(AProgramObj: GLhandleARB; AName: PGLchar): GLint; cdecl;
    glLinkProgramARB: procedure(AProgramObj: GLhandleARB); cdecl;
    glShaderSourceARB: procedure(AShaderObj: GLhandleARB; ACount: GLsizei; AString: PPGLchar; ALength: PGLint); cdecl;
    glUniform1fARB: procedure(ALocation: GLint; A2: GLfloat); cdecl;
    glUniform1iARB: procedure(ALocation: GLint; A2: GLint); cdecl;
    glUniform3fARB: procedure(ALocation: GLint; A2: GLfloat; A3: GLfloat; A4: GLfloat); cdecl;
    glUniform4fARB: procedure(ALocation: GLint; A2: GLfloat; A3: GLfloat; A4: GLfloat; A5: GLfloat); cdecl;
    glUseProgramObjectARB: procedure(AProgramObj: GLhandleARB); cdecl;
    // ---- 拡張: FBO（グループ全部あること）
    glBindFramebufferEXT: procedure(ATarget: GLenum; AFramebuffer: GLuint); cdecl;
    glCheckFramebufferStatusEXT: function(ATarget: GLenum): GLenum; cdecl;
    glDeleteFramebuffersEXT: procedure(A1: GLsizei; AFramebuffers: PGLuint); cdecl;
    glFramebufferTexture2DEXT: procedure(ATarget: GLenum; AAttachment: GLenum; ATextarget: GLenum; ATexture: GLuint; ALevel: GLint); cdecl;
    glGenFramebuffersEXT: procedure(A1: GLsizei; AFramebuffers: PGLuint); cdecl;
    // ---- 拡張: Multitexture（グループ全部あること）
    glActiveTextureARB: procedure(ATexture: GLenum); cdecl;
    // ---- 拡張: Debug（グループ全部あること）
    glDebugMessageCallbackARB: procedure(ACallback: Pointer; AUserParam: Pointer); cdecl;
