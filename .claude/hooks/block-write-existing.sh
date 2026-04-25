#!/usr/bin/env bash
# PreToolUse guard: deny Write to existing files inside golf-sync-swing/golf-sync-swing/.
# Reason: Xcode's PBXFileSystemSynchronizedRootGroup may revert Write changes — use Edit instead.
set -euo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
[[ "$tool" != "Write" ]] && exit 0

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
[[ -z "$path" ]] && exit 0

case "$path" in
  */golf-sync-swing/golf-sync-swing/*) ;;
  *) exit 0 ;;
esac

if [[ -e "$path" ]]; then
  jq -n --arg p "$path" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Use Edit, not Write, on existing file " + $p + ". Xcode auto-sync (PBXFileSystemSynchronizedRootGroup) can revert Write changes — see CLAUDE.md.")
    }
  }'
fi
exit 0
