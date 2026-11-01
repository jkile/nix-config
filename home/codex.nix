# Codex (OpenAI's CLI) — declaratively managed via home-manager's programs.codex
# module. Same split as ./claude-code.nix: Nix owns durable content like skills
# and rules, but config.toml is deliberately left UNMANAGED.
#
# Why config.toml is left alone: Codex's TUI persists interactive choices there —
# `/model` and `/approvals` rewrite the file in place. If home-manager generated
# it, it'd be a read-only store symlink and those writes would fail. Leaving
# `settings` at its default `{ }` makes the module skip the file entirely, so it
# stays a normal mutable file. Setting `settings` here would flip that trade-off —
# don't, unless you want the model/approval policy pinned in Nix.
#
# Auth (~/.codex/auth.json) is written by `codex login` and is likewise mutable.
#
# Rules can be managed here now: Home Manager writes them under
# ~/.codex/rules/*.rules, while Codex may still maintain its own default.rules
# if you accept persistent approvals interactively.
#
# Skills are the same ./agent-skills/ tree Claude Code reads; both agents use the
# SKILL.md format, so one folder serves both. Note the module symlinks each skill
# *directory* (not per-file, as claude-code does) because Codex doesn't follow a
# symlinked SKILL.md yet — openai/codex#10470.
#
# The 26.05 stable branch can lag Codex releases by weeks, so use unstable for
# this one fast-moving CLI while keeping the rest of the system on stable.
{ pkgsUnstable, ... }:

{
  programs.codex = {
    enable = true;
    package = pkgsUnstable.codex;
    skills = ./agent-skills;
  };
}
