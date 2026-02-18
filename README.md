# claude-plan-codex-review

Second-opinion plan review gate for [Claude Code](https://www.anthropic.com/claude-code) using [Codex](https://github.com/openai/codex).

## How it works

A `PreToolUse` hook intercepts `ExitPlanMode` and sends the plan to Codex for an independent review before presenting it to the user.

```
  ExitPlanMode called
         │
         ▼
  Hash plan content
         │
         ▼
  Same hash as last deny? ──yes──> Allow through (escape hatch)
         │
         no
         │
         ▼
  Send to Codex for review
         │
         ├── APPROVE ──> Allow through, pass observations as context
         │
         ├── NEEDS_CHANGES ──> Deny with feedback, store hash
         │
         └── Error / malformed ──> Allow through (fail open)
```

The gate is **fail-open**: if `codex` is not installed, not on `$PATH`, or returns a malformed response, the plan passes through without review. This ensures the plugin never blocks your workflow due to external tool issues.

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) must be installed and on `$PATH`

## Install

```sh
/plugin marketplace add manzaltu/claude-plan-codex-review
/plugin install claude-plan-codex-review@claude-plan-codex-review
```

## Local Development

```sh
claude --plugin-dir ~/projects/claude-plan-codex-review
```

## License

Copyright (c) 2026 Yoav Orot. All rights reserved.

Licensed under the [GNU General Public License v3.0 or later](LICENSE).
