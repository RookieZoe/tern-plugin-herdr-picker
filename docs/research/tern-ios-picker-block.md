# What Tern iOS's current release does with a 0.5.x picker block

Research for issue #8 (map: issue #2), for the real-iPhone run in issue #9. Checked on 2026-11-26
against desktop Tern 0.9.35 (`tern --version` → `0.9.35 (ccfae03)`), the online plugin docs, the
changelog and UI code built into the 0.9.35 macOS binary, Tern's build site and the App Store.

The block in question: plugin 0.5.2's Herdr block, a host-half block whose view puts
`tern.ui.node("picker", …)` in its `layer` region (`size = "md"`, or `"screen"` when
`cx.rows < 28`; `layout = "tree"` and `tabs` in the pane step; `actions` Close/Back (`esc`),
Choose (`enter`), Create here (`cmd`+`enter`); `mark = {icon = "provider:<id>"}` logos). It reads
every key in its `key` hook and every tap as a `select` / `activate` / `action` event, and opens a
pane with `tern split <cx.pane> right --json -- /bin/sh -c "printf OSC 7501 idle; exec hc attach"`,
`cx:exit(0)`, then `tern focus <block>` (`TERN_PANE` set to the new block).

Each claim is marked **documented** (a source says so), **binary** (seen in UI code or strings in the
0.9.35 macOS binary, which also carries the phone layout that `tern web serve` uses on a phone; the
iOS app is a separate build, so treat this as strong evidence, not proof), **inferred**, or **not
documented**.

## Sources

| Tag | Source |
|---|---|
| [arch] | Plugin docs, Architecture: <https://docs.stencil.so/tern/concepts/architecture.html> |
| [matrix] | Plugin docs, Support Matrix: <https://docs.stencil.so/tern/concepts/support-matrix.html> |
| [blocks] | Plugin docs, Blocks ("Opening blocks", "Keys and paste"): <https://docs.stencil.so/tern/guides/blocks.html> |
| [picker] | Plugin docs, UI nodes › picker (Lists, Menus and Navigation), in <https://docs.stencil.so/tern/print.html> |
| [tsp] | Plugin docs, Tern Surface Protocol › Input and Events (`resize` event), in the same print page |
| [cli] | `tern focus --help`, `tern split --help` (0.9.35) |
| [cl x.y.z] | Tern changelog section x.y.z, embedded in the 0.9.35 binary (`strings /Applications/Tern.app/Contents/MacOS/tern`); the same text Tern shows after an update |
| [css] | `omp-phone-pickers.css` and the picker renderer's strings in the 0.9.35 binary |
| [set] | Settings text in the 0.9.35 binary (General › Closing) |
| [build] | <https://build.stencil.so/tern> and its API `https://build.stencil.so/api/products` |
| [store] | iTunes Search API (`itunes.apple.com/search`, US store), queried for "tern", "tern stencil", "tern terminal" |
| [#7] | The real-iPhone probe of issue #7 (Tern iOS 0.9.27), as recorded in `docs/tern-plugin-findings.md` § iOS |

## 1. Which iOS version is current, and does it render the `picker` node?

### The current iOS version: not publicly documented

- Tern iOS is not on the App Store. No Stencil app named Tern turns up in the store search [store]. It
  ships through **TestFlight**: "Every release on mobile: iPhone and iPad through TestFlight, Android
  as an APK on build.stencil.so" [cl 0.9.0]; the pairing dialog says "No Tern on your phone yet? Get
  it at build.stencil.so/tern: TestFlight on iPhone and iPad, an APK on Android." [bin strings]
- The build site doesn't say which build is current without a sign-in: `/api/products` lists Tern as
  `"public": false, "access": false, "latest": null`, and `/api/products/tern/builds` answers
  `{"error":"unauthenticated"}` [build]. So **the current iOS version number and its date are not
  documented** anywhere public.
- The newest changelog section is **0.9.35**, the desktop version installed here. 0.9.33–0.9.35 carry
  no "iOS & Android" notes; the last ones are in 0.9.32 and 0.9.30 [cl]. "Every release on mobile"
  notwithstanding, the phone has lagged: on 2026-11-24 the phone's TestFlight offered 0.9.27 while the
  Mac ran 0.9.32 [#7]. **The real-iPhone run must read the version off the phone.**

### Does it render the `picker` node?

- **Plugin blocks show on iOS: documented.** Support Matrix: "Plugin blocks visible — iOS: Yes, from
  attached hosts" [matrix]. A block's view travels as Surface Protocol bytes in the pane's output, so
  "every window attached to the session mirrors the block, and so do iOS and the web tab" [arch].
- **The `picker` node on a phone: not documented in the plugin docs.** The picker page names no
  platform limits; the node "is built for omp … and is styled by omp-pickers.css, which is loaded for
  every surface, so it looks the same in a plugin block" [picker].
- **A phone variant of the picker exists: documented for omp, binary for the details.** "omp's
  pickers, panels and questions open as sheets" on phones [cl 0.9.14]. The 0.9.35 binary carries
  `omp-phone-pickers.css` with rules under `html.tn-phone .sf-picker.ph` [css]:
  - the sheet rises from the bottom (`ph-rise`), full width, rounded top, up to 88% of the height,
    with a grab handle (`.pk-grab`) that can be dragged (`ph-held`, `--ph-dy`);
  - `sz-md` is `min(<fit>, 540px)` tall; `sz-screen` gets the modal background;
  - hidden on a phone: the head icon, the count, the scope column, the preview, column heads, the
    **selection bar** (`.pk-selbar`) and every keycap (`.sf-kbd`, `.kbds`, the bar's `esc` button);
  - the head `esc` keycap becomes a text pill (`.pk-done`, "Done"); action-bar buttons are 44 px
    pills, plus a "More actions" button (`.pk-more`); `tabs` become a horizontally scrolling row of
    36 px chips; rows are 16 px text with 18 px rounded highlights, `.cur` rows accent-tinted.
- **Whether a plugin block's picker gets that phone variant (the `ph` class) or the desktop sheet
  squeezed to a phone width: not documented.** Either way it should draw something (inferred). On the
  desktop sheet, the documented narrow rules apply: under 760 px the subtitle hides, under 640 px the
  count hides [picker].
- **`layout = "tree"`, `mark` provider logos: not documented for phones.** The phone stylesheet
  doesn't override `.lay-tree`, `.pk-guides`, `.pk-chev` or `.pk-mark.logo`, so the shared rules draw
  them (binary, inferred). The 0.5.x block also falls back to initials when Tern lacks the logo, as
  on desktop [picker].
- **`size = "md"` / `"screen"`:** both have phone rules [css]. Which one the block picks depends on
  `cx.rows` on the phone (§ 4); not documented.
- **Risk to check (binary, inferred):** the phone hides `.pk-selbar`, the bar the desktop draws for
  `selected`. If nothing else marks `.pk-row.sel` on a phone, the row the block's keys select is not
  visible there, only `current` rows (check marks, tinted). Taps don't need it; typing + Enter does.

## 2. Do taps produce `select` / `activate` / `action` events on iOS?

**Not documented for iOS; inferred yes.**

- The picker's event table is written in clicks: click a row → `select`; click the selected row (or
  the row clicked last) or double-click → `activate`; click a tab → `action` `tab` with `value`; click
  an action-bar button → `action` with its id; click the backdrop or head esc → the escape action's id
  or `close` [picker].
- Tern treats a tap as a click elsewhere on phones: "Agent questions can be answered on iPhone and
  iPad: tapping or clicking an answer picks it" [cl 0.9.11]; "Touch-first phone: every screen is
  reworked for fingers, with rows and buttons big enough to hit" [cl 0.9.14]; plugin blocks' drag
  to reorder works "with touch and hold on phones" [cl 0.9.32]; nodes can carry `actions.hold`, "which
  a phone lists when the node is long-pressed" [cl 0.9.14].
- The phone picker's own controls (binary): the Done pill (`ph-done` beside `close` in the renderer's
  strings), the More actions menu, the drag handle. Whether Done and a drag-down send the block's
  escape action / `close`, and whether one tap on a row sends `select` then needs a second tap for
  `activate` (as on desktop), is **not documented**. With the selection bar hidden (§ 1), "tap once to
  select, again to open" would look like a dead first tap.
- [#7] saw no picker; its `list` node rows and the `key` hook worked from the phone.

## 3. Typing into a block with no real text field

- **The picker draws no text field on any platform: documented.** "It draws no real text field: the
  search line shows your query with a drawn caret, so typing, arrows, Enter and Escape must be handled
  in your block's key handler" [picker]. Keys reach `key` as `{name, text, ctrl, alt, shift, meta}`;
  `meta` is Cmd on macOS; a paste is one call with `name = "paste"` [blocks]. "⌘C, selections and IME
  composition are not offered in the search line" [picker, combobox].
- **The phone's keyboard reaches `key`: seen on a device** (0.9.27) [#7]. A tapped `input` node there
  took focus but showed no text; the picker has no `input`, so that problem doesn't arise.
- **Whether the software keyboard appears over a picker block, and what raises it: not documented.**
  0.9.16 "Fixed stray link underlines and keyboard pop-ups in chats and plugin blocks" [cl 0.9.16],
  i.e. Tern doesn't want the keyboard to pop up on its own over a plugin block. How [#7] raised it
  wasn't recorded. Autocorrect/predictive text, which can send whole words, is not documented for
  blocks.
- **Esc, Tab, Ctrl, Alt, arrows: documented, for terminals.** A key row above the keyboard (esc, tab,
  ctrl, alt, arrows) [cl 0.9.14]; it shows in omp chats too [cl 0.9.27], in landscape and on tablets
  [cl 0.9.19]; custom chords and sequences such as `ctrl+b>%` can be added in Settings › Keyboard ›
  Key row [cl 0.9.19]. **Whether the key row shows over a plugin block: not documented.**
- **⌘ (for Create here, `cmd+enter`): no documented equivalent.** The key row has no ⌘ key, and
  whether a custom key-row entry can be `cmd+enter` is not documented. The action bar's buttons are
  the way (Create here is a tappable button on the phone sheet [css]); keycaps are hidden there.
- **Gestures:** a swipe from the left edge is Tern's Back [cl 0.9.14] (whether a block sees it: not
  documented); the phone picker's drag handle may dismiss the sheet (binary, not documented).
- Backspace: the system keyboard's delete key should arrive as `backspace` (inferred from [#7] seeing
  keys arrive). Going up a folder in New space without a keyboard needs a tappable row or action,
  which 0.5.x has only as keys.

## 4. Where the drawer-search "New … block" places a block on a phone, and its size

- **Placement: not documented for phones.** On desktop the palette's "New *title* block" opens
  "Beside the focused pane, or as the palette's placement modifier says", with no `args` [blocks].
  The phone's drawer search pill stands in for the palette [cl 0.9.14] and finds the host's
  "New … block" rows [#7], but where it puts the block isn't stated. 0.9.35 "New blocks fill a tab in
  neat rows and columns" [cl 0.9.35]. A phone shows one pane of a tab at a time and switches panes
  from the title in the top bar [cl 0.9.14], so a split beside the focused pane would likely fill the
  phone's screen as the tab's visible pane (inferred).
- **Size: documented in principle, numbers not documented.** "A pane shown in several windows
  (another computer, a phone, a browser) has one width, that of the window the user worked in last"
  [tsp]; "a shared pane takes the size of the window you're using" [cl 0.9.6]. So while the phone is
  in use, the block's `cx.cols` / `cx.rows` are the phone's (inferred for `BlockCx`, which re-renders
  on resize [blocks]), and the Mac's window shows it at that size too. The phone's actual row and
  column count is not documented; the 0.5.x block draws `size = "screen"` below 28 rows, `"md"` at 28
  or more, so record `cx.rows` on the phone.

## 5. `tern focus` / `tern split --json` on the Mac, and OSC 7501 on the phone

- **`tern focus` moves one window: documented.** "tern focus BLOCK — its window shows it"; every
  command "works on one window's sessions: --window KEY's, else the window of the pane it runs in (the
  window whose sessions hold $TERN_PANE now, else $TERN_WINDOW_KEY's), else the first window" [cli].
  Focus is per-window UI state: "a window's tabs, focus, palette, keymap … belong to that window"
  [arch].
- **Whether the phone counts as a window the CLI can pick, and which window wins when both the Mac and
  the phone show the session: not documented.** Phone events carry `window = ""` [#7], and `""` is
  the CLI's name for the *first* window [cli], so the CLI can't address the phone by key (inferred).
  0.5.x passes `TERN_PANE` and no `--window`, so `tern focus` may move the Mac's window, not the
  phone's.
- **`tern split` shows on the phone: seen on a device.** The new pane showed "on every window of the
  session, the phone included" [#7]. Whether the phone then shows it or stays where it was is not
  recorded; whether closing the block (`cx:exit(0)`) leaves the phone on the new pane is not
  documented.
- **OSC 7501 reaches the phone: inferred.** The pane's bytes go to every replica, iOS included [arch];
  Tern has shown OSC 7501 program status on pane icons since 0.7.0 [cl 0.7.0]. Desktop asks before closing only "when one
  is busy (a command, an agent mid-turn, an editor); idle shells and agents close at once" [set].
- **Whether the phone honours `state=idle` when closing: not documented**, and may be moot: the phone
  uses "Undo instead of confirmations" [cl 0.9.14], so it may never ask "Close block?" at all. Note
  that `hc attach` could itself print a later OSC 7501 state that overrides the `idle` printed
  before `exec`; whether it does is not documented.

## For the real-iPhone run (issue #9)

Settled before the run:

- Plugin blocks render on iOS; the picker has a phone sheet variant in Tern's UI code (bottom sheet,
  Done pill, chip tabs, button bar, keycaps hidden). Expect that look, or a squeezed desktop sheet.
- No ⌘ equivalent exists: Create here has to be the tappable action-bar button.
- The phone sizes the pane: `cx.rows`/`cx.cols` are the phone's while it's in use.
- The phone version can't be looked up online: note it from the phone (TestFlight lags desktop).

Must-check items to add:

1. Does the selected row show? (The phone hides `.pk-selbar`.) Type to filter, then press Enter:
   does the right row open, and can you see which one?
2. One tap on a row: does it open, or only select (needing a second tap)?
3. Done pill and dragging the sheet down: do they send the block's Close/Back (`close` action), or
   close the whole block, or nothing?
4. Does the key row (esc, tab, arrows) show over the block? Does the keyboard come up at all, and how?
5. `cx.rows` on the phone (portrait, landscape): which `size` does the block pick?
6. After `tern split` + `cx:exit(0)` + `tern focus`: does the phone show the new pane, and does the
   Mac's window jump to it?
7. Closing the attached pane on the phone: a confirmation, an Undo toast, or neither?
