#!/usr/bin/env bb
;; genkhronos — EGL と GLES2 の定数を Khronos のヘッダから Pascal へ写す。
;;
;; なぜ要るか:
;;   設計（§9、第 11 章 #17）は khronos のヘッダ一式（7 万行）を使わず、必要な
;;   定数と関数だけを持つと決めている。定数の値を手で写すと写し間違える
;;   （CLAUDE.md: 大きな定数表は qwen にも手にも写させない）。
;;
;; 使い方:
;;   tools/genkhronos.bb     reference/SDL/src/video/khronos から src/generated/ の
;;                           インクルードファイル 2 つを作る
;;
;; 写すもの:
;;   - egl.h と gl2.h の数値の #define はすべて（EGL 1.5 と GLES 2.0 の本体）
;;   - 拡張（eglext.h、gl2ext.h）は下の一覧にあるものだけ。SDL の SDL_egl.c と
;;     render/opengles2 が使うもの。一覧にあってヘッダに無ければ止まる
;;
;; 写さないもの:
;;   EGL_CAST(...) で定義されるポインタ定数（EGL_NO_CONTEXT など）と
;;   EGL_DONT_CARE。型が絡むので PaPiMeLa.Platform.EGL に手で書く。

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private khronos "reference/SDL/src/video/khronos")
(def ^:private out-dir "src/generated")

(def ^:private egl-extensions
  ["EGL_PLATFORM_WAYLAND_KHR" "EGL_PLATFORM_DEVICE_EXT"
   "EGL_CONTEXT_MAJOR_VERSION_KHR" "EGL_CONTEXT_MINOR_VERSION_KHR"
   "EGL_CONTEXT_FLAGS_KHR" "EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR"
   "EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR" "EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE_BIT_KHR"
   "EGL_CONTEXT_OPENGL_ROBUST_ACCESS_BIT_KHR"
   "EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR"
   "EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT_KHR"
   "EGL_CONTEXT_OPENGL_NO_ERROR_KHR" "EGL_OPENGL_ES3_BIT_KHR"
   "EGL_COLOR_COMPONENT_TYPE_EXT" "EGL_COLOR_COMPONENT_TYPE_FIXED_EXT"
   "EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT"
   "EGL_GL_COLORSPACE_KHR" "EGL_GL_COLORSPACE_LINEAR_KHR" "EGL_GL_COLORSPACE_SRGB_KHR"
   "EGL_PRESENT_OPAQUE_EXT"])

(def ^:private gles2-extensions
  ["GL_MIN_EXT" "GL_MAX_EXT" "GL_TEXTURE_EXTERNAL_OES" "GL_BGRA_EXT"])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genkhronos: " msg)))
  (System/exit 1))

(defn- read-defines
  "ヘッダの数値の #define を [名前 値の文字列] の並びで返す（ヘッダの順）。"
  [rel prefix]
  (let [p (str khronos "/" rel)]
    (when-not (fs/exists? p) (fail p " が無い。reference/SDL を用意すること"))
    (vec (for [[_ n v] (re-seq (re-pattern (str "(?m)^#define (" prefix "[A-Za-z0-9_]+)\\s+(0x[0-9A-Fa-f]+|[0-9]+)\\s*$"))
                               (slurp p))]
           [n v]))))

(defn- pick [defs names what]
  (let [m (into {} defs)]
    (vec (for [n names]
           [n (or (m n) (fail what " に " n " が無い"))]))))

(defn- pascal-value [v]
  (if (str/starts-with? v "0x")
    (str "$" (str/upper-case (subs v 2)))
    v))

(defn- check-case-collisions
  "Pascal は大文字小文字を区別しない。小文字にして重なる名前があれば止める（D-09 系）。"
  [defs]
  (let [dups (->> defs (map first) distinct (group-by str/lower-case)
                  (filter #(> (count (val %)) 1)))]
    (when (seq dups)
      (fail "大文字小文字だけが違う名前がある: " (pr-str (map val dups))))))

(defn- emit [path title sources license sections]
  (let [all (mapcat second sections)
        ;; 同じ名前が本体と拡張の両方にあれば本体を残す
        seen (atom #{})
        sb (StringBuilder.)]
    (check-case-collisions all)
    (.append sb (str "{ " title "\n\n"
                     "  tools/genkhronos.bb が " sources " から生成する。手で直さず、\n"
                     "  生成器を直して作り直すこと。元のヘッダは Copyright The Khronos Group Inc.、\n"
                     "  " license "。ここに写しているのは定数の名前と値だけである。 }\n\n"))
    (doseq [[label defs] sections]
      (.append sb (str "  // ---- " label "\n"))
      (doseq [[n v] defs :when (not (@seen n))]
        (swap! seen conj n)
        (.append sb (format "  %-50s = %s;\n" n (pascal-value v))))
      (.append sb "\n"))
    (spit path (str sb))
    (count @seen)))

(let [egl-core (read-defines "EGL/egl.h" "EGL_")
      egl-ext (pick (read-defines "EGL/eglext.h" "EGL_") egl-extensions "eglext.h")
      gl-core (read-defines "GLES2/gl2.h" "GL_")
      gl-ext (pick (read-defines "GLES2/gl2ext.h" "GL_") gles2-extensions "gl2ext.h")
      n-egl (emit (str out-dir "/egl_constants.inc") "EGL の定数"
                  "EGL/egl.h と EGL/eglext.h" "SPDX-License-Identifier: Apache-2.0"
                  [["egl.h（EGL 1.5）" egl-core] ["eglext.h（使うものだけ）" egl-ext]])
      n-gl (emit (str out-dir "/gles2_constants.inc") "GLES 2.0 の定数"
                 "GLES2/gl2.h と GLES2/gl2ext.h" "SPDX-License-Identifier: MIT"
                 [["gl2.h（GLES 2.0）" gl-core] ["gl2ext.h（使うものだけ）" gl-ext]])]
  (println (format "genkhronos: EGL %d（本体 %d、拡張 %d）、GLES2 %d（本体 %d、拡張 %d）"
                   n-egl (count egl-core) (count egl-ext)
                   n-gl (count gl-core) (count gl-ext))))
