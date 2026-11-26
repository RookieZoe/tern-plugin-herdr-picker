# Tern plugin API: what we found

Notes from building this plugin against Tern 0.9.29 (`tern --version` → `0.9.29 (379ecc4)`) and
herdr-core `hc` 0.1.21. The API reference is the type file Tern generates for a plugin directory:

```sh
tern plugin types plugin   # writes plugin/tern.d.luau (git-ignored here)
```

Rechecked against Tern 0.9.35 for 0.5.1 (2026-11-26); the 0.9.32 → 0.9.35 changes to the plugin API
were `actions.outside` and settings `slot = "search"`, neither used here. Recheck these points after
a Tern upgrade; any of them may change.

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
- `cx:pick` and `cx:prompt` always open over the focused pane. Neither takes a placement, so a
  plugin can't centre them in the window; with several splits they sit off-centre. `tern.ui.node`'s
  `overlay` kind only draws inside a plugin block, and zooming the pane around the picker is a hack
  that leaves the pane zoomed if anything fails.
- Since 0.5.1 the plugin no longer uses `cx:pick`: its own block draws Tern's `picker` node (see
  [The `picker` node](#the-picker-node)), which looks like the palette and can show tabs, badges,
  logos and a tree.
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
  Up to 0.5.0 this plugin had only a window half and listed local panes only; since 0.5.1 its Herdr
  block lives in `host.luau`, so it lists the panes of the host the session belongs to.
- Every block a manifest declares in `[[blocks]]` also gets a "New … block" row in the palette under
  Plugins (`palette: true` in `tern plugin list --json`). Removing the block removes the row.
- `cx.layout:split(target, "right", { command = …, cwd = … })` opens a terminal split running a shell
  command and returns its pane number. `cx.session:panes()` and `cx.layout:focus(pane)` find and
  focus it again. (0.5.0 kept an address → pane map in `tern.kv` to find a pane it had opened; that
  missed panes attached any other way, so 0.5.1 reads `tern ls --json` instead, below.)
- `tern.getenv`, `tern.fs`, `tern.kv`, `tern.json`, `tern.log` and `tern.timer` work in both halves.
  `tern.runtime.os` is `"macos"`, `"linux"`, `"windows"` or `"ios"`.

## Host-half blocks

Checked on desktop with Tern 0.9.32 and a throwaway plugin (2026-11-24). Full notes are on the
`research/host-half-block` branch.

- The session daemon's `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`, and `TERN_EXE` is unset. A bare
  `{"hc", …}` in `tern.process.run` raises and aborts the handler, so call `hc` and `tern` by
  absolute path, inside `pcall`, with `timeout_ms`.
- Starting a process doesn't count toward the host half's 2 s Lua budget per call; one call may take
  at most 20 s of wall time.
- A block can't become a terminal, and `BlockCx` has no layout API. To open a pane from a block, the
  host half runs `tern split <cx.pane> right --window <ev.window> --json -- <cmd>`, then
  `cx:exit(0)` closes the block. `--window` must follow the subcommand; before it, the call fails.
  Alternatively `cx:open("tern-<plugin>:…")` reaches the window half's `tern.route.link`, which can
  call `cx.layout:split`.
- Only the window half opens a block with launch args (`cx:new_block(kind, args)`, `Launch`,
  `RouteDecision`). The palette's "New … block" row passes `args = []`.
- Block lists (`tern.ui.list`) have no `group` field and blocks have no built-in filter.
- `window_start` runs once per window for the window's whole life, not again after
  `tern plugin reload` or unlink + link. A top-level `tern.timer` in the window half gets a fresh
  `cx` on each load; with `cx.session:event` and `cx:action("block:<plugin>.<block>")` it can drive a
  block in tests.

## Opening, focusing and replacing blocks

Checked on macOS with Tern 0.9.35, 2026-11-25/26, first with a throwaway probe plugin, then in 0.5.1.

- `cx:new_block(kind, args, how, opts)` placements (`How`):
  - `"beside"` with `opts.dir = "down"` or `"right"` splits the focused pane and focuses the block.
    0.5.1 opens the Herdr block this way (⌘⇧H below, ⌘⌥H right).
  - `"glimpse"` floats the block over the whole tab, in no split, until a click outside it. It
    doesn't take the keyboard even with `{ focus = true }`: keys keep going to the pane under it
    until `cx.layout:focus(pane)` runs (the probe called it at once and again from a 100 ms
    `tern.timer`). Tern draws its own frame around it (a title bar with Keep beside / Keep in a new
    tab, and a hint along the bottom), which a plugin can't remove.
  - `"over"` takes the focused pane's slot and parks that pane until the block closes. A parked pane
    is in no tab, so `tern split <parked pane>` fails (`no block is called …`). Split the block
    itself instead.
  - Reloading a plugin turns an open glimpse block into an ordinary split.
- A block can't turn into a terminal. To "replace" itself, the Herdr block runs
  `tern split <cx.pane> right --json -- <cmd>` from the host half, then `cx:exit(0)`: the new pane
  takes over the closed block's slot. `tern split` leaves the focus where it was, so the block then
  runs `tern focus <doc.block>` (the `block` field of the `--json` reply).
- Call `cx:exit(0)` before `tern focus`: a closing block hands the focus to a neighbour, and that can
  land after the focus call. A process `tern.process.run` started keeps running, and its callback
  still runs, after the block that started it has closed (the VM owns it).
- `tern ls --json` lists `sessions[].tabs[].blocks[]`, each with `id`, `program`, `args`, `command`,
  `live` and `exited`. It covers one window's sessions: `--window`'s, else the window showing
  `$TERN_PANE`, else the first window. The daemon sets no `TERN_PANE`, so the plugin passes the
  block's own pane in `env`.
- A block Tern opened with a command shows that command wrapped in the user's shell:
  `program = "/bin/zsh"`, `args = ["-c", "<the whole command as one shell-quoted line>"]`, and
  `command` the same line. A plugin looking for its own command must match that quoted line, not
  separate arguments (0.5.1 missed its own `/bin/sh -c '…attach "$1"' …/hc t44` blocks until it
  did). A pane a person opened by typing `hc attach t2p` shows `args = ["-l", "-c", "…/hc attach t2p"]`.
- Closing a block whose program is running asks "Close block? … is running" unless the program has
  reported itself idle with OSC 7501: the plugin starts
  `/bin/sh -c "printf '\033]7501;state=idle\007'; exec \"$0\" attach \"$1\"" <hc> <addr>`. Not done on
  Windows, which still asks.

## The `picker` node

From Tern's docs (UI nodes › picker) and checked in a host-half block on Tern 0.9.35.

- `tern.ui.node("picker", props)` placed in a block view's `layer` region draws the palette-style
  glass sheet over the block; `size = "md"` is the palette's size. In `main` it only covers its
  container.
- It draws no real text field: `query` is shown with a drawn caret, and every key (arrows, Enter,
  Esc, Backspace, Tab, ←/→, text) reaches the block's `key` hook, which updates `query`,
  `selected` and the rest. Key names seen: `up`, `down`, `left`, `right`, `enter`, `escape`,
  `backspace`, `tab`. The node doesn't switch `tabs` on ←/→ itself.
- Pointer input comes as `event`s: `select` / `activate` with `item`, and `action` with `act` =
  `tab` (with `value`), `close`, `clear`, `retry` or an `actions[]` id.
- Useful props: `items` (`id`, `label`, `detail`, `icon`, `mark = {text, icon = "provider:<id>"}`
  for a provider logo, `badges = {{text, tone}}`, `hits` in UTF-16 offsets, `disabled`), `order`
  (ids, or `{group, label, count}` headings), `selected`, `current` (ids drawn with a check), `tabs`
  / `tab`, `actions` (`{id, label, keys, primary, disabled}`; an action with `esc` in its keys
  replaces the head's esc keycap), `title`, `subtitle`, `state` (`loading`, `error`, `ready`),
  `message`, `empty`.
- `layout = "tree"` draws depth guides and a chevron: each item's `depth` indents it, `open = true`
  / `false` draws the chevron open or shut, and an item without `open` is a leaf. Folding is the
  plugin's job: it leaves the children out.

## Logs and keys

- Only `tern.log.warn` and `tern.log.error` reach the log files; `tern.log.info` is dropped. The
  window half logs to `~/Library/Logs/Tern/tern.log`, the host half to `tern-daemon.log`.
- `tern.command{ keys = { "cmd+shift+h" } }` sets a default key in the plugin layer. A person
  rebinds or turns it off in `settings.json` `keybinds` with the action name
  `plugin.<plugin>.<command id>` (an empty list turns a key off), so a plugin needs no settings UI
  for keys. A plugin key that the defaults or preset already bind is dropped with a
  "plugin bind left out" warning in the log. `cmd` on Windows and Linux is the Windows/Super key, so
  the plugin uses `ctrl` there.
- Tern's Linux/Windows preset binds `ctrl+shift+h`, so 0.5.2's Ctrl+Shift+H for "open below" was
  dropped there (the Linux daemon log: `plugin bind left out: the preset binds these keys
  keys="ctrl+shift+h"`). `ctrl+alt+h` and `ctrl+alt+shift+h` are free in 0.9.35's preset (its
  default chords are in the binary's strings as `pc:…` / `apple:…`); 0.5.3 uses them.

## Randomness

- Luau's `math.random` in Tern's VM starts from the same seed on every load, and `os.time` isn't
  there to reseed it (a table's address doesn't help either). Two plugin loads made the same
  "random" herdr space and tab ids, so a new space landed in an older one. Get random bytes from
  the OS instead: `od -An -N32 -tx1 /dev/urandom` (Windows: `[guid]::NewGuid()` in PowerShell).
- `tern.fs.read` can't read `/dev/urandom`: without `max_bytes` it reads forever, and with
  `max_bytes` it takes regular files only.

## iOS

From Tern's docs (Architecture, Support Matrix) and the 0.9.32 changelog; details on the
`research/tern-ios-plugins` branch.

- The phone runs window halves only, from its own folder (Files › On My iPhone › Tern › Plugins),
  without JIT. A `window.luau` installed on the Mac doesn't run there. The Mac's daemon still runs the
  Mac's `host.luau` for Mac panes the phone opens.
- `tern.process.run` raises on iOS; `tern.fetch` works. The phone's `tern.fs` sees only the phone.
- The New (+) sheet is per host: a folder picker, a New tab / In tab toggle, and a "Workspace blocks"
  list of native block kinds only.

Checked on a real iPhone (Tern iOS 0.9.27, the latest; Mac on 0.9.32) with a throwaway probe plugin,
2026-11-24 (issue #7):

- The New sheet lists no plugin blocks, on the phone or on the Mac's +, even with `palette = true`.
  The phone's drawer search pill (its stand-in for the palette) finds a host's "New … block" rows and
  a phone-installed window half's `tern.command` rows.
- A host-half block opened from the phone gets `args = []` and the focused pane's folder as
  `cx.cwd`. Its `hc` calls run on the Mac. Route A (`tern split <cx.pane> right -- hc attach …`, then
  `cx:exit(0)`) shows the new pane on every window of the session, the phone included. Phone events
  carry `window = ""`.
- The phone's keyboard reaches the block's `key` hook. A tapped `input` node took focus but showed
  no text and sent no `edit` events.
- A window half in Files › Tern › Plugins reloads a few seconds after its file changes. On the phone,
  `cx:pick` (groups, icons), `cx:prompt` and `cx.layout:split` with a command (run on the Mac) work.
  An unknown icon name doesn't raise there. `tern.kv` is per device.

## Remote hosts

From Tern's docs (Distribution, Window API) and checked on two machines, 2026-11-26 (issue #11): a
Mac Tern 0.9.35 window attached to a Debian host (Tern 0.9.35, hc 0.1.17), herdr-picker 0.5.2 on
each. Research notes are on the `research/tern-remote-install` branch.

- A plugin with both halves needs installing on both machines. The client's copy gives the
  `tern.command` keys and the link route; the host's gives the block and its "New … block" palette
  row. With only the client's, the keys' `cx:new_block` returns nil (the plugin toasts "isn't
  installed on this host") and the palette has no block row. With only the host's, the palette row
  works end to end and the keys do nothing. Tern doesn't compare the two copies' versions.
- The host-half block runs `hc` on the host, so it lists and opens the host's herdr-core panes.
  `tern split` / `tern focus` run by the host's daemon (`--window ""`) reached the remote client's
  window, even with a local window on the host that also has key `""`; a local window showing the
  same session changed along with it. A macOS client honoured OSC 7501 `state=idle` from a Linux
  host: closing the attached pane didn't ask.
- `cx.layout:split(…, { command = … })` in the client's window half runs the command on the host.
  So a window half that builds a program path from the client's `HOME` / `tern.fs` (as 0.5.2's
  link-route fallback did for `hc`) gets a path the host may not have: the pane ended with exit
  127. 0.5.3 has the host half put its own `hc` path in the link. A `cx:open("tern-<plugin>:…")`
  from the host with no window half on the client does nothing visible.
- Pane ids differ between the host and a window attached to it, so a host-half pane id handed to the
  window half (0.5.2's link `target`) can name an unrelated local pane. The window half can find a
  plugin block without ids: `cx.session:panes()` gives each pane's plugin-qualified kind in `block`
  (`"herdr-picker.herdr"`), and `link.pane` is the pane the link came from.
- `cx:new_block(kind, args, "beside", …)` raises "no focused pane to open beside" in a session with
  no blocks (seen on a remote host's empty session). Check `cx.session:focused()` first and open it
  with `"tab"` instead.

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

## herdr-core, the Herdr app and spaces

Checked against herdr-app 0.1.17 and hc 0.1.22.

- `herdr` (the TUI, 0.9.x) is a separate, older product with its own server, socket and
  `session.json`. It shares nothing with herdr-core or the Herdr app; `hc --skill` calls it "the older
  terminal multiplexer". This plugin doesn't use it.
- herdr-core runs every terminal. The Herdr app (`herdr-app`) is one client that arranges them into
  spaces and tabs; this plugin is another client.
- The layout lives in herdr-core, in an opaque JSON document named `herdr-app` (`doc.get` through
  `hc connect`): `spaces[] → tabs[] → root → { terminal: "t14" }`. Ids are `sp`/`tb` plus 32 hex
  digits. Writing it directly would race the app (newest write wins, no merge).
- Terminals join it through labels: `herdr.space=<id>` and `herdr.tab=<id>`. An id the app doesn't
  know becomes a new space or tab, named after the folder or repo. The app writes
  `where="<space> / <tab>"` back onto the terminal, the `where` that `hc ls` shows. Adoption leaves
  the space the app shows unchanged.
- `hc ls --json` carries no labels. herdr-core's `terminal.list` method does, in one call:
  `printf '{"jsonrpc":"2.0","id":1,"method":"terminal.list","params":{}}\n' | hc connect --json`
  (`tern.process.run` passes it as `stdin`). Its terminals have no `agent` or `where` field:
  `where` is `labels.where`, `status` is `{app, state, msg}`, and `foreground.name` can be a version
  (`2.1.331` for Claude Code). The plugin joins it to `hc ls` by address rather than derive those.
  `hc schema` lists every method.
- Every terminal in a space carries `herdr.space`, but some (made inside the Herdr app) lack
  `herdr.tab`, so labels don't show the full tab layout. Count tabs by the tab half of `where`.
- A terminal started with an existing `herdr.space` and a fresh `herdr.tab` joins that space as its
  next tab. Verified 2026-11-24 with hc 0.1.22 (window open): `where` became `herdr-picker / 2`
  within a second.
- `herdr-app do space.new` also makes a space, but only while the app's window is running.
- The app adopts labels when a terminal first appears. Changing an existing terminal's
  `herdr.space` / `herdr.tab` with `hc label` changes the labels only: the terminal stays where it
  was in the `herdr-app` document, and its `where` doesn't change. Moving a terminal to another space
  means starting a new one with the new labels. (Seen 2026-11-26, Herdr app running.)
- Agent status in `hc ls` comes from the program's own OSC 7501 reports, with no per-agent hook.

## Tern APIs the new-space step uses

- There is no native file or folder dialog, so the Herdr block browses folders itself with
  `tern.fs.list` (0.5.0 asked for a path with `cx:prompt`, which resolves with the text, `nil` when
  dismissed).
- `tern.fs.list` gives names only. It raises on a file, which tells folders from files.
  `tern.files.button` can add a button to the Files pane header (unused here).
- `cx.session:panes()` gives each pane's `cwd` (`""` when unknown); `cx.session:focused()` gives the
  focused pane number.

## Agent-to-agent communication: use herdr-core, not Tern

Neither tool lets agents message each other directly; something (a script, a plugin or an agent
itself) reads one agent's reply and sends it to another. For that, herdr-core's `hc` is the better
fit, and Tern is where a person watches and steps in (what this plugin is for). The Tern side comes
from `tern.d.luau` and `tern <cmd> --help`; the `hc` side was verified with live Claude Code agents
(see below).

What Tern offers:

- `cx.agents` (window half only): `list()`, `start({prompt, cwd, command})`, `ask(agent, text)`
  (queued until the agent can take it), `wait(agent)` (resolves with the last reply once idle),
  `transcript(agent)` (structured chat for Tern's own omp agent only; `{}` for others),
  `interrupt`, `stop`. With the `agent_finished` window event, a plugin can relay A's reply to B.
- The CLI, from any Tern pane: `tern send BLOCK text …`, `tern capture BLOCK --scrollback`,
  `tern wait BLOCK --until idle=MS`, `tern events`. This works on screen text and silence, not on
  replies.
- A pane this plugin opens runs `hc attach`, so Tern probably sees `hc`, not an agent, and
  `cx.agents` may not reach it (unverified).

Why `hc` is the better fit:

- It addresses agents by terminal address or name: `hc send <t> <text>`, `hc read <t>`,
  `hc wait <t>` (until it stops working, or `--output X`), `hc interrupt <t>`, `hc keys <t> …`.
- It knows who started whom: a terminal an agent starts with `hc run` records that agent as its
  `parent` (`hc get <t> --json`), and the parent can wait on it with `hc wait --children`.
- It needs no Tern window or plugin, and reaches other machines with `hc machine`.
- It treats every agent CLI the same, where Tern reads structured replies from omp only.

### Verified behaviour

Checked on 2026-11-24 with hc 0.1.22 and Claude Code 2.1.331 (haiku), by a throwaway script that
started every terminal as `proto-*` with `--no-parent` and removed them afterwards; all 6 checks
passed. The script wasn't kept.

1. A plain shell: `hc send` types a line, `hc wait <t> --output X` ends when X is printed,
   `hc read` returns the screen.
2. Script ↔ agent: `hc send <t> --wait "…"` returns when the agent's turn ends (status `idle` →
   `done`, `turn` 0 → 1), and `hc read` shows the reply. The message reaches the agent wrapped as
   `<hc from="t3b">…</hc>`, naming the sender's terminal.
3. Agent → child agent: a parent agent ran `hc run --bg --name proto-child claude …`,
   `hc wait --children all`, `hc read proto-child`, and relayed the child's answer. The child's
   `parent` field held the parent's address.
4. Child → parent: a child that runs `hc send <parent> "…"` lands in the parent's input as
   `<hc from="t3w proto-reporter">REPORT=64</hc>`. Killing the child put
   `<hc>t3w proto-reporter exited (exit 129). Read: hc read t3w</hc>` into the parent's input, and
   the parent went to read it on its own.

What the docs alone got wrong:

- hc does **not** note the parent when a child agent merely finishes a turn. A child is expected to
  report with `hc send <parent>`; hc notes the parent only when a child can't (blocked, error,
  exited), per `hc --skill`. `--no-notify` and `notes = false` in
  `~/.config/herdr-core/config.toml` turn those notes off.
- Sends from a terminal count as from that terminal even with `--no-parent`: a script run inside an
  hc terminal is still `from="<its address>"`.
- `claude --allowedTools 'Bash(hc:*)' "prompt"` swallows the prompt as another tool name. Put `--`
  before the prompt, or start the agent bare and `hc send` the task once it reports `idle`.
- Start helpers with `--no-parent` when the caller is itself an agent in an hc terminal, or their
  exit notes are typed into the caller.

## Testing a plugin

- `tern plugin install <dir> --force` replaces an installed copy; `tern plugin link <dir>` uses the
  directory in place. `tern plugin list --json` shows `status` and `problems` after a reload.
- `tern ctl shot NAME` screenshots the live window (saved relative to the window's working
  directory, e.g. `~/target/shots/tern/live/`).
- `tern ctl palette` opens the palette in the live window.
- `tern ctl run TEXT` types TEXT into the focused terminal and presses Enter; it does **not** run a
  plugin command. There is no `tern ctl` command that runs an action by name, so a plugin command
  has to be triggered by hand.
