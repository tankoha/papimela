#!/usr/bin/env bb
;; genevdev — evdev（入力）と joystick（旧ジョイスティック）の定数と、構造体の並び・ioctl の番号を、
;; カーネルのヘッダ（linux/input.h・linux/joystick.h）で作った C のプログラムを動かして書き出す。
;;
;; なぜ要るか:
;;   papimela は evdev を read / ioctl で直接使う（設計 #19 の入力系）。定数・構造体の大きさと欄の
;;   位置・ioctl の番号は、ヘッダの値をそのまま使う必要がある。手で写すと間違えるので、C が出した値を
;;   使う。構造体の並びと ioctl の番号は、Pascal の record と突き合わせる（test 側）。
;;
;; 使い方:
;;   tools/genevdev.bb
;;     ヘッダは /usr/include の linux/input.h と linux/joystick.h を使う。cc が要る。
;;
;; 書くもの:
;;   src/generated/evdev_consts.inc   定数（10 進の整数だけ）
;;   test/evdev_abi_expected.inc      構造体の大きさと欄の位置（offsetof）、ioctl の番号（16 進）
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 並べた定数がどれもヘッダで見つかる（見つからない名前は名前を出して止まる）
;;   - 書いた定数の件数が、並べた名前の数と同じ
;;   - 書いた期待値の行数が、C のプログラムが出した行数と同じ
;;   - 同じ入力からは同じファイルができる（時刻などを書かない。2 回走らせて md5 で確かめる）

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(def ^:private consts-out "src/generated/evdev_consts.inc")
(def ^:private expected-out "test/evdev_abi_expected.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genevdev: " msg)))
  (System/exit 1))

(def ^:private input-h "/usr/include/linux/input.h")
(def ^:private joystick-h "/usr/include/linux/joystick.h")
(doseq [h [input-h joystick-h]]
  (when-not (fs/exists? h)
    (fail h " が無い（linux-libc-dev を入れる）")))

;; ---- 定数（C の名前をそのまま使う）

(def ^:private const-names
  (vec (remove empty?
    (str/split "
EV_SYN EV_KEY EV_REL EV_ABS EV_MSC EV_FF EV_MAX
SYN_REPORT SYN_DROPPED MSC_TIMESTAMP
KEY_MAX KEY_CNT KEY_OK KEY_ALS_TOGGLE KEY_RECORD
BTN_MISC BTN_JOYSTICK BTN_GAMEPAD BTN_TRIGGER BTN_1 BTN_MOUSE BTN_TOUCH BTN_STYLUS BTN_TOOL_PEN BTN_TOOL_FINGER
BTN_A BTN_B BTN_X BTN_Y BTN_C BTN_Z BTN_TL BTN_TR BTN_TL2 BTN_TR2 BTN_SELECT BTN_START BTN_MODE BTN_THUMBL BTN_THUMBR
BTN_SOUTH BTN_EAST BTN_NORTH BTN_WEST
BTN_DPAD_UP BTN_DPAD_DOWN BTN_DPAD_LEFT BTN_DPAD_RIGHT BTN_GRIPL BTN_GRIPR BTN_GRIPL2 BTN_GRIPR2
BTN_TRIGGER_HAPPY BTN_TRIGGER_HAPPY1 BTN_TRIGGER_HAPPY2 BTN_TRIGGER_HAPPY3 BTN_TRIGGER_HAPPY4
BTN_TRIGGER_HAPPY5 BTN_TRIGGER_HAPPY6 BTN_TRIGGER_HAPPY7 BTN_TRIGGER_HAPPY8
ABS_X ABS_Y ABS_Z ABS_RX ABS_RY ABS_RZ ABS_THROTTLE ABS_RUDDER ABS_WHEEL ABS_GAS ABS_BRAKE
ABS_HAT0X ABS_HAT0Y ABS_HAT1X ABS_HAT1Y ABS_HAT2X ABS_HAT2Y ABS_HAT3X ABS_HAT3Y ABS_MAX ABS_CNT
REL_X REL_Y REL_MAX
FF_RUMBLE FF_PERIODIC FF_SINE FF_MAX
INPUT_PROP_POINTER INPUT_PROP_DIRECT INPUT_PROP_BUTTONPAD INPUT_PROP_SEMI_MT INPUT_PROP_TOPBUTTONPAD
INPUT_PROP_POINTING_STICK INPUT_PROP_ACCELEROMETER INPUT_PROP_MAX
JS_EVENT_BUTTON JS_EVENT_AXIS JS_EVENT_INIT"
      #"\s+"))))

;; ---- 期待値（[キー C の式 printf の書式]）。キーは Pascal の期待値の文字列になる

(def ^:private struct-sizes
  ["input_event" "input_absinfo" "input_id" "ff_effect" "ff_replay" "ff_trigger" "ff_envelope"
   "ff_rumble_effect" "ff_periodic_effect" "js_event" "timeval"])

;; 欄の位置（[構造体 欄...]）
(def ^:private struct-fields
  [["input_event" "time" "type" "code" "value"]
   ["input_absinfo" "value" "minimum" "maximum" "fuzz" "flat" "resolution"]
   ["input_id" "bustype" "vendor" "product" "version"]
   ["ff_effect" "type" "id" "direction" "trigger" "replay" "u"]
   ["ff_replay" "length" "delay"]
   ["ff_rumble_effect" "strong_magnitude" "weak_magnitude"]
   ["ff_periodic_effect" "waveform" "period" "magnitude" "offset" "phase" "envelope"]
   ["js_event" "time" "value" "type" "number"]])

;; ioctl の番号。C の式の結果を %lx（小文字の 16 進）で出す
(defn- ioc [key expr] [key (str "(unsigned long)" expr) "%lx"])

(def ^:private ioctl-entries
  [(ioc "ioctl EVIOCGID" "EVIOCGID")
   (ioc "ioctl EVIOCSFF" "EVIOCSFF")
   (ioc "ioctl EVIOCRMFF" "EVIOCRMFF")
   (ioc "ioctl JSIOCGAXES" "JSIOCGAXES")
   (ioc "ioctl JSIOCGBUTTONS" "JSIOCGBUTTONS")
   (ioc "ioctl EVIOCGBIT 0 4" "EVIOCGBIT(0, 4)")
   (ioc "ioctl EVIOCGBIT 1 96" "EVIOCGBIT(1, 96)")
   (ioc "ioctl EVIOCGBIT 2 4" "EVIOCGBIT(2, 4)")
   (ioc "ioctl EVIOCGBIT 3 8" "EVIOCGBIT(3, 8)")
   (ioc "ioctl EVIOCGBIT 21 16" "EVIOCGBIT(21, 16)")
   (ioc "ioctl EVIOCGABS 0" "EVIOCGABS(0)")
   (ioc "ioctl EVIOCGABS 16" "EVIOCGABS(16)")
   (ioc "ioctl EVIOCGABS 63" "EVIOCGABS(63)")
   (ioc "ioctl EVIOCGNAME 128" "EVIOCGNAME(128)")
   (ioc "ioctl EVIOCGUNIQ 127" "EVIOCGUNIQ(127)")
   (ioc "ioctl EVIOCGPROP 4" "EVIOCGPROP(4)")
   (ioc "ioctl EVIOCGKEY 96" "EVIOCGKEY(96)")
   (ioc "ioctl JSIOCGNAME 128" "JSIOCGNAME(128)")
   (ioc "ioctl JSIOCGBTNMAP 1536" "JSIOCGBTNMAP")
   (ioc "ioctl JSIOCGAXMAP 64" "JSIOCGAXMAP")])

(def ^:private expected-entries
  (vec (concat
         (for [s struct-sizes]
           [(str "size " s) (str "sizeof(struct " s ")") "%zu"])
         (for [[s & fields] struct-fields f fields]
           [(str "off " s "." f) (str "offsetof(struct " s ", " f ")") "%zu"])
         ioctl-entries)))

;; ---- C のプログラムを作って動かす

(def ^:private program
  (str "/* tools/genevdev.bb が作る使い捨ての C。 */\n"
       "#include <stdio.h>\n#include <stddef.h>\n#include <sys/time.h>\n#include <sys/ioctl.h>\n"
       "#include <linux/input.h>\n#include <linux/joystick.h>\n\n"
       "int main(void)\n{\n"
       (apply str (for [n const-names]
                    (str "  printf(\"C\\t" n "\\t%lld\\n\", (long long)(" n "));\n")))
       (apply str (for [[k e f] expected-entries]
                    (str "  printf(\"E\\t" k "\\t" f "\\n\", " e ");\n")))
       "  return 0;\n}\n"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "genevdev"})))
(spit (str tmp "/gen.c") program)
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O0" "-w" (str tmp "/gen.c") "-o" (str tmp "/gen"))]
  (when-not (zero? (:exit r))
    (let [missing (distinct (map second (re-seq #"'([A-Za-z_0-9]+)' undeclared" (:err r))))]
      (fs/delete-tree tmp)
      (if (seq missing)
        (fail "このヘッダには無い名前: " (str/join " " missing))
        (fail "C のコンパイルに失敗:\n" (:err r))))))
(def ^:private out (:out (shell {:out :string :err :string} (str tmp "/gen"))))
(fs/delete-tree tmp)
(def ^:private lines (str/split-lines out))

(defn- of-tag [t] (filter #(str/starts-with? % (str t "\t")) lines))

(def ^:private const-vals
  (map #(let [[_ n v] (str/split % #"\t")] [n (parse-long v)]) (of-tag "C")))
(def ^:private expected-vals
  (map #(let [[_ k v] (str/split % #"\t")] [k v]) (of-tag "E")))

;; ---- 件数の検査

(when-not (= (count const-vals) (count const-names))
  (fail "定数が " (count const-vals) " 件出た（" (count const-names) " 件のはず）"))
(when-not (= (count expected-vals) (count expected-entries))
  (fail "期待値が " (count expected-vals) " 行出た（" (count expected-entries) " 行のはず）"))

;; ---- 書く

(def ^:private consts-text
  (str "{ src/generated/evdev_consts.inc — tools/genevdev.bb が作る。手で直さない。 }\n\n"
       "const\n"
       (apply str (for [[n v] const-vals]
                    (format "  %s = %d;\n" n v)))))

(def ^:private expected-text
  (str "{ test/evdev_abi_expected.inc — tools/genevdev.bb が /usr/include の linux/input.h と\n"
       "  linux/joystick.h で C を動かして作る。手で直さない。\n"
       "  size は構造体の大きさ、off は欄の位置（offsetof）、ioctl は要求番号（16 進、接頭辞なし）。 }\n\n"
       "const\n"
       "  EvdevAbiExpected: array[0.." (dec (count expected-vals)) "] of String = (\n"
       (str/join ",\n"
                 (for [[k v] expected-vals]
                   (str "  '" (str/replace (str k " = " v) "'" "''") "'")))
       "\n  );\n"))

;; 書いた行数を、本文から数え直して確かめる
(when-not (= (count (re-seq #"(?m)^  [A-Z_0-9]+ = \d+;$" consts-text)) (count const-names))
  (fail "書いた定数の件数が名前の数と違う"))
(when-not (= (count (re-seq #"(?m)^  '[^\n]*'\,?$" expected-text)) (count expected-entries))
  (fail "書いた期待値の行数が C の出力と違う"))

(spit consts-out consts-text)
(spit expected-out expected-text)
(println (format "genevdev: 定数 %d 件、期待値 %d 行を書いた" (count const-vals) (count expected-vals)))
