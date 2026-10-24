#!/usr/bin/env bb
;; genjoystick — ジョイスティックの VID/PID の表とコントローラの表を SDL から Pascal へ写す。
;;
;; なぜ要るか:
;;   SDL_joystick.c の 11 の VID/PID の表（ホイール・アーケードスティック・禁止の機器など、数百行）と
;;   controller_list.h（Valve の 600 余りのコントローラの表）は、手でも qwen でも写さない
;;   （CLAUDE.md: 大きな表は生成器で作る）。
;;
;; 使い方:
;;   tools/genjoystick.bb    reference/SDL/src/joystick/{SDL_joystick.c,controller_list.h} から
;;                           src/generated/joystick_tables.inc を作る
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 各表の項目数が、元の MAKE_VIDPID / MAKE_CONTROLLER_ID の行数（コメントアウトを除く）と一致する
;;   - コントローラの種類の名前が、controller_type.h の列挙に全部ある
;;   - 同じ VID/PID の二重は報告だけする（SDL の表にも二重がある。探索は先頭から見るだけなので結果は同じ）

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private src-joy "reference/SDL/src/joystick/SDL_joystick.c")
(def ^:private src-list "reference/SDL/src/joystick/controller_list.h")
(def ^:private src-type "reference/SDL/src/joystick/controller_type.h")
(def ^:private out "src/generated/joystick_tables.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genjoystick: " msg)))
  (System/exit 1))

(doseq [f [src-joy src-list src-type]]
  (when-not (fs/exists? f) (fail f " が無い。reference/SDL を用意すること（docs/ORIGIN.md）")))

(def ^:private joy (slurp src-joy))

;; ---- VID/PID の表 ----
;; static Uint32 initial_xxx[] = { MAKE_VIDPID(0x0079, 0x18a1), // 名前 ... };
(def ^:private list-names
  [["old_xboxone_controllers" "OldXboxOneControllers"]
   ["arcadestick_devices" "ArcadeStickDevices"]
   ["blacklist_devices" "BlacklistDevices"]
   ["flightstick_devices" "FlightStickDevices"]
   ["gamecube_devices" "GameCubeDevices"]
   ["rog_gamepad_mice" "ROGGamepadMice"]
   ["throttle_devices" "ThrottleDevices"]
   ["wheel_devices" "WheelDevices"]
   ["guitar_devices" "GuitarDevices"]
   ["drum_devices" "DrumDevices"]
   ["zero_centered_devices" "ZeroCenteredDevices"]])

(defn- vidpid-entries [name]
  (let [m (re-find (re-pattern (str "(?s)static Uint32 initial_" name "\\[\\] = \\{(.*?)\\n\\};")) joy)]
    (when-not m (fail "表が見つからない: initial_" name))
    (->> (str/split-lines (second m))
         (map str/trim)
         (remove #(str/starts-with? % "//"))
         (keep (fn [line]
                 (when-let [[_ v p c] (re-find #"MAKE_VIDPID\(\s*0[xX]([0-9a-fA-F]+)\s*,\s*0[xX]([0-9a-fA-F]+)\s*\)\s*,?\s*(?://\s*(.*))?" line)]
                   {:vid (str/lower-case v) :pid (str/lower-case p) :comment (some-> c str/trim)}))))))

(defn- expected-count [name]
  ;; 元の行数。コメントアウトされた行（// MAKE_VIDPID）は数えない
  (let [m (re-find (re-pattern (str "(?s)static Uint32 initial_" name "\\[\\] = \\{(.*?)\\n\\};")) joy)]
    (->> (str/split-lines (second m))
         (map str/trim)
         (remove #(str/starts-with? % "//"))
         (filter #(str/includes? % "MAKE_VIDPID("))
         count)))

(defn- pascal-comment [s]
  (when s (str "  // " (str/replace s #"[{}]" ""))))

(def ^:private list-blocks
  (for [[c p] list-names]
    (let [es (vidpid-entries c)
          n (expected-count c)]
      (when-not (= n (count es)) (fail c ": " (count es) " 件を読んだが、元は " n " 件"))
      (let [ids (map (fn [e] (str (:vid e) (:pid e))) es)]
        (when-not (= (count ids) (count (set ids)))
          ;; 元の表にも二重がある。そのまま写す（探索は先頭から見るだけなので結果は変わらない）
          (println "genjoystick: 注意:" c "に二重の VID/PID があります:" (first (first (filter (fn [[_ n]] (> n 1)) (frequencies ids))))))
        (str "  Joystick" p "Initial: array[0.." (dec (count es)) "] of LongWord = (\n"
             (str/join "\n"
                       (map-indexed (fn [i e] (str "    $" (:vid e) (:pid e) (if (< i (dec (count es))) "," "") (pascal-comment (:comment e)))) es))
             "\n  );\n")))))

;; ---- コントローラの表 ----
(def ^:private type-values
  (let [t (slurp src-type)]
    (into {} (map (fn [[_ n v]] [n (Integer/parseInt v)])
                  (re-seq #"k_eControllerType_(\w+)\s*=\s*(-?\d+)" t)))))

(def ^:private controller-lines
  (->> (str/split-lines (slurp src-list))
       (map str/trim)
       (remove #(str/starts-with? % "//"))
       (filter #(str/starts-with? % "{ MAKE_CONTROLLER_ID"))))

(def ^:private controllers
  (map (fn [line]
         (if-let [[_ v p t n] (re-find #"MAKE_CONTROLLER_ID\s*\(\s*0[xX]([0-9a-fA-F]+)\s*,\s*0[xX]([0-9a-fA-F]+)\s*\)\s*,\s*k_eControllerType_(\w+)\s*,\s*(NULL|\"[^\"]*\")" line)]
           (let [tv (get type-values t)]
             (when-not tv (fail "controller_type.h に無い種類: " t))
             {:vid (str/lower-case v) :pid (str/lower-case p) :type tv :tname t
              :name (if (= n "NULL") nil (subs n 1 (dec (count n))))})
           (fail "読めない行: " line)))
       controller-lines))

(let [raw (->> (str/split-lines (slurp src-list))
               (map str/trim)
               (remove #(str/starts-with? % "//"))
               (remove #(str/starts-with? % "#define"))
               (filter #(str/includes? % "MAKE_CONTROLLER_ID")))]
  (when-not (= (count raw) (count controllers))
    (fail "controller_list.h: " (count raw) " 行のうち " (count controllers) " 件しか読めなかった（MAKE_CONTROLLER_ID の #define 行を除く）")))

(let [ids (map (fn [c] (str (:vid c) (:pid c))) controllers)
      dup (filter (fn [[_ n]] (> n 1)) (frequencies ids))]
  (when (seq dup)
    ;; 元の表に重複があっても、先に出た方が使われる（SDL の線形探索）。報告だけして続ける
    (println "genjoystick: 注意: controller_list.h に二重の VID/PID があります（先頭が使われる）:" (str/join "," (map first dup)))))

(defn- pas-string [s]
  (str "'" (str/replace s "'" "''") "'"))

(spit out
      (str "{ src/generated/joystick_tables.inc — tools/genjoystick.bb が作る。手で直さない。\n"
           "  SDL の joystick/SDL_joystick.c の VID/PID の表 " (count list-names) " 個と、controller_list.h（Valve。zlib）の\n"
           "  コントローラの表 " (count controllers) " 件。 }\n\n"
           "const\n"
           (str/join "\n" list-blocks)
           "\n  // コントローラの表（controller_list.h）。Kind は controller_type.h の値、Name は無ければ空。\n"
           "  JoystickControllerTable: array[0.." (dec (count controllers)) "] of record\n"
           "    DeviceID: LongWord;\n"
           "    Kind    : Integer;\n"
           "    Name    : String;\n"
           "  end = (\n"
           (str/join ",\n"
                     (map (fn [c] (str "    (DeviceID: $" (:vid c) (:pid c) "; Kind: " (:type c)
                                       "; Name: " (if (:name c) (pas-string (:name c)) "''") ")"))
                          controllers))
           "\n  );\n"))
(println (format "genjoystick: VID/PID の表 %d 個（%s 件）、コントローラ %d 件を %s に書いた"
                 (count list-names)
                 (str/join "+" (map #(count (vidpid-entries (first %))) list-names))
                 (count controllers) out))
