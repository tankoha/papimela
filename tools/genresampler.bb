#!/usr/bin/env bb
;; genresampler — 周波数の変換（リサンプル）の係数の表を、SDL のコードそのものを C で動かして作る。
;;
;; なぜ要るか:
;;   SDL は起動時に sinf / sqrtf と Bessel 関数で 8 x 12 x 4 = 384 個の係数を単精度で計算する
;;   （SDL_audioresample.c の GenerateResamplerFilter）。FPC の Sin が glibc の sinf とビット単位で
;;   同じ値を返す保証は無いので、計算は Pascal に写さず、SDL のコードを C のコンパイラと libm で
;;   動かした結果を表にする（設計書 #52: リサンプラの係数表はそのまま）。
;;
;; 使い方:
;;   tools/genresampler.bb    reference/SDL/src/audio/SDL_audioresample.c から
;;                            src/generated/audio_resampler_filter.inc を作る（cc が要る）
;;
;; 写し方:
;;   SDL のソースから CubicLeastSquares・BesselI0・SincTable・Sinc・GenerateResamplerFilter と
;;   RESAMPLER_xxx の定義をそのまま切り出し、SDL_sinf → sinf などの置き換えだけをした C を
;;   作って動かす。RESAMPLER_ZERO_CROSSINGS は、x86 で SIMD を持つ SDL と同じ 6 に決める
;;   （SDL は SSE か NEON の組み込み関数を持つ版で 6、持たない版で 5）。係数は単精度のビット
;;   （LongWord）で出す。読み書きで丸めが入らないように。
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 切り出す関数と定義がどれも見つかる
;;   - 係数が 384 個ある
;;   - 中心の係数（ResamplerFilter[0][5] の 0 次の項）が 1.0 である（フィルタの中心は 1）

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(def ^:private src "reference/SDL/src/audio/SDL_audioresample.c")
(def ^:private out "src/generated/audio_resampler_filter.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genresampler: " msg)))
  (System/exit 1))

(when-not (fs/exists? src)
  (fail src " が無い。reference/SDL を用意すること（docs/ORIGIN.md）"))

(def ^:private text (slurp src))

(defn- grab
  "SDL のソースから、re に合う最初の部分を取り出す。"
  [what re]
  (or (re-find re text) (fail what " が見つからない")))

(def ^:private defines
  (str/join "\n"
            (for [n ["RESAMPLER_SAMPLES_PER_FRAME" "RESAMPLER_BITS_PER_ZERO_CROSSING"
                     "RESAMPLER_SAMPLES_PER_ZERO_CROSSING"]]
              (grab n (re-pattern (str "(?m)^#define " n " .*$"))))))

(def ^:private functions
  (str/join "\n\n"
            (for [[n re] [["Cubic" #"(?s)typedef union Cubic\n\{\n    float v\[4\];"]
                          ["CubicLeastSquares" #"(?s)static void CubicLeastSquares\(.*?\n\}\n"]
                          ["BesselI0" #"(?s)static float BesselI0\(.*?\n\}\n"]
                          ["SincTable" #"(?s)static void SincTable\(.*?\n\}\n"]
                          ["Sinc" #"(?s)static float Sinc\(.*?\n\}\n"]
                          ["ResamplerFilter" #"static Cubic ResamplerFilter\[[^;]*;"]
                          ["GenerateResamplerFilter" #"(?s)static void GenerateResamplerFilter\(void\)\n\{.*?\n\}\n"]]]
              (let [g (grab n re)]
                (if (= n "Cubic")
                  "typedef union Cubic { float v[4]; } Cubic;"
                  g)))))

(def ^:private program
  (str "/* tools/genresampler.bb が作る使い捨ての C。SDL_audioresample.c の関数をそのまま使う。 */\n"
       "#include <math.h>\n#include <float.h>\n#include <stdio.h>\n#include <string.h>\n"
       "#define SDL_sinf sinf\n#define SDL_sqrtf sqrtf\n#define SDL_FLT_EPSILON FLT_EPSILON\n"
       "#define SDL_PI_F 3.141592653589793238462643383279502884F\n"
       "#define RESAMPLER_ZERO_CROSSINGS 6\n"
       defines "\n\n" functions "\n\n"
       "int main(void)\n{\n"
       "    GenerateResamplerFilter();\n"
       "    for (int i = 0; i < RESAMPLER_SAMPLES_PER_ZERO_CROSSING; i++)\n"
       "        for (int j = 0; j < RESAMPLER_SAMPLES_PER_FRAME; j++)\n"
       "            for (int k = 0; k < 4; k++) {\n"
       "                unsigned u; memcpy(&u, &ResamplerFilter[i][j].v[k], 4);\n"
       "                printf(\"%d %d %d %08X\\n\", i, j, k, u);\n"
       "            }\n"
       "    return 0;\n}\n"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "genresampler"})))
(def ^:private csrc (str tmp "/gen.c"))
(def ^:private exe (str tmp "/gen"))
(spit csrc program)
(let [r (shell {:continue true :err :string} "cc" "-O2" "-o" exe csrc "-lm")]
  (when-not (zero? (:exit r)) (fail "cc に失敗した:\n" (:err r))))
(def ^:private lines
  (->> (:out (shell {:out :string} exe)) str/split-lines (remove str/blank?)))
(fs/delete-tree tmp)

(when-not (= 384 (count lines))
  (fail "係数が " (count lines) " 個（384 個のはず）"))

(def ^:private table
  (reduce (fn [m l]
            (let [[i j k h] (str/split l #" ")]
              (assoc-in m [(parse-long i) (parse-long j) (parse-long k)] h)))
          {} lines))

(when-not (= "3F800000" (get-in table [0 5 0]))
  (fail "中心の係数が 1.0 でない: " (get-in table [0 5 0])))

(def ^:private output
  (str "{ src/generated/audio_resampler_filter.inc — tools/genresampler.bb が\n"
       "  reference/SDL/src/audio/SDL_audioresample.c の GenerateResamplerFilter を C で動かして作る。\n"
       "  手で直さない。ResamplerFilterBits[i, j, k] は ResamplerFilter[i][j].v[k] の単精度のビット\n"
       "  （零交差 6、零交差あたり 8 標本、1 フレーム 12 標本の 3 次式の係数）。 }\n\n"
       "const\n"
       "  ResamplerFilterBits: array[0..7, 0..11, 0..3] of LongWord = (\n"
       (str/join ",\n"
                 (for [i (range 8)]
                   (str "    (\n"
                        (str/join ",\n"
                                  (for [j (range 12)]
                                    (str "      ("
                                         (str/join ", " (for [k (range 4)] (str "$" (get-in table [i j k]))))
                                         ")")))
                        ")")))
       ");\n"))

(spit out output)
(println (str "genresampler: 384 個の係数を " out " に書いた"))
