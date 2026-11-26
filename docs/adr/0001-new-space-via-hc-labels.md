# New spaces are made with hc labels, not herdr-app

`Herdr: new space` starts a Terminal with `hc run --bg` carrying fresh `herdr.space=sp<32 hex>` and `herdr.tab=tb<32 hex>` labels, and lets the Herdr app adopt the unknown ids as a new Space and Tab. We chose this over `herdr-app do space.new` because it needs only herdr-core, so it works while the Herdr window is closed and never moves the person's Herdr view. It leans on adoption behaviour the Herdr app documents in its `AGENTS.md` ("an id Herdr doesn't know becomes a new space or tab") rather than on a command API, so recheck it after a Herdr upgrade.

The plugin reads Spaces the same way. It runs `hc ls --json` (program, status and `where` as hc reports them) and herdr-core's `terminal.list` method through `hc connect` (which carries every label) side by side, joins them by address with `hc ls` leading, and treats Terminals sharing a `herdr.space` label as one Space, named by the first half of their `where`. Pick a pane and new tab both read this joined list. `Herdr: new tab` adds a Terminal with an existing `herdr.space` and a fresh `herdr.tab`. We chose this over reading the `herdr-app` layout document because that document's shape belongs to the Herdr app; the labels are the contract the app itself documents. The cost: a Space with no live Terminal can't be seen, and the Space's own folder isn't known.

## Considered Options

- `herdr-app do space.new --focus false`: names the Space and returns the Terminal address, but fails whenever the Herdr window isn't running.
- Writing herdr-core's `herdr-app` layout document directly: rejected, the newest write wins with no merging, so it would race the Herdr app.

## Consequences

The new Space has no name of its own: Herdr calls it after its first Terminal's repo or folder. Verified 2026-11-24 with herdr-app 0.1.17 and hc 0.1.22 (window open): the Space appeared as `tmp / 1` and the shown Space did not change. Adoption with the window closed is assumed, not tested.

Everything rests on the ids being new. Up to 0.5.0 they came from Luau's `math.random`, which Tern's VM seeds the same way on every load, so a later load could repeat an id and a "new" Space or Tab landed inside an older one (seen 2026-11-26). Since 0.5.1 they come from the OS's random bytes. A Terminal adopted into the wrong Space can't be moved by relabelling it: the app keeps it where it first put it, so it has to be replaced by a new Terminal.
