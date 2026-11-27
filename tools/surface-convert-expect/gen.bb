#!/usr/bin/env bb
;; gen — tools/surface-convert-expect/sc_cases.c を SDL に通して、結果を test/surface_convert_expected.inc に書く。
;;
;; 使い方:
;;   tools/surface-convert-expect/gen.bb <静的に作った SDL のビルドの場所>
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
(def ^:private tmp (str (fs/create-temp-dir {:prefix "scexp"})))
(def ^:private exe (str tmp "/sc_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/surface-convert-expect/sc_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(when (str/includes? out "INIT-ERR") (fail out))
(def ^:private lines (str/split-lines out))
(when (some #(re-find #"^X " %) lines) (fail "SDL が転送を断った場面がある:\n" (str/join "\n" (filter #(re-find #"^X " %) lines))))
(def ^:private rows (filter #(re-find #"^C " %) lines))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/surface_convert_expected.inc"
      (str "{ test/surface_convert_expected.inc — tools/surface-convert-expect/gen.bb が作る。手で直さない。\n"
           "  参照版 SDL のサーフェスの変換（SDL_ConvertSurface と SDL_ConvertSurfaceAndColorspace）の結果。1 行 = 1 場面:\n"
           "  'C 場面 src形式 src色空間 dst形式 求めた色空間(- = SDL_ConvertSurface、U = ConvertSurfaceAndColorspace) w h src白点 srcヘッドルーム トーンマップ src画素 srcパレット dst画素 dst色空間 dst白点 dstヘッドルーム dstトーンマップ'。\n"
           "  数値は 16 進（浮動小数は 32 ビットの並び）、ブレンドは SDL の値（1 = BLEND、2 = ADD、4 = MOD、8 = MUL）。 }\n\n"
           "const\n  SurfaceConvertExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
