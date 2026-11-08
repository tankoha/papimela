#!/usr/bin/env bb
;; gen — tools/pen-expect/pen_cases.c を参照版の SDL に通して、手順と結果を
;;       test/test_pen_cases.inc（T-87）と test/test_wayland_tablet_cases.inc（T-88）に書く。
;;
;; 使い方:
;;   tools/pen-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所。SDL_AddPenDevice などは内部の関数なので、共有ライブラリでは使えない。
;;     作り方は docs/HANDOFF.md §2.1 の cmake の引数（ビデオの dummy は既定で入る。-DSDL_VIDEO は切らない）。
;;     MALLOC_PERTURB_ を変えて 2 回動かし、出力が同じでなければ止まる（初期化していない値を拾っていないか）。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "penexp"})))
(def ^:private exe (str tmp "/pen_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/pen-expect/pen_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))

(defn- run [mode perturb]
  (let [r (shell {:continue true :out :string :err :string
                  :extra-env {"MALLOC_PERTURB_" (str perturb) "SDL_VIDEO_DRIVER" "dummy"}}
                 exe mode)]
    (when-not (zero? (:exit r)) (fail mode " が失敗:\n" (:err r) (:out r)))
    (when (str/includes? (:out r) "INIT-ERR") (fail (:out r)))
    (:out r)))

(defn- q [s] (str "'" (str/replace s "'" "''") "'"))

;; SDL のマウスのボタン番号は 1 左、2 中、3 右。papimela は 1 左、2 右、3 中（Seat の BTN_RIGHT → 2、
;; BTN_MIDDLE → 3）。期待値の MouseButtonDown / Up の番号だけを papimela の番号に直す
;; （X1 = 4、X2 = 5 は同じ）。
(defn- papimela-button [row]
  (let [f (str/split row #" ")]
    (if (and (= (count f) 7) (#{"MouseButtonDown" "MouseButtonUp"} (nth f 1)))
      (str/join " " (assoc f 4 (case (nth f 4) "2" "3" "3" "2" (nth f 4))))
      row)))

(defn- write [mode file const what]
  (let [a (run mode 0) b (run mode 165)]
    (when-not (= a b) (fail mode " の出力が MALLOC_PERTURB_ で変わる"))
    (let [rows (map papimela-button (filter #(re-find #"^[NSERC] " %) (str/split-lines a)))]
      (spit file
            (str "{ " file " — tools/pen-expect/gen.bb が作る。手で直さない。\n"
                 "  " what "\n"
                 "  1 行ずつ: 'N 場面'、'S 手順'、'E イベント'、'R 問い合わせの答え'、'C カーソルの要求'。\n"
                 "  形式は tools/pen-expect/pen_cases.c の頭。 }\n\n"
                 "const\n  " const ": array[0.." (dec (count rows)) "] of String = (\n"
                 (str/join ",\n" (map #(str "    " (q %)) rows))
                 "\n  );\n"))
      (println (format "gen: %s に %d 行を書いた" file (count rows))))))

(write "pen" "test/test_pen_cases.inc" "PenCases"
       "参照版 SDL の SDL_pen.c（SDL_AddPenDevice / SDL_SendPen* ほか）に手順を通した結果。")
(write "tablet" "test/test_wayland_tablet_cases.inc" "TabletCases"
       "SDL_waylandevents.c の tablet_tool_handle_* の写しに tablet-v2 の知らせの列を通した結果。")
