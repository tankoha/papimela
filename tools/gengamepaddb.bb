#!/usr/bin/env bb
;; gengamepaddb — SDL_gamepad_db.h の Linux のブロックを Pascal の文字列の配列へ写す。
;;
;; なぜ要るか:
;;   SDL_gamepad_db.h の s_GamepadMappings[] のうち Linux 用のブロックは 279 項目の
;;   文字列の表で、手でも qwen でも写さない（CLAUDE.md: 大きな表は生成器で作る）。
;;
;; 使い方:
;;   tools/gengamepaddb.bb   reference/SDL/src/joystick/SDL_gamepad_db.h から
;;                           src/generated/gamepad_db_linux.inc を作る
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - ブロックの中に # の行が #if と #endif の二つだけ（入れ子が無い）
;;   - ブロックにバックスラッシュが無い（C の文字列のエスケープを解く必要が無い）
;;   - ブロックの行は、空行か注釈か項目（"..." の行）だけ
;;   - 項目の数が、先頭が " の行の数と一致する（末尾の /* 注釈 */ は捨てる）
;;   - 各項目は、カンマ区切りで 3 個以上の欄を持ち、先頭は 16 進 32 桁以上の GUID
;;     （32 桁でないものは失敗にせず、行番号と桁数を報告する。SDL 側の誤りがあるため）
;;   - 書いたあと読み直し、'' を ' に戻すと元の項目と同じ順序で一致する
;;   - 同じ GUID の二重は報告だけする

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private src "reference/SDL/src/joystick/SDL_gamepad_db.h")
(def ^:private out "src/generated/gamepad_db_linux.inc")
(def ^:private if-line "#if defined(SDL_JOYSTICK_LINUX) || defined(SDL_PLATFORM_OPENBSD)")
;; 項目の行は `    "...",` だが、末尾に /* 注釈 */ が付く行が 3 件ある（SDL の元の表のまま）。
;; 注釈は捨てる（Pascal 側の文字列には入れない）。
(def ^:private entry-re #"^    \"(.*?)\",\s*(?:/\*.*\*/)?\s*$")
(def ^:private guid-re #"(?i)[0-9a-f]{32,}")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gengamepaddb: " msg)))
  (System/exit 1))

(when-not (fs/exists? src)
  (fail src " が無い。reference/SDL を用意すること（docs/ORIGIN.md）"))

(def ^:private lines (vec (str/split-lines (slurp src))))

;; ---- ブロックの範囲（#if の行は文字で探し、対応する #endif は次の #endif の行）----
(def ^:private start
  (or (first (keep-indexed (fn [i l] (when (= (str/trim l) if-line) i)) lines))
      (fail "#if の行が見つからない: " if-line)))

(def ^:private end
  (or (first (keep-indexed (fn [i l] (when (and (> i start) (str/starts-with? l "#endif")) i)) lines))
      (fail "#if に対応する #endif が見つからない")))

(def ^:private block (subvec lines start (inc end)))
(def ^:private body (subvec lines (inc start) end))

;; ---- 確認: 入れ子・バックスラッシュ・項目でも注釈でもない行 ----
(when (some #(str/starts-with? (str/trim %) "#") body)
  (fail "ブロックの中に入れ子の # 行がある（この生成器は入れ子を扱わない）"))

(when (some #(str/includes? % "\\") block)
  (fail "ブロックにバックスラッシュがある（この生成器は C のエスケープを解かない）"))

(doseq [l body]
  (let [t (str/trim l)]
    (when-not (or (str/blank? t)
                  (str/starts-with? t "//")
                  (str/starts-with? t "/*")
                  (str/starts-with? t "\""))
      (fail "項目でも空行でも注釈でもない行: " l))))

;; ---- 項目 ----
(def ^:private independent-count
  (count (filter #(str/starts-with? (str/trim %) "\"") body)))

;; [元ファイルの行番号 項目の文字列] の組。行番号は報告に使う
(def ^:private entry-src
  (vec (keep-indexed (fn [i l]
                       (when-let [m (re-matches entry-re l)]
                         [(+ start i 2) (second m)]))
                     body)))

(def ^:private entries (mapv second entry-src))

(when-not (= (count entries) independent-count)
  (fail "項目の行 " independent-count " 件のうち " (count entries) " 件しか読めなかった（形式は 4 空白 + \"...\",）"))

(when (empty? entries)
  (fail "項目が 1 件も無い"))

(doseq [[ln e] entry-src]
  (let [fields (str/split e #",")
        guid (first fields)]
    (when (or (< (count fields) 3) (not (re-matches guid-re guid)))
      (fail "項目の形が違う: " e))
    ;; 元の表の誤り（SDL 側）。切り詰めも除外もしない。報告だけする
    (when (not= (count guid) 32)
      (println "gengamepaddb: 注意: 行" ln "の GUID が" (count guid) "桁"))))

(let [guids (map #(first (str/split % #",")) entries)
      dups (filter (fn [[_ n]] (> n 1)) (frequencies guids))]
  (when (seq dups)
    ;; 元の表にも二重がある。そのまま写す（SDL の探索は先頭から見るだけ）
    (doseq [[g n] dups]
      (println "gengamepaddb: 注意: 同じ GUID の二重:" g "(" n " 件)"))))

;; ---- 書く ----
(defn- pas-string [s]
  (str "'" (str/replace s "'" "''") "'"))

(def ^:private n (count entries))

(fs/create-dirs (fs/parent out))

(spit out
      (str "{ src/generated/gamepad_db_linux.inc — tools/gengamepaddb.bb が作る。手で直さない。\n"
           "  SDL_gamepad_db.h の Linux のブロック（" n " 件）。順序は元のまま。 }\n\n"
           "const\n"
           "  GamepadDBLinux: array[0.." (dec n) "] of String = (\n"
           (str/join ",\n" (map (fn [e] (str "    " (pas-string e))) entries))
           "\n  );\n"))

;; ---- 読み直して往復検査 ----
(let [written (vec (str/split-lines (slurp out)))
      item-lines (filter #(str/starts-with? % "    '") written)
      got (vec (keep #(second (re-matches #"^    '(.*)',?$" %)) item-lines))]
  (when-not (= (count item-lines) n)
    (fail "書いた .inc の項目行が " (count item-lines) " 件（期待は " n " 件）"))
  (let [back (mapv #(str/replace % "''" "'") got)]
    (when-not (= back entries)
      (let [i (first (keep-indexed (fn [i [a b]] (when (not= a b) i)) (map vector back entries)))]
        (fail "往復検査に失敗: " (inc (or i 0)) " 件目が元と違う")))))

(println (str "gengamepaddb: " n " 件を書いた（" out "）"))
