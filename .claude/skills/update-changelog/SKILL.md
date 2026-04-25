---
name: update-changelog
description: Update docs/changelog.md and docs/project_status.md after a milestone or major change. Reads recent git commits, groups them into Added/Changed/Fixed sections, and appends a dated entry.
---

# update-changelog

Update the project changelog and status docs after a meaningful milestone. CLAUDE.md mandates: "Update files in the docs folder after major milestones and major additions to the project."

## Inputs

The user may pass a free-text description of the milestone (e.g. "Smart camera M3 — auto-replay"). If absent, infer one from the dominant theme of the commit range.

## Workflow

1. **Find the cutoff commit.** Run `git log --oneline --decorate -1 docs/changelog.md` to find when the changelog was last touched. Use that commit's hash as the lower bound.

2. **Read the recent history** between that commit and HEAD:
   ```
   git log <cutoff>..HEAD --pretty=format:'%h%x09%s'
   ```

3. **Read the existing changelog** at `docs/changelog.md` to match its format (heading style, version scheme, date format). Do not invent a new format — extend the existing one.

4. **Group commits** by Conventional Commits prefix:
   - `feat:` / `add:` → **Added**
   - `fix:` → **Fixed**
   - `refactor:` / `chore:` / `perf:` → **Changed**
   - `docs:` / `test:` → skip unless they describe a user-visible change.

5. **Write the entry.** Lead each line with the *user-visible* effect, not the commit subject. Squash duplicate fixes. If a commit has both a fix and a feature, list it under the feature.

6. **Update `docs/project_status.md`** in the same edit pass — bump the "Current state" / "Last milestone" line if such fields exist; do not invent fields that aren't already there.

7. **Do not commit.** Show the diff to the user and let them commit it themselves (or follow up with "now commit this").

## Output

After editing, summarize in 1-2 sentences: which entry was added, how many commits were folded in, anything ambiguous you skipped. Don't list every commit — the changelog itself is the artifact.

## Guardrails

- Never overwrite the changelog — only append (or insert at the top under the latest heading).
- Use today's date from the environment (`Today's date is YYYY-MM-DD` in CLAUDE context).
- If `docs/changelog.md` doesn't exist, ask the user for the format they want before creating it.
