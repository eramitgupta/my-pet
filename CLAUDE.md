# CLAUDE.md

Shared project instructions for every agent live in AGENTS.md:

@AGENTS.md

## Claude Code specifics

- Rules in `.claude/rules/` load automatically when you touch files matching their `paths:`
  frontmatter, so you don't need to open them by hand as other agents do.
- Skills in `.claude/skills/` (also exposed as `.agents/skills/` for other tools) are listed in
  AGENTS.md → "Available skills". Invoke them with the Skill tool.
- Keep shared guidance in `AGENTS.md`. Put only Claude-specific notes here, so the tools never
  drift apart.
