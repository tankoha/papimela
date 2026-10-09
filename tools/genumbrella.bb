#!/usr/bin/env bb
;; genumbrella — アンブレラ（PaPiMeLa.pas）の中身を公開層のユニットから作る。
;;
;; なぜ要るか:
;;   アンブレラは、公開層のユニットの型・定数・関数を 1 つのユニットから使える
;;   ように並べ直す（設計 §2.2）。手で並べると、公開 API を足したときにここへ
;;   足し忘れる。そこで各ユニットの interface 部を読んで機械的に作り、CI が
;;   `--check` で古さを見る。
;;
;; 使い方:
;;   tools/genumbrella.bb           src/generated/umbrella_interface.inc と
;;                                  umbrella_implementation.inc を作り直す
;;   tools/genumbrella.bb --check   作り直した結果をディスクのファイルと比べ、
;;                                  違えば（古ければ）終了コード 1
;;
;; 写すもの（各ユニットの interface 部の最上位の宣言だけ）:
;;   - 型      TFoo = PaPiMeLa.Unit.TFoo;（前方宣言は飛ばす）
;;   - type helper は別名にできない（FPC が拒む。実測）ので、元の helper から
;;     派生させる:  THelper = type helper(PaPiMeLa.Unit.THelper) for TTarget end;
;;   - 定数    NAME = PaPiMeLa.Unit.NAME;
;;   - 関数・手続き  同じ引数（既定値も）の inline の関数を置き、元を呼ぶ
;;
;; 写さないもの:
;;   - PMLRegister* と PMLFind*（バックエンドを書く人向け。アンブレラには並べない）
;;   - Video.Backend と TextInput.Backend は、登録済みの名前を問い合わせる関数だけ
;;
;; 読めない構文に当たったら、間違ったものを出さずに止まる（型付き定数、interface 部の
;;   var、ジェネリクス、未知のディレクティブ、コンパイラ指令、二重に出る名前）。

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private src-dir "src")
(def ^:private out-dir "src/generated")
(def ^:private interface-file (str out-dir "/umbrella_interface.inc"))
(def ^:private implementation-file (str out-dir "/umbrella_implementation.inc"))

;; 並べるユニットと順序。:only があれば、その名前の関数だけ（型も定数も無し）。
(def ^:private units
  [{:unit "PaPiMeLa.Types"}
   {:unit "PaPiMeLa.Errors"}
   {:unit "PaPiMeLa.Core"}
   {:unit "PaPiMeLa.Events"}
   {:unit "PaPiMeLa.Events.Drop" :only #{"PMLURIToLocalPath" "PMLURIListToLocalPaths"}}
   {:unit "PaPiMeLa.Events.Keymap"}
   {:unit "PaPiMeLa.Keycodes" :dir "src/generated"}
   {:unit "PaPiMeLa.Pixels"}
   {:unit "PaPiMeLa.Surface"}
   {:unit "PaPiMeLa.Surface.Blit"}
   {:unit "PaPiMeLa.Surface.BMP"}
   {:unit "PaPiMeLa.IO"}
   {:unit "PaPiMeLa.Video"}
   {:unit "PaPiMeLa.Clipboard"}
   {:unit "PaPiMeLa.Render"}
   {:unit "PaPiMeLa.TextInput"}
   {:unit "PaPiMeLa.Time"}
   {:unit "PaPiMeLa.Atomic"}
   {:unit "PaPiMeLa.Threading"}
   {:unit "PaPiMeLa.App"}
   {:unit "PaPiMeLa.Video.Backend" :only #{"PMLVideoBackendNames"}}
   {:unit "PaPiMeLa.TextInput.Backend" :only #{"PMLTextInputBackendNames"}}])

(def ^:private excluded-prefixes ["pmlregister" "pmlfind"])

;; 元の宣言に付いていてよいディレクティブ。出力では inline を必ず付け、overload は
;; 同じ名前が複数あるときに付ける。これ以外は意味が変わるので止まる。
(def ^:private allowed-directives #{"inline" "overload"})
(def ^:private known-directives
  #{"inline" "overload" "cdecl" "stdcall" "register" "pascal" "safecall" "deprecated"
    "platform" "experimental" "forward" "external" "assembler" "varargs" "noreturn"})

(def ^:private ^:dynamic *where* nil)   ; {:unit .. :src ..} — エラーの行番号用

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genumbrella: " msg)))
  (System/exit 1))

(defn- line-of [offset]
  (inc (count (filter #{\newline} (subs (:src *where*) 0 (min offset (count (:src *where*))))))))

(defn- fail-at [tok & msg]
  (fail (:unit *where*) ":" (line-of (:a tok)) ": " (apply str msg)))

;; ---------------------------------------------------------------- 字句

(defn- blank-comments
  "コメントを空白に置き換える（改行は残す）。文字列の中の { や // は見ない。
   {$...} のコンパイラ指令も空白にするが、位置を directives に控える（interface 部の
   中にあれば意味が変わるので、呼び出し側が止まる）。"
  [src directives]
  (let [n (count src)
        sb (StringBuilder.)
        blank (fn [from to]
                (doseq [k (range from to)]
                  (.append sb (if (= (.charAt ^String src k) \newline) \newline \space))))]
    (loop [i 0]
      (when (< i n)
        (let [c (.charAt ^String src i)
              c2 (when (< (inc i) n) (.charAt ^String src (inc i)))]
          (cond
            (= c \')
            (let [end (loop [j (inc i)]
                        (cond
                          (>= j n) (fail (:unit *where*) ": 文字列が閉じていない")
                          (and (= (.charAt ^String src j) \')
                               (< (inc j) n) (= (.charAt ^String src (inc j)) \'))
                          (recur (+ j 2))
                          (= (.charAt ^String src j) \') (inc j)
                          :else (recur (inc j))))]
              (.append sb (subs src i end))
              (recur end))

            (= c \{)
            (let [end (let [e (str/index-of src "}" i)]
                        (if e (inc e) (fail (:unit *where*) ": { が閉じていない")))]
              (when (= c2 \$)
                (swap! directives conj {:a i :s (subs src i (min end (+ i 20)))}))
              (blank i end)
              (recur end))

            (and (= c \() (= c2 \*))
            (let [e (str/index-of src "*)" (+ i 2))
                  end (if e (+ e 2) (fail (:unit *where*) ": (* が閉じていない"))]
              (blank i end)
              (recur end))

            (and (= c \/) (= c2 \/))
            (let [e (or (str/index-of src "\n" i) n)]
              (blank i e)
              (recur e))

            :else
            (do (.append sb c) (recur (inc i)))))))
    (str sb)))

(def ^:private token-re
  #"(?s)(&?[A-Za-z_][A-Za-z0-9_]*)|(\$[0-9A-Fa-f]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|((?:'(?:[^']|'')*'|#\$?[0-9A-Fa-f]+|\^[A-Za-z])+)|(:=|\.\.|<>|<=|>=|<<|>>|\S)")

(defn- tokenize [clean]
  (let [m (re-matcher token-re clean)]
    (loop [acc []]
      (if (.find m)
        (recur (conj acc {:t (cond (.group m 1) :id (.group m 2) :num (.group m 3) :str :else :sym)
                          :s (.group m)
                          :a (.start m)
                          :b (.end m)}))
        acc))))

(defn- id? [tok & names]
  (and tok (= :id (:t tok))
       (or (empty? names) (some #(= (str/lower-case (:s tok)) %) names))))

(defn- sym? [tok s] (and tok (= :sym (:t tok)) (= (:s tok) s)))

(defn- slice [clean a b]
  (str/replace (str/trim (subs clean a b)) #"\s*\n\s*" " "))

;; ---------------------------------------------------------------- 構文

(defn- skip-balanced
  "i は ( か [ を指す。対応する閉じの次の位置を返す。"
  [toks i]
  (let [n (count toks)]
    (loop [j i depth 0]
      (when (>= j n) (fail-at (nth toks i) "括弧が閉じていない"))
      (let [t (nth toks j)]
        (cond
          (or (sym? t "(") (sym? t "[")) (recur (inc j) (inc depth))
          (or (sym? t ")") (sym? t "]")) (if (= depth 1) (inc j) (recur (inc j) (dec depth)))
          :else (recur (inc j) depth))))))

(defn- find-semicolon
  "i から、括弧の外の最初の ; の位置。"
  [toks i]
  (let [n (count toks)]
    (loop [j i]
      (when (>= j n) (fail-at (nth toks i) "; が見つからない"))
      (let [t (nth toks j)]
        (cond
          (or (sym? t "(") (sym? t "[")) (recur (skip-balanced toks j))
          (sym? t ";") j
          :else (recur (inc j)))))))

(defn- body-opener?
  "class / interface の直後を見て、本体（end まで続く）が付くかを返す。"
  [toks j]
  (let [k (inc j)
        k (if (id? (nth toks k nil) "abstract" "sealed") (inc k) k)
        k (if (sym? (nth toks k nil) "(") (skip-balanced toks k) k)
        k (if (sym? (nth toks k nil) "[") (skip-balanced toks k) k)
        t (nth toks k nil)]
    (not (or (sym? t ";") (id? t "of")))))

(defn- scan-type-decl
  "型宣言の末尾（; の位置）を返す。record / class / object / interface / helper の
   本体は end まで読み飛ばす。"
  [toks i]
  (let [n (count toks)]
    (loop [j i blocks 0]
      (when (>= j n) (fail-at (nth toks i) "型宣言の終わりが見つからない"))
      (let [t (nth toks j)
            prev (nth toks (dec j) nil)]
        (cond
          (or (sym? t "(") (sym? t "[")) (recur (skip-balanced toks j) blocks)
          (sym? t ";") (if (zero? blocks) j (recur (inc j) blocks))
          (id? t "end") (recur (inc j) (dec blocks))
          (id? t "record") (recur (inc j) (inc blocks))
          (id? t "type") (if (id? (nth toks (inc j) nil) "helper")
                           (recur (+ j 2) (inc blocks))
                           (recur (inc j) blocks))
          (id? t "class")
          (cond
            (id? (nth toks (inc j) nil) "function" "procedure" "property" "var"
                 "constructor" "destructor" "operator" "const" "type")
            (recur (inc j) blocks)
            (id? (nth toks (inc j) nil) "helper") (recur (+ j 2) (inc blocks))
            (body-opener? toks j) (recur (inc j) (inc blocks))
            :else (recur (inc j) blocks))
          (id? t "object") (if (id? prev "of") (recur (inc j) blocks) (recur (inc j) (inc blocks)))
          (id? t "interface") (if (body-opener? toks j) (recur (inc j) (inc blocks)) (recur (inc j) blocks))
          :else (recur (inc j) blocks))))))

(defn- parse-type-decl [toks i]
  (let [name-tok (nth toks i)
        eq (nth toks (inc i) nil)]
    (when-not (= :id (:t name-tok))
      (fail-at name-tok "型宣言として読めない: " (:s name-tok)))
    (when (sym? eq "<")
      (fail-at name-tok "ジェネリクス " (:s name-tok) " は扱えない"))
    (when-not (sym? eq "=")
      (fail-at name-tok "型宣言として読めない: " (:s name-tok) " の次が = ではない"))
    (let [end (scan-type-decl toks (+ i 2))
          t2 (nth toks (+ i 2))
          t3 (nth toks (+ i 3) nil)
          name (:s name-tok)
          range [(:a name-tok) (:b (nth toks end))]]
      (cond
        ;; 前方宣言
        (and (id? t2 "class" "interface") (sym? t3 ";"))
        {:next (inc end) :decl nil}

        ;; type helper / record helper / class helper
        (and (id? t2 "type" "record" "class") (id? t3 "helper"))
        (let [k (+ i 4)
              [k] (if (sym? (nth toks k nil) "(") [(skip-balanced toks k)] [k])]
          (when-not (id? (nth toks k nil) "for")
            (fail-at name-tok "helper の for が見つからない: " name))
          (let [target (nth toks (inc k) nil)]
            (when-not (and target (= :id (:t target)))
              (fail-at name-tok "helper の対象が読めない: " name))
            {:next (inc end)
             :decl {:kind :helper :name name :keyword (str (:s t2) " helper")
                    :target (:s target) :range range}}))

        :else
        {:next (inc end) :decl {:kind :type :name name :range range}}))))

(defn- parse-const-decl [toks i]
  (let [name-tok (nth toks i)
        nxt (nth toks (inc i) nil)]
    (when-not (= :id (:t name-tok))
      (fail-at name-tok "定数宣言として読めない: " (:s name-tok)))
    (when (sym? nxt ":")
      (fail-at name-tok "型付き定数 " (:s name-tok) " は扱えない"))
    (when-not (sym? nxt "=")
      (fail-at name-tok "定数宣言として読めない: " (:s name-tok) " の次が = ではない"))
    {:next (inc (find-semicolon toks (+ i 2)))
     :decl {:kind :const :name (:s name-tok)}}))

(defn- split-groups
  "[from, to) のトークンを、括弧の外の ; で分ける。"
  [toks from to]
  (loop [j from cur [] acc []]
    (cond
      (>= j to) (if (seq cur) (conj acc cur) acc)
      (or (sym? (nth toks j) "(") (sym? (nth toks j) "["))
      (let [e (skip-balanced toks j)]
        (recur e (into cur (subvec toks j e)) acc))
      (sym? (nth toks j) ";") (recur (inc j) [] (conj acc cur))
      :else (recur (inc j) (conj cur (nth toks j)) acc))))

(defn- parse-param-group [clean g]
  (let [first-tok (first g)
        mod? (and (id? first-tok "const" "var" "out" "constref") (> (count g) 1)
                  (not (sym? (second g) ",")) (not (sym? (second g) ":")))
        body (if mod? (subvec g 1) g)
        colon (first (keep-indexed (fn [k t] (when (sym? t ":") k)) body))
        name-toks (if colon (subvec body 0 colon) body)
        names (vec (remove #(sym? % ",") name-toks))
        _ (when (or (empty? names) (not-every? #(= :id (:t %)) names))
            (fail-at first-tok "引数が読めない: " (slice clean (:a first-tok) (:b (peek g)))))
        eq (when colon
             (first (keep-indexed
                      (fn [k t] (when (and (> k colon) (sym? t "=")) k)) body)))
        impl-last (if eq (nth body (dec eq)) (peek g))]
    {:names (mapv :s names)
     :iface (slice clean (:a first-tok) (:b (peek g)))
     :impl (slice clean (:a first-tok) (:b impl-last))
     :mod (when mod? (str/lower-case (:s first-tok)))}))

(defn- parse-routine [clean toks i]
  (let [kw (str/lower-case (:s (nth toks i)))
        name-tok (nth toks (inc i) nil)
        _ (when-not (and name-tok (= :id (:t name-tok)))
            (fail-at (nth toks i) kw " の名前が読めない"))
        _ (when (or (sym? (nth toks (+ i 2) nil) ".") (sym? (nth toks (+ i 2) nil) "<"))
            (fail-at name-tok "メソッドの実装かジェネリクスらしい: " (:s name-tok)))
        j (+ i 2)
        [params j] (if (sym? (nth toks j nil) "(")
                     (let [e (skip-balanced toks j)]
                       [(mapv #(parse-param-group clean %) (split-groups toks (inc j) (dec e))) e])
                     [[] j])
        [result j] (if (= kw "function")
                     (do
                       (when-not (sym? (nth toks j nil) ":")
                         (fail-at name-tok "function の戻り値の型が読めない: " (:s name-tok)))
                       (let [semi (find-semicolon toks (inc j))]
                         [(slice clean (:a (nth toks (inc j))) (:b (nth toks (dec semi)))) semi]))
                     [nil j])
        semi (if (= kw "function")
               j
               (do (when-not (sym? (nth toks j nil) ";")
                     (fail-at name-tok "; が見つからない: " (:s name-tok)))
                   j))]
    (loop [h semi dirs #{}]
      (let [t (nth toks (inc h) nil)
            t2 (nth toks (+ h 2) nil)]
        (if (and t (= :id (:t t)) (sym? t2 ";")
                 (contains? known-directives (str/lower-case (:s t))))
          (let [d (str/lower-case (:s t))]
            (when-not (contains? allowed-directives d)
              (fail-at t "ディレクティブ " d " は扱えない（" (:s name-tok) "）"))
            (recur (+ h 2) (conj dirs d)))
          {:next (inc h)
           :decl {:kind :routine :keyword kw :name (:s name-tok)
                  :params params :result result :directives dirs}})))))

(defn- parse-interface
  "interface 部のトークン列から宣言の並びを返す。"
  [toks]
  (loop [i 0 section nil acc []]
    (if (>= i (count toks))
      acc
      (let [t (nth toks i)]
        (cond
          (id? t "uses") (recur (inc (find-semicolon toks i)) nil acc)
          (id? t "type") (recur (inc i) :type acc)
          (id? t "const") (recur (inc i) :const acc)
          (id? t "var" "threadvar" "resourcestring")
          (fail-at t "interface 部の " (:s t) " は扱えない")
          (id? t "operator") (fail-at t "最上位の operator は扱えない")
          (id? t "function" "procedure")
          (let [{:keys [next decl]} (parse-routine (:clean *where*) toks i)]
            (recur next nil (conj acc decl)))
          (= section :type)
          (let [{:keys [next decl]} (parse-type-decl toks i)]
            (recur next section (cond-> acc decl (conj decl))))
          (= section :const)
          (let [{:keys [next decl]} (parse-const-decl toks i)]
            (recur next section (conj acc decl)))
          :else (fail-at t "読めない構文: " (:s t)))))))

(defn- read-unit
  "ユニットの interface 部を読み、宣言の並びを返す。"
  [{:keys [unit dir]}]
  (let [path (str (or dir src-dir) "/" unit ".pas")]
    (when-not (fs/exists? path) (fail "ファイルが無い: " path))
    (let [src (slurp path)]
      (binding [*where* {:unit unit :src src}]
        (let [directives (atom [])
              clean (blank-comments src directives)
              toks (tokenize clean)
              start (first (keep-indexed (fn [k t] (when (id? t "interface") k)) toks))
              end (first (keep-indexed (fn [k t] (when (id? t "implementation") k)) toks))]
          (when-not (and start end (< start end))
            (fail path ": interface / implementation が見つからない"))
          (binding [*where* (assoc *where* :clean clean)]
            (let [decls (parse-interface (subvec toks (inc start) end))
                  ;; 型宣言の中（クラスの本体の {$IFDEF ...} など、メンバの出し分け）は
                  ;; 最上位の名前に影響しないので許す。それ以外は意味が変わりうる。
                  ranges (keep :range decls)]
              (doseq [d @directives
                      :when (< (:a (nth toks start)) (:a d) (:a (nth toks end)))
                      :when (not-any? (fn [[a b]] (< a (:a d) b)) ranges)]
                (fail (:unit *where*) ":" (line-of (:a d)) ": interface 部のコンパイラ指令 "
                      (:s d) " は読めない"))
              decls)))))))

;; ---------------------------------------------------------------- 選別と検査

(defn- excluded? [d]
  (and (= :routine (:kind d))
       (some #(str/starts-with? (str/lower-case (:name d)) %) excluded-prefixes)))

(defn- select-decls [{:keys [unit only]} decls]
  (let [decls (remove excluded? decls)]
    (if only
      (let [picked (filter #(and (= :routine (:kind %)) (contains? only (:name %))) decls)]
        (when (not= (count picked) (count only))
          (fail unit ": 並べる関数 " (pr-str only) " のうち見つかったのは "
                (pr-str (map :name picked))))
        picked)
      decls)))

(defn- check-names!
  "同じ名前が 2 度出たら止まる。関数どうしの同名（オーバーロード）だけは許す。"
  [per-unit]
  (let [all (for [[u decls] per-unit d decls] (assoc d :unit (:unit u)))]
    (doseq [[k ds] (group-by #(str/lower-case (:name %)) all)
            :when (> (count ds) 1)
            :when (not (every? #(= :routine (:kind %)) ds))]
      (fail "名前 " (:name (first ds)) " が 2 度出る: "
            (str/join ", " (map #(str (:unit %) "（" (name (:kind %)) "）") ds))))))

;; ---------------------------------------------------------------- 出力

(def ^:private line-limit 100)

(defn- header-text [d mode overloaded?]
  (let [groups (mapv (if (= mode :iface) :iface :impl) (:params d))
        tail (str (when (:result d) (str ": " (:result d))) ";"
                  (when (= mode :iface) (str " inline;" (when overloaded? " overload;"))))
        one (str (:keyword d) " " (:name d)
                 (when (seq groups) (str "(" (str/join "; " groups) ")")) tail)]
    (if (or (<= (count one) line-limit) (< (count groups) 2))
      one
      (str (:keyword d) " " (:name d) "(\n"
           (str/join ";\n" (map #(str "  " %) groups))
           ")" tail))))

(defn- call-text [unit d]
  (let [args (str/join ", " (mapcat :names (:params d)))
        call (str unit "." (:name d) (when (seq args) (str "(" args ")")))]
    (if (:result d)
      (str "  Result := " call ";")
      (str "  " call ";"))))

(defn- file-header [what unit-names]
  (str "// " what "\n"
       "// tools/genumbrella.bb が次のユニットの interface 部から生成する。手で直さず、\n"
       "// 生成器を直して作り直すこと（tools/genumbrella.bb --check が古さを調べる）。\n"
       (str/join "" (map #(str "//   " % "\n") unit-names))
       "\n"))

(defn- generate [per-unit]
  (let [routine-counts (frequencies (for [[_ ds] per-unit d ds :when (= :routine (:kind d))]
                                      (str/lower-case (:name d))))
        overloaded? #(> (get routine-counts (str/lower-case (:name %)) 0) 1)
        unit-names (map #(:unit (first %)) per-unit)
        iface (StringBuilder.)
        impl (StringBuilder.)
        counts (atom {:types 0 :helpers 0 :consts 0 :routines 0 :overloads 0})]
    (.append iface (file-header "アンブレラ（PaPiMeLa.pas）の interface 部に入る宣言。" unit-names))
    (.append impl (file-header "アンブレラ（PaPiMeLa.pas）の implementation 部に入る本体。" unit-names))
    (doseq [[{:keys [unit]} decls] per-unit
            :let [types (filter #(#{:type :helper} (:kind %)) decls)
                  consts (filter #(= :const (:kind %)) decls)
                  routines (filter #(= :routine (:kind %)) decls)]
            :when (seq decls)]
      (.append iface (str "// ---- " unit "\n"))
      (when (seq types)
        (.append iface "type\n")
        (doseq [d types]
          (if (= :helper (:kind d))
            (do (swap! counts update :helpers inc)
                (.append iface (format "  %s = %s(%s.%s) for %s end;\n"
                                       (:name d) (:keyword d) unit (:name d) (:target d))))
            (do (swap! counts update :types inc)
                (.append iface (format "  %s = %s.%s;\n" (:name d) unit (:name d)))))))
      (when (seq consts)
        (.append iface "const\n")
        (doseq [d consts]
          (swap! counts update :consts inc)
          (.append iface (format "  %s = %s.%s;\n" (:name d) unit (:name d)))))
      (when (seq routines)
        (.append impl (str "// ---- " unit "\n"))
        (doseq [d routines]
          (swap! counts update :routines inc)
          (when (overloaded? d) (swap! counts update :overloads inc))
          (.append iface (str (header-text d :iface (overloaded? d)) "\n"))
          (.append impl (str (header-text d :impl false) "\n"
                             "begin\n" (call-text unit d) "\nend;\n\n"))))
      (.append iface "\n"))
    {:interface (str iface) :implementation (str impl) :counts @counts}))

(defn- build []
  (let [per-unit (vec (for [u units] [u (select-decls u (read-unit u))]))]
    (check-names! per-unit)
    (generate per-unit)))

(let [check? (some #{"--check"} *command-line-args*)
      unknown (remove #{"--check"} *command-line-args*)
      _ (when (seq unknown) (fail "知らない引数: " (str/join " " unknown)))
      {:keys [counts] :as out} (build)
      {:keys [types helpers consts routines overloads]} counts]
  (when (zero? (+ types helpers consts routines))
    (fail "宣言が 1 つも見つからない"))
  (if check?
    (let [stale (for [[path text] [[interface-file (:interface out)]
                                   [implementation-file (:implementation out)]]
                      :when (or (not (fs/exists? path)) (not= (slurp path) text))]
                  path)]
      (when (seq stale)
        (binding [*out* *err*]
          (doseq [p stale] (println "genumbrella: 古い:" p))
          (println "genumbrella: tools/genumbrella.bb で作り直すこと"))
        (System/exit 1))
      (println "genumbrella: 最新"))
    (do
      (fs/create-dirs out-dir)
      (spit interface-file (:interface out))
      (spit implementation-file (:implementation out))))
  (println (format "genumbrella: 型 %d、helper %d、定数 %d、関数 %d（うちオーバーロード %d）"
                   types helpers consts routines overloads)))
