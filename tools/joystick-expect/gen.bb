#!/usr/bin/env bb
;; gen — tools/joystick-expect/joy_cases.c を SDL に通して、結果を test/joystick_expected.inc に書く。
;;
;; 使い方:
;;   tools/joystick-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所。ジョイスティックと仮想ジョイスティックを入れて作る:
;;       cmake -G Ninja -S reference/SDL -B <場所> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON \
;;         -DSDL_TESTS=OFF -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF \
;;         -DSDL_AUDIO=OFF -DSDL_GPU=OFF -DSDL_VULKAN=OFF -DSDL_CAMERA=OFF -DSDL_SENSOR=OFF -DSDL_DIALOG=OFF \
;;         -DSDL_TRAY=OFF -DSDL_JOYSTICK=ON -DSDL_HAPTIC=ON -DSDL_HIDAPI=ON -DSDL_HIDAPI_JOYSTICK=OFF \
;;         -DSDL_HIDAPI_LIBUSB=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS=-ffp-contract=off && ninja -C <場所>
;;     （仮想ジョイスティックは SDL_HIDAPI が ON でないと作られない。cmake の依存の付き方）
;;     実機のジョイスティックが繋がっていると、場面の前提が崩れるので止まる。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "joyexp"})))
(def ^:private exe (str tmp "/joy_cases"))
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O1" "-w" "-Ireference/SDL/include" "tools/joystick-expect/joy_cases.c" "-o" exe
               (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(when (str/includes? out "INIT-ERR") (fail out))
(def ^:private rows (map #(subs % 2) (filter #(str/starts-with? % "L ") (str/split-lines out))))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/joystick_expected.inc"
      (str "{ test/joystick_expected.inc — tools/joystick-expect/gen.bb が作る。手で直さない。\n"
           "  参照版 SDL のジョイスティックのコアと仮想ジョイスティックの記録。1 行 = 1 行。\n"
           "  '== 場面'、'-- 更新'（その後に出たイベント）、'ev ...'（イベント）、'cb ...'（仮想の呼び出し）など。 }\n\n"
           "const\n  JoystickExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q %)) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
