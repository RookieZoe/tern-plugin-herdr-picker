# Herdr Picker

A Tern plugin that lists the panes running in
[herdr-core](https://herdr.dev) (`hc`) and opens the one you pick in a Tern split.

Run **Herdr: pick a pane** from the command palette. Tern's own picker opens with every live
herdr-core pane, split into two groups:

- **Agent CLIs**: panes running an agent such as `claude-code` or `codex`, with its status
  (working, needs input, done, idle) and directory.
- **Terminals**: plain shells (`zsh`, `bash`, `pwsh`, `cmd`…), with the shell and directory.

Type to filter, ↑/↓ to move, ↵ to attach. The chosen pane opens to the right of the focused one,
running `hc attach <address>` in the pane's directory. A pane already open in this window shows a
check, and picking it again focuses that split instead of opening another.

```
Find a herdr-core pane…

Agent CLIs
  ✦  my-app / 2      claude-code  ·  done  ·  ~/Codes/my-app
  ✦  api / 1         codex  ·  working  ·  ~/Codes/api
Terminals
  >_ my-app / 1      terminal · zsh  ·  ~/Codes/my-app
```

## Requirements

- Tern with plugin support
- herdr-core's `hc` CLI, version with `hc ls --json` and `hc attach`

Works on macOS, Linux and Windows.

## Install

```sh
tern plugin install github.com/RookieZoe/tern-plugin-herdr-picker
```

Or from a local clone, using it in place while you edit it:

```sh
git clone https://github.com/RookieZoe/tern-plugin-herdr-picker
tern plugin link ./tern-plugin-herdr-picker
tern plugin reload herdr-picker
```

You can bind the command to a key; its action name is `plugin.herdr-picker.pick`.

## Finding `hc`

The plugin looks for `hc` in this order:

1. The `HC_BIN` environment variable
2. `~/.local/bin/hc`
3. `%LOCALAPPDATA%\Programs\herdr-core\hc.exe` or `%LOCALAPPDATA%\Programs\herdr-app\hc.exe` (Windows)
4. `/opt/homebrew/bin/hc`, `/usr/local/bin/hc`
5. `hc` on `PATH`

Tern started from the Dock, Start menu or a desktop launcher may not see the `PATH` your shell sets
up. If the picker reports that it can't run `hc`, set `HC_BIN` to its full path.

## How panes are classified

`hc ls --json` reports each pane's foreground program. A pane counts as a terminal when that program
is a known shell (`sh`, `bash`, `zsh`, `fish`, `nu`, `pwsh`, `powershell`, `cmd`, …); anything else,
or any pane that reports an agent status, counts as an agent CLI. Finished panes aren't listed.

## Limitations

- The plugin lists the herdr-core panes of the machine the Tern window runs on. Panes of a remote
  Tern host aren't listed.
- Tern plugins can't add a category to the command palette, so the list opens as its own picker
  rather than as a palette tab.

## License

[MIT](LICENSE)
