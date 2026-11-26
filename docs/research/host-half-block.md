# What a host-half plugin block can do for a picker

Research for issue #4 (parent map #2). Checked on 2026-11-24 against Tern 0.9.32 (`0dd129e`) on
macOS and herdr-core `hc` 0.1.22.

Each answer is marked **confirmed** (with its source) or **inferred** (reasoned from sources, not
observed).

## Sources

- **Types**: `plugin/tern.d.luau`, regenerated with `tern plugin types plugin` from 0.9.32. Cited
  below by type name (`BlockDef`, `BlockCx`, `Launch`, …).
- **CLI help**: `tern --help`, `tern split --help`, `tern run --help`, `tern new --help`,
  `tern plugin --help`, `tern help dev`.
- **Changelog**: the release notes embedded in the Tern binary
  (`strings /Applications/Tern.app/Contents/MacOS/tern`).
- **Experiment**: a throwaway plugin `hbprobe` (host half with one `[[blocks]]` block, plus a window
  half that drove it), linked with `tern plugin link`, run twice in the live desktop window, then
  unlinked, with its `plugin-data` folder deleted. It wasn't committed. Its window half opened the
  block with `cx:new_block`, sent it events with `cx.session:event`, read it back with
  `cx.session:surface`/`read`/`view`, and logged both halves to files.

### The old host half is gone

The issue says the plugin had a block before 0.3.0. It isn't in this repository:
`git log --all -- '*host.luau'` and `git log --all -S'block.define'` both find nothing. History
starts at `a672574` with `window.luau` only, and the only remote refs are `main`, `v0.4.0` and
`v0.5.0`. No `host.luau` was found on disk either (`mdfind -name host.luau`, Tern's plugin folders).
It was dropped before the first commit here, so this research starts from the API itself.

## 1. Can the host half run `hc`, and under what budgets?

**Yes. Confirmed by experiment.** In a block's `event` handler, `tern.process.run` with a callback
ran on the Mac's session daemon:

| call | status | time | output |
|---|---|---|---|
| `~/.local/bin/hc ls --json` | 0 | 18–21 ms | 1.9 KB |
| `~/.local/bin/hc connect --json` with a `terminal.list` request on `stdin` | 0 | 44 ms | 12.8 KB |

What to watch for:

- **The daemon's `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`** (confirmed: `tern.getenv("PATH")` in
  the host half). A bare `{"hc", …}` **raises** `tern.process.run hc: No such file or directory`.
  The raise aborts the rest of the handler, and the daemon log records it
  (`~/Library/Logs/Tern/tern-daemon.log`). Use an absolute path: find `hc` once (for example
  `$HOME/.local/bin/hc`, or `/bin/zsh -lc 'command -v hc'`) and call `process.run` in `pcall`.
  `TERN_EXE` is unset in the daemon too (confirmed), so `tern` needs an absolute path as well
  (`~/.local/bin/tern` or `/Applications/Tern.app/Contents/MacOS/tern`).
- **Budgets** (confirmed from the `tern.d.luau` header): each call into the host half may run 2 s of
  Lua (50 ms in the window half). Native calls, starting a process included, don't count. A call
  may take at most ten budgets of wall time (20 s) including native calls. Going over raises
  `tern: <hook> exceeded <n> ms` and pauses that hook for 5 s, doubling per repeat up to 5 min.
  `process.run` with a callback returns at once, and its callback is a new call with its own
  budget, so `hc`'s run time never counts. Parsing a few KB of JSON is far below 2 s (inferred from
  the sizes above). Pass `timeout_ms` so a stuck `hc` can't hang.
- `tern.process.spawn` (streaming) is also available in the host half. The only places it raises
  are iOS and Carly's VM (confirmed, types). The host half of a phone-attached session runs on the
  Mac, so neither applies. That the iOS window really reaches the Mac's host half for a block is
  inferred and was not checked on a phone.
- `tern.pane.list()` in the host half returned 18 panes while the window saw 46 (confirmed). The
  host lists only its own panes. Don't use it to look up window state.

## 2. What UI can a block render? Touch?

**Confirmed by experiment** (`cx.session:surface` and the accessibility tree from
`cx.session:view`):

- **Scrollable list**: `tern.ui.list(items)` with props `selected` and `max = {lines = N}` rendered
  as a `ListBox` inside a `ScrollView`, one `ListBoxOption` per `hc` terminal (12 rows). Per the
  types, a list keeps its selected row in view only when `max` is set, and needs a `tern.ui.col`
  around it in `view`.
- **Table with row buttons**: `tern.ui.table(cols, rows, {selectable = true, selected = id})` with
  `TableRow{id, cells}` and a `{button = {text, act}}` cell rendered as rows, each with a `Button`.
  Per the types, clicks send `select`, double-clicks send `activate` (with `item` = the row id), a
  button cell sends `action` with `item`, and `menu` adds right-click actions. A table is the
  closest fit for "pane + where + status + Open".
- **Buttons**: `tern.ui.button(text, {actions = {click = "name"}})` rendered, and `action` events
  with `act` reached the host's `event` handler. Each event carries `window` (the sending window's
  key, `""` for the first window).
- **Text field**: `tern.ui.node("input", {placeholder = "Folder path", value = …})` rendered as a
  `TextInput` named "Folder path". `tern.ui.node("editor", …)` also rendered as a `TextInput`, but
  it ignored my `placeholder` (its accessible name was "Message"), so `editor` takes other props.
  Blocks opt into native editing with `features = {"edit"}`. Edits then arrive as `edit` events
  (types). The real `edit` payload wasn't observed: the probe sent a synthetic one, so its fields
  are **inferred**.
- **Typed keys**: the `key` hook received `{name = "x", text = "x", …}` (confirmed, by writing to
  the block's pty, see Q3). A block can do type-to-filter itself: append `key.text` to a filter
  string in state and re-render.
- **Grouped rows**: `Item` (list rows) has no `group` field, unlike `cx:pick`'s `PickItem`
  (confirmed, types). Group by stacking a `tern.ui.section(head, {…})` or `tern.ui.rule(label)` per
  space, or by giving each space its own table (inferred: not rendered in the probe).
- **No built-in filter field** on `list`/`table` in the types (confirmed). A block must filter its
  own state (inferred design).
- **Sheets**: `BlockView.layer` and the `overlay` node (`OverlayProps`: `head`, `foot`, `modal`,
  `anchor`) give a block its own modal. The changelog says "Controls in a plugin block's layer
  (sheets, modals) take clicks" (confirmed, changelog; not rendered in the probe).

**Touch on a phone: inferred from the changelog, not tested on an iPhone.** Relevant entries:

- "Tapping a field in a plugin block or omp dialog opens the keyboard" (iPhone/iPad).
- "Plugin blocks can let you drag items … with touch and hold on phones".
- "Fixed stray link underlines and keyboard pop-ups in chats and plugin blocks".
- "Plugins … a folder with a `plugin.toml` … (`tern plugin dir`; on iOS, Tern's Plugins folder in
  the Files app)". So plugins load on iOS too.

Plugin blocks are drawn by Tern's own UI, the same TSP nodes as native blocks, so taps on buttons
and rows should behave like clicks. Whether a phone's on-screen keyboard reaches a block's `key`
hook when no field has focus is unknown. Prefer a real `input` node over the `key` hook for
filtering on a phone. `tern audit --prelude <phone scenario>` (`tern help dev`) can measure touch
target sizes offscreen without a phone.

## 3. How does a picked row become a terminal pane running `hc attach`?

**The block can't turn itself into a terminal, and the host half has no layout API.** `BlockCx`
offers `toast`, `open`, `copy`, `render`, `save`, `exit`, `frame`, `blob` and `status`. It has no
`split`, `new_block` or `layout` (confirmed, types). `tern.ui.ansi` only displays text. These routes
do work:

**A. Host half runs the `tern` CLI. Confirmed on desktop.** From the block's `event` handler:

```lua
tern.process.run({ TERN, "split", tostring(cx.pane), "right", "--json", "--", HC, "attach", addr },
  { timeout_ms = 10000 }, function(r) … end)
```

This returned status 0 and `{"session":…, "tab":…, "block":…}`, and a split opened beside the block.
It worked with `--window <ev.window>` placed **after** the subcommand and without `--window` (it
then falls back to the first window). Before the subcommand, `--window ""` fails:
`tern: : No such file or directory`. `cx.pane` is the block id the CLI takes. The CLI has no
"open a plugin block" form: `LAUNCH` is only `[--cwd] [--keep-open] [--end-on-success] [-- COMMAND]`
(confirmed, help). Other commands follow the same pattern: `tern new tab`, `tern focus`,
`tern close`.

- **Replace itself**: split beside the block, then `cx:exit(0)`. `cx:exit` closed the block's pane
  (confirmed: `cx.session:pane(pane)` was `nil` afterwards). Close-then-split would lose the target
  pane, so split first.
- **On a phone (inferred, needs an iPhone check)**: the CLI acts on "one window's sessions". A
  session lives in the host's daemon, and windows follow it live. A split the Mac's CLI makes in
  that session should appear in the phone's window. It is unproven whether `--window`/the default
  window resolves to a remote (phone) window, or only to windows on the Mac. If no window on the Mac
  shows that session, the CLI may pick the wrong one. Pass `--window <ev.window>` from the event.

**B. Host `cx:open(link)` → window half's `tern.route.link`. Confirmed on desktop.** `cx:open`
from the block reached the window half's `tern.route.link` handler with
`{url = "tern-hbprobe:attach?addr=t0", pane = <window's focused pane>, mods}`. `pane` is the window's
focused pane, not the block. The handler has a `WindowCx`, and `cx.layout:split(…, {command = …})`
inside it opened a split; returning `{handled = true}` ended it. A `RouteDecision` may instead
return `{block = "<plugin>.<kind>", args = {…}}` to open a block (types). This route needs the
plugin's window half to run in the window that sent the event. On a phone that means the plugin
installed on the phone (the Files app's Plugins folder). `cx.layout:split` is a native call, so the
`tern.process.run`-raises-on-iOS problem doesn't apply. Inferred: the split's command runs on the
host of the session it splits, the Mac.

**C. `tern.pane.write(pane, text)`. Confirmed.** It writes into any host pane's pty. Written into
the block's own pane, `"x"` arrived at the block's `key` hook. It could type `hc attach X\r` into an
existing shell pane, but it doesn't make a new pane.

**Recommendation (inferred)**: use A for the host-only path (no phone-side plugin needed), with
`--window ev.window` and absolute paths. Keep B in mind if A misses the phone's window; that is
the open question for an iPhone check.

## 4. How does a block get launch args?

**Confirmed by experiment:**

- `cx:new_block("hbprobe.probe", {"mode=tab", "space=sp123"}, "beside", {focus = false})` returned
  the pane id. The host's `init(cx, args, saved)` got `args = ["mode=tab","space=sp123"]` exactly,
  and `title(state)` set the pane title "HB Probe mode=tab space=sp123".
- The palette row "New HB Probe block" (action id `block:<plugin>.<block>`, group = the plugin name)
  opened the block with **`args = []`**. Run with `cx:action("block:hbprobe.probe")`.
- `init` also gets `cx.pane`, `cx.cwd` (the focused pane's folder), `cx.cols` and `cx.rows`.
  `saved` was `null` for a new block in run 2. In run 1 it held the `save()` result on the first
  `init`, which I can't explain; treat `saved` as possibly present.

From the types (confirmed, types; not exercised):

- `Launch = {cwd, command, block, args}` sets what `cx.layout:split`, `new_tab` and `tab` open. A
  window can open a block with args in a split or tab directly.
- `RouteDecision = {block, args}` lets a `route.open` or `route.link` handler open a block with
  args.
- `BlockOpts = {focus, target, dir, ratio}` sets where `cx:new_block` puts the block.

So one block kind can serve every mode. Read `args[1]` (`"pick"`, `"new-space"`,
`"new-tab=<space id>"`) and fall back to "pick" for the palette's empty `args` (inferred design).
Only the window half can open a block with args (`cx:new_block`, `Launch`, `RouteDecision`). The
host half can't open a block, and the CLI can't either. A host-only flow therefore changes mode
inside the block (buttons or tabs in its own state), not by opening another block.

## Other findings

- A `[[blocks]]` entry takes `id`, `title`, `icon`, `files` and `palette`; `tern plugin list --json`
  shows them (confirmed). A manifest with blocks needs a `host` entry ("blocks need a host entry",
  binary string).
- `cx:exit(code)` ends the block and closes its pane (confirmed).
- For testing: `window_start` runs once per plugin per window *lifetime*. It didn't run again after
  `tern plugin reload` or unlink + link (confirmed). A top-level `tern.timer(…, function(cx) … end)`
  in the window half gets a fresh `cx` on every load and can drive a block. Use
  `cx.session:event(pane, {ev = "action", act = …})` to click and `cx.session:surface`/`view` to
  read back. This automates the "no `tern ctl` command runs a plugin action" gap in
  `docs/tern-plugin-findings.md`; `cx:action("block:<plugin>.<block>")` runs a palette row.

## Open questions for the map

- Does `tern split` run from the Mac's host half reach a phone attached through `tern remote`
  (route A), and does `--window ev.window` name the phone's window? Only an iPhone can answer this.
- Does the phone's on-screen keyboard deliver keys to a block's `key` hook, or only to `input`
  nodes?
