#!/usr/bin/env bb
;; gen — tools/gamepad-expect/{map_cases.c,gp_cases.c} を参照版の SDL に通して、記録を test/ に書く。
;;
;;   map_cases.c  マッピングの DB（AddMapping 系）   -> test/gamepad_mapping_expected.inc
;;   gp_cases.c   機器・開いたゲームパッド・イベント -> test/gamepad_expected.inc
;;
;; 使い方:
;;   tools/gamepad-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所。ジョイスティックと仮想ジョイスティックを入れて作る（tools/joystick-expect/gen.bb と同じ）:
;;       cmake -G Ninja -S reference/SDL -B <場所> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON \
;;         -DSDL_TESTS=OFF -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF \
;;         -DSDL_AUDIO=OFF -DSDL_GPU=OFF -DSDL_VULKAN=OFF -DSDL_CAMERA=OFF -DSDL_SENSOR=OFF -DSDL_DIALOG=OFF \
;;         -DSDL_TRAY=OFF -DSDL_JOYSTICK=ON -DSDL_HAPTIC=ON -DSDL_HIDAPI=ON -DSDL_HIDAPI_JOYSTICK=OFF \
;;         -DSDL_HIDAPI_LIBUSB=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS=-ffp-contract=off && ninja -C <場所>
;;     実機のジョイスティックが繋がっていると、場面の前提が崩れるので止まる。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "gpexp"})))

(defn- q [s] (str "'" (str/replace s "'" "''") "'"))

(defn- run-one [src out-file const-name what]
  (let [exe (str tmp "/" (fs/file-name src) ".exe")
        r (shell {:continue true :err :string :out :string}
                 "cc" "-O1" "-w" "-Ireference/SDL/include" src "-o" exe
                 (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
    (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r)))
    (let [out (:out (shell {:out :string :err :string} exe))]
      (when (str/includes? out "INIT-ERR") (fail out))
      (let [rows (map #(subs % 2) (filter #(str/starts-with? % "L ") (str/split-lines out)))]
        (spit out-file
              (str "{ " out-file " — tools/gamepad-expect/gen.bb が作る。手で直さない。\n"
                   "  参照版 SDL の" what "の記録。1 行 = 1 行。引数の改行などは \\n \\r \\\\ に書く。 }\n\n"
                   "const\n  " const-name ": array[0.." (dec (count rows)) "] of String = (\n"
                   (str/join ",\n" (map #(str "    " (q %)) rows))
                   "\n  );\n"))
        (println (format "gen: %s に %d 行を書いた" out-file (count rows)))))))

(run-one "tools/gamepad-expect/map_cases.c" "test/gamepad_mapping_expected.inc" "GamepadMapExpected"
         "ゲームパッドのマッピングの DB ('> 操作' とその結果 '= ...')")
(run-one "tools/gamepad-expect/gp_cases.c" "test/gamepad_expected.inc" "GamepadExpected"
         "ゲームパッドの機器・開いたゲームパッド・イベント")
