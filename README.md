# Guix skills for LLM agents

Agent skills that cover practical work with GNU Guix: packaging, building and debugging, dev shells, channels, system and home configuration, services, foreign binaries, and desktop troubleshooting on Guix System. They're general and not tied to any particular channel or machine.

Each skill is a folder with a `SKILL.md`: YAML front matter (`name`, `description`) and then the instructions. Some skills also have `references/` or `scripts/`, which the skill points to. This is the Agent Skills layout used by Claude Code and other agents.

## Skills

| Skill | Use it when… |
|---|---|
| [guix-host-environment](guix-host-environment/SKILL.md) | You're working on a Guix machine at all: tools that aren't installed, sudo, the non-FHS layout, logs, guardrails. **Start here.** |
| [guix-packaging](guix-packaging/SKILL.md) | Writing, updating or fixing a package, or judging whether software can be packaged. |
| [guix-build-debugging](guix-build-debugging/SKILL.md) | A build, pull or reconfigure fails, or a package needs verifying or smoke-testing. |
| [guix-local-development](guix-local-development/SKILL.md) | A repo's own `guix.scm`, `guix shell -D -f`, missing `make`/`cc`/`gdb`, installing from a file. |
| [guix-channels](guix-channels/SKILL.md) | Channel layout, `channels.scm`, authentication, substitutes, "object not found" after branch deletion. |
| [guix-system-configuration](guix-system-configuration/SKILL.md) | `operating-system` configs, reconfigure and roll-back, images and VMs. |
| [guix-services](guix-services/SKILL.md) | Writing new system or home service types with Shepherd. |
| [guix-home](guix-home/SKILL.md) | Guix Home: dotfiles, user packages, user services. |
| [guix-foreign-binaries](guix-foreign-binaries/SKILL.md) | Prebuilt, proprietary or FHS-dependent software (patchelf, `-CF` containers, bubblewrap), and Wine. |
| [guix-desktop-troubleshooting](guix-desktop-troubleshooting/SKILL.md) | Icons, video decoding, gamepads, flicker, NetworkManager sharing, missing admin tools. |

## Installing

**Claude Code**, for all projects:
```sh
mkdir -p ~/.claude/skills
for d in /path/to/guix-skills/*/; do ln -sfn "$d" ~/.claude/skills/"$(basename "$d")"; done
```
For one project only, link them into `<project>/.claude/skills/` instead. Claude loads a skill when its `description` matches the task. You can also ask for one by name.

**Other agents:** any agent that understands `SKILL.md` folders can use this directory as is. Otherwise, point the agent at this README and tell it to read the matching `SKILL.md` before starting Guix work.

## Conventions

- Placeholders: `my-channel` is a channel's top-level module name, `<pkg>` a package, `<dir>`/`<channel-dir>` the directory passed to `-L`.
- The facts were checked against a Guix checkout from November 2026. Guix changes quickly (renamed variables and services, new build-system keywords). When a name doesn't resolve, check `guix show`, `guix system search`, or the Guix source.
- Each skill says when to ask the user before acting. As a rule, `guix shell`, `guix build` and `guix system build` are safe, while anything that changes profiles or the running system needs confirmation.

## Maintaining

Keep each `SKILL.md` short and directive, and move long material into `references/`. When you learn a new lesson, add it to the skill whose `description` would trigger in that situation. Update the description too if it adds a new trigger.

## License

[WTFPL, Version 2](LICENSE).
