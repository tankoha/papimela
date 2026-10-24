#!/usr/bin/env bb
;; gen — tools/evdev-expect/caps_cases.c を参照版の SDL に通して、test/evdev_caps_expected.inc に書く。
;;
;; 使い方:
;;   tools/evdev-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所（tools/gamepad-expect/gen.bb と同じ作り方。SDL_EVDEV_GuessDeviceClass は
;;     libSDL3.a の中の内部の関数で、直接呼べる）。
;;
;; 確かめること: 書く行が 1 行以上あり、出力の種類が 6 通り以上出る（枝が通っている）

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "evexp"})))

(defn- q [s] (str "'" (str/replace s "'" "''") "'"))

(defn- run-one [src exe-name out-file const-name header min-kinds]
  (let [exe (str tmp "/" exe-name)
        r (shell {:continue true :err :string :out :string}
                 "cc" "-O1" "-w" "-Ireference/SDL/include" src "-o" exe
                 (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
    (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r)))
    (let [out (:out (shell {:out :string :err :string} exe))
          rows (map #(subs % 2) (filter #(str/starts-with? % "L ") (str/split-lines out)))]
      (when (empty? rows) (fail "行が無い: " src))
      (when (< (count (set (map #(last (str/split % #"[=|]")) rows))) min-kinds)
        (fail "出力の種類が少なすぎる: " src))
      (spit out-file
            (str "{ " out-file " — tools/evdev-expect/gen.bb が作る。手で直さない。\n  " header " }\n\n"
                 "const\n  " const-name ": array[0.." (dec (count rows)) "] of String = (\n"
                 (str/join ",\n" (map #(str "    " (q %)) rows))
                 "\n  );\n"))
      (println (format "gen: %s に %d 行を書いた" out-file (count rows))))))

(run-one "tools/evdev-expect/caps_cases.c" "caps" "test/evdev_caps_expected.inc" "EvdevCapsExpected"
         "参照版 SDL の SDL_EVDEV_GuessDeviceClass に通した能力のビットと種類。p・e・a・k・r はプロパティ・イベント・絶対軸・キー・相対軸のビット（メモリ上のバイトを先頭から並べた 16 進）。" 6)
(run-one "tools/evdev-expect/names_cases.c" "names" "test/joystick_names_expected.inc" "JoystickNamesExpected"
         "参照版 SDL の SDL_CreateJoystickName に通した、ベンダーとプロダクトとベンダー名と製品名（|で区切る）と、結果の名前。" 6)
