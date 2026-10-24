#!/usr/bin/env bb
;; gengl — デスクトップ OpenGL の定数と関数表を、SDL と GL のヘッダから Pascal へ写す。
;;
;; なぜ要るか:
;;   Render.GL（設計 #44）は SDL の render/opengl/ の移植で、SDL が使う GL の定数と関数だけを持つ。
;;   手で写すと写し間違える（CLAUDE.md: 大きな表は手にも qwen にも写させない）。
;;   reference/SDL の khronos には GL/ のヘッダが無い（GLES / GLES2 / GLES3 だけ）ので、定数の値と
;;   ARB / EXT 関数の型は、システムの GL/gl.h と GL/glext.h から取る。
;;
;; 使い方:
;;   tools/gengl.bb <GL ヘッダのある include ディレクトリ>
;;     ディレクトリは GL/gl.h と GL/glext.h を持つ所。システムに無ければ、開発用の .deb を
;;     スクラッチに展開して使う（docs/ORIGIN.md の「GL のヘッダ」）:
;;       apt-get download libgl-dev mesa-common-dev && for d in *.deb; do dpkg-deb -x $d root; done
;;       tools/gengl.bb root/usr/include
;;
;; 書くもの:
;;   src/generated/gl_constants.inc   定数（SDL の SDL_render_gl.c / SDL_shaders_gl.c が使う GL_ の名前。
;;                                    Apple 専用の名前と、SDL 自身のマクロは含まない）
;;   src/generated/gl_functions.inc   関数表のフィールド（コア = reference/SDL の SDL_glfuncs.h の有効な行。
;;                                    拡張 = SDL が PFN...PROC の型で使う ARB / EXT。glext.h の型から）
;;   src/generated/gl_bind_core.inc  PMLLoadGLFunctions の本文（コア）
;;   src/generated/gl_bind_<グループ>.inc  グループごとの本文（拡張。shader・fbo・multitexture・debug）
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 並べた定数がどれも GL ヘッダで見つかる（見つからない名前は名前を出して止まる）
;;   - 書いた定数・関数の件数が、元の一覧の件数と同じ
;;   - C の型がすべて対応表で解ける（解けない型は名前を出して止まる）
;;   - 同じ入力からは同じファイルができる（時刻などを書かない）

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private sdl-dir "reference/SDL/src/render/opengl")
(def ^:private out-dir "src/generated")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gengl: " msg)))
  (System/exit 1))

(def ^:private inc-dir (first *command-line-args*))
(when-not inc-dir (fail "GL ヘッダのある include ディレクトリを渡す"))
(def ^:private gl-h (str inc-dir "/GL/gl.h"))
(def ^:private glext-h (str inc-dir "/GL/glext.h"))
(doseq [p [gl-h glext-h (str sdl-dir "/SDL_glfuncs.h")]]
  (when-not (fs/exists? p) (fail p " が無い")))

;; ---- 定数。SDL の 2 つの .c が使う GL_ の名前から、Apple 専用と SDL のマクロを除いたもの

(def ^:private constant-names
  (str/split "GL_BGRA GL_BLEND GL_CLAMP_TO_EDGE GL_COLOR_ARRAY GL_COLOR_ATTACHMENT0_EXT GL_COLOR_BUFFER_BIT GL_CULL_FACE
GL_DEBUG_CALLBACK_FUNCTION_ARB GL_DEBUG_CALLBACK_USER_PARAM_ARB GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB GL_DEBUG_TYPE_ERROR_ARB
GL_DEPTH_TEST GL_DST_ALPHA GL_DST_COLOR GL_FALSE GL_FLOAT GL_FRAGMENT_SHADER_ARB GL_FRAMEBUFFER_COMPLETE_EXT
GL_FRAMEBUFFER_EXT GL_FRAMEBUFFER_SRGB GL_FUNC_ADD GL_FUNC_REVERSE_SUBTRACT GL_FUNC_SUBTRACT GL_INVALID_ENUM
GL_INVALID_OPERATION GL_INVALID_VALUE GL_LINEAR GL_LINES GL_LINE_SMOOTH GL_LINE_STRIP GL_LUMINANCE GL_LUMINANCE_ALPHA
GL_MAX GL_MAX_RECTANGLE_TEXTURE_SIZE_ARB GL_MAX_TEXTURE_SIZE GL_MAX_TEXTURE_UNITS_ARB GL_MIN GL_MODELVIEW GL_NEAREST
GL_NO_ERROR GL_OBJECT_COMPILE_STATUS_ARB GL_OBJECT_INFO_LOG_LENGTH_ARB GL_ONE GL_ONE_MINUS_DST_ALPHA
GL_ONE_MINUS_DST_COLOR GL_ONE_MINUS_SRC_ALPHA GL_ONE_MINUS_SRC_COLOR GL_OUT_OF_MEMORY GL_PACK_ALIGNMENT
GL_PACK_ROW_LENGTH GL_POINTS GL_PROJECTION GL_REPEAT GL_RGB8 GL_RGBA GL_RGBA8 GL_SCISSOR_TEST GL_SRC_ALPHA GL_SRC_COLOR
GL_STACK_OVERFLOW GL_STACK_UNDERFLOW GL_TABLE_TOO_LARGE GL_TEXTURE0 GL_TEXTURE0_ARB GL_TEXTURE1 GL_TEXTURE1_ARB
GL_TEXTURE2 GL_TEXTURE2_ARB GL_TEXTURE_2D GL_TEXTURE_COORD_ARRAY GL_TEXTURE_MAG_FILTER GL_TEXTURE_MIN_FILTER
GL_TEXTURE_RECTANGLE_ARB GL_TEXTURE_WRAP_S GL_TEXTURE_WRAP_T GL_TRIANGLES GL_TRUE GL_UNPACK_ALIGNMENT
GL_UNPACK_ROW_LENGTH GL_UNSIGNED_BYTE GL_UNSIGNED_INT_8_8_8_8_REV GL_VERSION GL_VERTEX_ARRAY GL_VERTEX_SHADER_ARB GL_ZERO"
             #"\s+"))

(defn- read-defines [path]
  (into {} (for [[_ n v] (re-seq #"(?m)^#define (GL_[A-Za-z0-9_]+)\s+(0x[0-9A-Fa-f]+|[0-9]+)\s*(?:/\*.*)?$" (slurp path))]
             [n v])))

(def ^:private defines (merge (read-defines glext-h) (read-defines gl-h)))

(defn- pascal-const [v]
  (if (str/starts-with? v "0x") (str "$" (str/upper-case (subs v 2))) v))

(def ^:private constants
  (vec (for [n constant-names]
         (if-let [v (get defines n)]
           [n (pascal-const v)]
           (fail "GL のヘッダに無い定数: " n)))))

;; ---- 型の対応表（C → Pascal。Platform.GL の型名）

(def ^:private scalar-types
  {"GLenum" "GLenum" "GLbitfield" "GLbitfield" "GLuint" "GLuint" "GLint" "GLint" "GLsizei" "GLsizei"
   "GLfloat" "GLfloat" "GLclampf" "GLclampf" "GLdouble" "GLdouble" "GLclampd" "GLclampd"
   "GLboolean" "GLboolean" "GLubyte" "GLubyte" "GLhandleARB" "GLhandleARB" "GLcharARB" "GLchar" "GLchar" "GLchar"
   "GLsizeiptr" "GLsizeiptr" "GLDEBUGPROCARB" "Pointer"})

(def ^:private pointer-types
  {"GLint" "PGLint" "GLuint" "PGLuint" "GLsizei" "PGLsizei" "GLfloat" "PGLfloat" "GLdouble" "PGLdouble"
   "GLubyte" "PGLubyte" "GLcharARB" "PGLchar" "GLchar" "PGLchar" "GLenum" "PGLenum"})

(defn- map-type
  "C の型（const とパラメータ名を除いたもの）を Pascal の型名にする。"
  [ctype]
  (let [stars (count (re-seq #"\*" ctype))
        base (-> ctype (str/replace "*" "") (str/replace #"\bconst\b" "") str/trim)]
    (cond
      (and (= base "void") (zero? stars)) :void
      (and (contains? #{"void" "GLvoid"} base) (pos? stars)) "Pointer"
      (and (zero? stars) (contains? scalar-types base)) (scalar-types base)
      (and (= stars 1) (contains? pointer-types base)) (pointer-types base)
      (and (= stars 2) (contains? #{"GLcharARB" "GLchar"} base)) "PPGLchar"
      :else (fail "型を解けない: " ctype))))

(defn- param-list [s]
  (let [s (str/trim s)]
    (if (or (str/blank? s) (= s "void")) [] (mapv str/trim (str/split s #",")))))

;; パラメータの C の宣言（「型 名前」または型だけ）から [型 名前または nil] を取る
(defn- split-param [p]
  (let [p (str/replace p #"\s+" " ")
        m (re-matches #"(.*?[\s\*])([A-Za-z_][A-Za-z0-9_]*)$" p)]
    (if (and m (not (contains? (into #{} (concat (keys scalar-types) ["void" "const"])) (nth m 2))))
      [(str/trim (nth m 1)) (nth m 2)]
      [(str/trim p) nil])))

(defn- pascal-param-name [i name]
  ;; 1〜2 字の名前は、"A" を付けると予約語（as）になるものがあるので、位置の名前にする
  (if (and name (> (count name) 2))
    (str "A" (str/upper-case (subs name 0 1)) (subs name 1))
    (str "A" (inc i))))

(defn- field [fname ret params]
  (let [ptypes (map-type ret)
        ps (map-indexed (fn [i p]
                          (let [[t n] (split-param p)]
                            (str (pascal-param-name i n) ": " (map-type t))))
                        params)
        sig (if (empty? ps) "" (str "(" (str/join "; " ps) ")"))]
    (if (= ptypes :void)
      (str "    " fname ": procedure" sig "; cdecl;")
      (str "    " fname ": function" sig ": " ptypes "; cdecl;"))))

;; ---- コア: SDL_glfuncs.h の有効な行（SDL_PROC）。複数行にまたがるものがある

(def ^:private core
  (let [text (slurp (str sdl-dir "/SDL_glfuncs.h"))
        ;; SDL_PROC( で始まり、閉じ括弧のあとの改行まで
        entries (re-seq #"(?m)^SDL_PROC\((.*?),\s*(gl[A-Za-z0-9_]+),\s*\((.*?)\)\)\s*$" text)
        entries2 (re-seq #"(?s)(?m)^SDL_PROC\(([^,\n]+),\s*(gl[A-Za-z0-9_]+),\s*\(((?:[^()]|\n)*?)\)\)" text)]
    (vec (for [[_ ret fname params] entries2]
           {:name fname :ret (str/trim ret) :params (param-list (str/replace params #"\s+" " "))}))))

(def ^:private unused-count
  (count (re-seq #"(?m)^SDL_PROC_UNUSED\(" (slurp (str sdl-dir "/SDL_glfuncs.h")))))
(def ^:private proc-count
  (count (re-seq #"(?m)^SDL_PROC\(" (slurp (str sdl-dir "/SDL_glfuncs.h")))))
(when-not (= (count core) proc-count)
  (fail "コアの関数を " (count core) " 件読んだ（SDL_PROC は " proc-count " 件）"))

;; ---- 拡張: SDL が PFN...PROC で使うもの。グループは SDL の使い方（shaders_gl.c / render_gl.c）に合わせる

(def ^:private ext-groups
  [["Shader"
    ["glAttachObjectARB" "glCompileShaderARB" "glCreateProgramObjectARB" "glCreateShaderObjectARB" "glDeleteObjectARB"
     "glGetInfoLogARB" "glGetObjectParameterivARB" "glGetUniformLocationARB" "glLinkProgramARB" "glShaderSourceARB"
     "glUniform1fARB" "glUniform1iARB" "glUniform3fARB" "glUniform4fARB" "glUseProgramObjectARB"]]
   ["FBO"
    ["glBindFramebufferEXT" "glCheckFramebufferStatusEXT" "glDeleteFramebuffersEXT" "glFramebufferTexture2DEXT"
     "glGenFramebuffersEXT"]]
   ["Multitexture" ["glActiveTextureARB"]]
   ["Debug" ["glDebugMessageCallbackARB"]]])

(def ^:private glext-text (slurp glext-h))

(defn- ext-entry [fname]
  (let [pfn (str "PFN" (str/upper-case fname) "PROC")
        m (re-find (re-pattern (str "typedef\\s+(.*?)\\s*\\(APIENTRYP\\s+" pfn "\\)\\s*\\((.*?)\\);")) glext-text)]
    (when-not m (fail "glext.h に型が無い: " pfn))
    {:name fname :ret (str/trim (nth m 1)) :params (param-list (str/replace (nth m 2) #"\s+" " "))}))

(def ^:private ext
  (vec (for [[g names] ext-groups] [g (mapv ext-entry names)])))

;; ---- 書く

(defn- ->field [{:keys [name ret params]}] (field name ret params))

(def ^:private functions-text
  (str "{ src/generated/gl_functions.inc — tools/gengl.bb が作る。手で直さない。\n"
       "  デスクトップ OpenGL の関数表のフィールド。コアは SDL_glfuncs.h の有効な行（" (count core) " 件）、\n"
       "  拡張は SDL が使う ARB / EXT の関数（" (reduce + (map (comp count second) ext)) " 件）。 }\n"
       "    // ---- コア（全部あること）\n"
       (str/join "\n" (map ->field core)) "\n"
       (apply str (for [[g es] ext]
                    (str "    // ---- 拡張: " g "（グループ全部あること）\n"
                         (str/join "\n" (map ->field es)) "\n")))))

(defn- bind-lines [entries]
  (str (str/join "\n" (for [{:keys [name]} entries] (format "  Bind(AFuncs.%s, '%s');" name name))) "\n"))

(def ^:private bind-files
  (into {"core" (bind-lines core)}
        (for [[g es] ext] [(str/lower-case g) (bind-lines es)])))

(def ^:private constants-text
  (str "{ src/generated/gl_constants.inc — tools/gengl.bb が作る。手で直さない。\n"
       "  SDL の render/opengl が使う GL の定数（" (count constants) " 件）。値は GL/gl.h と GL/glext.h から。 }\n"
       (apply str (for [[n v] constants] (format "  %s = %s;\n" n v)))))

;; 書いた行数を、本文から数え直して確かめる
(when-not (= (count (re-seq #"(?m)^  GL_[A-Z0-9_]+ = (?:\$[0-9A-F]+|[0-9]+);$" constants-text)) (count constant-names))
  (fail "書いた定数の件数が名前の数と違う"))
(when-not (= (count (re-seq #"(?m)^    gl[A-Za-z0-9_]+: (?:procedure|function)" functions-text))
             (+ (count core) (reduce + (map (comp count second) ext))))
  (fail "書いた関数の件数が元の一覧と違う"))
(when-not (= (reduce + (for [t (vals bind-files)] (count (re-seq #"(?m)^  Bind\(" t))))
             (+ (count core) (reduce + (map (comp count second) ext))))
  (fail "書いた Bind の件数が元の一覧と違う"))

(spit (str out-dir "/gl_constants.inc") constants-text)
(spit (str out-dir "/gl_functions.inc") functions-text)
(doseq [[g t] bind-files]
  (spit (str out-dir "/gl_bind_" g ".inc") (str "{ src/generated/gl_bind_" g ".inc — tools/gengl.bb が作る。手で直さない。 }\n" t)))
(println (format "gengl: 定数 %d 件、コア関数 %d 件（SDL の有効な行。無効な行 %d 件は写さない）、拡張関数 %d 件を書いた"
                 (count constants) (count core) unused-count (reduce + (map (comp count second) ext))))
