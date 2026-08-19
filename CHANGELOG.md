# Changelog

## 2026-08-18 — initial build

Panel app for the 7-inch 1280x480 secondary display, built to the "Instrument"
layout chosen from four design directions: three metric columns
(CPU / memory / storage), each with a hero figure and a top-five process list,
over a full-width thermal and fan ribbon.

**Landed**

- `StatsyKit`: sampling for CPU ticks, VM counters, swap, storage capacity and
  throughput, SMC temperatures and fans, network totals, and process ranking.
- `MetricsEngine` actor at 1 Hz; `PanelModel` publishes snapshots to SwiftUI.
- `PanelWindow` places a borderless window on the display matching the panel's
  exact pixel size, and re-seats it on display hot-plug.
- `statsy-probe` diagnostic CLI; `make-app.sh` bundles `Statsy.app` (LSUIElement).
- 46 tests across 10 suites: RingBuffer, Format, CPUCalculator,
  MemoryCalculator, ThermalCalculator, RateCalculator, TopParser,
  TopStreamParser, ProcessTable, SMC layout.

**Platform findings** (detail in `docs/sampling.md`)

Five places where the obvious API is wrong, each caught by checking against the
system tool rather than by reading docs:

1. Omitting inactive pages under-reports memory by ~44 GB.
2. Unprivileged libproc cannot see root-owned processes, so `top` is required.
3. Swift reused a C struct's tail padding, shortening the SMC request to 76 bytes.
4. `statfs` cannot distinguish APFS volumes sharing a container.
5. `NET_RT_IFLIST2` wraps at 4 GiB despite declaring 64-bit counters.

**Verified against** `top` (memory used, exact), `df` (capacity and per-volume,
exact), `netstat -ib` (network, exact), Stats.app's `smc` (GPU/SSD/battery
temperatures, exact).

Measured cost: 0.8% of one core for the app plus 0.2% for its `top` child,
59 MB resident — about 0.06% of an 18-core machine.

## 2026-08-18 — cleanup pass

Four-angle quality review (reuse, simplification, efficiency, altitude) over the
whole tree, then applied. The efficiency pass benchmarked the sampling paths
rather than estimating them, which reordered the priorities.

**Performance**

- Thermals decimated to a 5s cadence: the 130-key SMC read was 85% of the app's
  CPU and blocked the engine actor 17ms of every second.
- `SMCReader` construction moved from `init` to `start()`, off the main thread —
  it was costing ~0.5s of dead time before the window appeared.
- `top` column ranges resolved once per header instead of searched per field per
  row (~20k string comparisons per block).
- Storage now fetches only the driver's `Statistics` property rather than copying
  and bridging every property to read two numbers.
- `SegmentedBar` no longer mints a UUID per segment per frame; `CoreGrid` builds
  its divider set once per render instead of once per core; `ProcessList`
  computes its peak once instead of once per row.

App CPU dropped 0.8% → 0.2% of one core.

**Correctness of presentation**

- The temperature colour ramp (30–90 °C) and the track beneath it (20–100 °C)
  disagreed about what counted as hot. Both now consume
  `Theme.temperatureFraction`.

**Removed**

- `RingBuffer`, `Snapshot.cpuHistory` and the engine plumbing behind them: a
  complete history pipeline maintained every second with no consumer, since the
  chosen layout has no sparkline. `MachineInfo.coreCount` likewise unread.
  Test count 46 → 42, all of the difference being tests for the deleted type.

**Structure**

- `ProcessSource` now yields unranked samples; `MetricsEngine` ranks. The seam
  previously sat above the ranking policy, so a privileged helper would have had
  to reimplement it — the opposite of what the seam is for.
- `VolumeUsage` carries a `role`; `Theme` maps role to colour. The pane had been
  switching on volume-name strings owned by another target.
- Display selection asks CoreGraphics which screen is built in, rather than
  comparing against `NSScreen.main`, which follows keyboard focus and could
  re-seat the panel onto the wrong display on hot-plug.
- Shared `Double.clamped01`, one `Format.decimal`, one scaling primitive behind
  `binary`/`rate`, and `MachineSource` reusing `HostSource`'s sysctl wrappers.

**Skipped**

- Caching volume capacity behind a refresh interval (9–25 µs/sample — the
  staleness is not worth the state).
- Storing each sensor's cluster on `SensorKey` to avoid re-deriving it from the
  key string (6 µs/sample, and it would couple the SMC layer to the calculator's
  classification).
- Moving `MachineInfo.summary`/`uptimeDescription` out of the kit — the panel and
  `statsy-probe` are two genuine consumers of the same strings.
