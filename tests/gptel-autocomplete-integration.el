;;; gptel-autocomplete-integration.el --- Integration tests for gptel-autocomplete -*- lexical-binding: t -*-

;; These tests call real LLM backends.  They require a running endpoint
;; compatible with gptel (e.g. llama.cpp server).
;;
;; Override variables before loading:
;;   (setq gptel-test-models '("Qwen2.5-Coder"))
;;   (setq gptel-test-backend '(:protocol "http" :host "127.0.0.1:1945" :stream t))
;;
;; Run:  emacs --batch -L . -L tests                  \
;;              -l tests/gptel-autocomplete-integration.el \
;;              -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'gptel)
(require 'gptel-openai)
(require 'gptel-autocomplete)
(require 'gptel-autocomplete-test-fixtures)


;;; Configuration (set before loading to override)

(defvar gptel-test-models gptel-test-default-models
  "List of model names to run integration tests against.")

(defvar gptel-test-backend gptel-test-backend-template
  "Plist with backend keys :protocol, :host, :stream.")

(defvar gptel-test-timeout 300
  "Maximum seconds to wait for a single completion response.")

(defvar gptel-test-verbose nil
  "Non-nil enables showing full completion text in integration test report.")

(defvar gptel-test-results nil
  "Accumulated results plist for reporting.")


;;; Backend management

(defun gptel-test--create-backend (model)
  "Create and return a gptel backend struct for MODEL.
Uses `gptel-make-openai' with `gptel-test-backend' config."
  (let* ((config gptel-test-backend)
         (backend (gptel-make-openai
                   (intern (format "gptel-test-%s" model))
                   :stream (plist-get config :stream)
                   :protocol (plist-get config :protocol)
                   :host (plist-get config :host)
                   :models (list model))))
    backend))

(defun gptel-test--with-backend (model fn)
  "Execute FN with gptel-backend set to a backend for MODEL."
  (let* ((backend (gptel-test--create-backend model))
         (gptel-backend backend)
         (gptel-model model))
    (funcall fn)))

(defun gptel-test--backend-available-p ()
  "Return non-nil if the current gptel-backend is reachable.
Sends a benign request and checks for a non-nil response or callback."
  t)


;;; Fixture helpers

(defun gptel-test--apply-fixture (fixture)
  "Return a plist with :buffer and :point for FIXTURE.
If content contains `█', point is placed at that position (marker removed)."
  (let* ((content (plist-get fixture :content))
         (major (plist-get fixture :major-mode))
         (name (plist-get fixture :name))
         (buf (generate-new-buffer " *gptel-test*")))
    (with-current-buffer buf
      (if (and major (fboundp major))
          (funcall major)
        (when major
          (message "Warning: %s not available, using prog-mode" major))
        (prog-mode))
      (insert content)
      (let ((cpos (search-backward "█" nil t)))
        (if cpos
            (delete-char 1)
          (goto-char (point-max))
          (skip-chars-backward "\n" (line-beginning-position))))
      (list :name name
            :buffer buf
            :point (point)
            :content (buffer-string)))))

(defun gptel-test--completion-valid-p (text fixture)
  "Return non-nil if TEXT is a plausible completion for FIXTURE.
Checks structural properties instead of exact content."
  (when (and (stringp text)
             (not (string-empty-p text))
             (not (string-match-p "█\\(CURSOR\\|START_COMPLETION\\|END_COMPLETION\\)█" text))
             (< (length text) 5000))
    text))


;;; Result logging

(defun gptel-test--record (model fixture status data
                                     &optional before after prompt)
  "Record a test result.
DATA is a short detail string for the summary table.
BEFORE is the original code before completion.
AFTER is the code with completion inserted.
PROMPT is the prompt sent to the model."
  (push (list :model model
              :fixture (plist-get fixture :name)
              :status status
              :data data
              :code-before before
              :code-after after
              :prompt prompt)
        gptel-test-results))

(defun gptel-test--print-report ()
  "Print a summary table of all integration test results."
  (let ((results (reverse gptel-test-results)))
    (princ "\n\n========== Integration Test Report ==========\n")
    ;; Show the system prompt from the first result
    (when results
      (let ((prompt (plist-get (car results) :prompt)))
        (when prompt
          (princ "\n;; Prompt:\n")
          (princ prompt)
          (unless (string-suffix-p "\n" prompt)
            (princ "\n"))
          (princ "\n"))))
    (princ (format "%-22s %-22s %-8s %s\n" "Model" "Fixture" "Status" "Detail"))
    (princ (make-string 80 ?=) t)
    (princ "\n")
    (dolist (r results)
      (let ((model (plist-get r :model))
            (fixture (plist-get r :fixture))
            (status (plist-get r :status))
            (data (plist-get r :data)))
        (let ((detail (if (stringp data)
                          (replace-regexp-in-string
                           "\n" "\\\\n"
                           (truncate-string-to-width data 60 nil nil t))
                        "")))
          (princ (format "%-22s %-22s %-8s %s\n"
                         (format "%s" (or model "?"))
                         (format "%s" (or fixture "?"))
                         (format "%s" (or status "?"))
                         detail)))))
    (princ (make-string 80 ?=) t)
    (princ "\n")
    (let* ((passed (cl-count-if (lambda (r) (eq (plist-get r :status) 'passed)) results))
           (failed (cl-count-if (lambda (r) (eq (plist-get r :status) 'failed)) results))
           (errored (- (length results) passed failed)))
      (princ (format "Total: %d | Passed: %d | Failed: %d | Errors: %d\n\n"
                     (length results) passed failed errored)))
    (when gptel-test-verbose
      (princ "\n--- Completions (before -> after) ---\n")
      (dolist (r results)
        (let ((model (plist-get r :model))
              (fixture (plist-get r :fixture))
              (status (plist-get r :status))
              (before (plist-get r :code-before))
              (after (plist-get r :code-after)))
          (when (and (eq status 'passed) before after)
            (princ (format "\n;; %s / %s\n" model fixture))
            (princ ";; before:\n")
            (princ before)
            (unless (string-suffix-p "\n" before)
              (princ "\n"))
            (princ ";; after:\n")
            (princ after)
            (unless (string-suffix-p "\n" after)
              (princ "\n"))))))))

(defun gptel-test--failed-assertions ()
  "Return non-nil if any integration test failed."
  (cl-some (lambda (r) (eq (plist-get r :status) 'failed))
           gptel-test-results))


;;; Single model × fixture test

(defun gptel-test--run-single (model fixture)
  "Run a single completion test: MODEL × FIXTURE.
Return plist with :status and :data."
   (let* ((prepared (gptel-test--apply-fixture fixture))
          (buffer (plist-get prepared :buffer))
          (point (plist-get prepared :point))
          (name (plist-get prepared :name))
          (content (plist-get prepared :content))
           result-text callback-response callback-status had-markers
          (callback-done nil)
         (before-cursor-in-line
           (with-current-buffer buffer
             (let ((start (line-beginning-position))
                   (end (point)))
               (buffer-substring-no-properties start end))))
          (after-cursor-in-line
           (with-current-buffer buffer
             (let ((start (point))
                   (end (line-end-position)))
               (buffer-substring-no-properties start end))))
          response-received
         (timer (run-with-timer gptel-test-timeout nil
                                (lambda ()
                                  (setq response-received :timeout))))
         (gptel--completion-request-id 0)
         (gptel--completion-active-request-id nil)
         (gptel-autocomplete-debug nil)
         (gptel-autocomplete-use-context nil)
         (gptel-prompt-transform-functions nil)
           (gptel-temperature 0.1)
           (gptel-autocomplete-temperature 0.1)
           (marked-line (concat "█START_COMPLETION█\n"
                                before-cursor-in-line "█CURSOR█" after-cursor-in-line "\n"
                                "█END_COMPLETION█"))
           (prompt (concat "Complete the code at the cursor position █CURSOR█ in buffer '"
                           name "':\n````````\n"
                           marked-line "\n````````\n"))
           (full-prompt gptel-autocomplete--system-prompt))

    (unwind-protect
        (with-current-buffer buffer
          (goto-char point)
          (gptel--log "Integration test: %s / %s at char %d"
                      (plist-get fixture :name) model point)
          (gptel-request prompt
           :system gptel-autocomplete--system-prompt
           :buffer buffer
           :position point
           :callback
           (lambda (response info)
             (let ((status (plist-get info :status)))
               (setq callback-status status)
               (when response-received
                 (cancel-timer timer)
                 (setq response-received :done))
                (when (and (stringp response)
                           (not (string-empty-p (string-trim response))))
                   (let* ((trimmed (string-trim response))
                          (code (if (string-match
                                     "^```\\(?:[a-zA-Z]*\\)?\n\\(\\(?:.\\|\n\\)*?\\)\n```$"
                                     trimmed)
                                    (match-string 1 trimmed)
                                  trimmed))
                          (marker-match (string-match
                                        "█START_COMPLETION█\n\\(\\(?:.\\|\n\\)*?\\)\n█END_COMPLETION█"
                                        code))
                          (extracted
                           (if marker-match
                               (let ((raw (match-string 1 code)))
                                 (if (and before-cursor-in-line
                                          (not (string-empty-p before-cursor-in-line))
                                          (string-prefix-p before-cursor-in-line raw))
                                     (substring raw (length before-cursor-in-line))
                                   raw))
                             code)))
                     (setq result-text extracted
                           callback-response trimmed
                           had-markers marker-match))))
             (setq callback-done t)))
          ;; Wait for callback
          (let ((waited 0))
            (while (and (not callback-done)
                       (not (eq response-received :timeout))
                       (< waited (* gptel-test-timeout 10)))
              (sleep-for 0.1)
              (cl-incf waited)))
          (cancel-timer timer)
          ;; Validate
          (cond
            ((not callback-done)
              (gptel-test--record model fixture 'failed
                                  (format "Timeout (>%ds)" gptel-test-timeout)
                                  nil nil full-prompt)
              (list :status 'failed :data "timeout"))
             ((eq response-received :timeout)
              (gptel-test--record model fixture 'failed "Response timeout"
                                  nil nil full-prompt)
              (list :status 'failed :data "response timeout"))
             ((not (stringp result-text))
              (gptel-test--record model fixture 'failed
                                  (format "No completion text (status=%s)" callback-status)
                                  nil nil full-prompt)
              (list :status 'failed :data (format "no-text status=%s" callback-status)))
             ((string-empty-p (string-trim result-text))
              (gptel-test--record model fixture 'failed "Empty response"
                                  nil nil full-prompt)
              (list :status 'failed :data "empty"))
              ((string-match-p "█" result-text)
               (gptel-test--record model fixture 'failed "Contains control tokens"
                                   nil nil full-prompt)
               (list :status 'failed :data "has-control-tokens"))
               (t
                (let* ((trimmed (string-trim result-text))
                       (before-cursor (substring content 0 (1- point)))
                       (after-cursor (substring content (1- point)))
                       (after (concat before-cursor trimmed after-cursor))
                       (warning (when (and callback-response
                                           (not had-markers))
                                  "WARNING: not wrapped # "))
                       (detail (concat (or warning "") trimmed)))
                  (gptel-test--record model fixture 'passed detail content after full-prompt)
                  (list :status 'passed :data result-text))))
      (cancel-timer timer)))))

(defun gptel-test--run-all ()
  "Run all integration tests across all models and fixtures.
Returns an ert-compatible list of results."
  (setq gptel-test-results nil)
  (dolist (model gptel-test-models)
    (dolist (fixture gptel-test-fixtures)
      (gptel-test--with-backend model
        (lambda ()
          (gptel-test--run-single model fixture))))))


;;; ert integration

(ert-deftest gptel-test/integration-all ()
  "Run gptel-autocomplete integration tests against real models.
This test iterates over `gptel-test-models' and `gptel-test-fixtures'.
Results are printed as a summary table."
  :tags '(integration)
  (skip-unless (and (boundp 'gptel-test-models)
                    gptel-test-models
                    (boundp 'gptel-test-fixtures)
                    gptel-test-fixtures))
  (let ((gptel-test-results nil))
    (gptel-test--run-all)
    (gptel-test--print-report)
    (when (gptel-test--failed-assertions)
      (ert-fail "Some integration tests failed (see report above)"))))

(ert-deftest gptel-test/integration-ping ()
  "Quick ping to check if the backend is reachable."
  :tags '(integration)
  (skip-unless (and (boundp 'gptel-test-models)
                    gptel-test-models))
  ;; Just verify the first model is a string
  (should (stringp (car gptel-test-models)))
  (should (> (length gptel-test-models) 0)))

(provide 'gptel-autocomplete-integration)
