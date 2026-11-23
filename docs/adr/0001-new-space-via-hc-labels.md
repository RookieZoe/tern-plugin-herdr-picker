# New spaces are made with hc labels, not herdr-app

`Herdr: new space` starts a Terminal with `hc run --bg` carrying fresh `herdr.space=sp<32 hex>` and `herdr.tab=tb<32 hex>` labels, and lets the Herdr app adopt the unknown ids as a new Space and Tab. We chose this over `herdr-app do space.new` because it needs only herdr-core, so it works while the Herdr window is closed and never moves the person's Herdr view. It leans on adoption behaviour the Herdr app documents in its `AGENTS.md` ("an id Herdr doesn't know becomes a new space or tab") rather than on a command API, so recheck it after a Herdr upgrade.

## Considered Options

- `herdr-app do space.new --focus false`: names the Space and returns the Terminal address, but fails whenever the Herdr window isn't running.
- Writing herdr-core's `herdr-app` layout document directly: rejected, the newest write wins with no merging, so it would race the Herdr app.

## Consequences

The new Space has no name of its own: Herdr calls it after its first Terminal's repo or folder. Verified 2026-11-24 with herdr-app 0.1.17 and hc 0.1.22 (window open): the Space appeared as `tmp / 1` and the shown Space did not change. Adoption with the window closed is assumed, not tested.
