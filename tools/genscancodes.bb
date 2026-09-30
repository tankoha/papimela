#!/usr/bin/env bb
;; genscancodes — SDL のキーボードの表を Pascal のユニットへ写す。
;;
;; なぜ要るか:
;;   スキャンコード 249 個、キーコード 259 個、evdev からの変換表 768 項目、
;;   キーシムから Unicode への表 500 項目余り。手で写すと必ずどこかで写し間違える
;;   （CLAUDE.md: 大きな定数表は qwen にも手にも写させない）。SDL のソースを読んで
;;   機械的に出力し、出力の数を元の数と突き合わせる。
;;
;; 使い方:
;;   tools/genscancodes.bb        reference/SDL から src/generated/ の 2 ユニットを作る
;;
;; 出力:
;;   src/generated/PaPiMeLa.Keycodes.pas         公開。TPMLScancode と PMLK_* 定数
;;   src/generated/PaPiMeLa.Keycodes.Tables.pas  内部。変換表と名前の表
;;
;; 入力（すべて reference/SDL 以下）:
;;   include/SDL3/SDL_scancode.h         SDL_Scancode の列挙
;;   include/SDL3/SDL_keycode.h          SDLK_* の定義
;;   src/events/scancodes_linux.h        evdev のキーコード → スキャンコード
;;   src/events/SDL_keymap.c             既定のキー配置、スキャンコードの名前
;;   src/events/SDL_keysym_to_keycode.c  Unicode にならないキーシム → キーコード
;;   src/events/imKStoUCS.c              キーシム → Unicode

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private sdl "reference/SDL")
(def ^:private out-dir "src/generated")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genscancodes: " msg)))
  (System/exit 1))

(defn- slurp-sdl [rel]
  (let [p (str sdl "/" rel)]
    (when-not (fs/exists? p) (fail p " が無い。reference/SDL を用意すること"))
    (slurp p)))

(defn- block
  "text の中で start-re に一致する行から、最初の end-re（既定は `};`）までを返す。"
  ([text start-re] (block text start-re "\\n\\s*\\};"))
  ([text start-re end-re]
  (let [m (re-find (re-pattern (str "(?s)" start-re ".*?" end-re)) text)]
    (or (if (string? m) m (first m))
        (fail "ブロックが見つからない: " start-re)))))

;; ---- Pascal の識別子 ----

;; objfpc モードの予約語。列挙の要素名がこれと重なったら & を付ける。
(def ^:private reserved
  #{"and" "array" "as" "asm" "begin" "case" "class" "const" "constructor"
    "destructor" "dispinterface" "div" "do" "downto" "else" "end" "except"
    "exports" "file" "finalization" "finally" "for" "function" "goto" "if"
    "implementation" "in" "inherited" "initialization" "inline" "interface"
    "is" "label" "library" "mod" "nil" "not" "object" "of" "on" "operator"
    "or" "out" "packed" "procedure" "program" "property" "raise" "record"
    "repeat" "resourcestring" "set" "shl" "shr" "string" "then" "threadvar"
    "to" "try" "type" "unit" "until" "uses" "var" "while" "with" "xor"
    "self" "result"})

(defn- member-name
  "SDL_SCANCODE_ の後ろの名前を列挙の要素名にする。数字で始まるものは Digit を前に付ける。"
  [n]
  (let [n (if (re-matches #"\d.*" n) (str "Digit" n) n)]
    (if (reserved (str/lower-case n)) (str "&" n) n)))

(defn- check-case-collisions
  "Pascal は大文字小文字を区別しない。小文字にして重なる名前があれば止める（D-09 系）。"
  [what names]
  (let [dups (->> names (group-by str/lower-case) (filter #(> (count (val %)) 1)))]
    (when (seq dups)
      (fail what " に大文字小文字だけが違う名前がある: " (pr-str (map val dups))))))

(defn- commented-lines
  "[コード 注釈] の並びを、区切りのカンマを注釈より前に置いた行にする。
   カンマを行末に付けると `// 注釈,` となり、カンマが注釈に呑まれる。"
  [width items]
  (let [n (count items)]
    (str/join "\n" (map-indexed (fn [i [code comment]]
                                  (format (str "    %-" width "s // %s")
                                          (if (< i (dec n)) (str code ",") code) comment))
                                items))))

(defn- pascal-string
  "C の文字列リテラルの中身を Pascal の文字列リテラルにする。"
  [s]
  (let [unescaped (-> s (str/replace "\\\\" "\u0000") (str/replace "\\\"" "\"")
                      (str/replace "\u0000" "\\"))]
    (str "'" (str/replace unescaped "'" "''") "'")))

(defn- hex8 [n] (format "$%08X" n))
(defn- hex4 [n] (format "$%04X" n))

;; ---- 読み取り ----

(defn- read-scancodes
  "SDL_Scancode の列挙。値 → 名前（SDL_SCANCODE_ を除いたもの）の sorted-map。"
  []
  (let [text (block (slurp-sdl "include/SDL3/SDL_scancode.h") "typedef enum SDL_Scancode" "\\} SDL_Scancode;")
        pairs (for [[_ n v] (re-seq #"(?m)^\s*SDL_SCANCODE_([A-Z0-9_]+)\s*=\s*(\d+)" text)
                    :when (not= n "COUNT")]
                [(parse-long v) n])
        by-value (group-by first pairs)]
    (doseq [[v ps] by-value :when (> (count ps) 1)]
      (fail "同じ値のスキャンコードが複数ある: " v " " (map second ps)))
    (into (sorted-map) pairs)))

(defn- read-keycodes
  "SDLK_* の定義。[名前 値] の並び（ヘッダの順）。"
  []
  (let [text (slurp-sdl "include/SDL3/SDL_keycode.h")]
    (vec (for [[_ n v] (re-seq #"(?m)^#define SDLK_([A-Z0-9_]+)\s+0x([0-9a-fA-F]+)u" text)]
           [n (Long/parseLong v 16)]))))

(defn- read-linux-table [sc-by-name]
  (let [text (block (slurp-sdl "src/events/scancodes_linux.h")
                    "static SDL_Scancode const linux_scancode_table\\[\\] = \\{")
        entries (for [[_ idx n] (re-seq #"/\*\s*(\d+),\s*0x[0-9a-f]+\s*\*/\s*SDL_SCANCODE_([A-Z0-9_]+)" text)]
                  [(parse-long idx) n])]
    (doseq [[i [idx n]] (map-indexed vector entries)]
      (when (not= i idx) (fail "scancodes_linux.h の " i " 番目の注釈が " idx))
      (when-not (sc-by-name n) (fail "scancodes_linux.h の未知のスキャンコード " n)))
    (mapv second entries)))

(defn- read-scancode-names []
  (let [text (block (slurp-sdl "src/events/SDL_keymap.c")
                    "static const char \\*SDL_scancode_names\\[SDL_SCANCODE_COUNT\\] =")
        entries (for [[_ idx v] (re-seq #"/\*\s*(\d+)\s*\*/\s*(NULL|\"(?:[^\"\\]|\\.)*\")" text)]
                  [(parse-long idx) (when (not= v "NULL") (subs v 1 (dec (count v))))])]
    (doseq [[i [idx _]] (map-indexed vector entries)]
      (when (not= i idx) (fail "SDL_scancode_names の " i " 番目の注釈が " idx)))
    (into {} entries)))

(defn- read-extended-key-names []
  (let [text (block (slurp-sdl "src/events/SDL_keymap.c")
                    "static const char \\*SDL_extended_key_names\\[\\] = \\{")]
    (mapv second (re-seq #"\"([^\"]*)\"" text))))

(defn- read-sdlk-list [start-re]
  (let [text (block (slurp-sdl "src/events/SDL_keymap.c") start-re)]
    (mapv second (re-seq #"SDLK_([A-Z0-9_]+)" text))))

(defn- read-extended-default-symbols []
  (let [text (block (slurp-sdl "src/events/SDL_keymap.c") "\\} extended_default_symbols\\[\\] = \\{")]
    (vec (for [[_ k s] (re-seq #"\{\s*SDLK_([A-Z0-9_]+),\s*SDL_SCANCODE_([A-Z0-9_]+)\s*\}" text)]
           [k s]))))

(defn- read-default-switch
  "SDL_GetDefaultKeyFromScancode の switch。[スキャンコード名 キーコード名] の並び。
   case が続いて return を共有する書き方にも対応する。"
  []
  (let [text (slurp-sdl "src/events/SDL_keymap.c")
        fn-text (or (second (re-find #"(?s)static SDL_Keycode SDL_GetDefaultKeyFromScancode\(SDL_Scancode scancode, SDL_Keymod modstate\)\s*\{(.*?)\n\}" text))
                    (fail "SDL_GetDefaultKeyFromScancode が見つからない"))
        sw (or (second (re-find #"(?s)switch \(scancode\) \{(.*)" fn-text))
               (fail "既定の switch が見つからない"))
        tokens (re-seq #"case SDL_SCANCODE_([A-Z0-9_]+):|return SDLK_([A-Z0-9_]+);" sw)]
    (loop [ts tokens pending [] acc []]
      (if-let [[_ c r] (first ts)]
        (cond c (recur (rest ts) (conj pending c) acc)
              r (recur (rest ts) [] (into acc (map #(vector % r) pending))))
        acc))))

(defn- read-keysym-to-keycode []
  (let [text (block (slurp-sdl "src/events/SDL_keysym_to_keycode.c")
                    "\\} keysym_to_keycode_table\\[\\] = \\{")]
    (vec (for [[_ ks k] (re-seq #"\{\s*0x([0-9a-fA-F]+),\s*SDLK_([A-Z0-9_]+)\s*\}" text)]
           [(Long/parseLong ks 16) k]))))

(defn- read-ucs-tables
  "imKStoUCS.c の表と、関数の中の範囲判定。
   範囲は [above below 表の名前 base]（C の keysym > above && keysym < below と
   表[keysym - base]）。"
  []
  (let [text (slurp-sdl "src/events/imKStoUCS.c")
        tables (into {}
                 (for [[_ n body] (re-seq #"(?s)static unsigned short (?:const )?keysym_to_unicode_(\w+)\[\] = \{(.*?)\};" text)]
                   [n (mapv #(Long/parseLong % 16)
                            (map second (re-seq #"0x([0-9a-fA-F]+)" (str/replace body #"/\*.*?\*/" ""))))]))
        ranges (for [[_ above below n base]
                     (re-seq #"keysym > 0x([0-9a-f]+) && keysym < 0x([0-9a-f]+)\)\s*return keysym_to_unicode_(\w+)\[keysym - 0x([0-9a-f]+)\]" text)]
                 [(Long/parseLong above 16) (Long/parseLong below 16) n (Long/parseLong base 16)])]
    (doseq [[_ _ n _] ranges] (when-not (tables n) (fail "imKStoUCS.c の未知の表 " n)))
    (when (not= (count ranges) (count tables))
      (fail "imKStoUCS.c の表 " (count tables) " 個に対して範囲判定が " (count ranges) " 個"))
    {:tables tables :ranges (vec ranges)}))

;; ---- 出力 ----

(def ^:private header-common
  "  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
  Copyright (C) 2026 papimela contributors
  （zlib ライセンス本文は papimela.inc を参照）

  このファイルは tools/genscancodes.bb が生成する。手で直さず、生成器を直して
  作り直すこと。")

(defn- emit-keycodes [scancodes keycodes]
  (let [members (for [v (range 512)]
                  (if-let [n (scancodes v)] (member-name n) (str "Unused" v)))
        sb (StringBuilder.)]
    (check-case-collisions "スキャンコード" members)
    (check-case-collisions "キーコード" (map first keycodes))
    (.append sb (str "{
  PaPiMeLa.Keycodes — スキャンコードとキーコード

  Origin : ported from SDL (include/SDL3/SDL_scancode.h, include/SDL3/SDL_keycode.h)
           Scope: SDL_Scancode と SDLK_* の名前と値。値は SDL と同じ。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.6、§11 #26

  WHAT:
    TPMLScancode（キーの物理的な位置。USB HID Usage）と TPMLKeycode（配列に
    従ったキーの意味）。

  WHY:
    ゲームは「W の位置のキー」を見たい（TPMLScancode.W）。ショートカットは
    「W と書いてあるキー」を見たい（PMLK_W）。キーシム（XKB）はプラットフォーム層の
    ものなので、アプリはこのユニットだけで済むようにする。

  RESOLVED:
    - TPMLScancode は 0..511 の隙間の無い列挙にした。FPC は値を指定した列挙を
      配列の添字に使えない（「enums with assignments cannot be used as array
      index」）。SDL の値の無いところは UnusedNNN で埋め、Ord の値は SDL と一致する
    - 数字で始まる名前は Digit を付ける（SDL_SCANCODE_1 → TPMLScancode.Digit1）。
      予約語と重なる名前は & を付ける（SDL_SCANCODE_END → TPMLScancode.&END）
    - キーコードは列挙にしない。印字できるキーの値は Unicode のコードポイントで、
      範囲が開いているため。型を分けた LongWord と定数にする

" header-common "
}
unit PaPiMeLa.Keycodes;

{$I papimela.inc}

interface

type
  TPMLScancode = (\n"))
    (.append sb (commented-lines 28 (map-indexed (fn [i m] [m i]) members)))
    (.append sb "\n  );\n\n")
    (.append sb "  TPMLKeycode = type LongWord;\n\nconst\n")
    (.append sb "  PMLK_EXTENDED_MASK = TPMLKeycode(1 shl 29);\n")
    (.append sb "  PMLK_SCANCODE_MASK = TPMLKeycode(1 shl 30);\n\n")
    (doseq [[n v] keycodes]
      (.append sb (format "  PMLK_%-24s = TPMLKeycode(%s);\n" n (hex8 v))))
    (.append sb "\nimplementation\n\nend.\n")
    (str sb)))

(defn- emit-tables [{:keys [scancodes keycodes linux names ext-names normal shifted
                            ext-default default-switch ks-kc ucs]}]
  (let [kc (into {} keycodes)
        sc-name->member (into {} (for [[_ n] scancodes] [n (member-name n)]))
        key (fn [n] (or (when (kc n) (str "PMLK_" n)) (fail "未知のキーコード SDLK_" n)))
        sc (fn [n] (str "TPMLScancode." (or (sc-name->member n) (fail "未知のスキャンコード " n))))
        sb (StringBuilder.)
        {:keys [tables ranges]} ucs
        ;; 表を 1 本の配列に並べ、範囲ごとに先頭の位置を持つ
        layout (reduce (fn [acc [above below n base]]
                         (conj acc {:above above :below below :name n :base base
                                    :offset (reduce + (map :count acc))
                                    :count (count (tables n))}))
                       [] ranges)
        ucs-data (vec (mapcat #(tables (:name %)) layout))]
    ;; 範囲判定と表の大きさが合っているかを出力前に見る（D-36 はここで見つかる）
    (doseq [{:keys [above below name base count]} layout]
      (when (not= (inc above) base)
        (binding [*out* *err*]
          (println (format "genscancodes: 注意 imKStoUCS.c の範囲 0x%x < keysym < 0x%x は表 %s の先頭 0x%x より手前から始まる（上流の不具合 D-36）。生成した表の引き方は先頭より前を引かない"
                           above below name base))))
      (when (> (- below base) count)
        (fail "imKStoUCS.c の範囲が表 " name " の末尾を越える")))
    (.append sb (str "{
  PaPiMeLa.Keycodes.Tables — キーボードの変換表（内部用）

  Origin : ported from SDL (src/events/scancodes_linux.h, src/events/SDL_keymap.c,
           src/events/SDL_keysym_to_keycode.c, src/events/imKStoUCS.c)
           Scope: 表のデータだけ。表を引く処理は PaPiMeLa.Events.Keymap にある。
           SDL revision: see docs/ORIGIN.md
  Design : docs/DESIGN.md §4.6、§11 #26

  WHAT:
    evdev のキーコード → スキャンコード、既定（US 配列）のキー配置、
    スキャンコードの名前、キーシム → キーコード、キーシム → Unicode。

  WHY:
    アプリが直接使うものではない。PaPiMeLa.Events.Keymap と Wayland のシートが引く。

" header-common "
}
unit PaPiMeLa.Keycodes.Tables;

{$I papimela.inc}

interface

uses
  PaPiMeLa.Keycodes;

type
  TPMLKeysymKeycode = record
    Keysym : LongWord;
    Keycode: TPMLKeycode;
  end;

  TPMLScancodeKeycode = record
    Scancode: TPMLScancode;
    Keycode : TPMLKeycode;
  end;

  { imKStoUCS.c の範囲 1 つ。C の条件は `keysym > Above && keysym < Below` で、
    値は PML_KEYSYM_UCS_DATA[Offset + keysym - Base]。 }
  TPMLKeysymUcsRange = record
    Above, Below, Base: LongWord;
    Offset, Count     : Integer;
  end;

const\n"))
    ;; evdev → スキャンコード
    (.append sb (format "  // scancodes_linux.h。添字は evdev のキーコード（xkb のキーコード - 8）。\n  PML_LINUX_SCANCODES: array[0..%d] of TPMLScancode = (\n" (dec (count linux))))
    (.append sb (commented-lines 38 (map-indexed (fn [i n] [(sc n) i]) linux)))
    (.append sb "\n  );\n\n")
    ;; 名前
    (.append sb "  // SDL_keymap.c の SDL_scancode_names。名前の無いものは空文字列。\n  PML_SCANCODE_NAMES: array[TPMLScancode] of String = (\n")
    (.append sb (str/join ",\n" (for [v (range 512)]
                                  (format "    %s" (if-let [s (names v)] (pascal-string s) "''")))))
    (.append sb "\n  );\n\n")
    (.append sb (format "  // SDL_extended_key_names。PMLK_EXTENDED_MASK の付いたキーコードの下位ビット - 1 が添字。\n  PML_EXTENDED_KEY_NAMES: array[0..%d] of String = (\n" (dec (count ext-names))))
    (.append sb (str/join ",\n" (map #(str "    " (pascal-string %)) ext-names)))
    (.append sb "\n  );\n\n")
    ;; 既定の配置
    (doseq [[label nm lst] [["normal_default_symbols。Digit1 から Slash まで、Shift なし。" "PML_NORMAL_DEFAULT_SYMBOLS" normal]
                           ["shifted_default_symbols。同じ範囲の Shift あり。" "PML_SHIFTED_DEFAULT_SYMBOLS" shifted]]]
      (.append sb (format "  // %s\n  %s: array[0..%d] of TPMLKeycode = (\n" label nm (dec (count lst))))
      (.append sb (str/join ",\n" (map #(str "    " (key %)) lst)))
      (.append sb "\n  );\n\n"))
    (.append sb (format "  // extended_default_symbols。\n  PML_EXTENDED_DEFAULT_SYMBOLS: array[0..%d] of TPMLScancodeKeycode = (\n" (dec (count ext-default))))
    (.append sb (str/join ",\n" (for [[k s] ext-default] (format "    (Scancode: %s; Keycode: %s)" (sc s) (key k)))))
    (.append sb "\n  );\n\n")
    (.append sb (format "  // SDL_GetDefaultKeyFromScancode の switch（印字できないキー）。\n  PML_DEFAULT_KEYS: array[0..%d] of TPMLScancodeKeycode = (\n" (dec (count default-switch))))
    (.append sb (str/join ",\n" (for [[s k] default-switch] (format "    (Scancode: %s; Keycode: %s)" (sc s) (key k)))))
    (.append sb "\n  );\n\n")
    ;; キーシム → キーコード
    (.append sb (format "  // SDL_keysym_to_keycode.c の keysym_to_keycode_table。\n  PML_KEYSYM_KEYCODES: array[0..%d] of TPMLKeysymKeycode = (\n" (dec (count ks-kc))))
    (.append sb (str/join ",\n" (for [[ks k] ks-kc] (format "    (Keysym: %s; Keycode: %s)" (hex8 ks) (key k)))))
    (.append sb "\n  );\n\n")
    ;; キーシム → Unicode
    (.append sb (format "  // imKStoUCS.c の範囲判定。\n  PML_KEYSYM_UCS_RANGES: array[0..%d] of TPMLKeysymUcsRange = (\n" (dec (count layout))))
    (.append sb (commented-lines 72 (for [{:keys [above below base offset count name]} layout]
                                      [(format "(Above: %s; Below: %s; Base: %s; Offset: %4d; Count: %3d)"
                                               (hex4 above) (hex4 below) (hex4 base) offset count)
                                       name])))
    (.append sb "\n  );\n\n")
    (.append sb (format "  // imKStoUCS.c の表を範囲の順に 1 本に並べたもの。\n  PML_KEYSYM_UCS_DATA: array[0..%d] of Word = (\n" (dec (count ucs-data))))
    (.append sb (str/join ",\n" (for [row (partition-all 8 ucs-data)]
                                  (str "    " (str/join ", " (map hex4 row))))))
    (.append sb "\n  );\n\nimplementation\n\nend.\n")
    (str sb)))

(let [scancodes (read-scancodes)
      sc-by-name (into {} (for [[v n] scancodes] [n v]))
      keycodes (read-keycodes)
      data {:scancodes scancodes
            :keycodes keycodes
            :linux (read-linux-table sc-by-name)
            :names (read-scancode-names)
            :ext-names (read-extended-key-names)
            :normal (read-sdlk-list "static const SDL_Keycode normal_default_symbols\\[\\] = \\{")
            :shifted (read-sdlk-list "static const SDL_Keycode shifted_default_symbols\\[\\] = \\{")
            :ext-default (read-extended-default-symbols)
            :default-switch (read-default-switch)
            :ks-kc (read-keysym-to-keycode)
            :ucs (read-ucs-tables)}]
  (spit (str out-dir "/PaPiMeLa.Keycodes.pas") (emit-keycodes scancodes keycodes))
  (spit (str out-dir "/PaPiMeLa.Keycodes.Tables.pas") (emit-tables data))
  (println (format "genscancodes: スキャンコード %d、キーコード %d、evdev 表 %d、名前 %d、既定キー %d、キーシム→キーコード %d、Unicode 範囲 %d（%d 項目）"
                   (count scancodes) (count keycodes) (count (:linux data))
                   (count (filter some? (vals (:names data))))
                   (count (:default-switch data)) (count (:ks-kc data))
                   (count (get-in data [:ucs :ranges]))
                   (reduce + (map count (vals (get-in data [:ucs :tables])))))))
