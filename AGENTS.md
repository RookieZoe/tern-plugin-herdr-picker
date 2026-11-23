# Herdr Picker

A Tern plugin (Luau, window half only) that lists herdr-core panes in Tern's picker and opens the chosen one in a split, and starts new herdr spaces. The package Tern installs is `plugin/` (`plugin.toml`, `window.luau`, its README and LICENSE); keep everything else outside it. `tern plugin types plugin` writes the API types. Tern plugin API findings and gotchas: `docs/tern-plugin-findings.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues of RookieZoe/tern-plugin-herdr-picker, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root, created when needed. See `docs/agents/domain.md`.
