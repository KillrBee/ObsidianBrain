SHELL := /bin/bash
VENV := .venv
PY := $(VENV)/bin/python

.PHONY: install-dev lint test test-bats test-pytest fixtures clean

install-dev:
	uv venv --quiet $(VENV) || python3 -m venv $(VENV)
	uv pip install --quiet --python $(PY) \
		pyyaml jsonschema "mcp>=1.2" pytest \
		"markitdown[pdf,docx,pptx,xlsx]" python-docx python-pptx openpyxl

lint:
	shellcheck install.sh uninstall.sh lib/*.sh \
		payload/scripts/lib/*.sh \
		payload/scripts/convert/*.sh \
		payload/scripts/index/*.sh \
		payload/scripts/search/*.sh \
		payload/scripts/context/*.sh \
		payload/scripts/memory/*.sh \
		payload/scripts/mcp/second-brain-mcp \
		tests/run_tests.sh

test:
	tests/run_tests.sh

test-bats:
	tests/run_tests.sh --bats-only

test-pytest:
	tests/run_tests.sh --pytest-only

fixtures:
	$(PY) tests/fixtures/generate_fixtures.py

clean:
	rm -rf $(VENV) .pytest_cache tests/pytest/__pycache__
