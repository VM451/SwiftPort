# Verification

Shared UI contract and visual regression infrastructure.

## Contracts/

`Contracts/*.json` are deterministic state fixtures — the single source of
truth every platform must render identically. Each file describes one
`TaskPhase` (`loading`, `empty`, `loaded`, `error`) plus tasks/error data.

Run them:

```sh
swiftport verify --mode contracts
```

Adding a fixture = adding a JSON file. Every platform's contract tests and
snapshot runner pick it up automatically — that is the point: a new state
cannot ship on one OS while silently missing on another.

## Snapshots/

Golden PNGs per platform, blessed explicitly:

```sh
swiftport verify --mode snapshots --update-snapshots   # bless current renders
swiftport verify --mode snapshots                      # compare (local gate)
swiftport verify --mode snapshots --capture-only       # capture without compare (CI)
```

Apple matrix per scenario (filenames encode the variant):

- themes: `light`, `dark`
- viewports: `compact` (480×360), `standard` (800×600), `expanded` (1200×800)
- stress variants on `standard`: `rtl` (right-to-left), `de` (German
  locale), `bold` (bold text weight). macOS `ImageRenderer` ignores
  `dynamicTypeSize`/`font` environment keys, so Dynamic Type coverage
  lands with the iOS capture path.

Example: `populated__dark__standard__largeType.png`

- `apple/` — macOS renders from `Apps/Apple`'s `snapshot-runner`.
  iOS goldens land with device/simulator capture.
- `current/` — gitignored; latest capture for diffing.

Golden comparison is machine-sensitive — font rasterization differs across
macOS versions and GPUs. Bless and compare on the same class of machine;
CI captures the matrix as artifacts rather than diffing foreign renders.

Pixel tolerance comes from `swiftport.toml` (`verify.snapshot_tolerance`,
default `0.001` = 0.1%). Any intentional UI change requires re-blessing —
that is the human sign-off the PRD mandates.
