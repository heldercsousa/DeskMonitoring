Commit staged or modified files in C:\Sync with minimal token usage.

Steps (execute exactly in order, no extra commentary):

1. Run `git status --short` to see changed files.
2. Run `git diff --stat HEAD` to confirm what changed.
3. Stage ONLY the relevant modified tracked files by name — never use `git add -A` or `git add .`.
4. Write a commit message: single line, ≤72 chars, imperative mood, no fluff.
5. Commit:
```
git commit -m "$(cat <<'EOF'
<message>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
6. Report the commit hash and message. Stop. Do not push unless explicitly asked.

Constraints:
- Never commit: Logs/, Mirror/, Config/rclone.conf, Config/credentials.enc, Config/realtime.ffs_real
- Never use --no-verify, --amend (unless user asks), or force flags
- If nothing changed, say so and stop
