# ABOUTME: Task runner recipes for the Proto3 distribution.
# `check` is the everyday gate (lint + test); `check-dist` adds the dzil build.

# Default recipe: show available recipes.
default:
    @just --list

# Everyday gate: lint then test. Used to close out every plan step and as the
# blocking CI gate (alongside the dedicated conformance job). Fast and depends
# only on perlcritic + prove.
check: lint test

# Release-oriented gate: everything in `check` plus the full Dist::Zilla build
# (`dzil test`), which validates the distribution assembles and installs. Kept
# separate from `check` because it needs the dzil toolchain + author plugins.
check-dist: check
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
