# Changelog

## 2026-09-23 — third target: strix

The third target is `strix`, a Strix Halo whose GPU serves a model out of system memory. That memory sits in the GTT pool, off the LRU lists, and appears in no `/proc/meminfo` bucket, so an 89 GiB resident model read as ~7 GiB in use on a nearly full machine — a confident wrong answer, which is the failure the panel exists not to give.

### The fold

On a target that declares `unifiedMemory`, GPU-held memory joins in use as a visible, separate GPU category: in use = active + wired + compressed + gpuShared. The gate is the declaration, never the presence of a series: ai-1 publishes the same `homelab_gpu_memory_used_bytes` figures, and folding them would count VRAM twice — once in the memory pane and once in the card's own bar.

A card is keyed on `memory_total_bytes`, so a `used` sample without a `total` draws no card while still raising the memory headline. That is the pane reporting physical occupancy and the band reporting cards, each doing its own job; the partial state is pinned by a test.

### The lone card

The 512 MiB VRAM carveout answers nothing on a Strix Halo; the model lives in the shared pool, so the card reads GTT. This kernel's amdgpu publishes no power cap, so the card renders power without a limit. Until the collector's amdgpu stage deploys, a panel pointed at strix draws no band and no segment — graceful degradation, pinned — while the fixture carries the contract's figures at their live sysfs values so the layout is exercised anyway.

### Landed

- `TargetRegistry` gains `strix`, with `RemoteTarget.unifiedMemory` declared; the memory pane gains the GPU segment and legend where `gpuShared` is non-zero.
- `RemoteMapper` gains the fold in `memory(from:)` and keys `gpus(from:)` on `memory_total_bytes`, the amdgpu contract's absent fields defaulting to zero rather than to a fabricated reading.
- `strix.prom`, a 432-line fixture: a real scrape with the pending amdgpu-stage contract appended, marked as such.
- `Statsy --render <path> --target <id> --fixture <path>`: one frame of a remote layout from a captured scrape, with no host attached. It refuses a fixture that does not carry the target's own collector metrics, so another machine's scrape cannot stand in for it.
- 22 tests added across one new suite and two existing ones. Suite total 129 to 151.

### Not done

The homelab collector's amdgpu stage — the change that makes strix's GPU figures real rather than fixture-pinned — lives in the observability repo and lands there. The contract it must meet is the fixture's five `homelab_gpu_*` series, with no power limit among them.

## 2026-09-21 — the panel gets out of the way of modal alerts

A Finder "empty the Trash?" confirmation opened on the 1280x480 display and vanished under the panel. Finder was app-modal and therefore wedged: no Finder window would open and the Dock icon did nothing, with nothing on screen to explain why. macOS had centred the alert there because the Trash window was parked on that display, and alerts follow their application's key window.

### The level trap

The panel sits at `.statusBar` (25) so the menu bar, which every display gets at `.mainMenu` (24) while "Displays have separate Spaces" is on, does not draw over the header. A modal alert sits at `.modalPanel` (8). Beating the menu bar and letting an alert through are not satisfiable by any one static level, so the level became dynamic.

### Landed

- `StatsyWindowing`, a new target holding both halves the way `StatsyKit` does. `ScreenOccupancy` owns the resting and ducked levels and carries the tests; `WindowListSource` is `CGWindowList` acquisition, untested as the samplers' sources are.
- `PanelWindow` polls every 2s while the panel is on screen, and lowers the window to `.normal` while something in the band is on its display. Lowering rather than ordering out leaves `reposition()` the only owner of presence and of the sampling lifecycle, so ducking cannot stop sampling or make the panel flicker. The poll starts and stops alongside `model.start()`/`model.stop()`, so an absent display costs nothing.
- 14 tests added across 2 new suites. Suite total 115 to 129.

### The band is the whole design

`.normal` exclusive to `.modalPanel` inclusive. Ordinary windows fall below it because sitting above them is the panel's purpose. Everything from `.utilityWindow` (19) up is furniture that never goes away, and ducking for furniture would retire the panel permanently.

The first cut of this ran the ceiling up to `.mainMenu` and carved the menu bar and status items out by hand. That admitted the Dock, which sits at 20 and follows the pointer onto whichever display is active — so the first time the pointer crossed onto the strip the panel would have ducked and stayed ducked, the exact failure the carve-outs existed to prevent. Naming the Dock as a third exception would have been the wrong fix; the band moved instead.

### Measurements

A window-list read costs 0.355ms, best-of-seven over 400 calls at `-O`. At the 2s interval that is 0.018% of a core. Cost is no longer what sets the interval — 2s bounds how long an alert can stay buried and matches `TopProcessSource`.

Walking the list as `NSDictionary` rather than bridging it to `[[String: Any]]` took the read from 1.165ms to 0.355ms. The bridge deep-copies all 63 entries into Swift dictionaries and every one is discarded. Dropping the unused owner-PID lookup was part of the same win.

### Found while measuring

- `NSAlert.window.level` reads 0 before the alert is displayed; the window server reports layer 8 once `runModal` is running. A predicate written from the AppKit value would have matched nothing.
- `CGDisplayBounds` already returns a display's frame in the window server's top-down space, which is what the window list uses. A hand-rolled AppKit-to-window-server flip and the four tests pinning its arithmetic were deleted in favour of it.
- `runModal` re-centres the alert on the key window's screen, discarding a `setFrameOrigin` made beforehand. The first verification run placed its alert on the left-hand display and proved nothing. Repositioning from a timer inside the modal session works.
- Verified end to end against the built bundle: a layer-8 window on the strip took the panel from 25 to 0 within one poll, and back to 25 within one poll of the alert closing.

### Out of scope

A sheet attached to a window parked on that display inherits its parent's level and is indistinguishable from an ordinary window, so the panel will still cover it. Moving the Trash window off the display removed the trigger that started this.

A deeper fix was considered and not taken: put the window at `.floating` (3), below every alert, and inset the content by the menu bar's height so the menu bar covers dead space instead of the header. That deletes this entire subsystem. It costs a header redesign and ~30 of 480 points of panel height permanently, on a display where type is already at 56% of usual physical size, so it is a layout decision rather than a cleanup.

## 2026-09-20 — second target: homelab-ai-1

The panel could only ever show the machine it ran on. It can now be pointed at `homelab-ai-1`, the three-GPU CUDA workstation, and switched back from the menu bar item without restarting anything.

### Transport

Statsy scrapes that host's node_exporter through an `ssh -L` forward. The alternatives were an OTLP pipeline and Grafana's query API. There is no OTLP receiver anywhere in the homelab; the only OpenTelemetry in `brandoncraft-observability` is a Grafana dashboard reading Temporal SDK metrics that arrive by scrape. Standing one up would have meant new services on both ends, and the receiver would have had to live on a laptop that sleeps and changes address. Grafana on `.72:3000` works today but couples the panel to the whole operations stack and needs a token in the Keychain. The forward needs no new listener, no UFW change and no credential inside the app, and it matches the pattern already used for the `.72` to `.73` query proxy.

UFW on `.88` admits port 9100 from the operations host alone, which is deliberate and stays that way. The exporter binds the host's LAN address rather than loopback, so the forward targets `192.168.68.88:9100` from inside the host, not `127.0.0.1`.

### Landed

- `StatsyKit/Remote`: `PrometheusText` (exposition-format scanner), `MetricSet` (name-bucketed lookup), `RemoteMapper` and its two extensions (pure, fixture-tested), `RemoteSnapshotProvider` and `SSHTunnel` (acquisition, untested, as the sources are).
- `SnapshotProvider` is the new seam. `MetricsEngine` conforms in one line, `PanelModel` no longer knows which kind of target it is showing, and `refreshInterval` moved onto the provider so a remote host can be polled at 2s while the local one stays at 1 Hz.
- `StatsyKit/Targets`: `Target`/`RemoteTarget`/`TargetRegistry`, `TargetSelection` (a line of text in Application Support), `TargetWatcher` (directory-watching, so a running panel repoints itself).
- Menu bar item gains a target submenu; `TargetMenuPresentation` in `StatsyControl` carries the decisions and the tests.
- Remote layout: the process lists have nothing to show, so that space becomes a full-width `GPUBand` of three cards with VRAM as the headline, and the ribbon carries service health and freshness instead of fans.
- `Snapshot` gains `gpus`, `services` and `link`; `MachineInfo` gains `host`, `platform`, `ranksProcesses` and a pre-worded `gpuDescription`.
- `statsy-probe --target <id>` and `Statsy --render <path>`, which writes one frame to a PNG at scale 1.0 so a layout can be checked without the 1280x480 display attached.
- 59 tests added across 5 new suites. Suite total 53 to 112.

### Measurements

Steady state on the remote target is 1.42% of one core, inside the 1.5% budget and with no `top` child to pay for. The fixture is a real 2,802-line scrape, reduced to the 598 series the mapper reads and redacted of MAC addresses and GPU serials before going into the repo.

Checked against the host's own tools: memory, swap, GPU VRAM, utilisation, power, temperature, load average, core count and uptime all agree with `free`, `nvidia-smi` and `uptime`. Storage disagreed by 4 GiB on the root volume until the mapper started preferring `node_filesystem_free_bytes`, which separates ext4's reserved blocks from space genuinely in use the way `df` does.

### Found while mapping

- ai-1's `netdev` collector is failing, so there are no per-interface byte counters at all. `node_netstat_IpExt_InOctets`/`OutOctets` carry the host-wide totals the panel actually wants. This is a real gap in the fleet monitoring, independent of Statsy.
- The CPU sensor is `k10temp`, not the `coretemp` the Intel host uses, so thermal mapping keys off `node_hwmon_chip_names` rather than a chip path.
- `acpitz` reports a steady 16.8 C that is not the temperature of anything, and is left unmapped rather than shown as an enclosure reading.
- `/mnt/nas-storage` is an autofs mount that node_exporter never sees. The fleet collector stats it on every run, so volumes fall back to `homelab_storage_*` for mounts the exporter cannot find.
- `CPUCalculator` was discarding a perfectly good load average on the no-baseline path. Local sampling primes its baseline in `start()` so it never showed, but the first remote sample hit it. Fixed at the calculator.

**Review pass** (reuse, simplification, efficiency, altitude)

- The parser now takes a name filter applied before the label block. A scrape is ~2,800 series and the mapper reads about 40; parsing labels for `go_*`, `promhttp_*` and 144 lines of `node_schedstat_*` was most of the cost of a scrape. `RemoteMapper.wants` declares the set, and a test asserts a filtered scrape maps identically to an unfiltered one so a reading can never be added without being declared.
- `MachineInfo.summary` and `platformVersion` are computed once in `init` rather than on every redraw, and `RemoteMapper` caches `MachineInfo` and the hwmon chip-to-cluster map after the first scrape.
- `start()` folds its probe scrape in as the baseline instead of discarding it and immediately re-fetching, and both entry points dropped a throwaway sample that `start()` had already made redundant. Three scrapes at startup became one.
- `GPUCard` was a second copy of `Pane`'s chrome and had already drifted from it by 3pt of padding. `Pane` gained a trailing slot and a subtitle; the card uses it.
- `SectionLabel` absorbed four inlined copies of its own styling.
- Layout predicates were derived four ways from two fields, which gave a GPU-less remote host a layout nobody designed. Each now answers one question: `isLocal`, `showsGPUBand`, `isCompact`, `hasProcessTelemetry`.
- `hasProcessTelemetry` reads `MachineInfo.ranksProcesses` rather than testing for locality, which keeps the `ProcessSource` invariant true: a privileged helper or a Linux process collector can turn the pane back on without the views changing.
- `Snapshot.marking(_:)` replaced an eleven-field rebuild in the stale path, where a forgotten field would have silently blanked a section.
- Smaller: dead `hasReadings`/`isLocal`/`hasBaseline`, a write-only `provider` property, `isRunning` restating `loop != nil`, per-core array literals, a per-line array allocation in the parser, and five grouped dictionaries built to read nine keys.

### Not done

Targets are compiled into `TargetRegistry` rather than read from a config file, and the `homelab_*` prefix is hard-coded in the mapper. For two targets on one machine that is the smaller thing. The parser still converts the 160 KB response to a `String` and scans it as `Character`s; the name filter takes most of the win a UTF-8 rewrite would, and the measured cost is inside budget.

## 2026-09-20 — menu bar controller

Statsy has no Dock icon and no menu bar entry, which is right on its own display and wrong on a laptop. Undocking re-seats the panel onto the built-in screen above the menu bar, where there is no way to quit it short of Activity Monitor. `make-app.sh` now builds a second bundle, Statsy Menu.app, whose only job is to start and stop the panel.

### Landed

- `StatsyControl`: `PanelLocator` (sibling bundle, then Launch Services, then `/Applications`) and `PanelMenuPresentation` (title, icon and enablement per state).
- `StatsyMenu`: `PanelProcess` over `NSWorkspace` and `NSRunningApplication`, `StatusItemController` for the status item and its menu.
- Workspace notifications keep the menu honest when the panel is launched or killed by something else, and `menuNeedsUpdate` re-reads the state on every drop-down.
- Stopping sends `terminate()` and escalates to `forceTerminate()` after 2s.
- `make-app.sh` takes a bundling function and emits both apps, ad-hoc signed, with `LSUIElement` on each.
- 11 tests in 2 suites: `PanelLocatorTests`, `PanelPresentationTests`. Suite total 42 → 53.

The symbol test is worth keeping: a mistyped SF Symbol name yields a blank menu bar item with no error anywhere, so each name is resolved against the running OS rather than trusted.

**Review pass** (reuse, simplification, efficiency, altitude)

- `menu.autoenablesItems = false`. AppKit enables any item with a valid target and action, so the toggle was live in the `.missing` state despite `isEnabled` being false. The only real defect the pass found.
- `refresh` early-returns on an unchanged state. It runs on every menu open, and rebuilding the `NSImage` is ~40 µs of the ~50 µs it costs.
- `PanelLocator.locate` checks its candidates lazily, so the sibling hit no longer pays for a Launch Services query it does not need, and its two filesystem calls now default to the real implementations — the production wiring had been untestable glue in `StatsyMenu`.
- `PanelProcess` caches the resolved bundle URL, re-resolving only once it stops existing.
- `stop()` polls `isTerminated` at 100ms instead of always sleeping out the full 2s grace.
- Dropped: the observer tokens and `deinit` in `PanelProcess` (the object lives for the process), the unused `Equatable` on `PanelMenuPresentation`, and `make-app.sh`'s redundant display-name parameter.
- Added `BundleIdentityTests`, which reads `make-app.sh` and asserts the panel's name and identifier still agree with `PanelLocator`. Renaming one silently breaks the controller with the suite still green. Confirmed to fail on a deliberate rename. 53 → 54 tests.

### Disconfirmed

A force-killed panel was expected to orphan its `top` child, which costs ~6.6% of a core while sampling. It does not: `top` takes SIGPIPE when the panel's pipe closes and exits within one 2s interval. Checked with `kill -9` and recorded as an invariant.

Idle cost of the controller, release build: ~0.04% of one core, 61 MB resident. The memory is what a second always-resident process actually costs here, not the CPU.

### Panel hides when its display is absent

The review's altitude finding was that the controller treated a symptom. `targetScreen()` fell back to any external display and then to the built-in one, so undocking re-seated the panel onto the laptop screen above the menu bar; the menu bar item made that dismissable but did not stop it happening.

- `targetScreen()` now matches 1280x480 exactly and returns nil otherwise. The `isBuiltIn` CoreGraphics check went with the fallback it existed for.
- `reposition()` orders the window out and stops the model when there is no target, and starts it again when one appears. The `didChangeScreenParametersNotification` observer was already wired up, so dock and undock are handled without new machinery.
- `PanelWindow` now owns the sampling lifecycle; `AppDelegate` no longer calls `model.start()`. An invisible panel that kept paying for `top` would defeat the point.

Verified both directions on a machine with no 1280x480 display: launching draws nothing, spawns no `top` child and sits at 0.0% CPU. Retargeting `PanelView.size` to the attached 2560x1440 display temporarily confirmed the window appears with live data and the `top` child starts.

## 2026-08-28 — pressure-oriented memory headline

- Changed the hero percentage from `top`-style used memory to **in use** memory
  (active + wired + compressed), so inactive memory no longer makes a healthy
  machine look nearly exhausted.
- Kept inactive pages visible as a separate `RECL` segment and renamed the
  underlying metrics to encode the distinction between in-use, reclaimable,
  and free memory.
- Updated `statsy-probe` to print both in-use and reclaimable memory. Live host
  verification reported 67 / 128 GiB in use with 58 GiB reclaimable.

## 2026-08-18 — initial build

Panel app for the 7-inch 1280x480 secondary display, built to the "Instrument"
layout chosen from four design directions: three metric columns
(CPU / memory / storage), each with a hero figure and a top-five process list,
over a full-width thermal and fan ribbon.

### Landed

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

### Performance

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

### Correctness of presentation

- The temperature colour ramp (30–90 °C) and the track beneath it (20–100 °C)
  disagreed about what counted as hot. Both now consume
  `Theme.temperatureFraction`.

### Removed

- `RingBuffer`, `Snapshot.cpuHistory` and the engine plumbing behind them: a
  complete history pipeline maintained every second with no consumer, since the
  chosen layout has no sparkline. `MachineInfo.coreCount` likewise unread.
  Test count 46 → 42, all of the difference being tests for the deleted type.

### Structure

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

### Skipped

- Caching volume capacity behind a refresh interval (9–25 µs/sample — the
  staleness is not worth the state).
- Storing each sensor's cluster on `SensorKey` to avoid re-deriving it from the
  key string (6 µs/sample, and it would couple the SMC layer to the calculator's
  classification).
- Moving `MachineInfo.summary`/`uptimeDescription` out of the kit — the panel and
  `statsy-probe` are two genuine consumers of the same strings.
