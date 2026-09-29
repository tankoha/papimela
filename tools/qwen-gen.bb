#!/usr/bin/env bb
;; qwen-gen — ollama の HTTP API で qwen2.5-coder にコードを書かせる。
;;
;; `ollama run` を使うと TUI が ANSI エスケープ（カーソル移動・行消去）を
;; 出力に混ぜ、長い行が折り返される位置でソースが壊れる。API は素のテキストを
;; 返すのでその問題が無い。
;;
;; 使い方:
;;   tools/qwen-gen.bb プロンプトファイル [出力ファイル]
;;   出力ファイルを省略すると標準出力へ。

(require '[babashka.http-client :as http]
         '[cheshire.core :as json])

(def ^:private endpoint
  (str (or (System/getenv "OLLAMA_HOST") "http://127.0.0.1:11434") "/api/generate"))

(def ^:private model
  (or (System/getenv "PAPIMELA_QWEN_MODEL") "qwen2.5-coder:14b"))

(defn- generate
  "プロンプトを投げて応答テキストだけを返す。stream false で 1 回の応答にまとめる。"
  [prompt]
  (let [resp (http/post endpoint
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
      (binding [*out* *err*]
        (println "ollama が" (:status resp) "を返した:" (:body resp)))
      (System/exit 1))
    (:response (json/parse-string (:body resp) true))))

(defn- strip-fences
  "```pascal … ``` で囲んで返してくることがあるので外す。"
  [s]
  (-> s
      (clojure.string/replace #"(?m)^```[a-zA-Z]*\s*$" "")
      clojure.string/trim))

(let [[prompt-file out-file] *command-line-args*]
  (when-not prompt-file
    (binding [*out* *err*]
      (println "使い方: tools/qwen-gen.bb プロンプトファイル [出力ファイル]"))
    (System/exit 2))
  (let [text (strip-fences (generate (slurp prompt-file)))]
    (if out-file
      (do (spit out-file (str text "\n"))
          (println "書き出した:" out-file
                   (str "(" (count (clojure.string/split-lines text)) " 行)")))
      (println text))))
