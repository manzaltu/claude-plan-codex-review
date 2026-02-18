#!/bin/bash
# PreToolUse hook for ExitPlanMode — sends plan to Codex for a second opinion.
#
# Extracts plan from tool_input.plan, hashes it, and compares to last review.
# If plan changed (or first review): sends to codex for verdict.
# Codex returns APPROVE or NEEDS_CHANGES.
# If approved: allows ExitPlanMode through, passes observations as context.
# If needs changes: denies with feedback. Re-reviewed if plan is edited.
# If plan unchanged since last deny: allows through (escape hatch).
#
# Fail-open: if codex is unavailable or returns a malformed response,
# the plan is allowed through without review.

# Fail open if codex is not installed
if ! command -v codex &>/dev/null; then
  exit 0
fi

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="pid-$$-$(date +%s)"
fi

FLAG_DIR="$HOME/.cache/claude-plan-codex-review"
HASH_FILE="$FLAG_DIR/plan-hash-$SESSION_ID"
LOCK_FILE="$FLAG_DIR/plan-lock-$SESSION_ID"
mkdir -p "$FLAG_DIR"

PLAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.plan // empty')
if [ -z "$PLAN_CONTENT" ]; then
  exit 0
fi

PLAN_HASH=$(printf '%s' "$PLAN_CONTENT" | sha256sum | cut -d' ' -f1)

# Lock to prevent race conditions on concurrent ExitPlanMode calls
exec 9>"$LOCK_FILE"
flock 9

# Plan unchanged since last deny — allow through (escape hatch)
if [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" = "$PLAN_HASH" ]; then
  rm -f "$HASH_FILE"
  exec 9>&-
  exit 0
fi

REVIEW=$(codex exec \
  "You are reviewing a Claude Code implementation plan. Claude Code built this plan and is about to present it to the user. Your review will be sent directly back to Claude Code — if you approve, the plan goes through; if you request changes, Claude will see your feedback and revise.

This is a high-level plan, not a detailed spec. Implementation details and edge cases will be resolved during coding. Accept reasonable assumptions. Do not nitpick the verification section.

APPROVE the plan if the overall approach is sound, even if details can be improved during implementation.

Only say NEEDS_CHANGES if the plan has a fundamentally wrong approach, a security issue, risks data loss, would break existing functionality, has auth/security regressions, or is missing something that would lead the implementation in the wrong direction. Use your judgement on whether edge cases are significant enough to block approval or should be mentioned as observations.

If uncertain and risks are low choose APPROVE with observations.

You must start your response with APPROVE or NEEDS_CHANGES on the first line, exactly. No preamble.

Format:
Line 1: APPROVE or NEEDS_CHANGES
Line 2: One-sentence rationale
Then if needed:
Blocking issues: (only for NEEDS_CHANGES)
- issue
Observations: (non-blocking notes for either verdict)
- observation

---

$PLAN_CONTENT" \
  --sandbox read-only \
  --model gpt-5.3-codex \
  2>/dev/null) || {
  exec 9>&-
  exit 0
}

# Parse verdict — strict first line only
VERDICT=$(printf '%s' "$REVIEW" | head -n1 | tr -d '[:space:]')

if [ "$VERDICT" = "APPROVE" ]; then
  rm -f "$HASH_FILE"
  exec 9>&-
  jq -n --arg review "$REVIEW" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: ("Codex approved the plan:\n\n" + $review),
      additionalContext: ("Codex approved the plan:\n\n" + $review)
    }
  }'
elif [ "$VERDICT" = "NEEDS_CHANGES" ]; then
  printf '%s' "$PLAN_HASH" > "$HASH_FILE"
  exec 9>&-
  jq -n --arg review "$REVIEW" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Codex second opinion:\n\n" + $review + "\n\nPlease address the issues above, update your plan, and call ExitPlanMode again.")
    }
  }'
else
  # Malformed response — fail open
  exec 9>&-
  exit 0
fi
