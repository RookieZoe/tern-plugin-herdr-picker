# Herdr Picker

A Tern plugin for [herdr-core](https://herdr.dev) (`hc`): pick a running herdr-core pane, start a
new herdr space, or add a tab to one, and open it in a Tern block.

## Usage

Press **⌘⇧H** to open the Herdr block below the pane you're in, or **⌘⌥H** to open it on its right
(Ctrl+Shift+H and Ctrl+Alt+H on Windows and Linux), or run either command from the palette. The
block offers **Open a pane**, **New space** and **New tab**; each goes on in the same block, and Esc
goes back a step, or closes the block from the first one. In a short block the sheet fills the
block instead of floating in it like the palette.

| Command | Default key | Action name |
|---|---|---|
| **Herdr: open below** | ⌘⇧H | `plugin.herdr-picker.open` |
| **Herdr: open right** | ⌘⌥H | `plugin.herdr-picker.open-right` |

To change a key, map its action name in the `keybinds` of Tern's `settings.json`; an empty list
(`"cmd+shift+h": []`) turns a key off.

The pane you end up with, running `hc attach <address>`, takes the block's place. On macOS and
Linux, closing it doesn't ask whether to end `hc`; on Windows it still asks. Either way, closing only
detaches: the herdr-core terminal keeps running.

### Open a pane

Every live herdr-core pane, with tabs to narrow them down: **All**, **Agents** and **Terminals**
(←/→ or Tab to switch). In each tab the panes are a tree by herdr space: a space with several panes
is a row of its own, with its tabs under it, agents and plain shells together; a space with one pane
is a single row. ↵ on a space folds or unfolds it; a search keeps every match unfolded.

- **Agent CLIs**, such as `claude-code` or `codex`, show their logo, status (working, needs input,
  done, idle) and directory.
- **Terminals**, plain shells (`zsh`, `bash`, `pwsh`, `cmd`…), show the shell and directory.

Type to filter, ↑/↓ to move (they wrap around at either end), ↵ to attach.

```
Find a herdr-core pane…
 All 13   Agents 4   Terminals 9

  ▾ ▸  media-xray-oss         3 panes  ·  ~/Codes/AI/media-xray
    │ ✳  Tab 1     done       claude-code
    │ >_ Tab 2                zsh
    │ >_ Tab 3                zsh
  ✦  api / 1       working    codex  ·  ~/Codes/api
  >_ my-app / 1               zsh  ·  ~/Codes/my-app
                                                 Close   Open
```

A pane already attached in a Tern block, by this plugin or not, shows a check. Picking it closes the
Herdr block and focuses that block instead of attaching again.

### New space

A folder browser opens at the pane's directory:

```
New space  ~/Codes
Filter folders, or type a path…

  >_ Use ~/Codes          start the new space here
  ▸  ..                   ~
  ▸  api/
  ▸  my-app/
                                Back   Create here   Choose
```

↵ on a folder goes into it, Backspace (with nothing typed) goes up, and **Use …** or **Create here**
(⌘↵) starts the space there. Type to filter the folders, or type a path starting with `/` or `~` to
jump to it. Folders starting with `.` aren't listed; type their path instead.

The plugin starts a shell in that folder through `hc` and opens it in the block's place. The Herdr app shows
it as a new space named after the folder or repo, without switching the space it's showing. To run
an agent there, start it in the new shell.

### New tab

Every herdr space that has a live pane, with its tab count and directory, so two spaces with the same
name can be told apart:

```
Add a tab to a herdr space…

  ▸  my-app            2 tabs  ·  ~/Codes/my-app
  ▸  api               1 tab  ·  ~/Codes/api
```

The plugin starts a shell in the space's first pane's directory and opens it in the block's place. The Herdr
app shows it as the space's next tab (`my-app / 3`). A space whose panes have all finished isn't
listed.

### Remote hosts and the phone

The block runs on the host the session belongs to, so in a window attached to a remote Tern host it
lists that host's herdr-core panes and browses that host's folders. Install the plugin on that host.
On Tern for iOS, open it from the drawer's search: **New Herdr block**.

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

## Finding `hc` and `tern`

The block runs in Tern's session daemon, whose `PATH` is the system default, so the plugin looks for
`hc` in this order:

1. The `HC_BIN` environment variable
2. `~/.local/bin/hc`
3. `/opt/homebrew/bin/hc`, `/usr/local/bin/hc`
4. `%LOCALAPPDATA%\Programs\herdr-core\hc.exe` or `%LOCALAPPDATA%\Programs\herdr-app\hc.exe` (Windows)
5. `hc` on `PATH` (Windows only)

If the block says it can't find `hc`, set `HC_BIN` to its full path where the daemon starts.

It opens panes with the `tern` CLI (`TERN_EXE`, then `/Applications/Tern.app`, `~/.local/bin`,
`/usr/local/bin`, `/usr/bin`, `%LOCALAPPDATA%\Programs\Tern`). Without one, the window opens the
pane instead.

## How panes are classified

`hc ls --json` reports each pane's foreground program; herdr-core's `terminal.list` adds the labels
that say which herdr space it belongs to. A pane counts as a terminal when that program
is a known shell (`sh`, `bash`, `zsh`, `fish`, `nu`, `pwsh`, `powershell`, `cmd`, …); anything else,
or any pane that reports an agent status, counts as an agent CLI. Finished panes aren't listed.

## Limitations

- Tern plugins can't add a category to the command palette, so the plugin opens its own block.
- New spaces get Herdr's automatic name; naming one needs the Herdr app (rename it there).

## License

[MIT](LICENSE)
