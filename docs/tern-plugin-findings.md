# Tern plugin API: what we found

Notes from building this plugin against Tern 0.9.29 (`tern --version` → `0.9.29 (379ecc4)`) and
herdr-core `hc` 0.1.21. The API reference is the type file Tern generates for a plugin directory:

```sh
tern plugin types plugin   # writes plugin/tern.d.luau (git-ignored here)
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
- `cx:pick` and `cx:prompt` always open over the focused pane. Neither takes a placement, so a
  plugin can't centre them in the window; with several splits they sit off-centre. `tern.ui.node`'s
  `overlay` kind only draws inside a plugin block, and zooming the pane around the picker is a hack
  that leaves the pane zoomed if anything fails.
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
- `herdr-app do space.new` also makes a space, but only while the app's window is running.
- Agent status in `hc ls` comes from the program's own OSC 7501 reports, with no per-agent hook.

## Tern APIs the new-space command uses

- `cx:prompt(opts)` asks for one line of text; it resolves with the text, `nil` when dismissed.
- There is no native file or folder dialog. `tern.fs.list` raises on a file, which tells folders
  from files. `tern.files.button` can add a button to the Files pane header (unused here).
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

Checked on 2026-11-24 with hc 0.1.22 and Claude Code 2.1.331 (haiku). The script is on branch
`prototype/hc-agent-comm` (`prototypes/hc-agent-comm/run.zsh`); all 6 checks passed.

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
