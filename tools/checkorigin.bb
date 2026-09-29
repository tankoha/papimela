#!/usr/bin/env bb
;; checkorigin — 各ユニットの Origin 行が docs/DESIGN.md 第11章の由来列と一致するか検査する。
;;
;; なぜ要るか:
;;   移植部分は zlib ライセンスの派生物で、SDL の著作権表示が必要になる。
;;   クリーンルームの部分にそれを書くと逆に事実と違う。どちらであるかは設計書の
;;   第11章が正本なので、ファイルの宣言がそことずれていないかを機械的に見る。
;;
;; 使い方:
;;   tools/checkorigin.bb            指摘があれば終了コード 1
;;
;; 検査するもの:
;;   1. src/ の各ユニットが第11章のどの行に属するか（属さなければ指摘）
;;   2. Origin 行の種別が由来列と一致するか
;;   3. 移植・一部移植なら SDL の著作権表示があるか。クリーンルームなら無いか

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private design "docs/DESIGN.md")
(def ^:private sdl-copyright "Sam Lantinga")

;; 由来列の表記 → Origin 行に現れるべき語
(def ^:private origin-kinds
  {"移植"               :ported
   "一部移植"            :partial
   "クリーンルーム"        :clean
   "クリーンルーム（生成）"  :generated})

(defn- classify-origin
  "Origin 行から種別を判定する。判定できなければ nil。"
  [line]
  (cond
    (str/includes? line "generated from")        :generated
    (str/includes? line "partially ported")      :partial
    (str/includes? line "ported from SDL")       :ported
    (str/includes? line "original work")         :clean))

(defn- kind-label [k]
  (case k
    :ported "移植" :partial "一部移植" :clean "クリーンルーム"
    :generated "クリーンルーム（生成）" (str k)))

(defn- expand-unit
  "第11章のモジュール列に出てくる名前を完全なユニット名にする。
   `.Wayland.Cursor` のような省略形は、同じ行の先頭の名前の接頭辞を使って補う。"
  [head name]
  (if-not (str/starts-with? name ".")
    name
    (let [parts (str/split head #"\.")
          ;; 長い接頭辞から順に試し、省略形の先頭要素と繋がるものを採る
          cands (for [n (range (count parts) 0 -1)]
                  (str (str/join "." (take n parts)) name))]
      (or (first (filter #(fs/exists? (str "src/" % ".pas")) cands))
          (last cands)))))

(defn- chapter11-rows
  "第11章の表から {ユニット名 由来種別} を作る。末尾が `.*` の行は接頭辞規則として扱う。"
  []
  (->> (str/split-lines (slurp design))
       (filter #(re-find #"^\|\s*\d+\s*\|" %))
       (mapcat
        (fn [line]
          (let [cols (mapv str/trim (str/split line #"\|"))
                modules (get cols 2 "")
                kind    (origin-kinds (get cols 7 ""))
                names   (map second (re-seq #"`([^`]+)`" modules))
                units   (filter #(str/starts-with? % "PaPiMeLa") names)
                head    (first units)]
            (when (and kind head)
              (for [n names
                    :when (or (str/starts-with? n "PaPiMeLa")
                              (str/starts-with? n "."))]
                [(expand-unit head n) kind])))))
       (into {})))

(defn- unit-name [path]
  (str/replace (fs/file-name path) #"\.pas$" ""))

(defn- check-file [rows path]
  (let [name     (unit-name path)
        text     (slurp (str path))
        ;; ヘッダのコメントブロックだけを見る。本文の文字列には反応させない。
        header   (first (str/split text #"(?m)^unit " 2))
        line     (first (filter #(str/includes? % "Origin") (str/split-lines header)))
        declared (some-> line classify-origin)
        expected (or (get rows name)
                     ;; `PaPiMeLa.X.*` のような行は接頭辞で一致させる
                     (some (fn [[k v]]
                             (when (and (str/ends-with? k ".*")
                                        (str/starts-with? name (subs k 0 (- (count k) 1))))
                               v))
                           rows))
        has-sdl? (str/includes? header sdl-copyright)]
    (cond
      (nil? line)
      [(str name ": Origin 行が無い")]

      (nil? declared)
      [(str name ": Origin 行の形式が分からない -> " (str/trim line))]

      (nil? expected)
      [(str name ": docs/DESIGN.md 第11章に対応する行が無い")]

      :else
      (cond-> []
        (not= declared expected)
        (conj (str name ": Origin は「" (kind-label declared)
                   "」だが第11章は「" (kind-label expected) "」"))

        (and (#{:ported :partial} declared) (not has-sdl?))
        (conj (str name ": 移植なのに SDL の著作権表示が無い"))

        (and (#{:clean} declared) has-sdl?)
        (conj (str name ": クリーンルームなのに SDL の著作権表示がある"))))))

(let [rows  (chapter11-rows)
      files (sort (map str (fs/glob "src" "**.pas")))
      probs (mapcat #(check-file rows %) files)]
  (println "checkorigin — Origin 行と docs/DESIGN.md 第11章の突き合わせ")
  (println (format "  第11章のユニット %d 件 / 検査したファイル %d 件"
                   (count rows) (count files)))
  (if (seq probs)
    (do (println)
        (doseq [p probs] (println "  [NG]" p))
        (println)
        (println (format "=== 不一致 %d 件 ===" (count probs)))
        (System/exit 1))
    (do (println "  不一致 0 件")
        (println)
        (println "=== Origin 行は設計書と一致している ==="))))
