#!/usr/bin/env bb
;; genalsa — ALSA の定数と構造体の並びを、libasound のヘッダで作った C のプログラムを動かして書き出す。
;;
;; なぜ要るか:
;;   ALSA の C API は、ヘッダの定数（PCM の形式、チャンネル位置など）と、チャンネルの並びの問い合わせが
;;   返す構造体（snd_pcm_chmap_query_t）の並びに頼る。papimela はヘッダを使えないので Pascal に写す
;;   （設計 #20）。定数は手で写さず、C が出した値をそのまま使う。
;;
;; 使い方:
;;   tools/genalsa.bb [ヘッダの根]
;;     ヘッダの根は alsa/ を持つ所（既定は /usr/include。libasound2-dev の .deb を展開した所でもよい。
;;     docs/ORIGIN.md）。cc が要る。
;;
;; 書くもの:
;;   src/generated/alsa_consts.inc   定数
;;   test/alsa_abi_expected.inc      構造体の大きさと位置、列挙の大きさ
;;
;; 確かめること（どれかが合わなければ止まる）: 定数・並びの件数が、ここに並べた数と同じ

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(def ^:private consts-out "src/generated/alsa_consts.inc")
(def ^:private expected-out "test/alsa_abi_expected.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genalsa: " msg)))
  (System/exit 1))

(def ^:private inc-root (or (first *command-line-args*) "/usr/include"))
(when-not (fs/exists? (str inc-root "/alsa/asoundlib.h"))
  (fail inc-root "/alsa/asoundlib.h が無い（libasound2-dev のヘッダの根を渡す）"))

;; ---- 定数

(def ^:private int-consts
  ["SND_PCM_STREAM_PLAYBACK" "SND_PCM_STREAM_CAPTURE"
   "SND_PCM_NONBLOCK"
   "SND_PCM_ACCESS_RW_INTERLEAVED"
   "SND_PCM_FORMAT_S8" "SND_PCM_FORMAT_U8" "SND_PCM_FORMAT_S16_LE" "SND_PCM_FORMAT_S16_BE"
   "SND_PCM_FORMAT_S32_LE" "SND_PCM_FORMAT_S32_BE" "SND_PCM_FORMAT_FLOAT_LE" "SND_PCM_FORMAT_FLOAT_BE"
   "SND_PCM_STATE_OPEN" "SND_PCM_STATE_SETUP" "SND_PCM_STATE_PREPARED" "SND_PCM_STATE_RUNNING"
   "SND_PCM_STATE_XRUN" "SND_PCM_STATE_DRAINING" "SND_PCM_STATE_PAUSED" "SND_PCM_STATE_SUSPENDED"
   "SND_PCM_STATE_DISCONNECTED"
   "SND_CHMAP_TYPE_NONE" "SND_CHMAP_TYPE_FIXED" "SND_CHMAP_TYPE_VAR" "SND_CHMAP_TYPE_PAIRED"
   "SND_CHMAP_UNKNOWN" "SND_CHMAP_NA" "SND_CHMAP_MONO" "SND_CHMAP_FL" "SND_CHMAP_FR"
   "SND_CHMAP_RL" "SND_CHMAP_RR" "SND_CHMAP_FC" "SND_CHMAP_LFE" "SND_CHMAP_SL" "SND_CHMAP_SR"
   "SND_CHMAP_RC"
   "ENOENT" "EAGAIN"])

;; ---- 構造体の並び（[C の名前 欄...]）。型の名前をそのまま sizeof / offsetof に渡す

(def ^:private layouts
  [["snd_pcm_chmap_t" "channels" "pos"]
   ["snd_pcm_chmap_query_t" "type" "map"]])

;; 列挙・型の大きさ

(def ^:private plain-types
  ["snd_pcm_uframes_t" "snd_pcm_sframes_t" "snd_pcm_format_t" "snd_pcm_access_t" "snd_pcm_stream_t"
   "snd_pcm_state_t" "enum snd_pcm_chmap_type" "enum snd_pcm_chmap_position"])

(def ^:private program
  (str "/* tools/genalsa.bb が作る使い捨ての C。 */\n"
       "#include <stdio.h>\n#include <stddef.h>\n#include <errno.h>\n"
       "#include <alsa/asoundlib.h>\n\n"
       "int main(void)\n{\n"
       "  printf(\"V %s\\n\", SND_LIB_VERSION_STR);\n"
       (apply str (for [c int-consts]
                    (format "  printf(\"I %s %%lld\\n\", (long long)(%s));\n" c c)))
       (apply str (for [[s & fields] layouts]
                    (str (format "  printf(\"L %s %%zu\\n\", sizeof(%s));\n" s s)
                         (apply str (for [f fields]
                                      (format "  printf(\"L %s.%s %%zu\\n\", offsetof(%s, %s));\n" s f s f))))))
       (apply str (for [t plain-types]
                    (format "  printf(\"L %s %%zu\\n\", sizeof(%s));\n" (str/replace t " " "_") t)))
       "  return 0;\n}\n"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "genalsa"})))
(spit (str tmp "/gen.c") program)
(let [r (shell {:continue true :err :string :out :string}
               "cc" "-O0" "-w" (str "-I" inc-root) (str tmp "/gen.c") "-o" (str tmp "/gen"))]
  (when-not (zero? (:exit r)) (fail "C のコンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} (str tmp "/gen"))))
(def ^:private lines (str/split-lines out))

(defn- of-tag [t] (filter #(str/starts-with? % (str t " ")) lines))
(defn- fields [l] (str/split l #" " 3))

(def ^:private ints (map #(let [[_ n v] (fields %)] [n (parse-long v)]) (of-tag "I")))
(def ^:private lays (map #(let [[_ n v] (fields %)] [n (parse-long v)]) (of-tag "L")))
(def ^:private hdr-version (let [v (first (of-tag "V"))] (when-not v (fail "ヘッダの版が出ない")) (subs v 2)))

(def ^:private n-layout (+ (reduce + (map count layouts)) (count plain-types)))
(doseq [[what got want] [["整数の定数" (count ints) (count int-consts)]
                         ["並び" (count lays) n-layout]]]
  (when-not (= got want) (fail what "が " got " 件（" want " 件のはず）")))

(defn- pas-ident [s] (str/replace s "." "_"))

(def ^:private consts-text
  (str "{ src/generated/alsa_consts.inc — tools/genalsa.bb が libasound のヘッダで C を動かして作る。\n"
       "  手で直さない。値は libasound のヘッダ（" hdr-version "）から。 }\n\n"
       "const\n"
       (apply str (for [[n v] ints]
                    (format "  %s = %s;\n" n (str v))))))

(def ^:private expected-text
  (str "{ test/alsa_abi_expected.inc — tools/genalsa.bb が libasound のヘッダで C を動かして作る。\n"
       "  手で直さない（" hdr-version " のヘッダ）。ALS_* は構造体と型の大きさ、ALO_* は欄の位置。 }\n\n"
       "const\n"
       (apply str (for [[n v] lays]
                    (if (str/includes? n ".") (format "  ALO_%s = %d;\n" (pas-ident n) v) (format "  ALS_%s = %d;\n" n v))))))

(spit consts-out consts-text)
(spit expected-out expected-text)
(println (format "genalsa: 定数 %d、並び %d を書いた" (count ints) (count lays)))
