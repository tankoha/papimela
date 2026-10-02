#!/usr/bin/env bb
;; gendebugfont — DebugText の 8x8 の字形を SDL のヘッダから Pascal へ写す。
;;
;; なぜ要るか:
;;   字形は 190 文字 x 8 行 = 1520 バイトの表で、手でも qwen でも写さない
;;   （CLAUDE.md: 大きな表は生成器で作る）。
;;
;; 使い方:
;;   tools/gendebugfont.bb    reference/SDL/src/render/SDL_render_debug_font.h から
;;                            src/generated/debug_font.inc を作る
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - バイト数が SDL_DEBUG_FONT_NUM_GLYPHS x 8 と一致する
;;   - 字形の見出しのコメント（「33 0x21 '!'」など）の数が SDL_DEBUG_FONT_NUM_GLYPHS と一致し、
;;     並びが 33..126、161..255、印 である
;;   - 各バイトの値が、同じ行のコメントの絵（左の画素が最下位ビット）と一致する
;;     （最後の字形だけは絵が左右逆。下の mirrored-comment-glyphs）。
;;     test_render_logical はコメントの絵から書き写した字形で検査するので、
;;     値と絵が食い違っていれば、ここで止めないと検査が嘘をつく
;;
;; 元のヘッダは SDL（zlib）だが、字形そのものは Marcel Sondaar の font8_8.asm と
;; IBM の VGA フォントに由来する Public Domain（ヘッダの注記による）。

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private src "reference/SDL/src/render/SDL_render_debug_font.h")
(def ^:private out "src/generated/debug_font.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gendebugfont: " msg)))
  (System/exit 1))

(when-not (fs/exists? src)
  (fail src " が無い。reference/SDL を用意すること（docs/ORIGIN.md）"))

(def ^:private text (slurp src))

(def ^:private num-glyphs
  (if-let [[_ n] (re-find #"(?m)^#define SDL_DEBUG_FONT_NUM_GLYPHS (\d+)\s*$" text)]
    (parse-long n)
    (fail "SDL_DEBUG_FONT_NUM_GLYPHS が見つからない")))

(def ^:private body
  (if-let [[_ b] (re-find #"(?s)SDL_RenderDebugTextFontData\[\] = \{(.*?)\};" text)]
    b
    (fail "SDL_RenderDebugTextFontData が見つからない")))

;; 字形の見出し: 「 * 33 0x21 '!'」と、最後の「 * 256 0x100 - missing character」。
(def ^:private headings
  (vec (for [[_ dec label] (re-seq #"(?m)^\s*\*\s+(\d+)\s+0x[0-9a-fA-F]+\s+(.*?)\s*$" body)]
         [(parse-long dec) label])))

(def ^:private rows
  (vec (for [[_ hex bits] (re-seq #"0x([0-9a-fA-F]{2}),?\s*/\*\s*([01]{8})\s*\*/" body)]
         [(Integer/parseInt hex 16) bits])))

;; 見出しのコメントにも「0x21」があるので、行頭のバイトだけを数える。
(def ^:private all-hex (count (re-seq #"(?m)^\s*0x[0-9a-fA-F]{2}" body)))

(when (not= (count headings) num-glyphs)
  (fail "見出しが " (count headings) " 個、SDL_DEBUG_FONT_NUM_GLYPHS は " num-glyphs))
;; 引く側（TPMLRenderer.DebugText）は 33..126 と 161..255 がこの順に並び、最後が
;; 印である前提で添字を求める。並びが変わったら止める。
(let [want (concat (range 33 127) (range 161 256))
      got  (map first (butlast headings))]
  (when (or (not= got want)
            (not (str/includes? (second (last headings)) "missing")))
    (fail "字形の並びが 33..126、161..255、印 になっていない")))
(when (not= (count rows) (* 8 num-glyphs))
  (fail "コメントつきのバイトが " (count rows) " 個、期待は " (* 8 num-glyphs)))
(when (not= all-hex (count rows))
  (fail "コメントの無いバイトがある（" all-hex " 個中 " (count rows) " 個にだけコメント）"))

;; 最後の字形（字形の無い文字の印）だけは、コメントの絵が左右逆（左が最上位ビット）に
;; 書かれている。SDL で実際に描くと値のとおり（1 行目の左端が塗られる）になることを
;; 確かめた（docs/TEST-LOG.md）。ここだけ絵を逆に読む。
(def ^:private mirrored-comment-glyphs #{(dec num-glyphs)})

(doseq [[i [v bits]] (map-indexed vector rows)]
  ;; コメントの絵は左から右。左の画素が最下位ビット（SDL の (*charpos >> ix) & 1）。
  (let [pic (if (mirrored-comment-glyphs (quot i 8)) bits (str/reverse bits))
        from-bits (Integer/parseInt pic 2)]
    (when (not= v from-bits)
      (fail "字形 " (quot i 8) " の " (mod i 8) " 行目: 値 " (format "0x%02x" v)
            " とコメントの絵 " bits " が合わない"))))

(def ^:private sb (StringBuilder.))
(defn- emit [& xs] (.append sb (apply str xs)) (.append sb "\n"))

(emit "{ DebugText の 8x8 の字形")
(emit "")
(emit "  tools/gendebugfont.bb が SDL の src/render/SDL_render_debug_font.h から生成する。")
(emit "  手で直さず、生成器を直して作り直すこと。字形は Marcel Sondaar の font8_8.asm と")
(emit "  IBM の VGA フォントに由来し、Public Domain（元のヘッダの注記による）。")
(emit "")
(emit "  1 字形 8 バイト、上の行から。各バイトは左の画素が最下位ビット。")
(emit "  並びは 33..126、161..255、最後に字形の無い文字の印。 }")
(emit "")
(emit "  PML_DEBUG_FONT_NUM_GLYPHS = " num-glyphs ";")
(emit "")
(emit "  PMLDebugFontData: array[0.." (dec (* 8 num-glyphs)) "] of Byte = (")
(doseq [[g [code label]] (map-indexed vector headings)]
  (let [bytes (subvec rows (* 8 g) (* 8 (inc g)))
        last? (= g (dec num-glyphs))
        ;; 見出しの文字は元のファイルの文字コードが壊れていることがあるので、番号だけ書く。
        note (if (str/includes? label "missing") "字形の無い文字の印" (format "U+%04X" code))]
    (emit "    " (str/join ", " (map #(format "$%02X" (first %)) bytes))
          (if last? " " ",") "  // " note)))
(emit "  );")

(fs/create-dirs (fs/parent out))
(spit out (str sb))
(println (str "gendebugfont: " num-glyphs " 字形（" (count rows) " バイト）を " out " へ書いた"))
