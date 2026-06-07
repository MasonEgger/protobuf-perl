# Session — Track project CLAUDE.md

- **Branch**: patch.
- **Model**: claude-opus-4-8.

## Change
- Committed the agent-authored `CLAUDE.md` (project guidance for Claude Code). Verified its
  claims hold on this branch after the docs cherry-pick: `Protobuf::Manual` now exists, the
  `bin/` scripts and `just` commands match, and the architecture/conventions notes are
  accurate.

## Context
- Final step before pushing `patch` and opening a PR into `main`. The branch carries the enum
  native-parser fix, the examples namespace fix, the cherry-picked docs (cpan.md, Manual.pod,
  SYNOPSIS ×10), and the style-audit lint cleanup.
