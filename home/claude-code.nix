# Claude Code (Anthropic's CLI) — declaratively managed via home-manager's
# programs.claude-code module. We own the *content* config here (skills today,
# with agents/commands/hooks/mcpServers ready to add), but deliberately leave
# settings.json UNMANAGED.
#
# Why settings.json is left alone: `/model`, `/config`, and the theme toggle
# write to ~/.claude/settings.json at runtime. If home-manager generated it,
# that file would be a read-only store symlink and those interactive changes
# would silently fail. So settings.json stays a normal mutable file (edit it in
# the app), and only the declarative bits below are Nix-owned. Setting the
# `settings` option here would flip that trade-off — don't, unless you want the
# model/theme pinned in Nix.
#
# Skills live as plain SKILL.md folders under ./agent-skills/ and are symlinked
# (recursively, so per-file) into ~/.claude/skills/. That directory is shared
# with Codex (see ./codex.nix) — the SKILL.md format is identical, so a skill
# dropped in as <name>/SKILL.md shows up in both agents with no change here.
#
# The module installs pkgs.claude-code itself (via programs.claude-code.package),
# so it's no longer listed in home.packages.
{ ... }:

{
  programs.claude-code = {
    enable = true;
    skills = ./agent-skills;
  };
}
