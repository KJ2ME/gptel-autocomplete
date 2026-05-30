;;; gptel-autocomplete-test-fixtures.el --- Test fixtures for gptel-autocomplete

(defconst gptel-test-fixtures
  `((:name "python-function"
     :major-mode python-mode
     :content ,(concat "def add(a, b):\n"
                       "    return a + ")
     :cursor-pos :eol)
    (:name "python-return-nil"
     :major-mode python-mode
     :content ,(concat "def find_user(uid):\n"
                       "    for u in users:\n"
                       "        if u.id == uid:\n"
                       "            return u\n"
                       "    return ")
     :cursor-pos :eol)
    (:name "js-arrow"
     :major-mode js-mode
     :content ,(concat "const double = (x) => ")
     :cursor-pos :eol)
    (:name "go-error"
     :major-mode go-mode
     :content ,(concat "func div(a, b float64) (float64, error) {\n"
                       "    if b == 0 {\n"
                       "        return 0, ")
     :cursor-pos :eol)
    (:name "python-lambda-key"
     :major-mode python-mode
     :content ,(concat "data.sort(key=lambda x: ")
     :cursor-pos :eol)
    (:name "rust-match"
     :major-mode rust-mode
     :content ,(concat "fn describe(x: Option<i32>) -> String {\n"
                       "    match x {\n"
                       "        ")
     :cursor-pos :eol))
  "List of fixture plists for integration tests.
Each entry has :name (symbol), :major-mode (mode function),
:content (string of code ending at the completion point),
:cursor-pos (:eol to complete at end of line).")

(defconst gptel-test-default-models
  '("Qwen2.5-Coder")
  "Default models for integration tests.
Set `gptel-test-models' before loading tests to override.")

(defconst gptel-test-backend-template
  '(:protocol "http" :host "127.0.0.1:1945" :stream t)
  "Default backend plist for integration tests.
Set `gptel-test-backend' before loading tests to override.")

(provide 'gptel-autocomplete-test-fixtures)
