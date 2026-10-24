#!/usr/bin/env bb
;; gen — tools/haptic-expect/haptic_cases.c を SDL に通して、結果を test/haptic_expected.inc に書く。
;;
;; 使い方:
;;   tools/haptic-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所（参照版 SDL を静的に作る。作り方は docs/HANDOFF.md §2.1。
;;     ジョイスティックの期待値と同じ /home/joerg/claude-work/sdl-ref-build-joy でよい）。
;;
;; SDL の C の関数（static）の本文は、手で写さずにソースから抜き出して使う:
;;   reference/SDL/src/haptic/linux/SDL_syshaptic.c の SDL_SYS_ToButton から SDL_SYS_ToFFEffect の終わりまで
;;   reference/SDL/src/haptic/SDL_haptic.c の SDL_Haptic_VIDPID_Naxes から SDL_Haptic_Get_Naxes の終わりまで
;; 抜き出しの始まりと終わりの目印が見つからなければ止まる。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))

(defn- extract
  "ファイルの行のうち、start に合う最初の行から、end に合う最初の行の手前まで。"
  [path start-re end-re]
  (let [lines (str/split-lines (slurp path))
        from (first (keep-indexed (fn [i l] (when (re-find start-re l) i)) lines))]
    (when-not from (fail path " に始まりの目印が無い: " start-re))
    (let [rest-lines (drop from lines)
          to (first (keep-indexed (fn [i l] (when (and (pos? i) (re-find end-re l)) i)) rest-lines))]
      (when-not to (fail path " に終わりの目印が無い: " end-re))
      (let [body (take to rest-lines)
            ;; 終わりの目印の直前の「/*」（次の関数の説明の始まり）は切る
            body (if (= "/*" (str/trim (last body))) (butlast body) body)]
        (str/join "\n" body)))))

(def ^:private toffeffect
  (extract "reference/SDL/src/haptic/linux/SDL_syshaptic.c"
           #"^static Uint16 SDL_SYS_ToButton" #"Creates a new haptic effect"))
(def ^:private naxes
  (extract "reference/SDL/src/haptic/SDL_haptic.c"
           #"^typedef struct SDL_Haptic_VIDPID_Naxes" #"^static SDL_Haptic \*SDL_haptics"))
(when-not (str/includes? toffeffect "SDL_SYS_ToFFEffect") (fail "ToFFEffect を抜き出せていない"))
(when-not (str/includes? naxes "SDL_Haptic_Get_Naxes") (fail "Get_Naxes を抜き出せていない"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "hapexp"})))
(spit (str tmp "/gen_toffeffect.inc") toffeffect)
(spit (str tmp "/gen_naxes.inc") naxes)
(def ^:private exe (str tmp "/haptic_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" (str "-I" tmp) "tools/haptic-expect/haptic_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(def ^:private rows (filter #(re-find #"^[EN] " %) (str/split-lines out)))
(fs/delete-tree tmp)
(when (zero? (count rows)) (fail "場面が 0 行"))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/haptic_expected.inc"
      (str "{ test/haptic_expected.inc — tools/haptic-expect/gen.bb が作る。手で直さない。\n"
           "  SDL の SDL_SYS_ToFFEffect と SDL_Haptic_Get_Naxes の本文を、そのまま動かした結果。1 行 = 1 場面:\n"
           "  'E 型 値... ok ff_effect の 48 バイト（16 進、失敗は -）'（効果の変換。値の並びは tools/haptic-expect/haptic_cases.c）、\n"
           "  'N ヒントの文字列（16 進、空は -） vid pid 結果'（ヒントの軸の数）。 }\n\n"
           "const\n  HapticExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
