EMACS ?= emacs
GPTEL_DIR ?= ~/.emacs.d/elpaca/builds/gptel
BATCHFLAGS = --batch -L . -L tests -L $(GPTEL_DIR)
ERT = -f ert-run-tests-batch-and-exit

.PHONY: test test-integration test-all clean

test:
	$(EMACS) $(BATCHFLAGS) \
	  -l tests/gptel-autocomplete-test.el \
	  $(ERT)

MODELS ?= Qwen2.5-Coder

test-integration:
	$(EMACS) $(BATCHFLAGS) \
	  -l tests/gptel-autocomplete-integration.el \
	  --eval "(setq gptel-test-models (split-string \"$(MODELS)\" \",\" t \"[ \t]+\"))" \
	  $(and $(VERBOSE),--eval "(setq gptel-test-verbose t)") \
	  $(and $(GPTEL_BACKEND),--eval '(setq gptel-test-backend (quote $(GPTEL_BACKEND)))') \
	  --eval "(ert-run-tests-batch-and-exit '(tag integration))"

test-all: test test-integration

clean:
	rm -f *.elc tests/*.elc
