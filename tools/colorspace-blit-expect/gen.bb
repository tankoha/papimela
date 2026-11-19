#!/usr/bin/env bb
;; gen — tools/colorspace-blit-expect/csb_cases.c を SDL に通して、結果を test/colorspace_blit_expected.inc に書く。
;;
;; 使い方:
;;   tools/colorspace-blit-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所（参照版 SDL を表示サーバ無しで静的に作る。作り方は tools/colorspace-expect/gen.bb の頭と
;;     docs/HANDOFF.md §2.1）。浮動小数の結果は CPU とコンパイラに依る。**積和を融合しない参照版で作る**
;;     （cmake に -DCMAKE_C_FLAGS=-ffp-contract=off）。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "csbexp"})))
(def ^:private exe (str tmp "/csb_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/colorspace-blit-expect/csb_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(when (str/includes? out "INIT-ERR") (fail out))
(def ^:private lines (str/split-lines out))
(when (some #(re-find #"^X " %) lines) (fail "SDL が転送を断った場面がある:\n" (str/join "\n" (filter #(re-find #"^X " %) lines))))
(def ^:private rows (filter #(re-find #"^B " %) lines))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/colorspace_blit_expected.inc"
      (str "{ test/colorspace_blit_expected.inc — tools/colorspace-blit-expect/gen.bb が作る。手で直さない。\n"
           "  参照版 SDL の色空間つきの転送（SDL_BlitSurfaceScaled。SDL_Blit_Slow_Float の経路）の結果。1 行 = 1 場面:\n"
           "  'B 場面 src形式 src色空間 dst形式 dst色空間 sw sh dw dh src矩形(x y w h) dst矩形(x y w h) ブレンド r g b a カラーキー\n"
           "     src白点 srcヘッドルーム dst白点 dstヘッドルーム トーンマップ src画素 srcパレット dst元の画素 dstパレット dst結果 dst結果のヘッドルーム'。\n"
           "  数値は 16 進（浮動小数は 32 ビットの並び）、ブレンドは SDL の値（1 = BLEND、2 = ADD、4 = MOD、8 = MUL）。 }\n\n"
           "const\n  ColorspaceBlitExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
