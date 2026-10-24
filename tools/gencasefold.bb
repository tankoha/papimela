#!/usr/bin/env bb
;; gencasefold — SDL_casefolding.h の大文字小文字の畳み込みの表を Pascal の配列へ写す。
;;
;; なぜ要るか:
;;   SDL_casefolding.h の畳み込みの表は、4 つの族（1_16 が 254 個、2_16 が 16 個、
;;   3_16 が 3 個、1_32 が 16 個）の小さな C の配列に分かれた 1504 件の表で、
;;   手でも qwen でも写さない（CLAUDE.md: 大きな表は生成器で作る）。
;;   写したあと元の文字の昇順に並べ直し、1 つの配列にする。
;;
;; 使い方:
;;   tools/gencasefold.bb    reference/SDL/src/stdlib/SDL_casefolding.h から
;;                           src/generated/casefold_tables.inc を作る
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 族ごとに、読んだ項目の数が「{ 0x で始まる行」の数と一致する（数え方を変えて二重に数える）
;;   - 0x の語の数が、族の欄の数（2 / 3 / 4 / 2）× 行の数と一致する
;;   - 項目の数の合計が N と一致し、全項目の元の文字（From）に二重が無い
;;   - 使う To が 0 でなく、From が 0x80 以上（ASCII の A-Z は SDL が別に扱う）
;;   - 書いたあと読み直し、項目数が N と一致し、From が狭義の昇順で、元の項目と一致する

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private src "reference/SDL/src/stdlib/SDL_casefolding.h")
(def ^:private out "src/generated/casefold_tables.inc")

;; 族の名前 => [欄の数（元の項目の 0x の数）, 畳んだ後の数（Count）]
(def ^:private families
  {"1_16" [2 1]
   "2_16" [3 2]
   "3_16" [4 3]
   "1_32" [2 1]})

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gencasefold: " msg)))
  (System/exit 1))

(when-not (fs/exists? src)
  (fail src " が無い。reference/SDL を用意すること（docs/ORIGIN.md）"))

(def ^:private lines (vec (str/split-lines (slurp src))))

;; ---- 族の配列の範囲（ヘッダの行から、閉じの `};` の行まで）----
(def ^:private header-re
  #"^static const CaseFoldMapping(\d)_(16|32) case_fold\1_\2_(\d{3})\[\] = \{$")

(defn- array-body [i]
  (let [end (first (filter #(= "};" (lines %)) (range (inc i) (count lines))))]
    (when-not end (fail "閉じの \"};\" が無い（ヘッダの行 " (inc i) "）"))
    (subvec lines (inc i) end)))

(def ^:private arrays
  (vec (keep-indexed (fn [i l]
                       (when-let [[_ arity bits n] (re-matches header-re l)]
                         {:family (str arity "_" bits) :line (inc i) :name n
                          :body (array-body i)}))
                     lines)))

(def ^:private array-counts
  (frequencies (map :family arrays)))

(doseq [[fam _] families]
  (when-not (contains? array-counts fam)
    (fail "族 " fam " の配列が 1 個も見つからない")))

;; ---- 項目を読む（族ごと）----
(defn- entry-re [k]
  (re-pattern (str "^\\s*\\{\\s*0x[0-9A-Fa-f]+" (apply str (repeat (dec k) "\\s*,\\s*0x[0-9A-Fa-f]+")) "\\s*\\},?\\s*$")))

(defn- parse-family [fam [k cnt] arrs]
  (let [body (mapcat :body arrs)
        ;; 数え方 1: 「{ 0x で始まる行」を数える（独立した数え方）
        loose (filter #(re-find #"^\s*\{ 0x" %) body)
        ;; 数え方 2: 0x の語を数えて欄の数で割る
        tokens (reduce + (map #(count (re-seq #"0x" %)) loose))
        ;; 読む: 形の厳密な行だけを項目にする
        strict (filter #(re-matches (entry-re k) %) loose)
        parsed (vec (for [l strict]
                      (let [vals (map #(Long/parseLong (second %) 16) (re-seq #"0x([0-9A-Fa-f]+)" l))]
                        vals)))]
    (when-not (= (count loose) (count strict))
      (fail fam ": 項目の形が違う行が " (- (count loose) (count strict)) " 件ある"))
    (when-not (= tokens (* k (count loose)))
      (fail fam ": 0x の語が " tokens " 個（行 " (count loose) " × 欄 " k " と合わない）"))
    (when-not (= (count parsed) (count loose))
      (fail fam ": " (count parsed) " 件を読んだが、行は " (count loose) " 件"))
    (println (str "gencasefold: " fam " の項目 " (count parsed) " 件（配列 " (count arrs) " 個）"))
    (mapv (fn [vals]
            {:from (first vals)
             :count cnt
             :to (vec (concat (rest vals) (repeat (- 3 cnt) 0)))})
          parsed)))

(def ^:private entries-by-family
  (into {}
        (for [[fam spec] families]
          [fam (parse-family fam spec (filter #(= fam (:family %)) arrays))])))

(def ^:private entries (vec (sort-by :from (mapcat val entries-by-family))))
(def ^:private n (count entries))

;; ---- 確認: 合計・二重・To と From の値 ----
(let [dups (filter (fn [[_ c]] (> c 1)) (frequencies (map :from entries)))]
  (when (seq dups)
    (fail "元の文字の二重がある: "
          (str/join ", " (map (fn [[f _]] (format "0x%04X" f)) dups)))))

(let [bad-from (filter #(< (:from %) 0x80) entries)]
  (when (seq bad-from)
    (fail "From が 0x80 未満の項目がある: "
          (str/join ", " (map #(format "0x%04X" (:from %)) bad-from)))))

(let [bad-to (filter (fn [e] (some zero? (take (:count e) (:to e)))) entries)]
  (when (seq bad-to)
    (fail "使う To が 0 の項目がある: "
          (str/join ", " (map #(format "0x%04X" (:from %)) bad-to)))))

(when (zero? n)
  (fail "項目が 1 件も無い"))

;; ---- 書く ----
(defn- hex4 [v] (str "$" (format "%04X" v)))

(defn- to-str [e i]
  (if (< i (:count e)) (hex4 (nth (:to e) i)) "0"))

(defn- entry-line [e]
  (str "(From: " (hex4 (:from e)) "; Count: " (:count e)
       "; To0: " (to-str e 0) "; To1: " (to-str e 1) "; To2: " (to-str e 2) ")"))

(fs/create-dirs (fs/parent out))

(spit out
      (str "{ src/generated/casefold_tables.inc — tools/gencasefold.bb が作る。手で直さない。\n"
           "  SDL_casefolding.h の大文字小文字の畳み込みの表 " n " 件を、元の文字の昇順に並べたもの。\n"
           "  Count は畳んだ後のコードポイントの数（1〜3）。使わない To は 0。 }\n\n"
           "const\n"
           "  CaseFoldTable: array[0.." (dec n) "] of TCaseFoldEntry = (\n"
           (str/join ",\n" (map (fn [e] (str "    " (entry-line e))) entries))
           "\n  );\n"))

;; ---- 読み直して検査 ----
(let [written (vec (str/split-lines (slurp out)))
      item-re #"^    \(From: \$([0-9A-F]{4,}); Count: ([123]); To0: (\$[0-9A-F]{4,}|0); To1: (\$[0-9A-F]{4,}|0); To2: (\$[0-9A-F]{4,}|0)\),?$"
      back (vec (keep #(when-let [[_ f c t0 t1 t2] (re-matches item-re %)]
                         {:from (Long/parseLong f 16) :count (Long/parseLong c)
                          :to [t0 t1 t2]})
                      written))
      back-to (fn [s] (if (= s "0") 0 (Long/parseLong (subs s 1) 16)))]
  (when-not (= (count back) n)
    (fail "書いた .inc の項目行が " (count back) " 件（期待は " n " 件）"))
  (when-not (re-find (re-pattern (str "array\\[0\\.\\." (dec n) "\\] of TCaseFoldEntry")) (slurp out))
    (fail "配列の宣言が 0.." (dec n) " になっていない"))
  (doseq [[a b] (partition 2 1 back)]
    (when-not (< (:from a) (:from b))
      (fail "From が昇順でない: " (format "0x%04X" (:from a)) " の次が " (format "0x%04X" (:from b)))))
  (let [got (map (fn [b] {:from (:from b) :count (:count b)
                          :to (mapv back-to (:to b))}) back)
        want (map (fn [e] {:from (:from e) :count (:count e)
                           :to (mapv (fn [i] (if (< i (:count e)) (nth (:to e) i) 0)) (range 3))}) entries)]
    (when-not (= (vec got) (vec want))
      (let [i (first (keep-indexed (fn [i [a b]] (when (not= a b) i)) (map vector got want)))]
        (fail "往復検査に失敗: " (inc (or i 0)) " 件目が元と違う")))))

(println (str "gencasefold: " n " 件（1_16 が " (count (entries-by-family "1_16"))
              "、2_16 が " (count (entries-by-family "2_16"))
              "、3_16 が " (count (entries-by-family "3_16"))
              "、1_32 が " (count (entries-by-family "1_32"))
              "）を書いた"))
