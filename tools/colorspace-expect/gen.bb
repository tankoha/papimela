#!/usr/bin/env bb
;; gen — tools/colorspace-expect/cs_cases.c を SDL に通して、結果を test/colorspace_expected.inc に書く。
;;
;; 使い方:
;;   tools/colorspace-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所（参照版 SDL を表示サーバ無しで静的に作る。作り方は
;;     tools/texture-lock-expect/gen.bb の頭と docs/HANDOFF.md §2.1）。SDL の内部の関数
;;     （SDL_sRGBtoLinear など）を直接呼ぶので、共有ライブラリ（system）では使えない。
;;     浮動小数の結果は CPU とコンパイラに依る（aarch64 の gcc は a * b + c を融合する）。
;;     **積和を融合しない参照版で作る**: 参照版を cmake で作るとき `-DCMAKE_C_FLAGS=-ffp-contract=off` を足す
;;     （aarch64 の gcc は既定で a * b + c を融合し、PQ が数百 ulp ずれる。x86_64 は融合しない）。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "csexp"})))
(def ^:private exe (str tmp "/cs_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/colorspace-expect/cs_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(when (str/includes? out "INIT-ERR") (fail out))
(def ^:private rows (filter #(re-find #"^[FMWX] " %) (str/split-lines out)))
(when (some #(re-find #"^X \S+ err " %) rows) (fail "SDL が変換を断った場面がある:\n" (str/join "\n" (filter #(re-find #"^X \S+ err " %) rows))))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/colorspace_expected.inc"
      (str "{ test/colorspace_expected.inc — tools/colorspace-expect/gen.bb が作る。手で直さない。\n"
           "  参照版 SDL の色空間の変換の結果。1 行 = 1 場面（先頭の 1 字が種類）:\n"
           "  'F 関数 入力 出力'（転送関数）、'M 原色 原色 値 x 9'（原色の行列）、'W 色空間 白点 ヘッドルーム'、\n"
           "  'X 場面 src形式 src色空間 dst形式 dst色空間 w h sw sh dw dh トーンマップ src dst'。数値は 16 進（浮動小数は 32 ビットの並び）。 }\n\n"
           "const\n  ColorspaceExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
