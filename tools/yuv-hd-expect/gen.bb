#!/usr/bin/env bb
;; gen — tools/yuv-hd-expect/yuv_cases.c を SDL に通して、結果を test/yuv_hd_expected.inc に書く。
;;
;; 使い方:
;;   tools/yuv-hd-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所（参照版 SDL を表示サーバ無しで静的に作る。作り方は
;;     tools/texture-lock-expect/gen.bb の頭と docs/HANDOFF.md §2.1）。
;;     SDL_CalculateYUVSize は内部の関数なので、共有ライブラリ（system）では使えない。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "yuvhd"})))
(def ^:private exe (str tmp "/yuv_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/yuv-hd-expect/yuv_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(when (str/includes? out "INIT-ERR") (fail out))
(def ^:private rows (filter #(re-find #"^[ZCTEB] " %) (str/split-lines out)))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/yuv_hd_expected.inc"
      (str "{ test/yuv_hd_expected.inc — tools/yuv-hd-expect/gen.bb が作る。手で直さない。\n"
           "  参照版 SDL の I444 / P010 の結果。1 行 = 1 場面（先頭の 1 字が種類）:\n"
           "  'Z 形式 w h 大きさ ピッチ'、'B 場面 値…'（黒と白の測定）、'C 形式 色空間 w h ハッシュ'、'T 場面 色空間 w h [ピッチ] ハッシュ'、'E 場面 文面'。 }\n\n"
           "const\n  YUVHDExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
