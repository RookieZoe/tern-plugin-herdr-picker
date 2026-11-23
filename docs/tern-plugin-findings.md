# Tern plugin API: what we found

Notes from building this plugin against Tern 0.9.29 (`tern --version` → `0.9.29 (379ecc4)`) and
herdr-core `hc` 0.1.21. The API reference is the type file Tern generates for a plugin directory:

```sh
tern plugin types <dir>   # writes <dir>/tern.d.luau (git-ignored here)
```

Recheck these points after a Tern upgrade; any of them may change.

## Command palette

- A plugin can't add a category (a tab such as Hosts or Sessions) to the command palette.
  `tern.command(def)` only adds an ordinary command row; `def.group` sets the heading it is listed
  under, not a tab.
- The closest thing is `cx:pick(opts)` (window half only). It opens Tern's own picker over the
  focused pane, styled like the palette: a filter field, `group` headings over consecutive items,
  per-item `icon`, dim `detail` text, a check for `current`, and an `action` word in the key legend.
  It returns an `Awaitable`; the chosen item comes back in `:next(function(item, err, cx) … end)`,
  `nil` when dismissed. Extra fields on an item ride along to the answer.
- Typing filters on `label`. Put anything the user should be able to search for in the label.
- An unknown icon name raises. The plugin calls `cx:pick` in `pcall` and retries without icons.
  Icon names seen in the Tern binary include `terminal`, `sparkle`, `list`, `server`, `folder` and
  `provider-<name>` brand icons (`provider-anthropic`, `provider-openai`, `provider-github`,
  `provider-cursor`, …). There is no published list.

## Window half and host half

- `window.luau` runs in the window, on the machine that shows Tern. `host.luau` runs in the session
  daemon of the host a pane belongs to, which can be a remote machine.
- `tern.process.run` in the window half runs on the window's machine. So a window-half picker that
  calls `hc ls` lists the local herdr-core panes only. Listing a remote host's panes needs the host
  half, through a plugin block (`tern.block.define`), opened with `cx:new_block("<plugin>.<block>")`.
  This plugin dropped its block in 0.3.0 and lists local panes only.
- Every block a manifest declares in `[[blocks]]` also gets a "New … block" row in the palette under
  Plugins (`palette: true` in `tern plugin list --json`). Removing the block removes the row.
- `cx.layout:split(target, "right", { command = …, cwd = … })` opens a terminal split running a shell
  command and returns its pane number. `cx.session:panes()` and `cx.layout:focus(pane)` find and
  focus it again. `tern.kv` persists the address → pane mapping between commands.
- `tern.getenv`, `tern.fs`, `tern.kv`, `tern.json`, `tern.log` and `tern.timer` work in both halves.
  `tern.runtime.os` is `"macos"`, `"linux"`, `"windows"` or `"ios"`.

## Internationalization

Tern offers no i18n support for plugins:

- `tern.d.luau` has no locale, language or translation API.
- `tern.runtime` holds only `os` and `jit`.
- `cx.settings` and `settings.json` have no language setting.
- `plugin.toml` has no localized fields.
- Tern itself ships English only; the app bundle has no `.lproj` resources.

A plugin that wants another language would have to read `LANG` through `tern.getenv`. That is
unreliable: Windows rarely sets it, and Tern launched from the Dock or Start menu may not inherit
it. This plugin uses English throughout.

## herdr-core output

`hc ls --json` prints `{ "terminals": [ … ] }`. Each terminal has:

| field | meaning |
|---|---|
| `address` | what `hc attach` takes, e.g. `t2p` |
| `where` | `<workspace> / <tab>`, the human name |
| `agent` | the foreground program: a shell (`zsh`) or an agent CLI (`claude-code`) |
| `cwd` | the pane's directory |
| `state` | `live` or `finished` (finished ones appear only with `--all`) |
| `status` | agent status (`working`, `blocked`, `done`, `idle`), present only for agents |
| `turn` | turn count |

There is no `name` field, despite what an earlier version of this plugin read.

## Testing a plugin

- `tern plugin install <dir> --force` replaces an installed copy; `tern plugin link <dir>` uses the
  directory in place. `tern plugin list --json` shows `status` and `problems` after a reload.
- `tern ctl shot NAME` screenshots the live window (saved relative to the window's working
  directory, e.g. `~/target/shots/tern/live/`).
- `tern ctl palette` opens the palette in the live window.
- `tern ctl run TEXT` types TEXT into the focused terminal and presses Enter; it does **not** run a
  plugin command. There is no `tern ctl` command that runs an action by name, so a plugin command
  has to be triggered by hand.
