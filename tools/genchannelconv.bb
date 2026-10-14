#!/usr/bin/env bb
;; genchannelconv — 音声のチャンネル数の変換（56 個）を SDL の生成済みヘッダから Pascal へ写す。
;;
;; なぜ要るか:
;;   SDL_audio_channel_converters.h は SDL の build-scripts/gen_audio_channel_conversion.c が
;;   作った 1068 行の C で、56 個の関数がそれぞれ決まった係数の式を持つ。手でも qwen でも
;;   写さない（CLAUDE.md: 大きな表は生成器で作る）。浮動小数の結果をビット単位で SDL と
;;   そろえるため、式は足し算・掛け算の順番も括弧もそのまま写す。
;;
;; 使い方:
;;   tools/genchannelconv.bb    reference/SDL/src/audio/SDL_audio_channel_converters.h から
;;                              src/generated/audio_channel_converters.inc を作る
;;
;; 写し方:
;;   - 各関数は procedure ConvXxxToYyy(ADst, ASrc: PSingle; ANumFrames: Integer)
;;   - 前から回るもの（for (i = num_frames; i; i--, src += N, dst += M)）と、後ろから回るもの
;;     （src += (num_frames-1); dst += (num_frames-1) * M; のあと src -= N, dst -= M）の 2 通り
;;   - const float srcXX = src[k];  →  SrcXX := ASrc[k];
;;     dst[k] /* XX */ = 式;        →  ADst[k] := 式;
;;   - 小数の定数 0.123f は Single(0.123)。Single どうしの演算なので、x86_64 の FPC は
;;     C（gcc）と同じ単精度の SSE の命令で計算する
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 関数が 56 個（8 x 8 から対角を除く）あり、名前の表 channel_converters[8][8] の
;;     対角が NULL で、ほかがすべて写した関数の名前である
;;   - 本体の各行が上の 2 つの形のどちらかで、式に知らない字句が無い

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private src "reference/SDL/src/audio/SDL_audio_channel_converters.h")
(def ^:private out "src/generated/audio_channel_converters.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genchannelconv: " msg)))
  (System/exit 1))

(when-not (fs/exists? src)
  (fail src " が無い。reference/SDL を用意すること（docs/ORIGIN.md）"))

(def ^:private text (slurp src))

(def ^:private fn-re
  #"(?s)static void SDL_Convert(\w+)\(float \*dst, const float \*src, int num_frames\)\n\{\n(.*?)\n\}\n")

(defn- step
  "ループの増分（src++ / src -= 2 など）を符号つきの数にする。"
  [s]
  (cond
    (= s "++") 1
    (= s "--") -1
    :else (let [[_ op n] (or (re-matches #"([+-])= (\d+)" s) (fail "知らない増分: " s))]
            (* (if (= op "+") 1 -1) (parse-long n)))))

(defn- expr
  "C の式を Pascal の式にする。使ってよい字句だけを置き換え、残りがあれば止まる。"
  [name e]
  (let [p (-> e
              (str/replace #"src\[(\d+)\]" "ASrc[$1]")
              (str/replace #"\bsrc([A-Z]+)\b" "Src$1")
              (str/replace #"(\d+\.\d+)f" "Single($1)"))
        rest (-> p
                 (str/replace #"ASrc\[\d+\]" "")
                 (str/replace #"Src[A-Z]+" "")
                 (str/replace #"Single\(\d+\.\d+\)" "")
                 (str/replace #"[ ()+*]" ""))]
    (when-not (str/blank? rest)
      (fail name ": 式に知らない字句がある: " e))
    p))

(defn- convert-fn [[_ name body]]
  (let [lines (->> (str/split-lines body) (map str/trim) (remove str/blank?))
        backward? (some #(str/starts-with? % "src += (num_frames-1)") lines)
        loop-line (or (first (filter #(str/starts-with? % "for (") lines))
                      (fail name ": ループが無い"))
        [_ sstep dstep] (or (re-matches #"for \(i = num_frames; i; i--, src ?(\+\+|--|[+-]= \d+), dst ?(\+\+|--|[+-]= \d+)\) \{" loop-line)
                            (fail name ": 知らないループ: " loop-line))
        sstep (step sstep)
        dstep (step dstep)
        start-of (fn [who]
                   (let [l (or (first (filter #(str/starts-with? % (str who " += (num_frames-1)")) lines))
                               (fail name ": 後ろから回るのに " who " の始まりが無い"))]
                     (if-let [[_ m] (re-matches (re-pattern (str who " \\+= \\(num_frames-1\\) \\* (\\d+);")) l)]
                       (parse-long m)
                       (if (= l (str who " += (num_frames-1);")) 1 (fail name ": 知らない始まり: " l)))))
        src-start (when backward? (start-of "src"))
        dst-start (when backward?
                    (let [l (or (first (filter #(str/starts-with? % "dst += (num_frames-1)") lines))
                                (fail name ": 後ろから回るのに dst の始まりが無い"))]
                      (if-let [[_ m] (re-matches #"dst \+= \(num_frames-1\) \* (\d+);" l)]
                        (parse-long m)
                        (if (= l "dst += (num_frames-1);") 1 (fail name ": 知らない始まり: " l)))))
        stmts (->> lines
                   (drop-while #(not (str/starts-with? % "for (")))
                   rest
                   (take-while #(not= % "}")))
        locals (atom [])
        body-lines
        (vec (for [s stmts]
               (if-let [[_ v e] (re-matches #"const float src([A-Z]+) = (.*);" s)]
                 (do (swap! locals conj (str "Src" v))
                     (str "    Src" v " := " (expr name e) ";"))
                 (if-let [[_ k e] (re-matches #"dst\[(\d+)\] /\* \w+ \*/ = (.*);" s)]
                   (str "    ADst[" k "] := " (expr name e) ";")
                   (fail name ": 知らない文: " s)))))]
    (when backward?
      (when-not (and (neg? sstep) (neg? dstep) (= (- dstep) dst-start) (= (- sstep) src-start))
        (fail name ": 後ろから回る増分が合わない")))
    (when (and (not backward?) (or (neg? sstep) (neg? dstep)))
      (fail name ": 前から回るのに増分が負"))
    {:name name
     :text
     (str "procedure Conv" name "(ADst, ASrc: PSingle; ANumFrames: Integer);\n"
          "var\n"
          "  I: Integer;\n"
          (when (seq @locals)
            (str "  " (str/join ", " @locals) ": Single;\n"))
          "begin\n"
          (when backward?
            (str "  // 出力が入力より大きいので、同じ置き場でも壊さないよう後ろから回る（SDL と同じ）。\n"
                 "  Inc(ASrc, (ANumFrames - 1) * " src-start ");\n"
                 "  Inc(ADst, (ANumFrames - 1) * " dst-start ");\n"))
          "  for I := ANumFrames downto 1 do\n"
          "  begin\n"
          (str/join "\n" body-lines) "\n"
          (if (pos? sstep) (str "    Inc(ASrc, " sstep ");\n") (str "    Dec(ASrc, " (- sstep) ");\n"))
          (if (pos? dstep) (str "    Inc(ADst, " dstep ");\n") (str "    Dec(ADst, " (- dstep) ");\n"))
          "  end;\n"
          "end;\n")}))

(def ^:private fns (mapv convert-fn (re-seq fn-re text)))

(when-not (= 56 (count fns))
  (fail "関数が " (count fns) " 個（56 個のはず）"))

(def ^:private table
  (let [[_ body] (or (re-find #"(?s)channel_converters\[8\]\[8\] = \{.*?\n(.*?)\n\};" text)
                     (fail "channel_converters の表が無い"))
        rows (->> (str/split-lines body)
                  (map str/trim)
                  (map #(re-find #"\{ (.*) \}" %))
                  (map second))]
    (when-not (= 8 (count rows)) (fail "表の行が " (count rows) " 行"))
    (vec (for [r rows]
           (let [cells (map str/trim (str/split r #","))]
             (when-not (= 8 (count cells)) (fail "表の列が 8 でない: " r))
             (vec cells))))))

(def ^:private names (set (map :name fns)))

(doseq [i (range 8) j (range 8)]
  (let [c (get-in table [i j])]
    (if (= i j)
      (when-not (= c "NULL") (fail "対角 [" i "][" j "] が NULL でない: " c))
      (let [[_ n] (or (re-matches #"SDL_Convert(\w+)" c) (fail "表の名前が読めない: " c))]
        (when-not (names n) (fail "表の " c " が写した関数に無い"))))))

(def ^:private output
  (str "{ src/generated/audio_channel_converters.inc — tools/genchannelconv.bb が\n"
       "  reference/SDL/src/audio/SDL_audio_channel_converters.h から生成する。手で直さない。\n"
       "  56 個のチャンネル数の変換と、その表 ChannelConverters[元][先]（1..8。同じ数は nil）。 }\n\n"
       (str/join "\n" (map :text fns))
       "\nconst\n"
       "  ChannelConverters: array[1..8, 1..8] of TPMLChannelConverter = (\n"
       (str/join ",\n"
                 (for [i (range 8)]
                   (str "    ("
                        (str/join ", "
                                  (for [j (range 8)]
                                    (let [c (get-in table [i j])]
                                      (if (= c "NULL") "nil" (str "@Conv" (subs c 11))))))
                        ")")))
       ");\n"))

(spit out output)
(println (str "genchannelconv: " (count fns) " 個の変換と 8x8 の表を " out " に書いた"))
