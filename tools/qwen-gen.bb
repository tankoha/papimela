#!/usr/bin/env bb
;; qwen-gen — qwen にコードを書かせる。手元の ollama か、Amazon Bedrock へ投げる。
;;
;; `ollama run` を使うと TUI が ANSI エスケープ（カーソル移動・行消去）を
;; 出力に混ぜ、長い行が折り返される位置でソースが壊れる。API は素のテキストを
;; 返すのでその問題が無い。
;;
;; 使い方:
;;   tools/qwen-gen.bb プロンプトファイル [出力ファイル]
;;   出力ファイルを省略すると標準出力へ。
;;
;; 投げ先（PAPIMELA_QWEN_BACKEND）:
;;   ollama（既定）  手元の ollama の HTTP API。量子化した qwen2.5-coder:14b。
;;                   OLLAMA_HOST（既定 http://127.0.0.1:11434）、PAPIMELA_QWEN_MODEL
;;   bedrock         Amazon Bedrock の Converse API。量子化していない Qwen3-Coder。
;;                   クラウドのセッションには ollama が無いので、こちらを使う。
;;                   AWS_BEARER_TOKEN_BEDROCK  Bedrock の API キー（環境の設定に置く。必須）
;;                   AWS_REGION                既定 us-west-2
;;                   PAPIMELA_QWEN_MODEL       Bedrock のモデル ID（既定は下の bedrock-default-model）
;;                   PAPIMELA_QWEN_MAX_TOKENS  出力の上限（既定 16000）
;;                   途中で切れた（stopReason が max_tokens）ら、書き出さずに終了コード 1。
;;                   使ったトークン数とモデル ID を標準エラーに出す。
;;                   PAPIMELA_TRUSTSTORE       TLS の信頼する証明書の置き場（既定は下の default-truststore が
;;                                             あればそれ）。bb はネイティブなので JAVA_TOOL_OPTIONS を読まない。
;;                                             クラウドのセッションのエージェントの proxy の CA はここに入っている

(require '[babashka.http-client :as http]
         '[cheshire.core :as json]
         '[clojure.string :as str])

(def ^:private backend
  (or (System/getenv "PAPIMELA_QWEN_BACKEND") "ollama"))

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "qwen-gen: " msg)))
  (System/exit 1))

;; ---- ollama（手元）

(defn- generate-ollama
  "プロンプトを投げて応答テキストだけを返す。stream false で 1 回の応答にまとめる。"
  [prompt]
  (let [endpoint (str (or (System/getenv "OLLAMA_HOST") "http://127.0.0.1:11434") "/api/generate")
        model    (or (System/getenv "PAPIMELA_QWEN_MODEL") "qwen2.5-coder:14b")
        resp (http/post endpoint
                        {:headers {"Content-Type" "application/json"}
                         :body    (json/generate-string
                                   {:model  model
                                    :prompt prompt
                                    :stream false
                                    ;; 実装を書かせるので決定性を上げる。
                                    :options {:temperature 0.1
                                              :num_ctx     16384}})
                         :timeout 900000})]
    (when-not (= 200 (:status resp))
      (fail "ollama が " (:status resp) " を返した: " (:body resp)))
    (:response (json/parse-string (:body resp) true))))

;; ---- Bedrock（クラウド）

;; 鍵を入れた後に、モデルの一覧で実物の ID を確かめてから書いた値（docs/HANDOFF.md §6）。
(def ^:private bedrock-default-model "qwen.qwen3-coder-30b-a3b-v1:0")

;; クラウドのセッションでは proxy の CA を入れた JVM の信頼の置き場（/root/.ccr/README.md）。
;; 手元の機械に無ければ、bb の既定（公開の CA）のままにする。
(def ^:private default-truststore "/etc/ssl/certs/java/cacerts")

(defn- https-client []
  (let [store (or (System/getenv "PAPIMELA_TRUSTSTORE")
                  (when (.exists (java.io.File. default-truststore)) default-truststore))]
    (if store
      (http/client {:ssl-context {:trust-store store :trust-store-pass "changeit"}})
      (http/client {}))))

(defn- generate-bedrock
  "Converse API に 1 往復だけ投げる。本文の text の塊をつなげて返す。"
  [prompt]
  (let [token  (System/getenv "AWS_BEARER_TOKEN_BEDROCK")
        region (or (System/getenv "AWS_REGION") "us-west-2")
        model  (or (System/getenv "PAPIMELA_QWEN_MODEL") bedrock-default-model)
        max-tokens (parse-long (or (System/getenv "PAPIMELA_QWEN_MAX_TOKENS") "16000"))
        _ (when (str/blank? token)
            (fail "AWS_BEARER_TOKEN_BEDROCK が無い。Bedrock の API キーを環境の設定"
                  "（Network secrets か環境変数）に置くこと。チャットには貼らない"))
        url  (str "https://bedrock-runtime." region ".amazonaws.com/model/"
                  (java.net.URLEncoder/encode model "UTF-8") "/converse")
        resp (http/post url
                        {:headers {"Content-Type"  "application/json"
                                   "Authorization" (str "Bearer " token)}
                         :body    (json/generate-string
                                   {:messages [{:role "user" :content [{:text prompt}]}]
                                    ;; 実装を書かせるので決定性を上げる（ollama の枝と同じ値）。
                                    :inferenceConfig {:temperature 0.1
                                                      :maxTokens   max-tokens}})
                         :timeout 900000
                         :client  (https-client)
                         :throw   false})
        _ (when-not (= 200 (:status resp))
            (fail "Bedrock（" region "、" model "）が " (:status resp) " を返した: " (:body resp)))
        body  (json/parse-string (:body resp) true)
        text  (->> (get-in body [:output :message :content])
                   (keep :text)
                   (str/join))
        usage (:usage body)]
    (binding [*out* *err*]
      (println (str "qwen-gen: " model "（" region "）入力 " (:inputTokens usage)
                    " トークン、出力 " (:outputTokens usage) " トークン、stopReason "
                    (:stopReason body))))
    (when (= "max_tokens" (:stopReason body))
      (fail "出力が上限（" max-tokens " トークン）で切れた。書き出さない。"
            "PAPIMELA_QWEN_MAX_TOKENS を上げるか、依頼を分けること"))
    (when (str/blank? text)
      (fail "応答に本文が無い: " (:body resp)))
    text))

;; ---- 共通

(defn- strip-fences
  "```pascal … ``` で囲んで返してくることがあるので外す。"
  [s]
  (-> s
      (str/replace #"(?m)^```[a-zA-Z]*\s*$" "")
      str/trim))

(defn- generate [prompt]
  (case backend
    "ollama"  (generate-ollama prompt)
    "bedrock" (generate-bedrock prompt)
    (fail "PAPIMELA_QWEN_BACKEND は ollama か bedrock（今は \"" backend "\"）")))

(let [[prompt-file out-file] *command-line-args*]
  (when-not prompt-file
    (binding [*out* *err*]
      (println "使い方: tools/qwen-gen.bb プロンプトファイル [出力ファイル]"))
    (System/exit 2))
  (let [text (strip-fences (generate (slurp prompt-file)))]
    (if out-file
      (do (spit out-file (str text "\n"))
          (println "書き出した:" out-file
                   (str "(" (count (str/split-lines text)) " 行)")))
      (println text))))
