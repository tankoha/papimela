#!/usr/bin/env bb
;; genpulse — PulseAudio の定数と構造体の並びを、libpulse のヘッダで作った C のプログラムを動かして書き出す。
;;
;; なぜ要るか:
;;   PulseAudio の C API は、ヘッダの定数と構造体の並びに頼る（pa_sink_info など、コールバックが
;;   ポインタで渡してくる構造体の欄を読む）。papimela はヘッダを使えないので Pascal に写す（設計 #20）。
;;   定数は手で写さず、C が出した値をそのまま使う。並びは Pascal の record と突き合わせる
;;   （test/test_pulse_abi.pas）。
;;
;; 使い方:
;;   tools/genpulse.bb [ヘッダの根]
;;     ヘッダの根は pulse/ を持つ所（既定は /usr/include。libpulse-dev の .deb を展開した所でもよい。
;;     docs/ORIGIN.md）。cc が要る。
;;
;; 書くもの:
;;   src/generated/pulse_consts.inc   定数（整数と文字列）
;;   test/pulse_abi_expected.inc      構造体の大きさと位置、列挙の大きさ、PA_xxx_IS_GOOD の表
;;
;; 確かめること（どれかが合わなければ止まる）: 定数・並びの件数が、ここに並べた数と同じ

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(def ^:private consts-out "src/generated/pulse_consts.inc")
(def ^:private expected-out "test/pulse_abi_expected.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genpulse: " msg)))
  (System/exit 1))

(def ^:private inc-root (or (first *command-line-args*) "/usr/include"))
(when-not (fs/exists? (str inc-root "/pulse/pulseaudio.h"))
  (fail inc-root "/pulse/pulseaudio.h が無い（libpulse-dev のヘッダの根を渡す）"))

;; ---- 定数

(def ^:private int-consts
  ["PA_PROTOCOL_VERSION" "PA_CHANNELS_MAX" "PA_INVALID_INDEX"
   "PA_SAMPLE_INVALID" "PA_SAMPLE_U8" "PA_SAMPLE_S16LE" "PA_SAMPLE_S16BE" "PA_SAMPLE_S32LE"
   "PA_SAMPLE_S32BE" "PA_SAMPLE_FLOAT32LE" "PA_SAMPLE_FLOAT32BE"
   "PA_CHANNEL_POSITION_INVALID" "PA_CHANNEL_POSITION_MONO" "PA_CHANNEL_POSITION_FRONT_LEFT"
   "PA_CHANNEL_POSITION_FRONT_RIGHT" "PA_CHANNEL_POSITION_FRONT_CENTER" "PA_CHANNEL_POSITION_LFE"
   "PA_CHANNEL_POSITION_REAR_LEFT" "PA_CHANNEL_POSITION_REAR_RIGHT" "PA_CHANNEL_POSITION_REAR_CENTER"
   "PA_CHANNEL_POSITION_SIDE_LEFT" "PA_CHANNEL_POSITION_SIDE_RIGHT"
   "PA_CHANNEL_MAP_DEFAULT"
   "PA_CONTEXT_UNCONNECTED" "PA_CONTEXT_CONNECTING" "PA_CONTEXT_AUTHORIZING" "PA_CONTEXT_SETTING_NAME"
   "PA_CONTEXT_READY" "PA_CONTEXT_FAILED" "PA_CONTEXT_TERMINATED"
   "PA_CONTEXT_NOFLAGS"
   "PA_STREAM_UNCONNECTED" "PA_STREAM_CREATING" "PA_STREAM_READY" "PA_STREAM_FAILED" "PA_STREAM_TERMINATED"
   "PA_STREAM_NOFLAGS" "PA_STREAM_ADJUST_LATENCY" "PA_STREAM_DONT_MOVE"
   "PA_OPERATION_RUNNING" "PA_OPERATION_DONE" "PA_OPERATION_CANCELLED"
   "PA_SEEK_RELATIVE"
   "PA_SUBSCRIPTION_MASK_SINK" "PA_SUBSCRIPTION_MASK_SOURCE" "PA_SUBSCRIPTION_MASK_SERVER"
   "PA_SUBSCRIPTION_EVENT_SINK" "PA_SUBSCRIPTION_EVENT_SOURCE" "PA_SUBSCRIPTION_EVENT_SERVER"
   "PA_SUBSCRIPTION_EVENT_FACILITY_MASK"
   "PA_SUBSCRIPTION_EVENT_NEW" "PA_SUBSCRIPTION_EVENT_CHANGE" "PA_SUBSCRIPTION_EVENT_REMOVE"
   "PA_SUBSCRIPTION_EVENT_TYPE_MASK"])

(def ^:private str-consts
  ["PA_PROP_APPLICATION_ICON_NAME" "PA_PROP_APPLICATION_NAME" "PA_PROP_MEDIA_ROLE"])

;; ---- 構造体の並び（[C の名前 欄...]）。コールバックが渡してくる構造体は、使う欄までの前半だけ

(def ^:private layouts
  [["pa_sample_spec" "format" "rate" "channels"]
   ["pa_channel_map" "channels" "map"]
   ["pa_buffer_attr" "maxlength" "tlength" "prebuf" "minreq" "fragsize"]
   ["pa_cvolume" "channels" "values"]
   ["pa_sink_info" "name" "index" "description" "sample_spec" "channel_map" "owner_module" "volume"
    "mute" "monitor_source" "monitor_source_name"]
   ["pa_source_info" "name" "index" "description" "sample_spec" "channel_map" "owner_module" "volume"
    "mute" "monitor_of_sink" "monitor_of_sink_name"]
   ["pa_server_info" "user_name" "host_name" "server_version" "server_name" "sample_spec"
    "default_sink_name" "default_source_name" "cookie" "channel_map"]])

;; 列挙の大きさ（C の enum は 4 バイトのことが多いが、確かめる）

(def ^:private enum-types
  ["pa_sample_format_t" "pa_channel_position_t" "pa_channel_map_def_t" "pa_context_state_t"
   "pa_stream_state_t" "pa_operation_state_t" "pa_stream_flags_t" "pa_context_flags_t"
   "pa_seek_mode_t" "pa_subscription_mask_t" "pa_subscription_event_type_t"])

(def ^:private program
  (str "/* tools/genpulse.bb が作る使い捨ての C。 */\n"
       "#include <stdio.h>\n#include <stddef.h>\n#include <stdint.h>\n"
       "#include <pulse/pulseaudio.h>\n\n"
       "int main(void)\n{\n"
       "  printf(\"V %s\\n\", pa_get_headers_version());\n"
       (apply str (for [c int-consts]
                    (format "  printf(\"I %s %%lld\\n\", (long long)(%s));\n" c c)))
       (apply str (for [c str-consts]
                    (format "  printf(\"S %s %%s\\n\", %s);\n" c c)))
       (apply str (for [[s & fields] layouts]
                    (str (format "  printf(\"L %s %%zu\\n\", sizeof(%s));\n" s s)
                         (apply str (for [f fields]
                                      (format "  printf(\"L %s.%s %%zu\\n\", offsetof(%s, %s));\n" s f s f))))))
       (apply str (for [t enum-types]
                    (format "  printf(\"L %s %%zu\\n\", sizeof(%s));\n" t t)))
       "  for (int i = 0; i <= 6; i++) printf(\"G ctx %d %d\\n\", i, PA_CONTEXT_IS_GOOD((pa_context_state_t)i) ? 1 : 0);\n"
       "  for (int i = 0; i <= 4; i++) printf(\"G stream %d %d\\n\", i, PA_STREAM_IS_GOOD((pa_stream_state_t)i) ? 1 : 0);\n"
       "  return 0;\n}\n"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "genpulse"})))
(spit (str tmp "/gen.c") program)
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O0" "-w" (str "-I" inc-root) (str tmp "/gen.c") "-o" (str tmp "/gen"))]
  (when-not (zero? (:exit r)) (fail "C のコンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} (str tmp "/gen"))))
(def ^:private lines (str/split-lines out))

(defn- of-tag [t] (filter #(str/starts-with? % (str t " ")) lines))
(defn- fields [l] (str/split l #" " 3))

(def ^:private ints (map #(let [[_ n v] (fields %)] [n (parse-long v)]) (of-tag "I")))
(def ^:private strs (map #(let [[_ n v] (fields %)] [n v]) (of-tag "S")))
(def ^:private lays (map #(let [[_ n v] (fields %)] [n (parse-long v)]) (of-tag "L")))
(def ^:private goods (map #(let [[_ k rest] (fields %) [i v] (str/split rest #" ")] [k (parse-long i) (parse-long v)]) (of-tag "G")))
(def ^:private hdr-version (let [v (first (of-tag "V"))] (when-not v (fail "ヘッダの版が出ない")) (subs v 2)))

(def ^:private n-layout (+ (reduce + (map count layouts)) (count enum-types)))
(doseq [[what got want] [["整数の定数" (count ints) (count int-consts)]
                         ["文字列の定数" (count strs) (count str-consts)]
                         ["並び" (count lays) n-layout]
                         ["IS_GOOD の表" (count goods) 12]]]
  (when-not (= got want) (fail what "が " got " 件（" want " 件のはず）")))

(defn- pas-ident [s] (str/replace s "." "_"))

(def ^:private consts-text
  (str "{ src/generated/pulse_consts.inc — tools/genpulse.bb が libpulse のヘッダで C を動かして作る。\n"
       "  手で直さない。値は libpulse のヘッダ（" hdr-version "）から。 }\n\n"
       "const\n"
       (apply str (for [[n v] ints]
                    (format "  %s = %s;\n" n
                            (if (neg? v) (str v) (if (> v 0x7fffffff) (format "LongWord($%X)" v) (str v))))))
       (apply str (for [[n v] strs]
                    (format "  %s = '%s';\n" n v)))))

(def ^:private expected-text
  (str "{ test/pulse_abi_expected.inc — tools/genpulse.bb が libpulse のヘッダで C を動かして作る。\n"
       "  手で直さない（" hdr-version " のヘッダ）。PAS_* は構造体と列挙の大きさ、PAO_* は欄の位置。\n"
       "  PAGoodContext / PAGoodStream は PA_CONTEXT_IS_GOOD / PA_STREAM_IS_GOOD の結果。 }\n\n"
       "const\n"
       (apply str (for [[n v] lays]
                    (if (str/includes? n ".") (format "  PAO_%s = %d;\n" (pas-ident n) v) (format "  PAS_%s = %d;\n" n v))))
       "\n  PAGoodContext: array[0..6] of Boolean = ("
       (str/join ", " (for [[k _ v] goods :when (= k "ctx")] (if (= v 1) "True" "False")))
       ");\n  PAGoodStream: array[0..4] of Boolean = ("
       (str/join ", " (for [[k _ v] goods :when (= k "stream")] (if (= v 1) "True" "False")))
       ");\n"))

(spit consts-out consts-text)
(spit expected-out expected-text)
(println (format "genpulse: 定数 %d、並び %d、IS_GOOD %d を書いた" (+ (count ints) (count strs)) (count lays) (count goods)))
