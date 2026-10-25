#!/usr/bin/env bb
;; genspirv — SDL の Vulkan レンダラの SPIR-V（コンパイル済みのシェーダ）と YCbCr の行列を Pascal の定数へ写す。
;;
;; なぜ要るか:
;;   Render.Vulkan（設計 #67）は SDL の render/vulkan/ の移植で、シェーダは SDL が HLSL から事前にコンパイルした
;;   SPIR-V のバイト列（VULKAN_*.h の uint32_t の配列）をそのまま使う。HLSL をコンパイルする道具はこの環境に無く、
;;   手で写すと写し間違える（CLAUDE.md: 大きな表は手にも qwen にも写させない）ので、ヘッダから機械的に写す。
;;
;; 使い方:
;;   tools/genspirv.bb            生成物を書く
;;   tools/genspirv.bb --check    書いてあるものが古くないかを見る（手元用。reference/SDL は CI に無い）
;;
;; 書くもの:
;;   src/generated/vulkan_shaders.inc   SDL の SPIR-V の配列（頂点 1 本と断片 4 本）。PQ（HDR）の 2 本は写さない
;;   src/generated/vulkan_ycbcr.inc     YCbCr → RGB の行列 5 つ（video/SDL_pixels.c の mat_BT601_Full_8bit ほか。
;;                                      並びは TPMLYCbCrType: BT601Full / BT601Limited / BT709Full / BT709Limited / BT2020Full）
;;
;; 確かめること（どれかが合わなければ止まる）:
;;   - 先頭の語が SPIR-V のマジックナンバー 0x07230203
;;   - 読んだ語の数が、配列の宣言どおり（ヘッダの { } の中の 0x の数と、書いた数が同じ）
;;   - 同じ入力からは同じファイルができる

(require '[babashka.fs :as fs]
         '[clojure.string :as str])

(def ^:private sdl-dir "reference/SDL/src/render/vulkan")
(def ^:private out-file "src/generated/vulkan_shaders.inc")
(def ^:private ycbcr-file "src/generated/vulkan_ycbcr.inc")

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "genspirv: " msg)))
  (System/exit 1))

;; [SDL の配列名 Pascal の名前 SDL の列挙子]。PQ（HDR）は後回し（docs/DESIGN.md #67）
(def ^:private shaders
  [["VULKAN_VertexShader" "VulkanVertexShader"]
   ["VULKAN_PixelShader_Colors" "VulkanPixelShaderColors"]
   ["VULKAN_PixelShader_Textures" "VulkanPixelShaderTextures"]
   ["VULKAN_PixelShader_Textures_Simple" "VulkanPixelShaderTexturesSimple"]
   ["VULKAN_PixelShader_Advanced" "VulkanPixelShaderAdvanced"]])

(defn- read-words [array-name]
  (let [f (str sdl-dir "/" array-name ".h")
        _ (when-not (fs/exists? f) (fail f " が無い"))
        text (slurp f)
        m (re-find (re-pattern (str "(?s)uint32_t " array-name "\\[\\]\\s*=\\s*\\{(.*?)\\};")) text)
        _ (when-not m (fail array-name " の配列が読めない"))
        body (second m)
        words (mapv #(str/upper-case (subs % 2)) (re-seq #"0x[0-9a-fA-F]{1,8}" body))
        raw-count (count (re-seq #"0x" body))]
    (when-not (= (count words) raw-count) (fail array-name ": 語の数が合わない"))
    (when-not (= (first words) "07230203") (fail array-name ": 先頭が SPIR-V のマジックナンバーでない: " (first words)))
    words))

(def ^:private text
  (str "{ src/generated/vulkan_shaders.inc — tools/genspirv.bb が作る。手で直さない。\n"
       "  SDL の Vulkan レンダラの SPIR-V（reference/SDL/src/render/vulkan/VULKAN_*.h。HLSL から事前にコンパイル済み）。\n"
       "  頂点 1 本と断片 4 本（Colors / Textures / Textures_Simple / Advanced）。PQ（HDR）の 2 本は写さない。 }\n"
       (apply str
              (for [[arr pas] shaders
                    :let [ws (read-words arr)]]
                (str "  " pas ": array[0.." (dec (count ws)) "] of LongWord = (\n"
                     (str/join ",\n" (for [row (partition-all 8 ws)]
                                       (str "    " (str/join ", " (map #(str "$" %) row)))))
                     ");\n")))))

;; ---- YCbCr の行列。SDL_pixels.c の static const float mat_*[]（16 個: オフセット・R・G・B の係数 4 個ずつ）

(def ^:private ycbcr-names
  ["mat_BT601_Full_8bit" "mat_BT601_Limited_8bit" "mat_BT709_Full_8bit" "mat_BT709_Limited_8bit" "mat_BT2020_Full_10bit"])

(defn- read-matrix [n]
  (let [text (slurp (str "reference/SDL/src/video/SDL_pixels.c"))
        m (re-find (re-pattern (str "(?s)static const float " n "\\[\\]\\s*=\\s*\\{(.*?)\\};")) text)
        _ (when-not m (fail n " が読めない"))
        body (str/replace (second m) #"//[^\n]*" "")
        nums (re-seq #"-?[0-9]+\.[0-9]+f?|-?[0-9]+f" body)]
    (when-not (= 16 (count nums)) (fail n ": 値が 16 個でない（" (count nums) "）"))
    (mapv #(str/replace % #"f$" "") nums)))

(def ^:private ycbcr-text
  (str "{ src/generated/vulkan_ycbcr.inc — tools/genspirv.bb が作る。手で直さない。\n"
       "  YCbCr → RGB の行列（SDL の video/SDL_pixels.c）。16 個: オフセット・R・G・B の係数を 4 個ずつ。\n"
       "  並びは TPMLYCbCrType（BT601Full / BT601Limited / BT709Full / BT709Limited / BT2020Full）。 }\n"
       "  VulkanYCbCrMatrix: array[0..4] of array[0..15] of Single = (\n"
       (str/join ",\n" (for [n ycbcr-names]
                         (str "    (" (str/join ", " (read-matrix n)) ")")))
       ");\n"))

(let [mode (first *command-line-args*)]
  (case mode
    nil (do (spit out-file text)
            (spit ycbcr-file ycbcr-text)
            (println (format "genspirv: %d 本の SPIR-V（語 %d 個）を %s に書いた" (count shaders)
                             (count (re-seq #"\$[0-9A-F]{1,8}" text)) out-file)))
    "--check" (if (and (= text (when (fs/exists? out-file) (slurp out-file)))
                       (= ycbcr-text (when (fs/exists? ycbcr-file) (slurp ycbcr-file))))
                (println "genspirv: 生成物は新しい")
                (fail out-file " が古い、または無い"))
    (fail "使い方: tools/genspirv.bb [--check]")))
