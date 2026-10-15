#!/usr/bin/env bb
;; genchmap — SDL の ALSA のチャンネルの並びの交渉（alsa_chmap_cfg と、その下の関数）を、SDL のソースから
;; 切り出して C で動かし、場面ごとの結果を test/alsa_chmap_expected.inc に書き出す。
;;
;; なぜ要るか:
;;   papimela の PMLAlsaNegotiateChannelMap（PaPiMeLa.Audio.Alsa）は SDL の同名の関数群の写し。
;;   手元のハードウェアでは通らない道（入れ替え、6 チャンネルの後ろと横、VAR の並び、重複、失敗）を、
;;   偽の ALSA 関数で試す。期待値は SDL の関数そのものを動かした結果にする（手で作らない）。
;;
;; 使い方:
;;   tools/alsa-parity/genchmap.bb [ヘッダの根]
;;     ヘッダの根は alsa/ を持つ所（既定は /usr/include）。reference/SDL も要る（docs/ORIGIN.md）。cc が要る。
;;
;; 注意: SDL の alsa_chmap_cfg_ordered_fixed_or_paired は全部一致した後に配列の外を 1 つ読む
;;   （PaPiMeLa.Audio.Alsa の PORT-NOTE）。ここでは外を 0 で埋めておくので、SDL も「全部一致」で入れる。

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(def ^:private sdl-src "reference/SDL/src/audio/alsa/SDL_alsa_audio.c")
(def ^:private out-file "test/alsa_chmap_expected.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genchmap: " msg)))
  (System/exit 1))

(def ^:private inc-root (or (first *command-line-args*) "/usr/include"))
(when-not (fs/exists? (str inc-root "/alsa/asoundlib.h")) (fail inc-root "/alsa/asoundlib.h が無い"))
(when-not (fs/exists? sdl-src) (fail sdl-src " が無い。reference/SDL を用意すること"))

(def ^:private sdl-text (slurp sdl-src))
(def ^:private region
  (or (re-find #"(?s)// To make easier to track parameters.*?(?=#define CHANS_N_SCAN_MODE__EQUAL_OR_ABOVE_REQUESTED_CHANS_N)" sdl-text)
      (fail "SDL の該当の範囲が見つからない")))

;; ---- 場面。[名前 チャンネル数 [[種類 位置...] ...] set_chmap の戻り値]
;; 種類: 1 FIXED, 2 VAR, 3 PAIRED。位置は SND_CHMAP_ の値（下の表）
;; UNKNOWN 0, NA 1, MONO 2, FL 3, FR 4, RL 5, RR 6, FC 7, LFE 8, SL 9, SR 10, RC 11

(def ^:private FL 3) (def ^:private FR 4) (def ^:private RL 5) (def ^:private RR 6)
(def ^:private FC 7) (def ^:private LFE 8) (def ^:private SL 9) (def ^:private SR 10) (def ^:private RC 11)
(def ^:private MONO 2) (def ^:private NA 1)

(def ^:private cases
  [["no_queries" 2 nil 0]
   ["stereo_fixed" 2 [[1 FL FR]] 0]
   ["stereo_paired" 2 [[3 FL FR]] 0]
   ["stereo_reversed_fixed" 2 [[1 FR FL]] 0]
   ["stereo_reversed_then_ordered" 2 [[1 FR FL] [1 FL FR]] 0]
   ["stereo_var" 2 [[2 FL FR]] 0]
   ["stereo_var_reversed" 2 [[2 FR FL]] 0]
   ["stereo_wrong_channel_count" 2 [[1 FL FR LFE] [1 MONO]] 0]
   ["stereo_no_match" 2 [[1 FL RL]] 0]
   ["stereo_duplicate" 2 [[1 FL FL]] 0]
   ["stereo_na_filler" 2 [[1 NA NA]] 0]
   ["stereo_install_fails" 2 [[1 FL FR]] -22]
   ["mono" 1 [[1 MONO]] 0]
   ["mono_other" 1 [[1 FL]] 0]
   ["ch3" 3 [[1 FL FR LFE]] 0]
   ["ch3_swizzle" 3 [[1 LFE FL FR]] 0]
   ["ch4" 4 [[1 FL FR RL RR]] 0]
   ["ch4_swizzle" 4 [[1 RL RR FL FR]] 0]
   ["ch5" 5 [[1 FL FR LFE RL RR]] 0]
   ["ch6_rear" 6 [[1 FL FR FC LFE RL RR]] 0]
   ["ch6_side" 6 [[1 FL FR FC LFE SL SR]] 0]
   ["ch6_rear_swizzle" 6 [[1 FL FR LFE FC RL RR]] 0]
   ["ch6_side_swizzle" 6 [[1 FR FL FC LFE SR SL]] 0]
   ["ch6_both" 6 [[1 FL FR FC LFE RL SL]] 0]
   ["ch6_none" 6 [[1 FL FR FC LFE FC FC]] 0]
   ["ch6_missing_fc" 6 [[1 FL FR LFE RL RR NA]] 0]
   ["ch6_unknown_pair" 6 [[1 FL FR FC LFE 0 0]] 0]
   ["ch6_unknown_pair_var" 6 [[2 FL FR FC LFE 0 0]] 0]
   ["ch6_var_side" 6 [[2 FL FR FC LFE SL SR]] 0]
   ["ch6_var_rear" 6 [[2 FL FR FC LFE RL RR]] 0]
   ["ch7" 7 [[1 FL FR FC LFE RC SL SR]] 0]
   ["ch8" 8 [[1 FL FR FC LFE RL RR SL SR]] 0]
   ["ch8_swizzle" 8 [[1 FR FL FC LFE RR RL SR SL]] 0]
   ["ch8_var" 8 [[2 FL FR FC LFE RL RR SL SR]] 0]
   ["ordered_wins_over_unordered" 4 [[1 FR FL RL RR] [1 FL FR RL RR]] 0]
   ["var_after_fixed_miss" 2 [[1 FL RL] [2 FL FR]] 0]
   ["unordered_after_var_miss" 2 [[2 FL RL] [1 FR FL]] 0]
   ["install_fails_6" 6 [[1 FL FR FC LFE RL RR]] -5]])

;; ---- C のプログラム

(defn- case-c [i [name n queries setfail]]
  (let [qs (or queries [])]
    (str "  { /* " name " */\n"
         "    static unsigned int qdata" i "[] = { " (str/join ", " (concat (for [[t & ps] qs] (str t ", " (count ps) ", " (str/join ", " (concat ps (repeat 4 0))))))) " };\n"
         "    snd_pcm_chmap_query_t *arr[" (inc (count qs)) "] = { 0 };\n"
         "    unsigned int *p = qdata" i ";\n"
         (apply str (for [[j [t & ps]] (map-indexed vector qs)]
                      (str "    arr[" j "] = (snd_pcm_chmap_query_t *)p; p += 2 + " (count ps) " + 4;\n")))
         "    run_case(\"" name "\", " n ", " (if queries (str "arr") "NULL") ", " setfail ");\n  }\n")))

(def ^:private program
  (str "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <stdbool.h>\n#include <alsa/asoundlib.h>\n\n"
       "typedef unsigned short SDL_AudioFormat; typedef unsigned char Uint8;\n"
       "#define SDL_assert(x)\n#define SDL_memcpy memcpy\n#define SDL_arraysize(a) (sizeof(a)/sizeof((a)[0]))\n"
       "#define SDL_ALSA_DEBUG 0\n#define LOGDEBUG(...)\n"
       "#define SDL_AUDIO_ALSA__CHMAP_CHANS_N_MAX 8\n#define SDL_AUDIO_ALSA__SDL_CHMAPS_N 9\n"
       "#define SDL_small_alloc(type, n, isstack) (*(isstack) = false, (type *)malloc(sizeof(type) * (n)))\n"
       "#define SDL_small_free(p, isstack) free(p)\n"
       "static bool SDL_SetError(const char *fmt, ...) { return false; }\n"
       "struct SDL_PrivateAudioData { void *pcm; };\n"
       "typedef struct SDL_AudioDevice { struct SDL_PrivateAudioData *hidden; int *chmap; struct { int channels; } spec; } SDL_AudioDevice;\n"
       "static int *SDL_ChannelMapDup(const int *map, int channels) { int *r = malloc(sizeof(int) * channels); memcpy(r, map, sizeof(int) * channels); return r; }\n"
       "/* 偽の ALSA */\n"
       "static snd_pcm_chmap_query_t **fake_queries; static int fake_set_result; static int set_called; static unsigned int set_pos[16]; static int set_n; static int free_called;\n"
       "static snd_pcm_chmap_query_t **ALSA_snd_pcm_query_chmaps(snd_pcm_t *pcm) { return fake_queries; }\n"
       "static void ALSA_snd_pcm_free_chmaps(snd_pcm_chmap_query_t **maps) { free_called++; }\n"
       "static int ALSA_snd_pcm_set_chmap(snd_pcm_t *pcm, const snd_pcm_chmap_t *map) { set_called++; set_n = map->channels; for (unsigned i = 0; i < map->channels; i++) set_pos[i] = map->pos[i]; return fake_set_result; }\n"
       "static const char *ALSA_snd_strerror(int e) { return \"fake error\"; }\n"
       "static int ALSA_snd_pcm_chmap_print(const snd_pcm_chmap_t *m, size_t n, char *b) { return 0; }\n\n"
       region "\n"
       "static void run_case(const char *name, int chans, snd_pcm_chmap_query_t **queries, int setfail)\n{\n"
       "  struct ALSA_pcm_cfg_ctx ctx; SDL_AudioDevice dev; struct SDL_PrivateAudioData hid;\n"
       "  memset(&ctx, 0, sizeof(ctx)); memset(&dev, 0, sizeof(dev)); memset(&hid, 0, sizeof(hid));\n"
       "  dev.hidden = &hid; ctx.device = &dev; ctx.chans_n = chans;\n"
       "  fake_queries = queries; fake_set_result = setfail; set_called = 0; free_called = 0; set_n = 0;\n"
       "  int status = alsa_chmap_cfg(&ctx);\n"
       "  printf(\"R %s %d %d %d\", name, status, set_called, free_called);\n"
       "  printf(\" |\"); for (int i = 0; i < set_n; i++) printf(\" %u\", set_pos[i]);\n"
       "  printf(\" |\"); if (dev.chmap) for (int i = 0; i < chans; i++) printf(\" %d\", dev.chmap[i]);\n"
       "  printf(\"\\n\");\n}\n\n"
       "int main(void)\n{\n"
       (apply str (map-indexed case-c cases))
       "  return 0;\n}\n"))

(def ^:private tmp (str (fs/create-temp-dir {:prefix "genchmap"})))
(spit (str tmp "/gen.c") program)
(let [r (shell {:continue true :err :string :out :string} "cc" "-O0" "-w" (str "-I" inc-root) (str tmp "/gen.c") "-o" (str tmp "/gen"))]
  (when-not (zero? (:exit r)) (fail "C のコンパイルに失敗:\n" (:err r))))
(def ^:private out (:out (shell {:out :string :err :string} (str tmp "/gen"))))
(def ^:private results
  (for [l (str/split-lines out) :when (str/starts-with? l "R ")]
    (let [[head inst sw] (str/split l #" \|" 3)
          [_ name status set-called free-called] (str/split head #" ")]
      {:name name :status (parse-long status) :set (parse-long set-called) :free (parse-long free-called)
       :installed (mapv parse-long (remove str/blank? (str/split (str/trim (or inst "")) #" ")))
       :swizzle (mapv parse-long (remove str/blank? (str/split (str/trim (or sw "")) #" ")))})))
(when-not (= (count results) (count cases)) (fail "場面の件数が合わない: " (count results) " / " (count cases)))

(defn- pas-arr [v] (if (empty? v) "()" (str "(" (str/join ", " v) ")")))
(def ^:private text
  (str "{ test/alsa_chmap_expected.inc — tools/alsa-parity/genchmap.bb が作る。手で直さない。\n"
       "  SDL の alsa_chmap_cfg（SDL_alsa_audio.c）を偽の ALSA で動かした結果。\n"
       "  Status は 0 = 入れた、1 = 次のチャンネル数、負 = 失敗。SetCalled は snd_pcm_set_chmap を呼んだ回数、\n"
       "  FreeCalled は snd_pcm_free_chmaps を呼んだ回数（SDL は成功した道で解放しない。papimela は解放する）。 }\n\n"
       "type\n  TChmapCase = record\n    Name: String;\n    Chans: Integer;\n    Queries: String;   // 'type:pos,pos;type:pos,pos'。'-' は問い合わせが nil\n"
       "    SetResult: Integer;\n    Status, SetCalled, FreeCalled: Integer;\n    Installed, Swizzle: array of Integer;\n  end;\n\n"
       "const\n  ChmapCases: array[0.." (dec (count cases)) "] of TChmapCase = (\n"
       (str/join ",\n"
                 (for [[[name n queries setfail] r] (map vector cases results)]
                   (format "    (Name: '%s'; Chans: %d; Queries: '%s'; SetResult: %d; Status: %d; SetCalled: %d; FreeCalled: %d; Installed: %s; Swizzle: %s)"
                           name n (if queries (str/join ";" (for [[t & ps] queries] (str t ":" (str/join "," ps)))) "-") setfail
                           (:status r) (:set r) (:free r) (pas-arr (:installed r)) (pas-arr (:swizzle r)))))
       "\n  );\n"))
(spit out-file text)
(println (format "genchmap: %d 場面を書いた" (count cases)))
