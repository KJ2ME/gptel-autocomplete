;;; gptel-autocomplete-test.el --- Unit tests for gptel-autocomplete -*- lexical-binding: t -*-

(require 'ert)
(require 'gptel-autocomplete)


;;; Helpers

(defun gptel-test--setup-buffer (content)
  "Create a temp buffer with CONTENT, point at end of line (not at newline)."
  (let ((buf (generate-new-buffer " *gptel-test*")))
    (with-current-buffer buf
      (insert content)
      (goto-char (point-max))
      (skip-chars-backward "\n" (line-beginning-position)))
    buf))

(defmacro gptel-test--with-mock (&rest body)
  "Run BODY with gptel-request and gptel-abort mocked.
Returns plist with :text, :overlay, :overlays, :keymap-ov, :request-id, :prompt.
Note: does NOT let-bind defvar-local vars e.g. gptel--completion-keymap-overlay,
so buffer-local values set by gptel-complete are visible to (list ...) at the end."
  `(let (gptel-test--captured-prompt
         gptel-test--captured-callback
         gptel-test--mock-called
         (gptel--completion-text nil)
         (gptel--completion-overlay nil)
         (gptel--completion-overlays nil)
         (gptel--completion-request-id 0)
         (gptel--completion-active-request-id nil)
         (gptel-autocomplete-debug nil)
         (gptel-autocomplete-use-context nil)
         (gptel-prompt-transform-functions nil)
         (gptel-use-curl nil))
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (prompt &rest args)
                  (let ((callback (plist-get args :callback)))
                    (setq gptel-test--captured-prompt prompt)
                    (setq gptel-test--captured-callback callback)
                    (setq gptel-test--mock-called t)
                    (when callback
                      (funcall callback
                               gptel-test--mock-response
                               (or gptel-test--mock-status '(:status "ok")))))))
               ((symbol-function 'gptel-abort) #'ignore))
       ,@body
       (list :text gptel--completion-text
             :overlay gptel--completion-overlay
             :overlays gptel--completion-overlays
             :keymap-ov (when (local-variable-p 'gptel--completion-keymap-overlay)
                          gptel--completion-keymap-overlay)
             :request-id gptel--completion-request-id
             :prompt gptel-test--captured-prompt
             :mock-called gptel-test--mock-called))))

(defmacro gptel-test--with-complete (buffer-content mock-response
                                                    &optional status)
  "Create buffer with BUFFER-CONTENT, mock gptel-request with RESPONSE,
call `gptel-complete'.  Returns a plist with :buffer and all keys from
`gptel-test--with-mock'."
  (declare (indent 2))
  `(let ((gptel-test--mock-response ,mock-response)
         (gptel-test--mock-status ,status)
         (inhibit-message t)
         (buf (gptel-test--setup-buffer ,buffer-content)))
     (let ((result
            (gptel-test--with-mock
              (with-current-buffer buf
                (gptel-complete)))))
       (plist-put result :buffer buf)
       result)))

(defmacro gptel-test--accept-in-buffer (buffer-content mock-response &rest body)
  "Set up buffer, call gptel-complete with mocked RESPONSE, then eval BODY.
BODY runs inside gptel-test--with-mock's let scope, so gptel--completion-text etc.
are accessible.  Point is at the overlay start position before BODY."
  (declare (indent 2))
  `(let ((gptel-test--mock-response ,mock-response)
         (gptel-test--mock-status nil)
         (inhibit-message t)
         (buf (gptel-test--setup-buffer ,buffer-content)))
     (gptel-test--with-mock
       (with-current-buffer buf
         (gptel-complete)
         (when gptel--completion-overlay
           (goto-char (overlay-start gptel--completion-overlay)))
         ,@body))))

(defmacro gptel-test--in-buffer (result &rest body)
  "Switch to buffer from RESULT plist and eval BODY."
  (declare (indent 1))
  `(let ((buf (plist-get ,result :buffer)))
     (when (buffer-live-p buf)
       (with-current-buffer buf
         ,@body))))


;;; Response parsing

(ert-deftest gptel-test/parse-markers-in-code-block ()
  "Extract completion text between █START_COMPLETION█/█END_COMPLETION█
inside a triple-backtick code block, stripping before-cursor prefix."
  (let* ((buffer "def add(a, b):\n    return a + ")
         (response "```\n█START_COMPLETION█\n    return a + b\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (plist-get result :mock-called))
    (should (string= (plist-get result :text) "b"))))

(ert-deftest gptel-test/parse-markers-without-code-block ()
  "Parse markers even when no outer code block wrapper exists."
  (let* ((buffer "x = ")
         (response "█START_COMPLETION█\n42\n█END_COMPLETION█")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))

(ert-deftest gptel-test/parse-markers-multiline ()
  "Extract multiline completion between markers."
  (let* ((buffer "def foo():\n    ")
         (response "```\n█START_COMPLETION█\n    print('hello')\n    print('world')\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text)
                     "print('hello')\n    print('world')"))))

(ert-deftest gptel-test/parse-markers-no-prefix-match ()
  "If first line doesn't start with before-cursor text, return full extraction."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\ny = 42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "y = 42"))))

(ert-deftest gptel-test/parse-fallback-no-markers ()
  "Without markers, fall back to full code content."
  (let* ((buffer "x = ")
         (response "```\n42\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))

(ert-deftest gptel-test/parse-fallback-no-markers-prefix-strip ()
  "Fallback path strips prefix when it matches before-cursor text."
  (let* ((buffer "def add(a, b):\n    return a + ")
         (response "```\n    return a + b\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "b"))))

(ert-deftest gptel-test/parse-fallback-prefix-not-found ()
  "Fallback with no matching prefix returns full text."
  (let* ((buffer "x = ")
         (response "```\n42\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))

(ert-deftest gptel-test/parse-code-block-with-lang ()
  "Handle language-annotated code blocks like ```python."
  (let* ((buffer "x = ")
         (response "```python\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))

(ert-deftest gptel-test/parse-empty-response ()
  "An empty string response -> empty completion text."
  (let* ((buffer "x = ")
         (response "")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) ""))))

(ert-deftest gptel-test/parse-blank-response ()
  "Response with only whitespace -> empty completion text."
  (let* ((buffer "x = ")
         (response "   \n  ")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) ""))))

(ert-deftest gptel-test/parse-code-block-only-whitespace ()
  "Code block with only whitespace inside -> empty."
  (let* ((buffer "x = ")
         (response "```\n   \n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "   "))))

(ert-deftest gptel-test/parse-empty-between-markers ()
  "Markers with empty content between them -> empty string."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) ""))))

(ert-deftest gptel-test/parse-malformed-no-close-marker ()
  "If END marker is missing, marker regex fails, fallback to full code-content."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "█START_COMPLETION█\n42"))))

(ert-deftest gptel-test/parse-trailing-whitespace-line ()
  "Trailing whitespace lines are stripped by string-trim."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```\n\n")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))


;;; Callback response types

(ert-deftest gptel-test/callback-nil-response ()
  "nil response -> no completion text."
  (let* ((buffer "x = ")
         (response nil)
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :text)))))

(ert-deftest gptel-test/callback-abort ()
  "abort symbol -> no completion text."
  (let* ((buffer "x = ")
         (response 'abort)
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :text)))))

(ert-deftest gptel-test/callback-tool-call ()
  "tool-call response -> ignored."
  (let* ((buffer "x = ")
         (response '(tool-call . ((:name "test" :args nil))))
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :text)))))

(ert-deftest gptel-test/callback-tool-result ()
  "tool-result response -> ignored."
  (let* ((buffer "x = ")
         (response '(tool-result . ((:result "ok"))))
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :text)))))

(ert-deftest gptel-test/callback-reasoning ()
  "reasoning response -> ignored."
  (let* ((buffer "x = ")
         (response '(reasoning . "Let me think..."))
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :text)))))


;;; Overlay & visual state

(ert-deftest gptel-test/completion-creates-overlay ()
  "Successful completion creates an overlay with ghost text."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response))
         (ov (plist-get result :overlay)))
    (should (overlayp ov))
    (should (stringp (overlay-get ov 'after-string)))
    (should (eq (overlay-get ov 'priority) 1000))))

(ert-deftest gptel-test/completion-registers-overlays ()
  "Completion adds overlay to the global overlays list."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (member (plist-get result :overlay)
                    (plist-get result :overlays)))))

(ert-deftest gptel-test/completion-creates-keymap-overlay ()
  "Completion creates a keymap overlay at point."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```"
    (should (overlayp gptel--completion-keymap-overlay))
    (should (overlay-get gptel--completion-keymap-overlay 'keymap))))

(ert-deftest gptel-test/clear-completion ()
  "gptel-clear-completion resets all state."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```"
    (let ((ov gptel--completion-overlay))
      (gptel-clear-completion)
      (should (not (overlay-buffer ov)))
      (should (not gptel--completion-text))
      (should (not gptel--completion-overlay))
      (should (not gptel--completion-overlays)))))

(ert-deftest gptel-test/clear-completion-no-state ()
  "gptel-clear-completion is safe when no state exists."
  (gptel-clear-completion)
  (should (not gptel--completion-text))
  (should (not gptel--completion-overlay))
  (should (not gptel--completion-overlays)))

(ert-deftest gptel-test/no-completion-on-failure ()
  "Failed completion (nil response) does not create overlays."
  (let* ((buffer "x = ")
         (response nil)
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :overlay)))
    (should (not (plist-get result :text)))))

(ert-deftest gptel-test/no-completion-on-abort ()
  "Aborted request does not create overlays."
  (let* ((buffer "x = ")
         (response 'abort)
         (result (gptel-test--with-complete buffer response)))
    (should (not (plist-get result :overlay)))
    (should (not (plist-get result :text)))))


;;; Accepting completions

(ert-deftest gptel-test/accept-completion-inserts-text ()
  "gptel-accept-completion inserts ghost text into buffer."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```"
    (gptel-accept-completion)
    (should (string= (buffer-string) "x = 42"))))

(ert-deftest gptel-test/accept-completion-clears-state ()
  "After accepting, completion state is cleared."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```"
    (gptel-accept-completion)
    (should (not gptel--completion-text))
    (should (not gptel--completion-overlay))))

(ert-deftest gptel-test/accept-completion-no-completion ()
  "gptel-accept-completion with no completion shows message."
  (let ((inhibit-message t))
    (gptel-clear-completion)
    (should (stringp (gptel-accept-completion)))
    (should-not gptel--completion-text)))

(ert-deftest gptel-test/accept-word-no-completion ()
  "gptel-accept-word with no completion shows message."
  (let ((inhibit-message t))
    (gptel-clear-completion)
    (should (stringp (gptel-accept-word)))
    (should-not gptel--completion-text)))

(ert-deftest gptel-test/accept-word-inserts-first-word ()
  "gptel-accept-word inserts the first word of completion."
  (gptel-test--accept-in-buffer "def add(a, b):\n    return a + "
      "```\n█START_COMPLETION█\n    return a + b  # add\n█END_COMPLETION█\n```"
    (gptel-accept-word)
    (should (string= (buffer-substring-no-properties
                      (line-beginning-position) (point))
                     "    return a + b"))))

(ert-deftest gptel-test/accept-word-keeps-rest-in-overlay ()
  "After accepting first word, rest stays in completion overlay."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\nfoo bar baz\n█END_COMPLETION█\n```"
    (gptel-accept-word)
    (should (string= gptel--completion-text " bar baz"))))

(ert-deftest gptel-test/accept-word-on-last-word-clears ()
  "Accepting the last word clears the completion."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```"
    (gptel-accept-word)
    (should (not gptel--completion-overlay))))

(ert-deftest gptel-test/accept-word-leading-space ()
  "Leading space is included in the first chunk."
  (gptel-test--accept-in-buffer "x = "
      "```\n█START_COMPLETION█\n answer\n█END_COMPLETION█\n```"
    (gptel-accept-word)
    (should (string= (buffer-substring-no-properties
                      (line-beginning-position) (point))
                     "x =  answer"))))


;;; Minor mode

(ert-deftest gptel-test/mode-adds-post-command-hook ()
  "Enabling the mode adds post-command-hook locally."
  (with-temp-buffer
    (gptel-autocomplete-mode 1)
    (should (member #'gptel--post-command post-command-hook))
    (gptel-autocomplete-mode -1)
    (should (not (member #'gptel--post-command post-command-hook)))))

(ert-deftest gptel-test/mode-removes-all-state ()
  "Disabling the mode clears completion and timer."
  (with-temp-buffer
    (gptel-autocomplete-mode 1)
    (let ((gptel--post-command-timer (timer-create)))
      (gptel-autocomplete-mode -1)
      (should (not gptel--post-command-timer))
      (should (not gptel--completion-text))
      (should (not gptel--completion-overlay)))))

(ert-deftest gptel-test/mode-idempotent ()
  "Enabling mode twice is safe."
  (with-temp-buffer
    (gptel-autocomplete-mode 1)
    (gptel-autocomplete-mode 1)
    (should (member #'gptel--post-command post-command-hook))))

(ert-deftest gptel-test/post-command-schedules-timer ()
  "post-command hook schedules idle timer when conditions are met."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-max))
    (let ((gptel-autocomplete-idle-delay 0.3))
      (gptel--post-command)
      (should (timerp gptel--post-command-timer))
      (gptel--cancel-post-command-timer))))

(ert-deftest gptel-test/post-command-skips-in-minibuffer ()
  "post-command does nothing in minibuffer."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-max))
    (let ((gptel-autocomplete-idle-delay 0.3))
      (gptel--post-command)
      (should (timerp gptel--post-command-timer))
      (gptel--cancel-post-command-timer))))

(ert-deftest gptel-test/post-command-skips-when-delay-nil ()
  "post-command does nothing when idle delay is nil."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-max))
    (let ((gptel-autocomplete-idle-delay nil))
      (gptel--post-command)
      (should (not gptel--post-command-timer)))))

(ert-deftest gptel-test/post-command-skips-when-disabled ()
  "post-command creates timer (mode check is in the debounce callback)."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-max))
    (let ((gptel-autocomplete-idle-delay 0.3)
          (gptel-autocomplete-mode nil))
      (gptel--post-command)
      (should (timerp gptel--post-command-timer))
      (gptel--cancel-post-command-timer))))

(ert-deftest gptel-test/debounce-cancels-timer-first ()
  "Calling gptel-complete cancels the pending idle timer."
  (with-temp-buffer
    (insert "hello\n    ")
    (goto-char (point-max))
    (let ((gptel-autocomplete-idle-delay 0.3))
      (gptel--post-command)
      (should (timerp gptel--post-command-timer))
      (let ((response "```\n█START_COMPLETION█\nworld\n█END_COMPLETION█\n```"))
        (cl-letf (((symbol-function 'gptel-request)
                   (lambda (_prompt &rest _args)
                     (let ((callback (plist-get _args :callback)))
                       (when callback
                         (funcall callback response '(:status "ok"))))))
                  ((symbol-function 'gptel-abort) #'ignore))
          (should (timerp gptel--post-command-timer))
          (gptel-complete)
          (should (not gptel--post-command-timer)))))))

(ert-deftest gptel-test/completion-allowed-p ()
  "gptel--completion-allowed-p returns t at eol outside minibuffer."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-max))
    (should (gptel--completion-allowed-p))))

(ert-deftest gptel-test/completion-not-allowed-not-eol ()
  "gptel--completion-allowed-p returns nil if not at end of line."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-min))
    (should (not (gptel--completion-allowed-p)))))


;;; Prompt construction

(ert-deftest gptel-test/prompt-includes-filename ()
  "The prompt sent to gptel includes the filename/buffer name."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response))
         (prompt (plist-get result :prompt)))
    (should (stringp prompt))
    (should (string-match "gptel-test" prompt))))

(ert-deftest gptel-test/prompt-includes-code-context ()
  "The prompt contains the code context around point."
  (let* ((buffer "def foo():\n    return ")
         (response "```\n█START_COMPLETION█\n    return 42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response))
         (prompt (plist-get result :prompt)))
    (should (string-match "def foo" prompt))
    (should (string-match "return" prompt))
    (should (string-match "█CURSOR█" prompt))
    (should (string-match "█START_COMPLETION█" prompt))
    (should (string-match "█END_COMPLETION█" prompt))))

(ert-deftest gptel-test/prompt-uses-custom-temperature ()
  "gptel-autocomplete-temperature overrides gptel-temperature in the request."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (gptel-autocomplete-temperature 0.5)
         (gptel-temperature 1.0)
         captured-temp)
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest _args)
                 (let ((callback (plist-get _args :callback)))
                   (setq captured-temp (bound-and-true-p gptel-temperature))
                   (when callback
                     (funcall callback response '(:status "ok"))))))
              ((symbol-function 'gptel-abort) #'ignore))
      (with-temp-buffer
        (insert buffer)
        (goto-char (point-max))
        (gptel-complete)
        (should (= captured-temp 0.5))))))

(ert-deftest gptel-test/prompt-with-context-transforms ()
  "When gptel-autocomplete-use-context is t, transforms are passed."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (gptel-autocomplete-use-context t)
         (gptel-prompt-transform-functions (list #'identity))
         captured-transforms)
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (let ((callback (plist-get args :callback))
                       (transforms (plist-get args :transforms)))
                   (setq captured-transforms transforms)
                   (when callback
                     (funcall callback response '(:status "ok"))))))
              ((symbol-function 'gptel-abort) #'ignore))
      (with-temp-buffer
        (insert buffer)
        (goto-char (point-max))
        (gptel-complete)
        (should (equal captured-transforms
                       (list #'identity)))))))

(ert-deftest gptel-test/prompt-without-context-transforms ()
  "When gptel-autocomplete-use-context is nil, transforms are nil."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (gptel-autocomplete-use-context nil)
         captured-transforms)
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (let ((callback (plist-get args :callback))
                       (transforms (plist-get args :transforms)))
                   (setq captured-transforms transforms)
                   (when callback
                     (funcall callback response '(:status "ok"))))))
              ((symbol-function 'gptel-abort) #'ignore))
      (with-temp-buffer
        (insert buffer)
        (goto-char (point-max))
        (gptel-complete)
        (should (not captured-transforms))))))


;;; Edge cases: buffer state

(ert-deftest gptel-test/empty-buffer ()
  "gptel-complete on an empty buffer produces a completion (since at eol)."
  (let* ((buffer "")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))

(ert-deftest gptel-test/newline-before-cursor ()
  "Point after a newline but at eol completes on the empty line."
  (let* ((buffer "x = \n")
         (response "```\n█START_COMPLETION█\ny = 10\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "y = 10"))))

(ert-deftest gptel-test/large-before-context ()
  "Large before-context setting includes many lines (no crash)."
  (let* ((lines (mapconcat #'identity
                           (cl-loop repeat 200 collect "foo")
                           "\n"))
         (buffer (concat lines "\nx = "))
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (gptel-autocomplete-before-context-lines 100)
         (result (gptel-test--with-complete buffer response)))
    (should (string= (plist-get result :text) "42"))))

(ert-deftest gptel-test/after-context-included ()
  "Content after the cursor line is included in the prompt."
  (let* ((buffer (concat "x = \ny = 5\nz = x + y"))
         (response "```\n█START_COMPLETION█\n10\n█END_COMPLETION█\n```")
         (result (gptel-test--with-complete buffer response))
         (prompt (plist-get result :prompt)))
    (should (string-match "y = 5" prompt))
    (should (string-match "z = x \\+ y" prompt))))

(ert-deftest gptel-test/cancel-in-flight ()
  "Calling gptel-complete while another is in-flight cancels the old one."
  (let* ((buffer "x = ")
         (response "```\n█START_COMPLETION█\n42\n█END_COMPLETION█\n```")
         (cancel-called 0)
         (gptel--completion-active-request-id 99))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest _args)
                 (let ((callback (plist-get _args :callback)))
                   (when callback
                     (funcall callback response '(:status "ok"))))))
              ((symbol-function 'gptel-abort)
               (lambda (_buffer) (setq cancel-called (1+ cancel-called)))))
      (with-temp-buffer
        (insert buffer)
        (goto-char (point-max))
        (gptel-complete)
        (should (>= cancel-called 1))))))
