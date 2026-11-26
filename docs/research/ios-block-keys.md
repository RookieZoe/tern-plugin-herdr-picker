# Why key events from Tern iOS don't reach a plugin block

Research for issue #13 (map: issue #2), after the real-iPhone run of issue #9. Checked on 2026-11-26
against desktop Tern 0.9.35 (`tern --version` → `0.9.35 (ccfae03)`): the online plugin docs, the
changelog and UI strings built into the 0.9.35 macOS binary, the generated `tern.d.luau`, the Mac's
own Tern logs, and Tern's public issue tracker. The earlier notes this builds on are
[tern-ios-plugins.md](tern-ios-plugins.md) and
[tern-ios-picker-block.md](tern-ios-picker-block.md).

The problem (#9): on an iPhone and an iPad running Tern iOS 0.9.33 against a Mac on 0.9.35, no key
from an external keyboard reaches the Herdr block's `key` hook (a `tern.log.warn` at its top logged
nothing), the soft keyboard can't be brought up over the block, and `tern send` on the Mac does
reach the hook. In #7 (Tern iOS 0.9.27) soft-keyboard typing did reach a probe block's hook.

Each claim is marked **documented** (a source says so), **binary** (seen in UI code or strings in
the 0.9.35 macOS binary), **log** (seen in the Mac's own Tern logs), **inferred**, or **unknown**.

## Sources

| Tag | Source |
|---|---|
| [blocks] | Plugin docs, Blocks › "Keys and paste": <https://docs.stencil.so/tern/guides/blocks.html> (also in <https://docs.stencil.so/tern/print.html>) |
| [focus] | Plugin docs, UI nodes › editor › "Focus and the caret" and "Native editing, edit and undo", and the `input` node page, in the print page |
| [tsp] | Plugin docs, Tern Surface Protocol › frame ops (`focus`) and Input and Events › Keys, events table (`focus`), in the print page |
| [ux] | Plugin docs, designing views › "Keyboard" ("Your program owns the keys …"), in the print page |
| [dts] | `tern plugin types plugin` → `plugin/tern.d.luau` (0.9.35): `BlockDef.key`, `BlockDef.features`, `Key`, `UiEvent` |
| [cl x.y.z] | Tern changelog section x.y.z, embedded in the 0.9.35 binary (`strings /Applications/Tern.app/Contents/MacOS/tern`) |
| [bin] | Other strings in the same binary: daemon/remote log messages, the settings doc comments, the feedback dialog |
| [log] | `~/Library/Logs/Tern/tern-daemon.log` and `tern-remote.log` on the Mac (read-only) |
| [#7] | Issue #7's resolution (iOS 0.9.27 probe), also in `docs/tern-plugin-findings.md` § iOS |
| [#9] | Issue #9's resolution (iOS 0.9.33 run of the 0.5.x block) |
| [gh] | Tern's public tracker, <https://github.com/stencil-hq/tern-sdk/issues>, searched 2026-11-26 |

## 1. Known limitation, regression, or the protocol gap?

**Short answer: none of the three is documented. The protocol gap is an unlikely cause; the more
likely one is that the Herdr block has nothing on the phone that can take the keyboard, which the
#7 probe had. A regression in the iOS client is possible but not shown.**

### Nothing in Tern's docs or changelog covers keys into plugin blocks on iOS

- The docs describe key routing only in desktop terms: "When the block's pane has focus, keys reach
  it the way they reach any program: the window's key bindings take the keys they bind first, and
  every other key goes to `key`" [blocks]. No page names a phone, iPad, soft keyboard or hardware
  keyboard for blocks (documented by absence: a search of the whole print page for phone, iPad,
  iOS, keyboard turns up only the plugin-folder, `tern.process`, `tern.fetch` and theme notes).
- The changelog's iOS & Android notes between 0.9.27 and 0.9.35 (the last ones are in 0.9.32
  and 0.9.30; 0.9.33–0.9.35 have none) say nothing about plugin blocks and keys [cl 0.9.28–0.9.35].
  The only plugin-block note for phones in that span is drag-to-reorder "with touch and hold on
  phones" [cl 0.9.32]. So it is **not a documented limitation, and no fix or change is announced**.
- Two older notes bear on it:
  - "Fixed stray link underlines and keyboard pop-ups in chats and plugin blocks" [cl 0.9.16]:
    since 0.9.16 the phone deliberately doesn't raise the keyboard over a plugin block on its own.
  - "Keys typed while a sheet is open on a phone no longer go to the terminal behind it" [cl 0.9.30,
    iOS & Android]: since 0.9.30 (after the 0.9.27 probe, before 0.9.33) an open sheet on a phone
    keeps typed keys from the pane behind it. Whether a plugin block's `picker` in its `layer` (which
    the phone draws as a bottom sheet, see the picker-block research) counts as such a sheet is
    **unknown**; if it does, that would swallow the keys (inferred, a candidate cause).
- No existing report on the public tracker matches (searched "plugin block key", "iOS plugin
  block", "hardware keyboard", "external keyboard", "key hook", "iPad keyboard") [gh]. The nearest
  are macOS-only plugin-key reports (#338 Alt letters, #193 native-editing races) and iOS IME
  reports for omp's composer (#196, #270, #301, #400).

### The protocol gap (65 vs 67) is unlikely to be the cause

- Tern is built to run mixed versions: the daemon logs `client protocol level differs id=… version=65
  daemon=67` at INFO and goes on serving the client [log] [bin]; the remote service logs "a client of
  another handshake version; serving what both know" [log] [bin]. Messages of a newer protocol are
  dropped by the older side ("request of a newer protocol ignored", "daemon message of a newer
  protocol", "reply of a newer protocol ignored") [bin], and features that need a newer level are
  refused by name ("the host's Tern is too old for canvases (protocol level …)") [bin].
- Here the **phone is the older side**, so what it sends (keys) is a message the newer daemon
  knows; only what the daemon sends the phone could be dropped (inferred from the above).
- **During #7 the gap was wider and keys worked.** The Mac's logs show the phone and iPad (two
  remote clients logging in over the LAN at the same moments) as `version=59` against
  `daemon=62` on 2026-11-24, the day of the #7 probe, and as `version=65` against `daemon=67` on
  2026-11-26, the day of #9 [log]. So iOS 0.9.27 speaks protocol 59 and iOS 0.9.33 speaks 65
  (inferred from the dates); a gap of 3 levels didn't stop keys reaching a block.
- **What protocol levels 66 and 67 changed is not documented.** They arrive with desktop
  0.9.34/0.9.35 (the Mac app logged as `version=67` against a still-running `daemon=65` on
  2026-11-26 [log]); those two changelog sections mention no key, input, focus or block-event
  routing change. 0.9.35's plugin items are `actions.outside` and the settings-page search field;
  "Cleaner look for the palette, pickers and dialogs" is cosmetic [cl 0.9.34, 0.9.35].
- In #9 the Mac's log shows **nothing at all** from the block's `key` hook for phone keys [#9], and
  no daemon warning about a refused message [log]. That fits the phone never sending the keys,
  rather than the daemon dropping them (inferred).

### What actually differs between #7 and #9: the block, not just the client

The #7 probe and the 0.5.x block are different blocks, so #7 vs #9 isn't a clean version comparison:

| | #7 probe (iOS 0.9.27) | 0.5.x Herdr block (iOS 0.9.33) |
|---|---|---|
| View | `hc ls` table with buttons, **an `input` node** | a `tern.ui.node("picker", …)` in the **`layer`** region; no `input` or `editor` |
| How the keyboard came up | not recorded, but the `input` "took focus" [#7] | can't be brought up [#9] |
| Keys in `key` | letters, `$`, backspace [#7] | none, soft or hardware keyboard [#9] |

- The docs tie the keyboard to a focused field: the focus op "names the node that owns the caret
  and the IME" [focus] [tsp], and "IME composition happens in Tern's hidden text area" [tsp]. The
  picker "draws no real text field: the search line shows your query with a drawn caret" (quoted in
  the picker-block research). So the Herdr block offers the phone **no field that owns the IME**.
- With the 0.9.16 fix stopping automatic keyboard pop-ups over plugin blocks [cl 0.9.16], the likely
  reading is: in #7, tapping the `input` gave Tern's hidden text area focus, which raised the soft
  keyboard, and keys then went to `key` as the docs say ("Keys still go to your key handler whichever
  field is focused" [focus]). The Herdr block has no such field, so nothing on the phone takes the
  keyboard, and an external keyboard's keys have nowhere to go either (**inferred**; iOS delivers
  keys to whatever holds input focus, and how Tern iOS handles a hardware key with no field focused
  is **unknown**).
- The second candidate is the 0.9.30 sheet rule above: the phone draws the picker as a sheet and may
  keep typed keys from the pane behind it (**inferred**). Both are consistent with the iPad failing
  too, though the iPad drew the desktop-style sheet [#9].
- A plain regression in the iOS client between 0.9.27 and 0.9.33 is **not ruled out**; nothing in
  the changelog points to one.

## 2. Does a block prop or node bring up the soft keyboard and route keys on a phone?

**Not documented for phones. The documented mechanism for "this field takes the keyboard" is an
`input` (or `editor`) node made the focus with the `focus` frame op; that is the one thing worth
trying.**

- There is **no block-level prop** for focus or the keyboard. `BlockDef` has `init`, `view`, `title`,
  `key`, `event`, `features`, `mode`, `chat`, `font` and resize/save hooks; none mentions a keyboard,
  focus or phone [dts]. `Key` is `{name, text, ctrl, alt, shift, meta}` [dts].
- **`input` node**: "A one-line field in a tinted well … Build it: `tern.ui.node("input", { text = …,
  cursor = … })`", focused with `cx:frame({ { "focus", "main.query" } })` [focus]. The focus op
  "names the node that owns the caret and the IME. The view diff never sends it, so a block sets it
  with a raw op" [focus]; frame op `["focus", id|null]`: "The editor or input that owns the caret and
  IME, or none" [tsp].
- A tap on an unfocused, non-readonly field sends `{ev = "focus", id = …}`: "A click asked for the
  keys … Move your focus there (and answer with a focus op), or ignore it: a modal overlay keeps the
  keys" [tsp] [focus]. The #7 probe's `input` "took focus but showed no text and sent no `edit`
  events" [#7]; whether it answered the `focus` event with a focus op isn't recorded.
- Keys still go to `key`, not to the field: "Focus only decides which field shows the live caret.
  Keys still go to your key handler whichever field is focused" [focus]; "Your program owns the
  keys: they reach a block's key handler … never a node" [ux].
- **`features = { "edit" }`** opts into native editing (a click places the caret, edits arrive as
  `edit` events) [dts] [focus], and only "while the user's Settings › Terminal › Native composer
  editing is on" [focus]. Without it, "every key … reaches your key handler" [focus], which is what
  the block wants; so `edit` isn't needed for keys, and #7 saw no `edit` events without it [#7].
- `chat = true` makes the block a chat (transcript + composer) [dts]; omp chats get the phone's key
  row [cl 0.9.27]. Whether a plugin chat block gets the key row or the keyboard on a phone is
  **unknown**, and it would change how Tern draws the whole block, so it doesn't suit a picker.
- **What would bring the keyboard up on a phone (inferred, untested):** an `input` node (say the
  picker's query mirrored into `dock` or `main`), made the focus with `cx:frame({{"focus", id}})`,
  either at once or when its `focus` event arrives from a tap. That is exactly the shape that worked
  in #7. Whether the focus op alone (no tap) raises the iOS keyboard is **unknown**; the 0.9.16 fix
  suggests Tern may want a tap first.
- The phone's settings carry an IME switch and the custom key row, both for terminal panes and
  composers ("Input methods … compose in terminal panes, programs' composers included"; "Keys of your
  own on the phone's key row") [bin]. Neither is documented for plugin blocks.

## 3. Is an upstream report the way forward?

**Yes, once one cheap device test has separated the causes above. Nothing has been filed.**

- **Where:** Tern's public tracker is the GitHub repository **stencil-hq/tern-sdk**, Issues
  (<https://github.com/stencil-hq/tern-sdk/issues>, issues enabled and in active use) [gh]. App bugs are
  filed there with a bracketed prefix, e.g. `[app][iOS] …`, `[app][plugins][macOS] 0.9.21: …` [gh].
  The repo's README gives no reporting guidance and there's no issue template [gh].
- **In-app:** desktop 0.9.34 added "Report an issue or performance problem (palette): send feedback,
  a screenshot or a short performance recording to the Tern team from Tern" [cl 0.9.34]; the dialog
  says "Tern adds its version, your system and its recent log" [bin]. The phone's 0.9.33 predates it
  (inferred). Sending from the Mac would attach the Mac's logs, which hold the `protocol level
  differs` lines but no trace of phone keys.
- **What a report would contain** (title in the tracker's style, e.g. `[app][iOS][plugins] 0.9.33:
  keys from the soft or a hardware keyboard never reach a plugin block's key hook; 0.9.27 did`):
  1. Versions: Tern iOS 0.9.33 (protocol 65) on iPhone and iPad, Mac 0.9.35 (protocol 67).
  2. A minimal host-half block: one with only a `key` hook that logs `key.name`, and one with a
     `picker` in `layer` (the Herdr block's shape); say which one fails.
  3. Steps: open the block from the drawer search on the phone; type on an external keyboard; try to
     bring up the soft keyboard.
  4. Expected: keys reach `key` as for any focused pane, as `tern send <block> keys down` does from
     the Mac. Actual: the hook logs nothing; the soft keyboard can't be raised.
  5. Contrast: iOS 0.9.27 delivered soft-keyboard keys to a block with an `input` node.
  6. Questions to ask: how a phone should raise the keyboard over a plugin block with no text field
     (and whether the focus op on an `input` does it); whether a `picker` in `layer` counts as a phone
     sheet under the 0.9.30 rule and keeps keys from the block; whether a hardware keyboard should
     reach a focused block pane with no field.
- **Before filing, one test on the phone settles which case it is** (inferred, cheap): add a
  throwaway `input` node to a block, answer its `focus` event with `cx:frame({{"focus", ev.id}})`,
  and tap it on iOS 0.9.33.
  - Keys arrive → not a regression; the Herdr block just needs a field to own the keyboard. The
    report becomes a docs/feature request ("say how a block takes the phone's keyboard"; "let a
    `picker` search line take it").
  - Keys arrive in a block without the picker, but not with it → the picker sheet keeps the keys;
    report that.
  - Nothing arrives even then → a regression since 0.9.27; report it as above.

## For the Herdr block on a phone (issues #14, #15)

- Assume **keys won't come back on their own**: no documented change is coming, the block has no
  field that can take the phone's keyboard, and the phone's TestFlight build lags desktop. The
  touch path already works end to end [#9]; design the phone experience around taps.
- Typing to filter on a phone would need a focusable `input` (with the focus op), which is an
  experiment, not a documented feature.
