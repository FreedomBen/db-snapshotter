.PHONY: help test test-unit lint shellcheck clean

SCRIPT := db-snapshot.sh
TESTS_DIR := tests

# Use the system bats if present.  If not, point at a vendored copy under
# tests/lib/bats-core/bin/bats (run `make bats-install` to populate it).
SYSTEM_BATS := $(shell command -v bats 2>/dev/null)
BATS_LIB := $(TESTS_DIR)/lib
BATS_CORE := $(BATS_LIB)/bats-core
ifeq ($(SYSTEM_BATS),)
  BATS := $(BATS_CORE)/bin/bats
  BATS_DEPS := bats-install
else
  BATS := $(SYSTEM_BATS)
  BATS_DEPS :=
endif

help:
	@echo "Available targets:"
	@echo "  make test           Run the bats test suite ($(BATS))"
	@echo "  make test-unit      Alias for 'make test'"
	@echo "  make lint           Run shellcheck on $(SCRIPT)"
	@echo "  make shellcheck     Alias for 'make lint'"
	@echo "  make bats-install   Vendor bats-core under $(BATS_LIB) (only needed if 'bats' is not on PATH)"
	@echo "  make clean          Remove the vendored bats install"

test: $(BATS_DEPS)
	@$(BATS) --recursive $(TESTS_DIR)

test-unit: test

lint: shellcheck

shellcheck:
	@shellcheck $(SCRIPT)

bats-install: $(BATS)

$(BATS):
	@mkdir -p $(BATS_LIB)
	@if [ ! -d $(BATS_CORE) ]; then \
	  echo "Cloning bats-core into $(BATS_CORE)..."; \
	  git clone --depth 1 https://github.com/bats-core/bats-core.git $(BATS_CORE); \
	fi

clean:
	@rm -rf $(BATS_LIB)
