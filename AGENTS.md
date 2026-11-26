# Herdr Picker

A Tern plugin (Luau) that opens a Herdr block in a split: there the user picks a herdr-core pane, starts a new herdr space, or adds a tab to one, and the chosen pane, running `hc attach`, takes the block's place. `host.luau` draws the block in the session daemon; `window.luau` holds the commands and keys and a link-route fallback. The package Tern installs is `plugin/` (`plugin.toml`, `window.luau`, `host.luau`, its README in English and Chinese (`README.md`, `README.zh-CN.md`) and LICENSE); keep everything else outside it. A change to `README.md` (root or `plugin/`) goes into its `README.zh-CN.md` too. `tern plugin types plugin` writes the API types. Tern plugin API findings and gotchas: `docs/tern-plugin-findings.md`; the research notes behind them, one file per question, live in `docs/research/` on `main`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues of RookieZoe/tern-plugin-herdr-picker, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root, created when needed. See `docs/agents/domain.md`.
