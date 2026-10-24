#!/usr/bin/env bb
;; gen — tools/messagebox-expect/mb_cases.c を参照版の SDL に通して、記録を test/messagebox_expected.inc に書く。
;;
;; 使い方:
;;   tools/messagebox-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所。ダイアログ（SDL_zenitymessagebox.c）を入れて作る。他は何も要らない:
;;       cmake -G Ninja -S reference/SDL -B <場所> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON \
;;         -DSDL_TESTS=OFF -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF \
;;         -DSDL_AUDIO=OFF -DSDL_GPU=OFF -DSDL_VULKAN=OFF -DSDL_CAMERA=OFF -DSDL_SENSOR=OFF -DSDL_DIALOG=ON \
;;         -DSDL_TRAY=OFF -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_HIDAPI=OFF -DCMAKE_BUILD_TYPE=Release && ninja -C <場所>
;;     zenity 本物は要らない。test/fake-zenity/zenity（偽物）を PATH の先頭に置く。
;;
;; 確かめること: 場面が 30 以上、zenity が動いた場面の引数が記録されている

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "mbexp"})))
(def ^:private exe (str tmp "/mb_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/messagebox-expect/mb_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private r (shell {:out :string :err :string :continue true} exe (str (fs/absolutize "test/fake-zenity")) (str tmp "/log")))
(when-not (zero? (:exit r)) (fail "mb_cases が失敗:\n" (:err r)))
(def ^:private rows (map #(subs % 2) (filter #(str/starts-with? % "L ") (str/split-lines (:out r)))))
(when (< (count (filter #(str/starts-with? % "C ") rows)) 30) (fail "場面が少ない"))
(when (zero? (count (filter #(str/starts-with? % "A 0 --question") rows))) (fail "引数が記録されていない"))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/messagebox_expected.inc"
      (str "{ test/messagebox_expected.inc — tools/messagebox-expect/gen.bb が作る。手で直さない。\n"
           "  参照版 SDL の SDL_Zenity_ShowMessageBox の記録。C = 場面、A = zenity に渡った引数（番号 値）、R = 結果と押されたボタンの ID。 }\n\n"
           "const\n  MessageBoxExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
