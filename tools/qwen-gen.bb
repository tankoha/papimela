#!/usr/bin/env bb
;; qwen-gen — qwen にコードを書かせる。送り先は環境変数 PAPIMELA_QWEN_BACKEND で選ぶ。
;;
;; - bedrock: AWS CLI の `aws bedrock-runtime converse` で qwen.qwen3-coder-next を呼ぶ。
;;   認証は CLI に任せる（`aws login` 済みであること）。リージョンは AWS_REGION
;;   （既定 ap-southeast-2。このモデルはシドニーの In-Region のみで、要求は国外へ出ない）。
;; - ollama（既定）: 手元の HTTP API で qwen2.5-coder:14b を呼ぶ。
;;   `ollama run` を使うと TUI が ANSI エスケープ（カーソル移動・行消去）を
;;   出力に混ぜ、長い行が折り返される位置でソースが壊れる。API は素のテキストを
;;   返すのでその問題が無い。
;;
;; 使い方:
;;   tools/qwen-gen.bb プロンプトファイル [出力ファイル]
;;   出力ファイルを省略すると標準出力へ。

(require '[babashka.fs :as fs]
         '[babashka.http-client :as http]
         '[babashka.process :as p]
         '[cheshire.core :as json])

(defn- fail [& msg]
  (binding [*out* *err*] (apply println msg))
  (System/exit 1))

(defn- generate-ollama [prompt]
  (let [model (or (System/getenv "PAPIMELA_QWEN_MODEL") "qwen2.5-coder:14b")
        url   (str (or (System/getenv "OLLAMA_HOST") "http://127.0.0.1:11434") "/api/generate")
        resp  (http/post url
                         {:headers {"Content-Type" "application/json"}
                          :body    (json/generate-string
                                    {:model  model
                                     :prompt prompt
                                     :stream false
                                     ;; 実装を書かせるので決定性を上げる。
                                     :options {:temperature 0.1
                                               :num_ctx     16384}})
                          :timeout 900000
                          :throw   false})]
    (when-not (= 200 (:status resp))
      (fail "ollama が" (:status resp) "を返した:" (:body resp)))
    (:response (json/parse-string (:body resp) true))))

(defn- generate-bedrock [prompt]
  (let [model  (or (System/getenv "PAPIMELA_QWEN_MODEL") "qwen.qwen3-coder-next")
        region (or (System/getenv "AWS_REGION") "ap-southeast-2")
        ;; プロンプトは CODING-STYLE.md の全文を含んで長いので、引数ではなくファイルで渡す。
        msgs   (fs/create-temp-file {:prefix "qwen-gen-" :suffix ".json"})]
    (try
      (spit (str msgs) (json/generate-string [{:role "user" :content [{:text prompt}]}]))
      (let [res (p/shell {:out :string :err :string :continue true}
                         "aws" "bedrock-runtime" "converse"
                         "--region" region
                         "--model-id" model
                         "--messages" (str "file://" msgs)
                         ;; 実装を書かせるので決定性を上げる。maxTokens はモデルの上限（16K）。
                         "--inference-config" (json/generate-string {:temperature 0.1 :maxTokens 16384})
                         "--cli-read-timeout" "0"
                         "--output" "json")]
        (when-not (zero? (:exit res))
          (fail "aws bedrock-runtime converse が失敗した:" (:err res)))
        (let [body (json/parse-string (:out res) true)]
          ;; 上限で切れたソースをそのまま採用しないよう、止める。
          (when (= "max_tokens" (:stopReason body))
            (fail "出力が maxTokens で切れた。仕様を分けて投げ直すこと"))
          (get-in body [:output :message :content 0 :text])))
      (finally (fs/delete-if-exists msgs)))))

(defn- strip-fences
  "```pascal … ``` で囲んで返してくることがあるので外す。"
  [s]
  (-> s
      (clojure.string/replace #"(?m)^```[a-zA-Z]*\s*$" "")
      clojure.string/trim))

(let [[prompt-file out-file] *command-line-args*
      backend (or (System/getenv "PAPIMELA_QWEN_BACKEND") "ollama")]
  (when-not prompt-file
    (binding [*out* *err*]
      (println "使い方: tools/qwen-gen.bb プロンプトファイル [出力ファイル]"))
    (System/exit 2))
  (let [prompt (slurp prompt-file)
        text   (strip-fences (case backend
                               "bedrock" (generate-bedrock prompt)
                               "ollama"  (generate-ollama prompt)
                               (fail "PAPIMELA_QWEN_BACKEND は bedrock か ollama:" backend)))]
    (if out-file
      (do (spit out-file (str text "\n"))
          (println "書き出した:" out-file
                   (str "(" (count (clojure.string/split-lines text)) " 行)")))
      (println text))))
