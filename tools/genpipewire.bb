#!/usr/bin/env bb
;; genpipewire — PipeWire の定数と、構造体の並び・pod・JSON の期待値を、PipeWire のヘッダで作った
;; C のプログラムを動かして書き出す。
;;
;; なぜ要るか:
;;   PipeWire の C API は、ヘッダの定数・構造体の並び・インライン関数（pod の組み立てと読み取り、
;;   JSON の読み取り、メソッドの呼び出し）に頼る。papimela はヘッダを使えないので、これらを
;;   Pascal に写す（設計 #21）。写しが合っているかは、本物のヘッダで作った C の出力と比べて
;;   確かめる。定数は手で写さず、C が出した値をそのまま使う。
;;
;; 使い方:
;;   tools/genpipewire.bb [ヘッダの根]
;;     ヘッダの根は pipewire-0.3/ と spa-0.2/ を持つ所（既定は /usr/include。
;;     libpipewire-0.3-dev と libspa-0.2-dev の .deb を展開した所でもよい）。cc が要る。
;;     SDL の関数を切り出すので reference/SDL も要る（docs/ORIGIN.md）。
;;
;; 書くもの:
;;   src/generated/pipewire_consts.inc   定数（整数と文字列）
;;   test/pipewire_abi_expected.inc      構造体の大きさと位置、pod の組み立ての結果（バイト列）、
;;                                       pod の読み取り（SDL の get_range_param・get_int_param）と
;;                                       JSON の読み取り（SDL の get_name_from_json・client_info）の結果
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 切り出す SDL の関数がどれも見つかる
;;   - 定数・並び・場面の件数が、ここに並べた数と同じ

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(def ^:private sdl-src "reference/SDL/src/audio/pipewire/SDL_pipewire.c")
(def ^:private consts-out "src/generated/pipewire_consts.inc")
(def ^:private expected-out "test/pipewire_abi_expected.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genpipewire: " msg)))
  (System/exit 1))

(def ^:private inc-root (or (first *command-line-args*) "/usr/include"))
(when-not (fs/exists? (str inc-root "/pipewire-0.3/pipewire/pipewire.h"))
  (fail inc-root "/pipewire-0.3/pipewire/pipewire.h が無い（libpipewire-0.3-dev のヘッダの根を渡す）"))
(when-not (fs/exists? sdl-src)
  (fail sdl-src " が無い。reference/SDL を用意すること（docs/ORIGIN.md）"))

;; ---- 定数

(def ^:private int-consts
  ["SPA_TYPE_None" "SPA_TYPE_Bool" "SPA_TYPE_Id" "SPA_TYPE_Int" "SPA_TYPE_Long" "SPA_TYPE_Float"
   "SPA_TYPE_Double" "SPA_TYPE_String" "SPA_TYPE_Bytes" "SPA_TYPE_Rectangle" "SPA_TYPE_Fraction"
   "SPA_TYPE_Bitmap" "SPA_TYPE_Array" "SPA_TYPE_Struct" "SPA_TYPE_Object" "SPA_TYPE_Sequence"
   "SPA_TYPE_Pointer" "SPA_TYPE_Fd" "SPA_TYPE_Choice" "SPA_TYPE_Pod"
   "SPA_TYPE_OBJECT_Format"
   "SPA_PARAM_EnumFormat" "SPA_PARAM_Format"
   "SPA_FORMAT_mediaType" "SPA_FORMAT_mediaSubtype"
   "SPA_FORMAT_AUDIO_format" "SPA_FORMAT_AUDIO_rate" "SPA_FORMAT_AUDIO_channels" "SPA_FORMAT_AUDIO_position"
   "SPA_MEDIA_TYPE_audio" "SPA_MEDIA_SUBTYPE_raw"
   "SPA_AUDIO_FORMAT_UNKNOWN" "SPA_AUDIO_FORMAT_U8" "SPA_AUDIO_FORMAT_S8" "SPA_AUDIO_FORMAT_S16_LE"
   "SPA_AUDIO_FORMAT_S16_BE" "SPA_AUDIO_FORMAT_S32_LE" "SPA_AUDIO_FORMAT_S32_BE" "SPA_AUDIO_FORMAT_F32_LE"
   "SPA_AUDIO_FORMAT_F32_BE"
   "SPA_AUDIO_CHANNEL_MONO" "SPA_AUDIO_CHANNEL_FL" "SPA_AUDIO_CHANNEL_FR" "SPA_AUDIO_CHANNEL_FC"
   "SPA_AUDIO_CHANNEL_LFE" "SPA_AUDIO_CHANNEL_SL" "SPA_AUDIO_CHANNEL_SR" "SPA_AUDIO_CHANNEL_RL"
   "SPA_AUDIO_CHANNEL_RR" "SPA_AUDIO_CHANNEL_RC"
   "SPA_AUDIO_MAX_CHANNELS"
   "SPA_CHOICE_None" "SPA_CHOICE_Range" "SPA_CHOICE_Step" "SPA_CHOICE_Enum" "SPA_CHOICE_Flags"
   "SPA_POD_ALIGN" "SPA_POD_MAX_SIZE"
   "SPA_DIRECTION_INPUT" "SPA_DIRECTION_OUTPUT"
   "PW_DIRECTION_INPUT" "PW_DIRECTION_OUTPUT"
   "PW_ID_CORE" "PW_ID_ANY"
   "PW_VERSION_CORE" "PW_VERSION_REGISTRY" "PW_VERSION_CORE_EVENTS" "PW_VERSION_REGISTRY_EVENTS"
   "PW_VERSION_NODE_EVENTS" "PW_VERSION_METADATA_EVENTS" "PW_VERSION_CLIENT_EVENTS" "PW_VERSION_STREAM_EVENTS"
   "PW_STREAM_STATE_ERROR" "PW_STREAM_STATE_UNCONNECTED" "PW_STREAM_STATE_CONNECTING"
   "PW_STREAM_STATE_PAUSED" "PW_STREAM_STATE_STREAMING"
   "PW_STREAM_FLAG_AUTOCONNECT" "PW_STREAM_FLAG_MAP_BUFFERS" "PW_STREAM_FLAG_RT_PROCESS"
   "ETIMEDOUT" "ENOSPC" "EINVAL" "EPROTO" "ENOTSUP"])

(def ^:private str-consts
  ["PW_TYPE_INTERFACE_Node" "PW_TYPE_INTERFACE_Metadata" "PW_TYPE_INTERFACE_Client"
   "PW_KEY_MEDIA_CLASS" "PW_KEY_NODE_DESCRIPTION" "PW_KEY_NODE_NAME" "PW_KEY_AUDIO_CHANNELS"
   "PW_KEY_CONFIG_NAME" "PW_KEY_MEDIA_TYPE" "PW_KEY_MEDIA_CATEGORY" "PW_KEY_MEDIA_ROLE"
   "PW_KEY_APP_NAME" "PW_KEY_APP_ICON_NAME" "PW_KEY_APP_ID" "PW_KEY_NODE_LATENCY" "PW_KEY_NODE_RATE"
   "PW_KEY_NODE_ALWAYS_PROCESS" "PW_KEY_MEDIA_NAME" "PW_KEY_TARGET_OBJECT"])

;; ---- 構造体の並び（[C の名前 欄...]）

(def ^:private layouts
  [["spa_list" "next" "prev"]
   ["spa_callbacks" "funcs" "data"]
   ["spa_interface" "type" "version" "cb"]
   ["spa_hook" "link" "cb" "removed" "priv"]
   ["spa_dict_item" "key" "value"]
   ["spa_dict" "flags" "n_items" "items"]
   ["spa_pod" "size" "type"]
   ["spa_pod_prop" "key" "flags" "value"]
   ["spa_pod_object_body" "type" "id"]
   ["spa_pod_object" "pod" "body"]
   ["spa_pod_choice_body" "type" "flags" "child"]
   ["spa_pod_choice" "pod" "body"]
   ["spa_pod_array_body" "child"]
   ["spa_param_info" "id" "flags" "user" "seq"]
   ["pw_core_info" "id" "cookie" "user_name" "host_name" "version" "name" "change_mask" "props"]
   ["pw_node_info" "id" "max_input_ports" "max_output_ports" "change_mask" "n_input_ports"
    "n_output_ports" "state" "error" "props" "params" "n_params"]
   ["pw_client_info" "id" "change_mask" "props"]
   ["pw_buffer" "buffer" "user_data" "size" "requested"]
   ["spa_buffer" "n_metas" "n_datas" "metas" "datas"]
   ["spa_data" "type" "flags" "fd" "mapoffset" "maxsize" "data" "chunk"]
   ["spa_chunk" "offset" "size" "stride" "flags"]
   ["pw_core_events" "version" "info" "done" "ping" "error" "remove_id" "bound_id" "add_mem"
    "remove_mem" "bound_props"]
   ["pw_core_methods" "version" "add_listener" "hello" "sync" "pong" "error" "get_registry"
    "create_object" "destroy"]
   ["pw_registry_events" "version" "global" "global_remove"]
   ["pw_registry_methods" "version" "add_listener" "bind" "destroy"]
   ["pw_node_events" "version" "info" "param"]
   ["pw_node_methods" "version" "add_listener" "subscribe_params" "enum_params" "set_param"
    "send_command"]
   ["pw_metadata_events" "version" "property"]
   ["pw_client_events" "version" "info" "permissions"]
   ["pw_stream_events" "version" "destroy" "state_changed" "control_info" "io_changed"
    "param_changed" "add_buffer" "remove_buffer" "process" "drained" "command" "trigger_done"]])

;; ---- pod を組み立てる場面（SDL の initialize_spa_info → spa_format_audio_raw_build）
;; [名前 SDL の形式 チャンネル数 周波数]

(def ^:private build-cases
  [["s16_2_48000" "SDL_AUDIO_S16LE" 2 48000]
   ["f32_2_44100" "SDL_AUDIO_F32LE" 2 44100]
   ["u8_1_8000" "SDL_AUDIO_U8" 1 8000]
   ["s8_3_22050" "SDL_AUDIO_S8" 3 22050]
   ["s16be_4_32000" "SDL_AUDIO_S16BE" 4 32000]
   ["s32_5_96000" "SDL_AUDIO_S32LE" 5 96000]
   ["s32be_6_48000" "SDL_AUDIO_S32BE" 6 48000]
   ["f32be_7_192000" "SDL_AUDIO_F32BE" 7 192000]
   ["f32_8_48000" "SDL_AUDIO_F32LE" 8 48000]
   ["unknown_2_48000" "0" 2 48000]])

;; ---- pod を読む場面（C で組み立て、SDL の get_range_param(rate) と get_int_param(channels) の結果）
;; [名前 C の式（spa_pod_builder *b から pod を作る）]

(def ^:private parse-cases
  [["range_rate_int_channels"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
       SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_audio),
       SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
       SPA_FORMAT_AUDIO_format, SPA_POD_Id(SPA_AUDIO_FORMAT_F32_LE),
       SPA_FORMAT_AUDIO_rate, SPA_POD_CHOICE_RANGE_Int(48000, 1, 384000),
       SPA_FORMAT_AUDIO_channels, SPA_POD_Int(2))"]
   ["plain_rate_range_channels"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_Format,
       SPA_FORMAT_AUDIO_rate, SPA_POD_Int(44100),
       SPA_FORMAT_AUDIO_channels, SPA_POD_CHOICE_RANGE_Int(2, 1, 64))"]
   ["enum_rate"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
       SPA_FORMAT_AUDIO_rate, SPA_POD_CHOICE_ENUM_Int(3, 44100, 44100, 48000),
       SPA_FORMAT_AUDIO_channels, SPA_POD_Int(6))"]
   ["step_rate"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
       SPA_FORMAT_AUDIO_rate, SPA_POD_CHOICE_STEP_Int(48000, 8000, 96000, 4000))"]
   ["enum_channels"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
       SPA_FORMAT_AUDIO_channels, SPA_POD_CHOICE_ENUM_Int(2, 8, 8))"]
   ["empty_object"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat)"]
   ["not_object"
    "spa_pod_builder_int(b, 48000), (struct spa_pod *)b->data"]
   ["rate_after_others"
    "spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
       SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_audio),
       SPA_FORMAT_AUDIO_position, SPA_POD_Array(sizeof(uint32_t), SPA_TYPE_Id, 2, positions2),
       SPA_FORMAT_AUDIO_channels, SPA_POD_Int(2),
       SPA_FORMAT_AUDIO_rate, SPA_POD_CHOICE_RANGE_Int(96000, 8000, 192000))"]
   ["range_four_values"
    "({ struct spa_pod_frame f0, f1;
        spa_pod_builder_push_object(b, &f0, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat);
        spa_pod_builder_prop(b, SPA_FORMAT_AUDIO_rate, 0);
        spa_pod_builder_push_choice(b, &f1, SPA_CHOICE_Range, 0);
        spa_pod_builder_int(b, 48000); spa_pod_builder_int(b, 8000);
        spa_pod_builder_int(b, 96000); spa_pod_builder_int(b, 1);
        spa_pod_builder_pop(b, &f1); spa_pod_builder_pop(b, &f0); })"]
   ["range_two_values"
    "({ struct spa_pod_frame f0, f1;
        spa_pod_builder_push_object(b, &f0, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat);
        spa_pod_builder_prop(b, SPA_FORMAT_AUDIO_rate, 0);
        spa_pod_builder_push_choice(b, &f1, SPA_CHOICE_Range, 0);
        spa_pod_builder_int(b, 48000); spa_pod_builder_int(b, 8000);
        spa_pod_builder_pop(b, &f1); spa_pod_builder_pop(b, &f0); })"]
   ["truncated_last_prop"
    "({ struct spa_pod *q = (struct spa_pod *)spa_pod_builder_add_object(b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
         SPA_FORMAT_AUDIO_rate, SPA_POD_CHOICE_RANGE_Int(48000, 1, 384000),
         SPA_FORMAT_AUDIO_channels, SPA_POD_Int(2)); q->size -= 8; q; })"]])

;; ---- JSON を 1 トークンずつ（入れ物に入ってから spa_json_next を繰り返す）
;; 結果は「長さ:トークン」を | でつないだもの。最後に「=戻り値」。

(def ^:private json-tokens
  ["{\"a\":{\"b\":1},\"c\":2}"
   "{\"a\":[1,2,{\"x\":\"y\"}],\"b\":\"z\"}"
   "[\"s\",bare,{\"k\":\"v\"},[1,[2]],3]"
   "{ key = value, other = \"q\" }"
   "{\"k\":\"v\" # c\n,\"k2\":\"v2\"}"
   "{\"a\" \"b\" \"c\"}"
   "{\"a\":1]"
   "[1,2}"
   "{\"a\":\"bad\\q\"}"
   "{\"a\":\"open}"
   "{\"a\":\"x\u0001\"}"
   "{a\\b:1}"
   "[ :1 ]"
   "{\"k\":\\v}"
   "{\"a\":1"
   "[[1],2]"
   "{\"k\":\"\u00e9\u3042\"}"])

;; ---- JSON（SDL の get_name_from_json と client_info の session.services）

(def ^:private json-names
  ["{\"name\":\"alsa_output.usb-Burr-Brown_PCM2704-00.analog-stereo\"}"
   "{ \"name\": \"alsa_input.pci-0000_0c_00.6.analog-stereo\" }"
   "{\"name\":\"esc\\\"aped\\\\back\\/slash\"}"
   "{\"name\":\"tab\\tnl\\nuni\\u00e9\\u3042\\ud83c\\udfb5x\"}"
   "{\"name\":\"bad\\uZZZZu\"}"
   "{\"name\":\"lone\\udc00x\"}"
   "{ name = bare-word }"
   "{\"description\":\"too long a key\"}"
   "{\"nam\":\"short key\"}"
   "{\"name\":\"\"}"
   "{\"name\":}"
   "{\"name\""
   "\"just a string\""
   "[\"name\",\"in array\"]"
   "not json at all"
   ""
   "{\"name\":{\"nested\":1}}"
   "{\"name\":\"\u00e9t\u00e9\"}"
   "{\"name\":\"control\u0001char\"}"
   "  # comment\n{\"name\":\"after comment\"}"
   (str "{\"name\":\"" (apply str (repeat 255 "a")) "\"}")
   (str "{\"name\":\"" (apply str (repeat 253 "b")) "\"}")
   (str "{\"name\":\"" (apply str (repeat 254 "c")) "\"}")])

(def ^:private json-services
  ["[\"audio\",\"video\"]"
   "[\"video\", \"bluetooth.audio\"]"
   "[ video audio ]"
   "[]"
   "{\"audio\":true}"
   "[\"audio"
   "[\"vid\\u0065o\",\"aud\\u0069o\"]"])

;; ---- C のプログラム

(def ^:private sdl-text (slurp sdl-src))

(defn- grab [what re]
  (or (re-find re sdl-text) (fail "SDL の " what " が見つからない")))

(def ^:private sdl-functions
  (str/join "\n\n"
            [(grab "channel_map" #"(?s)// Channel maps that match the order in SDL_Audio.h\n.*?#define COPY_CHANNEL_MAP\(c\)[^\n]*\n")
             (grab "initialize_spa_info" #"(?s)static void initialize_spa_info\(.*?\n\}\n")
             (grab "get_range_param" #"(?s)static bool get_range_param\(.*?\n\}\n")
             (grab "get_int_param" #"(?s)static bool get_int_param\(.*?\n\}\n")
             (grab "get_name_from_json" #"(?s)static char \*get_name_from_json\(.*?\n\}\n")
             (grab "client_info" #"(?s)static void client_info\(.*?\n\}\n")]))

(defn- c-string
  "バイト列を C の文字列リテラルにする（ASCII の印字できる文字のほかは 8 進）。"
  [s]
  (str "\""
       (apply str (for [b (.getBytes ^String s "UTF-8")]
                    (let [u (bit-and b 0xff)]
                      (cond
                        (= u 34) "\\\""
                        (= u 92) "\\\\"
                        (= u 63) "\\?"
                        (<= 32 u 126) (str (char u))
                        :else (format "\\%03o" u)))))
       "\""))

(defn- pas-string
  "バイト列を Pascal の文字列の式にする（印字できない文字と ' は #nn）。"
  [s]
  (let [bs (map #(bit-and % 0xff) (.getBytes ^String s "UTF-8"))]
    (if (empty? bs)
      "''"
      (str/join "+"
                (->> bs
                     (partition-by #(and (<= 32 % 126) (not= % 39)))
                     (map (fn [run]
                            (if (and (<= 32 (first run) 126) (not= (first run) 39))
                              (str "'" (apply str (map char run)) "'")
                              (apply str (map #(str "#" %) run))))))))))

(def ^:private program
  (str "/* tools/genpipewire.bb が作る使い捨ての C。 */\n"
       "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <strings.h>\n"
       "#include <stddef.h>\n#include <stdbool.h>\n#include <errno.h>\n#include <stdint.h>\n"
       "#include <pipewire/pipewire.h>\n#include <pipewire/extensions/metadata.h>\n"
       "#include <spa/param/audio/format-utils.h>\n#include <spa/utils/json.h>\n\n"
       "typedef uint8_t Uint8; typedef uint32_t Uint32; typedef int32_t Sint32;\n"
       "typedef struct { int format; int channels; int freq; } SDL_AudioSpec;\n"
       "#define SDL_AUDIO_U8 0x0008\n#define SDL_AUDIO_S8 0x8008\n#define SDL_AUDIO_S16LE 0x8010\n"
       "#define SDL_AUDIO_S16BE 0x9010\n#define SDL_AUDIO_S32LE 0x8020\n#define SDL_AUDIO_S32BE 0x9020\n"
       "#define SDL_AUDIO_F32LE 0x8120\n#define SDL_AUDIO_F32BE 0x9120\n"
       "#define SDL_memcpy memcpy\n#define SDL_strlen strlen\n#define SDL_strdup strdup\n#define SDL_strcmp strcmp\n"
       "#define PW_MAX_IDENTIFIER_LENGTH 256\n"
       "static bool pipewire_have_session_services;\nstatic bool pipewire_have_audio_service;\n\n"
       sdl-functions "\n\n"
       "static void hex(const char *tag, const char *name, const void *p, size_t n) {\n"
       "  const unsigned char *b = p; printf(\"%s %s \", tag, name);\n"
       "  for (size_t i = 0; i < n; i++) printf(\"%02x\", b[i]); printf(\"\\n\"); }\n\n"
       "int main(void)\n{\n"
       "  printf(\"V %s\\n\", pw_get_headers_version());\n"
       "  static const uint32_t positions2[] = { SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR };\n"
       (apply str (for [c int-consts]
                    (format "  printf(\"I %s %%lld\\n\", (long long)(%s));\n" c c)))
       (apply str (for [c str-consts]
                    (format "  printf(\"S %s %%s\\n\", %s);\n" c c)))
       (apply str (for [[s & fields] layouts]
                    (str (format "  printf(\"L %s %%zu\\n\", sizeof(struct %s));\n" s s)
                         (apply str (for [f fields]
                                      (format "  printf(\"L %s.%s %%zu\\n\", offsetof(struct %s, %s));\n"
                                              s f s f))))))
       (apply str (for [[n fmt ch rate] build-cases]
                    (format (str "  { uint8_t buf[1024]; struct spa_pod_builder bb = SPA_POD_BUILDER_INIT(buf, sizeof(buf));\n"
                                 "    struct spa_audio_info_raw info = {0}; SDL_AudioSpec spec = { %s, %d, %d };\n"
                                 "    initialize_spa_info(&spec, &info);\n"
                                 "    const struct spa_pod *p = spa_format_audio_raw_build(&bb, SPA_PARAM_EnumFormat, &info);\n"
                                 "    if (!p) { printf(\"X build %s\\n\"); return 1; }\n"
                                 "    hex(\"P\", \"%s\", p, SPA_POD_SIZE(p)); }\n")
                            fmt ch rate n n)))
       (apply str (for [[n expr] parse-cases]
                    (format (str "  { uint8_t buf[1024]; struct spa_pod_builder bbb = SPA_POD_BUILDER_INIT(buf, sizeof(buf));\n"
                                 "    struct spa_pod_builder *b = &bbb;\n"
                                 "    const struct spa_pod *p = (const struct spa_pod *)(%s);\n"
                                 "    int def = -1, min = -1, max = -1, ch = -1;\n"
                                 "    bool r = get_range_param(p, SPA_FORMAT_AUDIO_rate, &def, &min, &max);\n"
                                 "    bool c = get_int_param(p, SPA_FORMAT_AUDIO_channels, &ch);\n"
                                 "    hex(\"Q\", \"%s\", p, SPA_POD_SIZE(p));\n"
                                 "    printf(\"R %s %%d %%d %%d %%d %%d %%d\\n\", r, def, min, max, c, ch); }\n")
                            expr n n)))
       (apply str (for [[i s] (map-indexed vector json-names)]
                    (format (str "  { char *v = get_name_from_json(%s);\n"
                                 "    if (v) hex(\"J\", \"%d\", v, strlen(v)); else printf(\"J %d -\\n\"); free(v); }\n")
                            (c-string s) i i)))
       (apply str (for [[i s] (map-indexed vector json-tokens)]
                    (format (str "  { const char *s = %s; struct spa_json it[2]; const char *v; int r, n = 0;\n"
                                 "    spa_json_init(&it[0], s, strlen(s));\n"
                                 "    r = (s[0] == '[') ? spa_json_enter_array(&it[0], &it[1]) : spa_json_enter_object(&it[0], &it[1]);\n"
                                 "    printf(\"T %d \");\n"
                                 "    if (r <= 0) { printf(\"=%%d\\n\", r); } else {\n"
                                 "      while (n++ < 40 && (r = spa_json_next(&it[1], &v)) > 0) { printf(\"%%d:\", r); for (int k = 0; k < r; k++) printf(\"%%02x\", (unsigned char)v[k]); printf(\"|\"); }\n"
                                 "      printf(\"=%%d\\n\", r); } }\n")
                            (c-string s) i)))
       (apply str (for [[i s] (map-indexed vector json-services)]
                    (format (str "  { struct spa_dict_item it[] = { { \"session.services\", %s } };\n"
                                 "    struct spa_dict d = SPA_DICT_INIT(it, 1); struct pw_client_info ci = {0}; ci.props = &d;\n"
                                 "    pipewire_have_session_services = false; pipewire_have_audio_service = false;\n"
                                 "    client_info(NULL, &ci);\n"
                                 "    printf(\"K %d %%d %%d\\n\", pipewire_have_session_services, pipewire_have_audio_service); }\n")
                            (c-string s) i)))
       "  return 0;\n}\n"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "genpipewire"})))
(def ^:private csrc (str tmp "/gen.c"))
(def ^:private exe (str tmp "/gen"))
(spit csrc program)
(let [r (shell {:continue true :err :string} "cc" "-O1" "-std=gnu11" "-w"
               (str "-I" inc-root "/pipewire-0.3") (str "-I" inc-root "/spa-0.2")
               "-o" exe csrc)]
  (when-not (zero? (:exit r)) (fail "cc に失敗した:\n" (:err r))))
(def ^:private lines
  (->> (:out (shell {:out :string} exe)) str/split-lines (remove str/blank?)))
(fs/delete-tree tmp)

(defn- of-tag [t] (filter #(str/starts-with? % (str t " ")) lines))
(defn- fields [l] (str/split l #" " 3))

(def ^:private ints (map #(let [[_ n v] (fields %)] [n (parse-long v)]) (of-tag "I")))
(def ^:private strs (map #(let [[_ n v] (fields %)] [n v]) (of-tag "S")))
(def ^:private lays (map #(let [[_ n v] (fields %)] [n (parse-long v)]) (of-tag "L")))
(def ^:private pods (map #(let [[_ n v] (fields %)] [n v]) (of-tag "P")))
(def ^:private qpods (map #(let [[_ n v] (fields %)] [n v]) (of-tag "Q")))
(def ^:private rres (map #(let [[_ n v] (fields %)] [n (mapv parse-long (str/split v #" "))]) (of-tag "R")))
(def ^:private jres (map #(let [[_ n v] (fields %)] [(parse-long n) v]) (of-tag "J")))
(def ^:private hdr-version (let [v (first (of-tag "V"))] (when-not v (fail "ヘッダの版が出ない")) (subs v 2)))
(def ^:private tres (map #(let [[_ n v] (fields %)] [(parse-long n) v]) (of-tag "T")))
(def ^:private kres (map #(let [[_ n v] (fields %)] [(parse-long n) (mapv parse-long (str/split v #" "))]) (of-tag "K")))

(def ^:private n-layout (reduce + (map count layouts)))
(doseq [[what got want] [["整数の定数" (count ints) (count int-consts)]
                         ["文字列の定数" (count strs) (count str-consts)]
                         ["並び" (count lays) n-layout]
                         ["組み立ての場面" (count pods) (count build-cases)]
                         ["読み取りの場面" (count qpods) (count parse-cases)]
                         ["読み取りの結果" (count rres) (count parse-cases)]
                         ["JSON の名前" (count jres) (count json-names)]
                         ["JSON の services" (count kres) (count json-services)]
                         ["JSON のトークン" (count tres) (count json-tokens)]]]
  (when-not (= got want) (fail what "が " got " 件（" want " 件のはず）")))

(defn- pas-ident [s] (str/replace s "." "_"))

(def ^:private consts-text
  (str "{ src/generated/pipewire_consts.inc — tools/genpipewire.bb が PipeWire のヘッダで C を動かして作る。\n"
       "  手で直さない。値は libpipewire-0.3 / libspa-0.2 のヘッダ（PipeWire " hdr-version "）から。 }\n\n"
       "const\n"
       (apply str (for [[n v] ints]
                    (format "  %s = %s;\n" n
                            (if (neg? v) (str v) (if (> v 0x7fffffff) (format "LongWord($%X)" v) (str v))))))
       (apply str (for [[n v] strs]
                    (format "  %s = %s;\n" n (pas-string v))))))

(def ^:private expected-text
  (str "{ test/pipewire_abi_expected.inc — tools/genpipewire.bb が PipeWire のヘッダで C を動かして作る。\n"
       "  手で直さない（PipeWire " hdr-version " のヘッダ）。PWS_* は構造体の大きさ、PWO_* は欄の位置（x86_64）。PWBuild は SDL の initialize_spa_info と\n"
       "  spa_format_audio_raw_build の結果、PWParse は C で組み立てた pod と SDL の get_range_param /\n"
       "  get_int_param の結果、PWJson は SDL の get_name_from_json と client_info の結果。 }\n\n"
       "const\n"
       (apply str (for [[n v] lays]
                    (if (str/includes? n ".") (format "  PWO_%s = %d;\n" (pas-ident n) v) (format "  PWS_%s = %d;\n" n v))))
       "\ntype\n"
       "  TPWBuildCase = record Name: String; Format: Word; Channels, Freq: Integer; Hex: String; end;\n"
       "  TPWParseCase = record Name: String; Hex: String; RateOk: Boolean; RateDef, RateMin, RateMax: Integer;\n"
       "    ChannelsOk: Boolean; Channels: Integer; end;\n"
       "  TPWJsonName = record Input: String; Found: Boolean; Output: String; end;\n"
       "  TPWJsonServices = record Input: String; HaveServices, HaveAudio: Boolean; end;\n"
       "  TPWJsonTokens = record Input: String; Tokens: String; end;\n\n"
       "const\n"
       (format "  PWBuild: array[0..%d] of TPWBuildCase = (\n" (dec (count pods)))
       (str/join ",\n"
                 (for [[[n hx] [_ fmt ch rate]] (map vector pods build-cases)]
                   (format "    (Name: '%s'; Format: %s; Channels: %d; Freq: %d; Hex: '%s')"
                           n (if (= fmt "0") "0" (str "PML_AUDIO_" (subs fmt 10))) ch rate hx)))
       ");\n"
       (format "  PWParse: array[0..%d] of TPWParseCase = (\n" (dec (count qpods)))
       (str/join ",\n"
                 (for [[[n hx] [_ [r d mi ma c ch]]] (map vector qpods rres)]
                   (format "    (Name: '%s'; Hex: '%s'; RateOk: %s; RateDef: %d; RateMin: %d; RateMax: %d; ChannelsOk: %s; Channels: %d)"
                           n hx (if (= r 1) "True" "False") d mi ma (if (= c 1) "True" "False") ch)))
       ");\n"
       (format "  PWJsonNames: array[0..%d] of TPWJsonName = (\n" (dec (count jres)))
       (str/join ",\n"
                 (for [[[_ v] input] (map vector jres json-names)]
                   (format "    (Input: %s; Found: %s; Output: %s)"
                           (pas-string input) (if (= v "-") "False" "True")
                           (if (= v "-") "''"
                               (pas-string (String. (byte-array (map #(unchecked-byte (Integer/parseInt (apply str %) 16))
                                                                      (partition 2 v)))
                                                    "UTF-8"))))))
       ");\n"
       (format "  PWJsonServices: array[0..%d] of TPWJsonServices = (\n" (dec (count kres)))
       (str/join ",\n"
                 (for [[[_ [s a]] input] (map vector kres json-services)]
                   (format "    (Input: %s; HaveServices: %s; HaveAudio: %s)"
                           (pas-string input) (if (= s 1) "True" "False") (if (= a 1) "True" "False"))))
       ");\n"
       (format "  PWJsonTokens: array[0..%d] of TPWJsonTokens = (\n" (dec (count tres)))
       (str/join ",\n"
                 (for [[[_ v] input] (map vector tres json-tokens)]
                   (format "    (Input: %s; Tokens: '%s')" (pas-string input) v)))
       ");\n"))

(spit consts-out consts-text)
(spit expected-out expected-text)
(println (format "genpipewire: 定数 %d、並び %d、組み立て %d、読み取り %d、JSON %d + %d + %d を書いた"
                 (+ (count ints) (count strs)) (count lays) (count pods) (count qpods)
                 (count jres) (count kres) (count tres)))
