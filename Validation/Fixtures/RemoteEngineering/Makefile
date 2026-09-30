# Selects an explicitly overridable Python 3 interpreter without downloading dependencies.
PYTHON ?= python3

# Declares the user-visible deterministic verification target as non-file output.
.PHONY: test

# Runs only the fixture's local standard-library test process.
test:
	@$(PYTHON) test_shipping.py
