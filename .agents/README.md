# .agents

This is the cross-tool home for agent instructions, following the
[AGENTS.md](https://agents.md) and [Agent Skills](https://agentskills.io) conventions.

| Path | What it is |
|---|---|
| `skills/` → `../.claude/skills` | Workflows, each with a `SKILL.md` (name + description frontmatter). Codex discovers `.agents/skills`; Claude Code discovers `.claude/skills`. |
| `rules/` → `../.claude/rules` | Area rules. Claude Code auto-loads them by their `paths:` frontmatter; other agents read them as directed by the root `AGENTS.md`. |

Both are symlinks, so every tool reads the same files. Edit them in `.claude/`, or through
the symlink; either works. Shared top-level instructions live in the root `AGENTS.md`, which
`CLAUDE.md` and `GEMINI.md` import.
