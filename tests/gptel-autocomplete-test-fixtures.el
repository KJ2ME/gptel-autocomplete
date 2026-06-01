;;; gptel-autocomplete-test-fixtures.el --- Test fixtures for gptel-autocomplete

(defconst gptel-test-fixtures
  `((:name "python-add-b"
     :major-mode python-mode
     :content ,(concat "def add(a, b):\n"
                       "    return a + ")
     :cursor-pos :eol)
    (:name "python-return-none"
     :major-mode python-mode
     :content ,(concat "def find_user(uid):\n"
                       "    for u in users:\n"
                       "        if u.id == uid:\n"
                       "            return u\n"
                       "    return ")
     :cursor-pos :eol)
    (:name "js-multiply-by-two"
     :major-mode js-mode
     :content ,(concat "const multiply_by_two = (x) => ")
     :cursor-pos :eol)
    (:name "go-division-error"
     :major-mode go-mode
     :content ,(concat "func divide(a, b float64) (float64, error) {\n"
                       "    if b == 0 {\n"
                       "        return 0, ")
     :cursor-pos :eol)
    (:name "python-sort-by-first"
     :major-mode python-mode
     :content ,(concat "data = [(3, 'c'), (1, 'a'), (2, 'b')]\n"
                       "data.sort(key=lambda x: ")
     :cursor-pos :eol)
    (:name "rust-describe-option"
     :major-mode rust-mode
     :content ,(concat "fn describe_option(x: Option<i32>) -> String {\n"
                        "    match x {\n"
                        "        ")
     :cursor-pos :eol)
    (:name "js-else-log"
     :major-mode js-mode
     :content ,(concat "function print_adult_or_minor(age) {\n"
                        "    if (age >= 18) {\n"
                        "        console.log('Adult');\n"
                        "    } else█\n"
                        "}")
     :cursor-pos :cursor-marker)
    (:name "js-loop-up-to-n"
     :major-mode js-mode
     :content ,(concat "function print_up_to(n) {\n"
                        "    for (let i = 0; i█\n"
                        "}")
     :cursor-pos :cursor-marker)
    (:name "php-filter-positive"
     :major-mode php-mode
     :content ,(concat "<?php\n"
                       "$numbers = [1, -2, 3, -4];\n"
                       "$positive = array_filter($numbers, function($n) {\n"
                       "    return ")
     :cursor-pos :eol))
  "List of fixture plists for integration tests.
Each entry has :name (symbol), :major-mode (mode function),
:content (string of code ending at the completion point),
:cursor-pos (:eol to complete at end of line, or :cursor-marker
when content contains a █ marker for cursor position).")

(defconst gptel-test-default-models
  '("Qwen2.5-Coder")
  "Default models for integration tests.
Set `gptel-test-models' before loading tests to override.")

(defconst gptel-test-backend-template
  '(:protocol "http" :host "127.0.0.1:1945" :stream t)
  "Default backend plist for integration tests.
Set `gptel-test-backend' before loading tests to override.")

(provide 'gptel-autocomplete-test-fixtures)
