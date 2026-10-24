#!/usr/bin/env bb
;; gen — tools/filesystem-expect/{casefold_cases.c,fs_cases.c} を参照版の SDL に通して、記録を test/ に書く。
;;
;;   casefold_cases.c  大文字小文字の畳み込みと UTF-8 の読み進め  -> test/casefold_expected.inc
;;   fs_cases.c        ファイルシステム（フォルダの操作 + 環境変数の場面） -> test/filesystem_expected.inc
;;
;; 使い方:
;;   tools/filesystem-expect/gen.bb <静的に作った SDL のビルドの場所>
;;     場所は libSDL3.a を持つ所（tools/gamepad-expect/gen.bb と同じ作り方）。内部の関数 SDL_CaseFoldUnicode は
;;     静的ライブラリの中にあり、直接呼べる。
;;
;; 作業のフォルダは毎回新しく作る。環境の場面は SDL が値を覚えるので、1 場面ずつ別のプロセスで動かす。
;;
;; 確かめること: 畳み込みは 1500 件以上、フォルダの操作は 100 行以上、環境の場面は 10 以上

(require '[babashka.fs :as fs]
         '[babashka.process :refer [shell]]
         '[clojure.string :as str])

(defn- fail [& msg]
  (binding [*out* *err*] (println (apply str "gen: " msg)))
  (System/exit 1))

(def ^:private where (first *command-line-args*))
(when-not where (fail "SDL のビルドの場所を渡す"))
(def ^:private tmp (str (fs/create-temp-dir {:prefix "fsexp"})))

(defn- q [s] (str "'" (str/replace s "'" "''") "'"))

(defn- build [src name]
  (let [exe (str tmp "/" name)
        r (shell {:continue true :err :string :out :string}
                 "cc" "-O1" "-w" "-Ireference/SDL/include" src "-o" exe
                 (str where "/libSDL3.a") "-lm" "-lpthread" "-ldl")]
    (when-not (zero? (:exit r)) (fail "コンパイルに失敗:\n" (:err r)))
    exe))

(defn- lines-of [out] (map #(subs % 2) (filter #(str/starts-with? % "L ") (str/split-lines out))))

(defn- write-inc [out-file const-name header rows]
  (spit out-file
        (str "{ " out-file " — tools/filesystem-expect/gen.bb が作る。手で直さない。\n  " header " }\n\n"
             "const\n  " const-name ": array[0.." (dec (count rows)) "] of String = (\n"
             (str/join ",\n" (map #(str "    " (q %)) rows))
             "\n  );\n"))
  (println (format "gen: %s に %d 行を書いた" out-file (count rows))))

;; 畳み込み
(let [exe (build "tools/filesystem-expect/casefold_cases.c" "casefold")
      rows (lines-of (:out (shell {:out :string :err :string} exe)))]
  (when (< (count rows) 1500) (fail "畳み込みの行が少ない: " (count rows)))
  (write-inc "test/casefold_expected.inc" "CaseFoldExpected"
             "参照版 SDL の SDL_CaseFoldUnicode（F: 畳み込みのあるコードポイント）と SDL_StepUTF8（U: 読んだコードポイント。UB は SDL の不具合 D-82 で比べない）の記録。"
             rows))

;; ファイルシステム
(let [exe (build "tools/filesystem-expect/fs_cases.c" "fs")
      run (fn [& args]
            (let [d (str (fs/create-temp-dir {:prefix "fsexpwork" :path tmp}))
                  r (apply shell {:out :string :err :string :continue true} exe (concat args [d]))]
              (when-not (zero? (:exit r)) (fail "fs_cases が失敗: " args "\n" (:err r)))
              (when (str/includes? (:out r) "usage") (fail "使い方の誤り"))
              (lines-of (:out r))))
      n (Integer/parseInt (str/trim (:out (shell {:out :string} exe "envcount"))))
      ops-rows (let [d (str (fs/create-temp-dir {:prefix "fsexpwork" :path tmp}))
                     r (shell {:out :string :err :string :continue true} exe "ops" d)]
                 (when-not (zero? (:exit r)) (fail "ops が失敗:\n" (:err r)))
                 (lines-of (:out r)))
      env-rows (mapcat (fn [i]
                         (let [d (str (fs/create-temp-dir {:prefix "fsexpwork" :path tmp}))
                               r (shell {:out :string :err :string :continue true} exe "env" (str i) d)]
                           (when-not (zero? (:exit r)) (fail "env " i " が失敗:\n" (:err r)))
                           (lines-of (:out r))))
                       (range n))
      ;; 作業のフォルダを <T> に書き直す前に出力されるので、念のため tmp の名前が残っていないことを確かめる
      rows (concat ops-rows env-rows)]
  (when (< (count ops-rows) 100) (fail "フォルダの操作の行が少ない: " (count ops-rows)))
  (when (< n 10) (fail "環境の場面が少ない: " n))
  (when (some #(str/includes? % tmp) rows) (fail "作業のフォルダの名前が出力に残っている"))
  (write-inc "test/filesystem_expected.inc" "FilesystemExpected"
             "参照版 SDL のファイルシステム（ops: フォルダの操作、ENV: 環境変数の場面ごとの UF = ユーザーのフォルダ・PP = 設定のフォルダ）の記録。作業のフォルダは <T>。"
             rows))
