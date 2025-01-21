.PHONY: all test test-fast test-invariants sim lint clean compile

PYTHON ?= uv run python3
PYTEST ?= uv run pytest

all: compile test

compile:
	@echo "Compiling Vyper contracts..."
	@$(PYTHON) -c "import boa, glob; [boa.load_partial(f) for f in glob.glob('contracts/**/*.vy', recursive=True)]"
	@echo "All Vyper contracts compiled successfully."

test:
	$(PYTEST) tests/

test-fast:
	$(PYTEST) tests/ -k "not property and not stress"

test-invariants:
	$(PYTEST) tests/test_property_invariants.py

sim:
	$(PYTHON) -m simulator.risk_sim
	$(PYTHON) -m simulator.waterfall_sim

benchmark:
	$(PYTHON) -m simulator.benchmark

lint:
	$(PYTHON) -m ruff check .

clean:
	rm -rf .pytest_cache __pycache__ */__pycache__ */*/__pycache__
