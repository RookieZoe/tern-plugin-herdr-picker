# Where Herdr Picker must be installed when a Tern client attaches to a remote host

Research for the ticket "Where the plugin must be installed when a Tern client attaches to a remote
Tern host" (issue #10, map: issue #2). Checked on 2026-11-26 against Tern 0.9.35 (`ccfae03`) on
macOS, Tern's plugin docs, the changelog and strings in the 0.9.35 binary, and the plugin at 0.5.2
(`plugin/window.luau`, `plugin/host.luau`). No second machine was used.

Each answer is marked **documented** (a Tern doc says so, cited), **inferred** (follows from docs,
CLI help or the code, with the reasoning given) or **not documented**. What only a two-machine run
can settle is at the end.

"Client" is the machine showing the Tern window (desktop attached with `tern remote`, or the iOS
app). "Host" is the remote machine whose session daemon runs the session's panes.

## Sources

| Tag | Source |
|---|---|
| [arch] | Architecture: <https://docs.stencil.so/tern/concepts/architecture.html> ("Where each half runs", "The catalog") |
| [sec] | Trust and Security: <https://docs.stencil.so/tern/concepts/security.html> ("What a plugin can reach", "Remote hosts") |
| [dist] | Distribution: <https://docs.stencil.so/tern/guides/distribution.html> ("Remote hosts") |
| [blocks] | Blocks: <https://docs.stencil.so/tern/guides/blocks.html> ("Opening blocks", the block `cx` table) |
| [cmds] | Commands, Keys, and Overrides: <https://docs.stencil.so/tern/guides/commands.html> (window `cx` table) |
| [layout] | Layout and Workspaces: <https://docs.stencil.so/tern/guides/layout.html> ("Ids", "Arranging panes") |
| [io] | Files, Processes, and Storage: <https://docs.stencil.so/tern/guides/io.html> ("Which machine, which thread", `tern.process.run`) |
| [hooks] | Host Hooks and the Spawn Filter: <https://docs.stencil.so/tern/guides/hooks.html> |
| [win] | Window API: <https://docs.stencil.so/tern/reference/api-window.html> (`cx:new_block`, `cx:window_key`, `cx.layout:split`) |
| [err] | Errors: <https://docs.stencil.so/tern/reference/errors.html> |
| [limits] | Limits: <https://docs.stencil.so/tern/reference/limits.html> ("Pane and tab ids in Lua") |
| [actions] | Built-in Actions: <https://docs.stencil.so/tern/reference/actions.html> ("Remote hosts": `update_remote_host`) |
| [clidoc] | Command Line (`tern plugin`): <https://docs.stencil.so/tern/reference/cli.html> ("Common behavior") |
| [gloss] | Glossary: <https://docs.stencil.so/tern/reference/glossary.html> ("Window key") |
| [matrix] | Support Matrix: <https://docs.stencil.so/tern/concepts/support-matrix.html> |
| [dts] | `tern.d.luau` as embedded in the 0.9.35 binary (`EffectCx:open`, event `window` field) |
| [bin] | Other strings in the 0.9.35 binary (`strings /Applications/Tern.app/Contents/MacOS/tern`): changelog, the remote-setup probe script, config-file comments |
| [cli] | `tern split --help`, `tern focus --help`, `tern ls --help`, `tern inspect --help`, `tern remote` usage (0.9.35) |
| [findings] | `docs/tern-plugin-findings.md` on `main`, esp. § iOS (a real iPhone attached to a Mac) |

All docs pages are also in one file: <https://docs.stencil.so/tern/print.html>.

## Summary

- **Install both halves on both sides.** The host half (`host.luau`: the Herdr block and its palette
  row) must be on the **host**; the window half (`window.luau`: ⌘⇧H / ⌘⌥H and the
  `tern-herdr-picker:` link route) must be on the **client**. Tern's docs say so in as many words:
  "A plugin with both halves that you want for remote panes needs installing on both machines."
  [dist] Each side's copy is used only for its own half; the host's `window.luau` and the client's
  `host.luau` are unused for that session.
- **The block sees the host's herdr-core, and `hc attach` runs on the host.** The block runs in the
  host's daemon, so `hc ls` / `hc connect` list the host's terminals [arch] [io]; the pane it opens
  is a pane of the host, so `hc attach` runs there (documented for `cx.layout:split`, inferred for
  `tern split`). The client can't list or attach herdr-core terminals of a host it isn't attached to
  through this plugin.
- **The fallback's command runs on the host too** (`cx.layout:split` "on target's host" [win]
  [layout]; seen on a real iPhone [findings]). But the window half builds that command on the
  client: it looks for `hc` on the client's disk and with the client's `HOME`/`HC_BIN`, and it
  passes a host-side pane id as `target`. Both are wrong on a remote session (see Q3).

## Q1. Which installation provides each entry point?

| Entry point | Provided by | Status |
|---|---|---|
| ⌘⇧H / ⌘⌥H (`tern.command` in `window.luau`) | **Client's** window half | Documented: commands and key binds are window-half; the window half "runs from your plugins folder" on the machine showing the window, also for remote panes [arch] [dist] [sec] |
| What those commands open (`cx:new_block("herdr-picker.herdr", …)`) | **Host's** host half | Documented: `new_block` opens the kind "on the window's current host … or nil … when no Ready plugin there defines kind" [win] [cmds]; "Block types live on the host that runs the pane: a remote host needs the plugin installed there." [err] |
| Palette (desktop) / drawer search pill (iOS) row "New Herdr block" | **Host's** install (its catalog) | Documented: the host's catalog carries block types (id, title, icon, files, palette) and drives the "New *title* block" rows [arch "The catalog"]; the palette lists them "for each Ready block type … on the current host" [blocks]. iOS: seen on a real iPhone [findings § iOS]. The client's install does not add this row for a remote session (inferred: the row comes from the current host's catalog only) |
| The Herdr block itself (`host.luau`) | **Host's** host half | Documented: "Remote host attached to your window: On the remote host, in its daemon, from its plugins folder" [arch]; "Install a host half on the machine whose panes it should serve" [arch] [dist] |
| Link-route fallback (`tern.route.link` in `window.luau`) | **Client's** window half | Documented: routes are window-half [arch Ownership]; a block's `cx:open` "Opens a path or URL in those windows, through their routes" [blocks], i.e. the routes of the windows showing the pane, which run the client's window halves |

### Only the client has it

- ⌘⇧H / ⌘⌥H: `cx:new_block` returns `nil` and the plugin toasts "Herdr Picker isn't installed on
  this host" (`open_block` in `window.luau`). Documented behaviour of `new_block` [win]; the docs'
  own examples do the same toast [blocks example "review-queue"].
- No "New Herdr block" row for that host. Documented [blocks] [arch].
- So nothing lists the host's panes. Inferred.

### Only the host has it

- The "New Herdr block" palette / drawer row works and opens the block. Documented [blocks] [arch].
  The palette passes `args = []` [blocks], which the block treats as `mode=home`.
- The block opens its pane with the host's `tern split` CLI (Q2). That path needs no window half, so
  the whole flow works from the palette row as long as the host has a `tern` CLI the plugin finds.
  Inferred from `host.luau` (`open_pane` → `split_attach`).
- No ⌘⇧H / ⌘⌥H (window-half commands). Documented [dist].
- If the `tern` CLI is missing or fails, the block falls back to `cx:open("tern-herdr-picker:…")`.
  With no client route for that scheme, Tern's own open handles it: a non-path "opens as a link
  clicked in the focused pane: … anything else through the system" [win `cx:open`]. So the click
  ends up with the OS URL handler and no pane opens. Inferred; the block has already closed.

### Both have it

- Everything works as on one machine, with the caveats in Q2 and Q3. Documented split of roles
  [dist].
- **Versions.** Tern does not check that the two machines' copies of a plugin match: each machine
  loads its own folder, "Which plugins a remote host runs is that host's owner's decision" [sec],
  and the catalog only reports the host's version (Preferences › Plugins lists the host's plugins
  read-only under its name) [arch] [dist]. Not documented: any version check between halves.
  Inferred from the code, the halves talk only through:
  1. the block kind `herdr-picker.herdr` and the launch args `mode=<home|pick|space|tab>` and
     `target=<pane>` (`window.luau` passes `mode=home`; `host.luau` `init` parses both);
  2. the link `tern-herdr-picker:attach?addr=…&target=…&cwd=…`.

  Both have been the same since 0.5.1. A client on **0.5.0 or older** (window half only, it ran
  `hc ls` through `tern.process.run` on the client) lists the *client's* herdr-core terminals and
  splits the focused *remote* pane with `hc attach <client address>`, which runs on the host:
  wrong terminal or none. So: both sides on 0.5.1 or later; matching patch versions are not needed
  today, but the contract above must not change without bumping both. Tern itself may differ
  between the machines: Tern offers "Update remote host…" "while a connected host runs an older
  Tern" [actions] and `tern remote update HOST` [cli]; the plugin API used here is unchanged
  0.9.29 → 0.9.35 [findings].

## Q2. Does the block see the host's herdr-core, and where do `tern split` / `focus` / `ls` act?

**`hc ls` / `hc connect` see the host's herdr-core: documented.** The host half's processes run "Where
the panes run (the session daemon's machine, a remote host for its panes)" [io]; "`tern.getenv`,
`tern.fs` and `tern.process` there see the daemon's environment and machine" [hooks]. On a real
iPhone attached to a Mac, the block's `hc` calls ran on the Mac [findings § iOS]. The block's
`hc_bin()` searches the host's `$HOME/.local/bin/hc`, Homebrew and `/usr/local/bin`, or `HC_BIN` in
the host daemon's environment. Folders it browses for a new space are the host's (`tern.fs`) too.

**`tern split`, `tern focus` and `tern ls` run by the host daemon act on the host's daemon and reach
the client's window: inferred, partly seen.**

- The plugin runs the host's `tern` CLI (`tern_bin()` in `host.luau`: `TERN_EXE`, then
  `/Applications/Tern.app/…`, `~/Applications/Tern.app/…`, `~/.local/bin/tern`, `/usr/local/bin/tern`,
  `/usr/bin/tern`). Those are the places Tern's own remote-setup probe looks for `tern` on a host
  (`command -v tern`, `~/.local/bin/tern`, `/usr/local/bin/tern`, `/Applications/…`,
  `~/Applications/…`) [bin]. A host whose `tern` is only in `/usr/local/lib/tern-remote` (the copy
  `sudo tern remote install` runs as the system service [bin, changelog 0.9.x]) and not on one of
  those paths would hit the fallback (Q3) unless `TERN_EXE` is set. Inferred.
- A `tern` command talks to "the session daemon on this machine's socket" ("There is one daemon per user")
  [clidoc], here the host's daemon, the one that owns the block's pane.
  Documented for `tern plugin`; inferred for the scripting commands.
- It picks a window by `--window KEY`, else "the window whose sessions hold `$TERN_PANE`", else the
  first window [cli]. A window key "names a window's sessions in the daemon" [gloss]. The client's
  window is known to the host daemon under a host-side key: Tern's config keeps "Windows of remote
  hosts Tern's windows show instead of their own: host, this machine's window key, the host's window
  key" [bin], and host-half events carry "the window key of the window that sent the event, when a
  daemon knows it" [dts]. The plugin passes the block's own pane as `TERN_PANE` (no `--window`), so
  the CLI resolves to the host-side key whose sessions hold the block: the session the client shows.
  Inferred.
- `tern split` changes the session's layout, and "Layout changes are session changes: they
  replicate to every window showing the session" [layout]. So the new pane appears on the client
  whichever window key the CLI picked. **Seen** on a real iPhone attached to a Mac: route A
  (`tern split <cx.pane> right -- hc attach …`, then `cx:exit(0)`) showed the pane "on every window
  of the session, the phone included" [findings § iOS]. Not yet seen with a desktop client.
- `tern ls --json` covers one window key's sessions [cli]; with `TERN_PANE` set to the block's pane it
  lists the session the block is in. That is what the plugin needs ("already open" detection).
  Inferred.
- `tern focus BLOCK`: "its window shows it" [cli]. Focus is per window: "`cx.layout:focus` moves this
  window's focus only, and other windows keep their own" [layout]. **Not documented:** whether
  `tern focus` run on the host moves the focus in a remote client attached under that window key,
  or only in a window on the host itself, when both show the session. The iPhone run recorded where
  the pane appeared, not where the focus went. Needs a two-machine run.

**Where `hc attach` runs: on the host.** `tern split` makes a pane of the host's daemon, which starts
its program on that machine. Documented for the equivalent window call ("A split starts on target's
host" [layout] [win]); inferred for the CLI; seen on the iPhone run [findings].

**Herdr-core terminals of a host the client isn't attached to: no (inferred).** The block lists only
its own host's `hc` (above), and `cx:new_block` opens "on the window's current host" [win], so the
block always belongs to the host of the window's current session. To see another host's
terminals, switch the window to that host (it must have the plugin) [win "current host"]. herdr-core
itself can reach other machines (`hc machine add <ssh host>`, "Other machines, reached over ssh",
`hc machine --help`), but the plugin doesn't use it.

## Q3. The fallback: where does `cx.layout:split(…, { command = hc attach … })` run?

**On the host: documented.** "Splits pane target with a new pane on its dir side, on target's host,
in target's directory unless launch.cwd is set" [win]; "A split starts on target's host" [layout].
Seen on a real iPhone: a phone window half's `cx.layout:split` with a command ran on the Mac
[findings § iOS]. The client needs no `hc`.

The route does run on the client: the block's `cx:open` goes to "the windows showing the pane,
through their routes" [blocks], and while handling a block event it "acts in the window that sent
it" [dts `EffectCx:open`]. From a process callback (the plugin's case after `tern split` fails)
there is no sending window, so it goes to every window of the pane's window key [gloss "A host
effect goes to every window with the pane's window key"]: each client showing the session runs the
route and could split once. Inferred.

Two problems in today's fallback on a remote session (inferred from the code and the docs; not
seen):

1. **The `hc` path is the client's.** `attach_command()` in `window.luau` calls `hc_bin()`, which
   reads the client's `HC_BIN`/`HOME`/`LOCALAPPDATA` and checks paths with the client's `tern.fs`
   [io: the window half's files are "the machine the window runs on"]. The command then runs on the
   host. If the client has `~/.local/bin/hc`, the host gets `/Users/<client user>/.local/bin/hc`,
   which may not exist there (different user, Linux host, Windows client). If the client has no
   `hc` (an iPhone), it sends bare `hc`, which works only if `hc` is on the PATH of the host's shell
   for a `-c` command. Fix idea: have the host half put the host's `hc` path in the link
   (`&hc=…`), or have the window half pass a bare command the host resolves.
2. **`target` is a host-side pane id.** The block sends `target=<cx.pane>`, the host's own id. In a
   window, "A remote host's panes carry the host in the high bits of their ids … don't compare ids
   … with ids from the host half" [layout "Ids"]; Lua sees the host's own ids "below 2^44; a remote
   host's tag above it" [limits]. So for a remote session `cx.session:pane(target)` usually finds
   nothing and the route falls back to the focused pane (fine), but if the window also holds a
   **local** pane with the same small id, it splits that local pane and runs `hc attach` on the
   client. Fix idea: drop `target` from the link when `link.host` (or the link pane's host) is
   remote and split `link.pane` instead, or match by host.

The fallback is only reached when the host's `tern` CLI is missing or fails, so the main path is
unaffected.

## What only a two-machine run can settle

Setup: desktop Tern client A attached (`tern remote` / Add remote host) to host B; herdr-core on B
with a few terminals; Herdr Picker 0.5.2 installed on both (unless a step says otherwise). Ideally
also have a Tern window open on B itself showing the same session.

1. **Install matrix.** (a) Plugin on A only: ⌘⇧H toasts "isn't installed on this host"; no "New
   Herdr block" row in A's palette for B. (b) Plugin on B only: A's palette shows "New Herdr block";
   the block lists B's terminals; opening one works with no window half on A. (c) Both: ⌘⇧H opens
   the block in a split on A.
2. **Which herdr-core:** the block's list matches `hc ls` run on B, not on A (use an address only B
   has).
3. **`tern split` from B's daemon:** the new `hc attach` pane appears in A's window in the block's
   place, and runs on B (`hostname` in a pane, or `ps` on B).
4. **`tern focus` from B's daemon:** after opening, A's focus is on the new pane. Repeat with a window
   on B also showing the session: which window(s) get the focus? Also check B's `tern inspect --json`
   to see A's window key on B, and whether the block's `ev.window` is that key.
5. **"Already open":** open the same terminal twice from A; the second time it focuses the existing
   pane (`tern ls --json` on B with `TERN_PANE` sees A's session).
6. **Fallback:** temporarily set `TERN_EXE` to a bad path in B's daemon environment (or rename the
   plugin's `tern` lookups in a throwaway copy), open a terminal from A: does A's route split the
   right pane, does `hc attach` run on B, and does the client-side `hc` path from `attach_command()`
   exist on B? Repeat with a local pane on A whose window id equals the block's host pane id, if one
   can be arranged, to confirm problem 2.
7. **Fallback with no window half on A:** the `tern-herdr-picker:` link goes to the OS; nothing
   opens, and nothing worse happens.
8. **Version skew:** A on 0.5.0 (window half only) with B on 0.5.2: confirm A's ⌘⇧H lists A's
   terminals and opens a broken attach on B, as predicted.
