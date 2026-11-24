# Golden snapshots

Commit blessed PNGs here. Layout: `<scenario>__<theme>.png`
(e.g. `populated__dark.png`), rendered at 2x by `snapshot-runner`.

First-time setup:

```sh
swiftport verify --mode snapshots --update-snapshots
```

then commit the PNGs this produces. CI compares every PR against them.
