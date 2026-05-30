# ABOUTME: Task runner recipes for the Proto3 distribution.
# `check` is the gate every TDD step ends on: lint + test (+ dzil when present).

# Default recipe: show available recipes.
default:
    @just --list

# Full gate: lint then test. Used to close out every plan step.
check: lint test
    @if command -v dzil >/dev/null 2>&1; then \
        echo "==> dzil test"; dzil test; \
    else \
        echo "==> dzil not installed; skipping dzil test"; \
    fi

# Run the test suite against lib/.
test:
    prove -lr t

# Static analysis with Perl::Critic (gentle policy).
lint:
    @if command -v perlcritic >/dev/null 2>&1; then \
        echo "==> perlcritic --gentle lib t"; perlcritic --gentle lib t; \
    else \
        echo "==> perlcritic not installed; skipping lint"; \
    fi
