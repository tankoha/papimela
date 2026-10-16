#!/usr/bin/env bb
;; gen — tools/texture-colorkey-expect/colorkey_cases.c を SDL に通して、結果を test/texture_colorkey_expected.inc に書く。
;;
;; 使い方:
;;   tools/texture-colorkey-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所。参照版 SDL（reference/SDL）を表示サーバ無しで静的に作る
;;     （docs/HANDOFF.md §6、docs/TEST-LOG.md の使い捨て検証）:
;;       cmake -G Ninja -S reference/SDL -B <場所> -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_SHARED=OFF -DSDL_STATIC=ON \
;;         -DSDL_TESTS=OFF -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF \
;;         -DSDL_AUDIO=OFF -DSDL_GPU=OFF -DSDL_VULKAN=OFF -DSDL_CAMERA=OFF -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF \
;;         -DSDL_SENSOR=OFF -DSDL_DIALOG=OFF -DSDL_TRAY=OFF -DCMAKE_BUILD_TYPE=Release && ninja -C <場所>
;;     システムの SDL（3.4.2）に通すなら、場所の代わりに system を渡す（3.4.2 は参照版と違う所がある）。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所（または system）を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "ckexp"})))
(def ^:private exe (str tmp "/colorkey_cases"))
(def ^:private link
  (if (= where "system")
    ["-l:libSDL3.so.0"]
    [(str where "/libSDL3.a") "-lm" "-lpthread" "-ldl"]))
(let [r (apply shell {:continue true :err :string :out :string}
               (concat ["cc" "-O1" "-w" "-Ireference/SDL/include" "tools/texture-colorkey-expect/colorkey_cases.c" "-o" exe] link))]
  (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} exe)))
(def ^:private rows (filter #(str/starts-with? % "R ") (str/split-lines out)))
(when (str/includes? out "INIT-ERR") (fail out))
(defn- q [s] (str "'" (str/replace s "'" "''") "'"))
(spit "test/texture_colorkey_expected.inc"
      (str "{ test/texture_colorkey_expected.inc — tools/texture-colorkey-expect/gen.bb が作る。手で直さない。\n"
           "  SDL（" (if (= where "system") "システムの 3.4.2" "参照版") "）のソフトウェアのレンダラに、SDL_CreateTextureFromSurface を通した結果。\n"
           "  1 行 = 1 場面。'<場面> <テクスチャの形式> blend=.. cmod=.. amod=.. <ハッシュ> <ハッシュ（ブレンド無し）>。 }\n\n"
           "const\n  ColorKeyExpected: array[0.." (dec (count rows)) "] of String = (\n"
           (str/join ",\n" (map #(str "    " (q (subs % 2))) rows))
           "\n  );\n"))
(println (format "gen: %d 行を書いた" (count rows)))
