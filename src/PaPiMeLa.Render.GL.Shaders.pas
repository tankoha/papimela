{
  PaPiMeLa.Render.GL.Shaders — デスクトップ GL のレンダラドライバが使う GLSL のシェーダ

  Origin : ported from SDL (src/render/opengl/SDL_shaders_gl.c, src/render/opengl/SDL_shaders_gl.h)
           Scope: GLSL のソース 14 種（頂点 2 種・断片 13 種。PIXELART の 3 本は #version 130）、
           シェーダの作成（矩形テクスチャか通常かで前置きを変える、tex0〜tex3 の uniform を設定）、
           拡張の判定、SDL の GL_CreateShaderContext / GL_SupportsShader / GL_SelectShader /
           GL_DestroyShaderContext、GL_SelectShader の直前の uniform の値の記憶
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §11 #44

  WHAT:
    SDL の render/opengl が使う 14 本のシェーダ（SHADER_NONE を含む）を、GL のコンテキストが現在のときに
    コンパイルしてリンクし、選ぶ。コンパイルに失敗したシェーダは Supports が False になるだけで、
    ほかのシェーダは使える。

  WHY:
    GL 2.1 の互換プロファイルは固定機能のパイプラインなので、パレット・YUV・ピクセルアートの描画には
    シェーダ（ARB の拡張）が要る。SDL と同じ GLSL のソースを使うので、見た目も SDL に揃う。

  RESOLVED:
    - GLSL のソースは SDL_shaders_gl.c の文字列を機械的に写した（手元の bb が C の文字列から
      Pascal の定数を作った。リポジトリには置いていない）。手で打ち直していない。C の文字列を
      gcc で出力したものと、Pascal の定数を出力したものを diff で突き合わせ、全文が一致した
    - 例外は YUV の 5 本（YUV、NV12 の RA と RG、NV21 の RA と RG）の最後の 1 行だけ。変換の結果を 0..1 に
      挟んでから頂点の色を掛ける（SDL は挟まずに掛ける）。ソフトウェアのドライバは先に ARGB8888 へ直して
      挟むので、色の変調と合成を掛けたとき、挟まないと飽和した色で絵が割れる（Render.GLES2 と同じ。T-22 の
      YUV の場面で 1 成分 35 割れた）。SDL の文字列との違いはこの 5 行だけ
    - 拡張の名前は glGetString(GL_EXTENSIONS) の文字列を空白で区切った語の完全一致で調べる
      （SDL_GL_ExtensionSupported は SDL の中で同じ意味）
    - 拡張の関数は ARB のシェーダのグループ 15 本を全部求める。SDL は glUniform4fARB だけ検査から
      漏れていて、無いときに NULL を呼ぶ。papimela は検査に入れ、欠けたら nil を返す（意図した違い）
    - 矩形テクスチャのモードは、GL_ARB_texture_non_power_of_two が無く、GL_ARB_texture_rectangle か
      GL_EXT_texture_rectangle がある場合（SDL と同じ）。このとき断片シェーダの頭に
      sampler2D → sampler2DRect、texture2D → texture2DRect、UVCoordScale 0.5 を置く
    - 直前の uniform の値の記憶は SDL と同じく、シェーダごとに 4 個か 16 個の Single を持ち、
      バイト列で比べる（NaN の並びが同じなら同じと見なす）

  NOT RESOLVED:
    - コンパイルの失敗の文面（SDL は SDL_LogDebug で出す）は出さない。ログの口がこのユニットに無い。
      失敗したシェーダは Supports が False になることだけで知る
    - リンクの成否（GL_OBJECT_LINK_STATUS_ARB）は SDL と同じく見ない。glGetError が GL_NO_ERROR で
      あれば、リンクに失敗したプログラムも「使える」と数える（SDL からの疑い。報告に書いた）

  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）
}
unit PaPiMeLa.Render.GL.Shaders;

{$I papimela.inc}

interface

uses
  SysUtils,
  PaPiMeLa.Platform.GL;

type
  { SDL の GL_Shader（SHADER_NONE 〜 SHADER_NV21_RG）。並びも SDL と同じ。 }
  TPMLGLShader = (
    None,
    Solid,
    PaletteNearest,
    PaletteLinear,
    PalettePixelArt,
    RGB,
    RGBPixelArt,
    RGBA,
    RGBAPixelArt,
    YUV,
    NV12_RA,
    NV12_RG,
    NV21_RA,
    NV21_RG);

  { シェーダの文脈（SDL の GL_ShaderContext）。14 本のプログラムを持つ。GL のコンテキストが現在のときに使う。 }
  TPMLGLShaderContext = class
  strict private
    FFuncs:   TPMLGLFunctions;
    FRect:    Boolean;
    FProgram: array[TPMLGLShader] of GLhandleARB;
    FVert:    array[TPMLGLShader] of GLhandleARB;
    FFrag:    array[TPMLGLShader] of GLhandleARB;
    FParams:  array[TPMLGLShader] of array of Single;
    function  CompileShader(AShader: GLhandleARB; const AVersion, ADefines, ASource: String): Boolean;
    function  CompileShaderProgram(AShader: TPMLGLShader): Boolean;
    procedure DestroyShaderProgram(AShader: TPMLGLShader);
  public
    { シェーダが使えるなら作って返す。使えなければ nil（SDL の GL_CreateShaderContext が NULL を返す所）。
      AExtensions は glGetString(GL_EXTENSIONS) の文字列。AGetProc は関数の取り方（拡張のグループ Shader を引く）。
      glUniform4fARB も含めて 15 関数が揃うことを求める。 }
    class function TryCreate(AGetProc: TPMLGLGetProc; const AExtensions: String;
      const AFuncs: TPMLGLFunctions): TPMLGLShaderContext;
    destructor Destroy; override;
    { そのシェーダがコンパイルとリンクに成功して使えるか（SDL の GL_SupportsShader）。 }
    function  Supports(AShader: TPMLGLShader): Boolean;
    { シェーダを選ぶ（SDL の GL_SelectShader）。AParams が nil でなければ、前と同じ値のときは uniform を
      設定し直さない。パレットの線形・ピクセルアート・RGB / RGBA のピクセルアートは 4 個の Single
      （texel_size）、YUV 系は 16 個の Single（Yoffset・Rcoeff・Gcoeff・Bcoeff）。AShader = None は
      プログラムを外す（UseProgramObject(0)）。 }
    procedure Select(AShader: TPMLGLShader; AParams: PSingle);
  end;

implementation

uses
  PaPiMeLa.Platform.EGL.Surfaceless;

{ ---- GLSL のソース（SDL_shaders_gl.c の文字列をそのまま。bb で機械的に写した） ----

  PORT-NOTE: C の文字列の連結（"...\n" "..."）は Pascal の + と LF（#10）に直した。
  SDL の shader_source[] の表は、頂点・断片・断片の版の 3 本の配列にした（添字は TPMLGLShader）。
  断片の版が NULL のものは空文字列にした（CompileShaderProgram で frag_version を "" にするのと同じ）。 }

const
  LF = #10;

  ColorVertexShader =
    'varying vec4 v_color;' + LF +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;' + LF +
    '    v_color = gl_Color;' + LF +
    '}';

  TextureVertexShader =
    'varying vec4 v_color;' + LF +
    'varying vec2 v_texCoord;' + LF +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;' + LF +
    '    v_color = gl_Color;' + LF +
    '    v_texCoord = vec2(gl_MultiTexCoord0);' + LF +
    '}';

  RgbShaderPrologue =
    'varying vec4 v_color;' + LF +
    'varying vec2 v_texCoord;' + LF +
    'uniform sampler2D tex0;' + LF +
    LF;

  RgbPixelartShaderPrologue =
    'varying vec4 v_color;' + LF +
    'varying vec2 v_texCoord;' + LF +
    'uniform sampler2D tex0;' + LF +
    'uniform vec4 texel_size; // texel size (xy: texel size, zw: texture dimensions)' + LF +
    LF;

  PaletteShaderPrologue =
    'varying vec4 v_color;' + LF +
    'varying vec2 v_texCoord;' + LF +
    'uniform sampler2D tex0;' + LF +
    'uniform sampler2D tex1;' + LF +
    'uniform vec4 texel_size; // texel size (xy: texel size, zw: texture dimensions)' + LF +
    LF;

  PaletteShaderFunctions =
    'vec4 SamplePaletteNearest(vec2 uv)' + LF +
    '{' + LF +
    '    float index = texture2D(tex0, uv).r * 255.0;' + LF +
    '    return texture2D(tex1, vec2((index + 0.5) / 256.0, 0.5));' + LF +
    '}' + LF +
    LF +
    'vec4 SamplePaletteLinear(vec2 uv)' + LF +
    '{' + LF +
    '    // scale & offset uvs to integer values at texel centers' + LF +
    '    vec2 uv_texels = uv * texel_size.zw + 0.5;' + LF +
    LF +
    '    // get uvs for the center of the 4 surrounding texels by flooring' + LF +
    '    vec4 uv_min_max = vec4((floor(uv_texels) - 0.5) * texel_size.xy, (floor(uv_texels) + 0.5) * texel_size.xy);' + LF +
    LF +
    '    // blend factor' + LF +
    '    vec2 uv_frac = fract(uv_texels);' + LF +
    LF +
    '    // sample all 4 texels' + LF +
    '    vec4 texelA = SamplePaletteNearest(uv_min_max.xy);' + LF +
    '    vec4 texelB = SamplePaletteNearest(uv_min_max.xw);' + LF +
    '    vec4 texelC = SamplePaletteNearest(uv_min_max.zy);' + LF +
    '    vec4 texelD = SamplePaletteNearest(uv_min_max.zw);' + LF +
    LF +
    '    // bilinear interpolation' + LF +
    '    return mix(mix(texelA, texelB, uv_frac.y), mix(texelC, texelD, uv_frac.y), uv_frac.x);' + LF +
    '}' + LF +
    LF;

  PixelartShaderFunctions =
    'vec2 GetPixelArtUV(vec2 uv)' + LF +
    '{' + LF +
    '    vec2 boxSize = clamp(fwidth(uv) * texel_size.zw, 1e-5, 1.0);' + LF +
    '    vec2 tx = uv * texel_size.zw - 0.5 * boxSize;' + LF +
    '    vec2 txOffset = smoothstep(vec2(1.0) - boxSize, vec2(1.0), fract(tx));' + LF +
    '    return (floor(tx) + 0.5 + txOffset) * texel_size.xy;' + LF +
    '}' + LF +
    LF +
    'vec4 GetPixelArtSample(vec2 uv)' + LF +
    '{' + LF +
    '    return textureGrad(tex0, GetPixelArtUV(uv), dFdx(v_texCoord), dFdy(v_texCoord));' + LF +
    '}' + LF +
    LF;

  YuvShaderPrologue =
    'varying vec4 v_color;' + LF +
    'varying vec2 v_texCoord;' + LF +
    'uniform sampler2D tex0; // Y ' + LF +
    'uniform sampler2D tex1; // U ' + LF +
    'uniform sampler2D tex2; // V ' + LF +
    'uniform vec3 Yoffset;' + LF +
    'uniform vec3 Rcoeff;' + LF +
    'uniform vec3 Gcoeff;' + LF +
    'uniform vec3 Bcoeff;' + LF +
    LF;

  YuvShaderBody =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    vec2 tcoord;' + LF +
    '    vec3 yuv, rgb;' + LF +
    LF +
    '    // Get the Y value ' + LF +
    '    tcoord = v_texCoord;' + LF +
    '    yuv.x = texture2D(tex0, tcoord).r;' + LF +
    LF +
    '    // Get the U and V values ' + LF +
    '    tcoord *= UVCoordScale;' + LF +
    '    yuv.y = texture2D(tex1, tcoord).r;' + LF +
    '    yuv.z = texture2D(tex2, tcoord).r;' + LF +
    LF +
    '    // Do the color transform ' + LF +
    '    yuv += Yoffset;' + LF +
    '    rgb.r = dot(yuv, Rcoeff);' + LF +
    '    rgb.g = dot(yuv, Gcoeff);' + LF +
    '    rgb.b = dot(yuv, Bcoeff);' + LF +
    LF +
    '    // That was easy. :) ' + LF +
    '    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * v_color;' + LF +
    '}';

  Nv12ShaderPrologue =
    'varying vec4 v_color;' + LF +
    'varying vec2 v_texCoord;' + LF +
    'uniform sampler2D tex0; // Y ' + LF +
    'uniform sampler2D tex1; // U/V ' + LF +
    'uniform vec3 Yoffset;' + LF +
    'uniform vec3 Rcoeff;' + LF +
    'uniform vec3 Gcoeff;' + LF +
    'uniform vec3 Bcoeff;' + LF +
    LF;

  Nv12RaShaderBody =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    vec2 tcoord;' + LF +
    '    vec3 yuv, rgb;' + LF +
    LF +
    '    // Get the Y value ' + LF +
    '    tcoord = v_texCoord;' + LF +
    '    yuv.x = texture2D(tex0, tcoord).r;' + LF +
    LF +
    '    // Get the U and V values ' + LF +
    '    tcoord *= UVCoordScale;' + LF +
    '    yuv.yz = texture2D(tex1, tcoord).ra;' + LF +
    LF +
    '    // Do the color transform ' + LF +
    '    yuv += Yoffset;' + LF +
    '    rgb.r = dot(yuv, Rcoeff);' + LF +
    '    rgb.g = dot(yuv, Gcoeff);' + LF +
    '    rgb.b = dot(yuv, Bcoeff);' + LF +
    LF +
    '    // That was easy. :) ' + LF +
    '    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * v_color;' + LF +
    '}';

  Nv12RgShaderBody =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    vec2 tcoord;' + LF +
    '    vec3 yuv, rgb;' + LF +
    LF +
    '    // Get the Y value ' + LF +
    '    tcoord = v_texCoord;' + LF +
    '    yuv.x = texture2D(tex0, tcoord).r;' + LF +
    LF +
    '    // Get the U and V values ' + LF +
    '    tcoord *= UVCoordScale;' + LF +
    '    yuv.yz = texture2D(tex1, tcoord).rg;' + LF +
    LF +
    '    // Do the color transform ' + LF +
    '    yuv += Yoffset;' + LF +
    '    rgb.r = dot(yuv, Rcoeff);' + LF +
    '    rgb.g = dot(yuv, Gcoeff);' + LF +
    '    rgb.b = dot(yuv, Bcoeff);' + LF +
    LF +
    '    // That was easy. :) ' + LF +
    '    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * v_color;' + LF +
    '}';

  Nv21RaShaderBody =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    vec2 tcoord;' + LF +
    '    vec3 yuv, rgb;' + LF +
    LF +
    '    // Get the Y value ' + LF +
    '    tcoord = v_texCoord;' + LF +
    '    yuv.x = texture2D(tex0, tcoord).r;' + LF +
    LF +
    '    // Get the U and V values ' + LF +
    '    tcoord *= UVCoordScale;' + LF +
    '    yuv.yz = texture2D(tex1, tcoord).ar;' + LF +
    LF +
    '    // Do the color transform ' + LF +
    '    yuv += Yoffset;' + LF +
    '    rgb.r = dot(yuv, Rcoeff);' + LF +
    '    rgb.g = dot(yuv, Gcoeff);' + LF +
    '    rgb.b = dot(yuv, Bcoeff);' + LF +
    LF +
    '    // That was easy. :) ' + LF +
    '    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * v_color;' + LF +
    '}';

  Nv21RgShaderBody =
    LF +
    'void main()' + LF +
    '{' + LF +
    '    vec2 tcoord;' + LF +
    '    vec3 yuv, rgb;' + LF +
    LF +
    '    // Get the Y value ' + LF +
    '    tcoord = v_texCoord;' + LF +
    '    yuv.x = texture2D(tex0, tcoord).r;' + LF +
    LF +
    '    // Get the U and V values ' + LF +
    '    tcoord *= UVCoordScale;' + LF +
    '    yuv.yz = texture2D(tex1, tcoord).gr;' + LF +
    LF +
    '    // Do the color transform ' + LF +
    '    yuv += Yoffset;' + LF +
    '    rgb.r = dot(yuv, Rcoeff);' + LF +
    '    rgb.g = dot(yuv, Gcoeff);' + LF +
    '    rgb.b = dot(yuv, Bcoeff);' + LF +
    LF +
    '    // That was easy. :) ' + LF +
    '    gl_FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * v_color;' + LF +
    '}';

  FragmentSolid =
    'varying vec4 v_color;' + LF +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = v_color;' + LF +
    '}';

  FragmentPaletteNearest =
    PaletteShaderPrologue +
    PaletteShaderFunctions +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = SamplePaletteNearest(v_texCoord) * v_color;' + LF +
    '}';

  FragmentPaletteLinear =
    PaletteShaderPrologue +
    PaletteShaderFunctions +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = SamplePaletteLinear(v_texCoord) * v_color;' + LF +
    '}';

  FragmentPalettePixelart =
    PaletteShaderPrologue +
    PaletteShaderFunctions +
    PixelartShaderFunctions +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = SamplePaletteLinear(GetPixelArtUV(v_texCoord)) * v_color;' + LF +
    '}';

  FragmentRgb =
    RgbShaderPrologue +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = texture2D(tex0, v_texCoord);' + LF +
    '    gl_FragColor.a = 1.0;' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}';

  FragmentRgbPixelart =
    RgbPixelartShaderPrologue +
    PixelartShaderFunctions +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = GetPixelArtSample(v_texCoord);' + LF +
    '    gl_FragColor.a = 1.0;' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}';

  FragmentRgba =
    RgbShaderPrologue +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = texture2D(tex0, v_texCoord) * v_color;' + LF +
    '}';

  FragmentRgbaPixelart =
    RgbPixelartShaderPrologue +
    PixelartShaderFunctions +
    LF +
    'void main()' + LF +
    '{' + LF +
    '    gl_FragColor = GetPixelArtSample(v_texCoord);' + LF +
    '    gl_FragColor *= v_color;' + LF +
    '}';

  FragmentYuv =
    YuvShaderPrologue +
    YuvShaderBody;

  FragmentNv12Ra =
    Nv12ShaderPrologue +
    Nv12RaShaderBody;

  FragmentNv12Rg =
    Nv12ShaderPrologue +
    Nv12RgShaderBody;

  FragmentNv21Ra =
    Nv12ShaderPrologue +
    Nv21RaShaderBody;

  FragmentNv21Rg =
    Nv12ShaderPrologue +
    Nv21RgShaderBody;

  FragmentVersionSolid = '';
  FragmentVersionPaletteNearest = '';
  FragmentVersionPaletteLinear = '';
  FragmentVersionPalettePixelart = '#version 130' + LF;
  FragmentVersionRgb = '';
  FragmentVersionRgbPixelart = '#version 130' + LF;
  FragmentVersionRgba = '';
  FragmentVersionRgbaPixelart = '#version 130' + LF;
  FragmentVersionYuv = '';
  FragmentVersionNv12Ra = '';
  FragmentVersionNv12Rg = '';
  FragmentVersionNv21Ra = '';
  FragmentVersionNv21Rg = '';

  VertexSolid = ColorVertexShader;
  VertexPaletteNearest = TextureVertexShader;
  VertexPaletteLinear = TextureVertexShader;
  VertexPalettePixelart = TextureVertexShader;
  VertexRgb = TextureVertexShader;
  VertexRgbPixelart = TextureVertexShader;
  VertexRgba = TextureVertexShader;
  VertexRgbaPixelart = TextureVertexShader;
  VertexYuv = TextureVertexShader;
  VertexNv12Ra = TextureVertexShader;
  VertexNv12Rg = TextureVertexShader;
  VertexNv21Ra = TextureVertexShader;
  VertexNv21Rg = TextureVertexShader;

  { SDL の shader_source[]。SHADER_NONE は NULL ばかり（空文字列）。 }
  VertexSources: array[TPMLGLShader] of String = (
    '', VertexSolid, VertexPaletteNearest, VertexPaletteLinear, VertexPalettePixelart,
    VertexRgb, VertexRgbPixelart, VertexRgba, VertexRgbaPixelart, VertexYuv,
    VertexNv12Ra, VertexNv12Rg, VertexNv21Ra, VertexNv21Rg);

  FragmentSources: array[TPMLGLShader] of String = (
    '', FragmentSolid, FragmentPaletteNearest, FragmentPaletteLinear, FragmentPalettePixelart,
    FragmentRgb, FragmentRgbPixelart, FragmentRgba, FragmentRgbaPixelart, FragmentYuv,
    FragmentNv12Ra, FragmentNv12Rg, FragmentNv21Ra, FragmentNv21Rg);

  FragmentVersions: array[TPMLGLShader] of String = (
    '', FragmentVersionSolid, FragmentVersionPaletteNearest, FragmentVersionPaletteLinear,
    FragmentVersionPalettePixelart, FragmentVersionRgb, FragmentVersionRgbPixelart,
    FragmentVersionRgba, FragmentVersionRgbaPixelart, FragmentVersionYuv,
    FragmentVersionNv12Ra, FragmentVersionNv12Rg, FragmentVersionNv21Ra, FragmentVersionNv21Rg);

  // SDL の num_tmus_bound。tex0〜tex3 に 0〜3 を設定する
  NUM_TMUS_BOUND = 4;

  RectDefines =
    '#define sampler2D sampler2DRect' + LF +
    '#define texture2D texture2DRect' + LF +
    '#define UVCoordScale 0.5' + LF;
  PlainDefines =
    '#define UVCoordScale 1.0' + LF;

{ SDL の GL_SelectShader が texel_size（4 個）を使うシェーダ }
function UsesTexelSize(AShader: TPMLGLShader): Boolean;
begin
  Result := AShader in [TPMLGLShader.PaletteLinear, TPMLGLShader.PalettePixelArt,
    TPMLGLShader.RGBPixelArt, TPMLGLShader.RGBAPixelArt];
end;

{ uniform の値の長さ（Single の個数）。SDL の shader_params_len / sizeof(float) }
function ParamCount(AShader: TPMLGLShader): Integer;
begin
  if UsesTexelSize(AShader) then
    Result := 4
  else if Ord(AShader) >= Ord(TPMLGLShader.YUV) then
    Result := 16
  else
    Result := 0;
end;

{ SDL_GL_ExtensionSupported 相当（AExtensions は glGetString(GL_EXTENSIONS)）。 }
function HasExt(const AExtensions, AName: String): Boolean;
begin
  Result := PMLEGLHasExtension(AExtensions, AName);
end;

{ ---- TPMLGLShaderContext ---- }

class function TPMLGLShaderContext.TryCreate(AGetProc: TPMLGLGetProc; const AExtensions: String;
  const AFuncs: TPMLGLFunctions): TPMLGLShaderContext;
var
  Funcs: TPMLGLFunctions;
  Rect: Boolean;
  Shader: TPMLGLShader;
begin
  Result := nil;

  Rect := (not HasExt(AExtensions, 'GL_ARB_texture_non_power_of_two')) and
    (HasExt(AExtensions, 'GL_ARB_texture_rectangle') or HasExt(AExtensions, 'GL_EXT_texture_rectangle'));

  if not (HasExt(AExtensions, 'GL_ARB_shader_objects') and
          HasExt(AExtensions, 'GL_ARB_shading_language_100') and
          HasExt(AExtensions, 'GL_ARB_vertex_shader') and
          HasExt(AExtensions, 'GL_ARB_fragment_shader')) then
    Exit;
  // glGetError はコアの表から（SDL は SDL_GL_GetProcAddress("glGetError")）
  if not Assigned(AFuncs.glGetError) then
    Exit;
  Funcs := AFuncs;
  // PORT-NOTE: SDL は glUniform4fARB だけ検査に入れていない。papimela はグループの 15 本全部を求める
  if PMLLoadGLExtFunctions(AGetProc, Funcs, TPMLGLExtGroup.Shader) <> '' then
    Exit;

  Result := TPMLGLShaderContext.Create;
  try
    Result.FFuncs := Funcs;
    Result.FRect := Rect;
    // すべてのシェーダをコンパイルする。失敗したものは壊して、使えないことにする
    for Shader := Succ(TPMLGLShader.None) to High(TPMLGLShader) do
      if not Result.CompileShaderProgram(Shader) then
        Result.DestroyShaderProgram(Shader);
  except
    Result.Free;
    raise;
  end;
end;

destructor TPMLGLShaderContext.Destroy;
var
  Shader: TPMLGLShader;
begin
  // 作りかけ（TryCreate の途中）でも呼べるよう、ハンドルが 0 のものは何もしない
  if Assigned(FFuncs.glDeleteObjectARB) then
    for Shader := Low(TPMLGLShader) to High(TPMLGLShader) do
    begin
      DestroyShaderProgram(Shader);
      FParams[Shader] := nil;
    end;
  inherited Destroy;
end;

{ SDL の CompileShader。version / defines / source の 3 本を 1 つのシェーダにして、成否を返す。
  PORT-NOTE: SDL は失敗のとき SDL_LogDebug で文面を出す。ここでは出さない（NOT RESOLVED を参照）。 }
function TPMLGLShaderContext.CompileShader(AShader: GLhandleARB; const AVersion, ADefines,
  ASource: String): Boolean;
var
  Sources: array[0..2] of PGLchar;
  Status: GLint;
begin
  Sources[0] := PGLchar(PAnsiChar(AVersion));
  Sources[1] := PGLchar(PAnsiChar(ADefines));
  Sources[2] := PGLchar(PAnsiChar(ASource));

  FFuncs.glShaderSourceARB(AShader, Length(Sources), @Sources[0], nil);
  FFuncs.glCompileShaderARB(AShader);
  Status := 0;
  FFuncs.glGetObjectParameterivARB(AShader, GL_OBJECT_COMPILE_STATUS_ARB, @Status);
  Result := Status <> 0;
end;

{ SDL の CompileShaderProgram。SHADER_NONE は何もせず True。 }
function TPMLGLShaderContext.CompileShaderProgram(AShader: TPMLGLShader): Boolean;
var
  Defines: String;
  I: Integer;
  Location: GLint;
  TexName: AnsiString;
begin
  if AShader = TPMLGLShader.None then
    Exit(True);

  FFuncs.glGetError();

  // 使うテクスチャの型に合わせて sampler の型を選ぶ（ソースは常に sampler2D で書いてある）
  if FRect then
    Defines := RectDefines
  else
    Defines := PlainDefines;

  // プログラムを 1 つ作る
  FProgram[AShader] := FFuncs.glCreateProgramObjectARB();

  // 頂点シェーダ
  FVert[AShader] := FFuncs.glCreateShaderObjectARB(GL_VERTEX_SHADER_ARB);
  if not CompileShader(FVert[AShader], '', '', VertexSources[AShader]) then
    Exit(False);

  // 断片シェーダ
  FFrag[AShader] := FFuncs.glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB);
  if not CompileShader(FFrag[AShader], FragmentVersions[AShader], Defines, FragmentSources[AShader]) then
    Exit(False);

  // 2 つをプログラムに付けてリンクする
  FFuncs.glAttachObjectARB(FProgram[AShader], FVert[AShader]);
  FFuncs.glAttachObjectARB(FProgram[AShader], FFrag[AShader]);
  FFuncs.glLinkProgramARB(FProgram[AShader]);

  // sampler の uniform（tex0〜tex3）にテクスチャユニットの番号を設定する
  FFuncs.glUseProgramObjectARB(FProgram[AShader]);
  for I := 0 to NUM_TMUS_BOUND - 1 do
  begin
    TexName := AnsiString(Format('tex%d', [I]));
    Location := FFuncs.glGetUniformLocationARB(FProgram[AShader], PGLchar(PAnsiChar(TexName)));
    if Location >= 0 then
      FFuncs.glUniform1iARB(Location, I);
  end;
  FFuncs.glUseProgramObjectARB(0);

  Result := FFuncs.glGetError() = GL_NO_ERROR;
end;

procedure TPMLGLShaderContext.DestroyShaderProgram(AShader: TPMLGLShader);
begin
  if FVert[AShader] <> 0 then
  begin
    FFuncs.glDeleteObjectARB(FVert[AShader]);
    FVert[AShader] := 0;
  end;
  if FFrag[AShader] <> 0 then
  begin
    FFuncs.glDeleteObjectARB(FFrag[AShader]);
    FFrag[AShader] := 0;
  end;
  if FProgram[AShader] <> 0 then
  begin
    FFuncs.glDeleteObjectARB(FProgram[AShader]);
    FProgram[AShader] := 0;
  end;
end;

function TPMLGLShaderContext.Supports(AShader: TPMLGLShader): Boolean;
begin
  Result := FProgram[AShader] <> 0;
end;

procedure TPMLGLShaderContext.Select(AShader: TPMLGLShader; AParams: PSingle);
var
  Prog: GLhandleARB;
  Len: Integer;
  P: array[0..15] of Single;
  Location: GLint;

  procedure SetUniform3(const AName: AnsiString; AFirst: Integer);
  begin
    Location := FFuncs.glGetUniformLocationARB(Prog, PGLchar(PAnsiChar(AName)));
    if Location >= 0 then
      FFuncs.glUniform3fARB(Location, P[AFirst], P[AFirst + 1], P[AFirst + 2]);
  end;

begin
  Prog := FProgram[AShader];
  FFuncs.glUseProgramObjectARB(Prog);

  Len := ParamCount(AShader);
  Assert((AParams = nil) or (Len > 0), 'Select: this shader takes no parameters');
  if (AParams = nil) or (Len = 0) then
    Exit;

  // 直前と同じ値なら何もしない（SDL の SDL_memcmp。バイト列の比較）
  if (Length(FParams[AShader]) = Len) and
     CompareMem(AParams, @FParams[AShader][0], Len * SizeOf(Single)) then
    Exit;

  Move(AParams^, P[0], Len * SizeOf(Single));

  if UsesTexelSize(AShader) then
  begin
    Location := FFuncs.glGetUniformLocationARB(Prog, 'texel_size');
    if Location >= 0 then
      FFuncs.glUniform4fARB(Location, P[0], P[1], P[2], P[3]);
  end;

  if Ord(AShader) >= Ord(TPMLGLShader.YUV) then
  begin
    // YUV の AParams は Yoffset, 0, Rcoeff, 0, Gcoeff, 0, Bcoeff, 0（vec3 を 4 個ずつ詰めた並び）
    SetUniform3('Yoffset', 0);
    SetUniform3('Rcoeff', 4);
    SetUniform3('Gcoeff', 8);
    SetUniform3('Bcoeff', 12);
  end;

  // PORT-NOTE: SDL は malloc に失敗すると記憶しない。動的配列なので失敗は例外になる
  SetLength(FParams[AShader], Len);
  Move(AParams^, FParams[AShader][0], Len * SizeOf(Single));
end;

end.
