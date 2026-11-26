# Herdr Picker

A Tern plugin for [herdr-core](https://herdr.dev) (`hc`): pick a running herdr-core pane, start a
new herdr space, or add a tab to one, and open it in a Tern block.

## Usage

Press **⌘⇧H** to open the Herdr block below the pane you're in, or **⌘⌥H** to open it on its right
(**Ctrl+Alt+H** and **Ctrl+Alt+Shift+H** on Linux and Windows), or run either command from the
palette. In a session with no blocks yet, either key opens it in a tab of its own. The block offers
**Open a pane**, **New space** and **New tab**; each goes on in the same block, and Esc goes back a
step, or closes the block from the first one. In a short block the sheet fills the block instead of
floating in it like the palette.

| Command | macOS | Linux, Windows | Action name |
|---|---|---|---|
| **Herdr: open below** | ⌘⇧H | Ctrl+Alt+H | `plugin.herdr-picker.open` |
| **Herdr: open right** | ⌘⌥H | Ctrl+Alt+Shift+H | `plugin.herdr-picker.open-right` |

Linux and Windows don't get Ctrl+Shift+H because Tern's own keys already use it there.

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
jump to it (on Windows also `D:\…`, or just `D:`). Folders starting with `.` aren't listed; type
their path instead.

On a Windows host, **..** at a drive's root (`C:\`) lists the drives, with each one's label; ↵ on a
drive goes to its root, and Esc or Backspace goes back to the folder you came from. A drive that
isn't ready, such as an empty card reader, is shown but can't be picked.

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

The Herdr block runs on the host the session belongs to. In a window attached to a remote Tern host
it lists that host's herdr-core panes, browses that host's folders and starts new spaces there, and
`hc attach` runs on that host. The pane it opens shows up in your window and takes the focus as in a
local session.

The plugin has two halves, and each comes from a different machine:

| Install on | Gives you |
|---|---|
| The machine you're sitting at (the client) | The keys and the "Herdr: open …" commands, and the fallback below |
| The remote host | The Herdr block itself, and **New Herdr block** in the command palette |

So install it on both (see [On a remote host](#on-a-remote-host)). With only one:

- **Only on the client:** the keys say "Herdr Picker isn't installed on this host".
- **Only on the host:** the keys do nothing in that host's sessions, but **New Herdr block** in the
  palette works.

herdr-core has to run on the host too: the block only sees the herdr-core of the host the session
belongs to, never the client's or another machine's.

On Tern for iOS, open it from the drawer's search: **New Herdr block**. Nothing needs installing on
the phone; the plugin on the host the phone is attached to does the work.

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

### On a remote host

To use the plugin in a window attached to another machine's Tern (`tern remote`), install it on
that machine as well as on yours. Run the same command in a shell on the host (over `ssh`, or in a
pane of that host's session):

```sh
tern plugin install github.com/RookieZoe/tern-plugin-herdr-picker/plugin --force
tern plugin list   # herdr-picker <version> … ready
```

Then, on the host:

- Make sure `hc` is installed there and the block can find it ([below](#finding-hc-and-tern)); set
  `HC_BIN` for the host's daemon if it lives somewhere else.
- Keep both machines on the same plugin version; Tern doesn't check that they match. Update both
  with `--force`.

Works with macOS, Linux and Windows hosts. Open a window on the host's session and press the key, or
run **New Herdr block** from the palette: the list should show the host's panes, not yours.

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
`/usr/local/bin`, `/usr/bin`, `%LOCALAPPDATA%\Programs\Tern`). Without one, your window opens the
pane instead, running the host's `hc`. That needs the plugin on your machine too, and it doesn't
check whether the pane is already open somewhere.

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
