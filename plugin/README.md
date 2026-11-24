# Herdr Picker

A Tern plugin for [herdr-core](https://herdr.dev) (`hc`): pick a running herdr-core pane, start a
new herdr space, or add a tab to one, and open it in a Tern split.

## Usage

The plugin adds three commands to Tern's command palette:

| Command | Action name | What it does |
|---|---|---|
| **Herdr: pick a pane** | `plugin.herdr-picker.pick` | Lists live herdr-core panes; opens the one you pick |
| **Herdr: new space** | `plugin.herdr-picker.new-space` | Asks for a folder; starts a new herdr space with a shell there and opens it |
| **Herdr: new tab** | `plugin.herdr-picker.new-tab` | Asks for a herdr space; adds a tab with a shell to it and opens it |

Open the palette and type `herdr`, or bind an action name to a key in Tern's keymap. Either way the
pane opens in a split to the right of the focused pane, running `hc attach <address>`. A pane already
open in this window shows a check in the picker, and picking it again focuses that split instead of
opening another.

The picker and the folder browser open over the focused pane, not the middle of the window; Tern
offers plugins no other placement.

### Pick a pane

Tern's own picker opens with every live herdr-core pane, split into two groups:

- **Agent CLIs**: panes running an agent such as `claude-code` or `codex`, with its status
  (working, needs input, done, idle) and directory.
- **Terminals**: plain shells (`zsh`, `bash`, `pwsh`, `cmd`…), with the shell and directory.

Type to filter, ↑/↓ to move, ↵ to attach.

```
Find a herdr-core pane…

Agent CLIs
  ✦  my-app / 2      claude-code  ·  done  ·  ~/Codes/my-app
  ✦  api / 1         codex  ·  working  ·  ~/Codes/api
Terminals
  >_ my-app / 1      terminal · zsh  ·  ~/Codes/my-app
```

### New space

A folder browser opens at the focused pane's directory:

```
New herdr space in ~/Codes

  >_ Use ~/Codes          new space here
  ▸  ..                   ~
  ▸  api/
  ▸  my-app/
  ☰  Type a path…
```

Pick a subfolder or `..` to move, **Use …** to create the space there, or **Type a path…** to enter
one (`~` works). Folders starting with `.` aren't listed; type their path instead. Esc creates
nothing.

The plugin starts a shell in that folder through `hc` and opens it in a split. The Herdr app shows
it as a new space named after the folder or repo, without switching the space it's showing. To run
an agent there, start it in the new shell.

### New tab

A picker lists every herdr space that has a live pane, with its tab count and directory, so two
spaces with the same name can be told apart:

```
Add a tab to a herdr space…

  ▸  my-app            2 tabs  ·  ~/Codes/my-app
  ▸  api               1 tab  ·  ~/Codes/api
```

The plugin starts a shell in the space's first pane's directory and opens it in a split. The Herdr
app shows it as the space's next tab (`my-app / 3`). A space whose panes have all finished isn't
listed.

## Requirements

- Tern with plugin support
- herdr-core's `hc` CLI, version with `hc ls --json`, `hc connect` (`terminal.list`), `hc attach`
  and `hc run --label`
- The Herdr app is optional. Without it a new space's shell still opens in Tern; the space shows up
  once the app runs.

Works on macOS, Linux and Windows.

## Install

```sh
tern plugin install github.com/RookieZoe/tern-plugin-herdr-picker/plugin
```

This installs the latest commit on `main`; only the `plugin/` folder is copied. To update, run it
again with `--force`. Installed before 0.4.0 from the repo root? Run it once with `--force` to switch
to the slim copy.

To pin a version, download `herdr-picker-<version>.zip` from
[Releases](https://github.com/RookieZoe/tern-plugin-herdr-picker/releases), unzip it, and install
the folder:

```sh
tern plugin install ./herdr-picker --force
```

Or from a local clone, using it in place while you edit it:

```sh
git clone https://github.com/RookieZoe/tern-plugin-herdr-picker
tern plugin link ./tern-plugin-herdr-picker/plugin
tern plugin reload herdr-picker
```

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

`hc ls --json` reports each pane's foreground program; herdr-core's `terminal.list` adds the labels
that say which herdr space it belongs to. A pane counts as a terminal when that program
is a known shell (`sh`, `bash`, `zsh`, `fish`, `nu`, `pwsh`, `powershell`, `cmd`, …); anything else,
or any pane that reports an agent status, counts as an agent CLI. Finished panes aren't listed.

## Limitations

- The plugin lists the herdr-core panes of the machine the Tern window runs on. Panes of a remote
  Tern host aren't listed.
- Tern plugins can't add a category to the command palette, so the list opens as its own picker
  rather than as a palette tab.
- The picker, folder browser and path field open over the focused pane. Tern's `cx:pick` and
  `cx:prompt` take no placement, so they can't be centred in the window.
- New spaces get Herdr's automatic name; naming one needs the Herdr app (rename it there).

## License

[MIT](LICENSE)
