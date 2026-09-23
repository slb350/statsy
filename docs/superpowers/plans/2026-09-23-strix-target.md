# Strix Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Point the panel at `strix` (Strix Halo, unified memory) with an honest memory headline — GPU-resident memory folded in as a visible fourth in-use category — and a lone GPU band card that reads GTT rather than VRAM.

**Architecture:** All acquisition already exists (`SSHTunnel` → `RemoteSnapshotProvider` → `RemoteMapper`); this change adds a target declaration, a declared `unifiedMemory` flag that drives a new `MemoryMetrics.gpuShared` fold and the GPU card's memory label, and a fixture path through `--render`. The fleet collector's amdgpu stage does not exist yet and is **out of scope** — its contract is pinned by a fixture and tests, and the panel degrades gracefully (no band, no fold) until it deploys.

**Tech Stack:** Swift 6, Swift Testing (`swift-testing`), SwiftUI views (untested by repo convention, verified by PNG render), Prometheus text exposition fixtures.

**Spec:** `docs/superpowers/specs/2026-09-23-strix-target-design.md`

## Global Constraints

- `Memory In Use = active + wired + compressed` holds on every existing target; on a declared unified-memory target it becomes `active + wired + compressed + gpuShared`. The fold keys off `target.unifiedMemory`, **never** off the presence of a `homelab_gpu_memory_used_bytes` series — ai-1 publishes that series (discrete VRAM) and must fold nothing (`gpuShared == 0`).
- The strix tunnel facts: `sshUser: "steve"`, `sshHost: "192.168.68.63"`, `exporterHost: "192.168.68.63"`, default port 9100, `localPort: 19163` (ai-1 owns 19100).
- The GPU memory contract is **GTT, not the 512 MiB VRAM carveout**: `memoryTotal > 120 << 30` on strix. Card subtitle is `GTT` on unified targets, `VRAM` otherwise. amdgpu on this kernel publishes no power cap: `wattLimit == 0` renders as `"6 W"`, never `"6 / 0 W"`.
- Fixture values come from the live host at capture time (SSH `steve@192.168.68.63`, key auth, `BatchMode=yes`). Tests must not hardcode capture-dependent magnitudes where the fixture itself can supply the expectation.
- No changes to `~/dev/homelab/**` or `~/dev/strixtea/**` — those repos are being refactored in another session. No changes to `RemoteMapper.wants`, `SSHTunnel`, `RemoteSnapshotProvider`, `MetricsEngine`, or any local (macOS) sampler.
- Repo conventions: calculators/mappers pure and fixture-tested; sources verified against CLI tools; views verified by `--render` PNG; every invariant that lands in code also lands in `AGENTS.md`; `swift build && swift test` green before every commit.
- Panel geometry is sacred: 1280x480 at scale 1.0, type deliberately large. Do not "fix" sizes.

## Review Focus

1. **Unified fold double-counts on ai-1** — fold gated on series presence instead of the declaration. Pinned by `RemoteMapperStrixTests.noUnifiedFoldOnDiscreteHosts` (maps the strix fixture through ai-1's target: gpu cards present, gpuShared still 0).
2. **A scrape that carries a GPU series with garbage (negative/NaN)** — `RemoteMapper.bytes` guard bypassed by summing raw values. Pinned by `RemoteMapperStrixTests.unifiedFoldDiscardsNonFiniteValues` (fixture mutated to negative value → fold contributes 0 from that sample).
3. **The fold breaks the pane on every non-unified target** — segment/legend added unconditionally. Pinned by `MemoryMetrics.gpuShared == 0` on ai-1 plus render comparison in Task 5.
4. **`memory(from:)` signature change missed a caller** — stale `Self.memory(from:)`. Pinned by `swift build` in Task 3 (compile error is the test).
5. **Lone-card layout renders stretched or off-centre** — width cap or alignment dropped. Pinned by Task 5's PNG renders (`/tmp/strix-layout.png` read by the controller, ai-1 render compared unchanged).

---

### Task 1: Registry entry and the unified-memory declaration

**Files:**
- Modify: `Sources/StatsyKit/Targets/Target.swift`
- Test: `Tests/StatsyKitTests/TargetSelectionTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `RemoteTarget.unifiedMemory: Bool` (stored property, init parameter `unifiedMemory: Bool = false` after `collectorPrefix`); `TargetRegistry.strix: Target`; `TargetRegistry.all == [local, homelabAI1, strix]`. Later tasks read `TargetRegistry.strix.remote!` and `target.unifiedMemory`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/StatsyKitTests/TargetSelectionTests.swift`, inside the suite, after `exporterBinding()`:

```swift
    @Test("strix resolves, binds its exporter to its LAN address, and owns its own tunnel port")
    func strixResolves() throws {
        let target = try #require(TargetRegistry.target(id: "strix"))
        let remote = try #require(target.remote)
        // Same bind pattern as ai-1: the exporter listens on the LAN address,
        // so the tunnel lands on it from inside the host.
        #expect(remote.sshUser == "steve")
        #expect(remote.sshHost == "192.168.68.63")
        #expect(remote.exporterHost == "192.168.68.63")
        #expect(remote.exporterPort == 9100)
        #expect(remote.localPort == 19163)
        #expect(remote.localPort != TargetRegistry.homelabAI1.remote?.localPort)
        #expect(remote.metricsURL?.absoluteString == "http://127.0.0.1:19163/metrics")
    }

    @Test("strix declares unified memory; ai-1 stays discrete")
    func unifiedMemoryDeclaration() throws {
        #expect(try #require(TargetRegistry.strix.remote).unifiedMemory)
        #expect(!try #require(TargetRegistry.homelabAI1.remote).unifiedMemory)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TargetSelectionTests`
Expected: FAIL — `strixResolves` and `unifiedMemoryDeclaration` fail (`TargetRegistry.target(id: "strix")` is nil, `unifiedMemory` does not exist → the second is a compile error, which is the failing state).

- [ ] **Step 3: Implement**

In `Sources/StatsyKit/Targets/Target.swift`, add to `RemoteTarget` after the `collectorPrefix` property:

```swift
    /// Whether the GPU draws from system memory rather than its own VRAM.
    ///
    /// A unified-memory host serves models out of the GTT pool, which
    /// `/proc/meminfo` reports in no bucket at all: with 89 GiB of model
    /// resident, the buckets read 7 GiB in use. Declared rather than inferred
    /// from a series' presence, because homelab-ai-1 publishes GPU memory
    /// figures too — discrete VRAM its own card already accounts for.
    public let unifiedMemory: Bool
```

Add to `RemoteTarget.init`, parameter `unifiedMemory: Bool = false` after `collectorPrefix: String = "homelab_"`, assignment `self.unifiedMemory = unifiedMemory` after `self.collectorPrefix = collectorPrefix`.

Add to `TargetRegistry` after `homelabAI1`, and extend `all`:

```swift
    public static let strix = Target(
        id: "strix",
        name: "strix",
        source: .remote(
            RemoteTarget(
                // Same shape as ai-1: the exporter binds its LAN address and
                // UFW keeps it narrow, so the tunnel lands on it from inside.
                sshUser: "steve",
                sshHost: "192.168.68.63",
                exporterHost: "192.168.68.63",
                localPort: 19163,
                hostName: "strix",
                model: "Ryzen AI Max 395 16C/32T",
                gpuDescription: "Radeon 8060S 128 GB (unified)",
                volumes: [
                    RemoteVolume(mountPoint: "/", name: "Root", role: .system),
                    // NFS from BabyNas; a network volume stays out of the
                    // storage headline the way ai-1's NAS does.
                    RemoteVolume(
                        mountPoint: "/mnt/coldstore", name: "Coldstore", role: .network
                    ),
                ],
                diskDevice: "nvme0n1",
                unifiedMemory: true
            )
        )
    )

    public static let all: [Target] = [local, homelabAI1, strix]
```

(Replace the existing `all` declaration with the one above.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TargetSelectionTests`
Expected: PASS, all tests including the two new ones.

- [ ] **Step 5: Run the full suite**

Run: `swift build && swift test`
Expected: PASS (130 + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatsyKit/Targets/Target.swift Tests/StatsyKitTests/TargetSelectionTests.swift
git commit -m "feat(targets): register strix and declare its unified memory"
```

---

### Task 2: Strix fixture and the baseline mapper suite

**Files:**
- Create: `Tests/StatsyKitTests/Fixtures/strix.prom`
- Create: `Tests/StatsyKitTests/RemoteMapperStrixTests.swift`

**Interfaces:**
- Consumes: `TargetRegistry.strix` from Task 1; the existing `RemoteMapper` API unchanged.
- Produces: fixture resource `strix` (loadable via `Bundle.module`, subdirectory `Fixtures`); `RemoteMapperStrixTests.metrics`, `.target`, `.captured`, `mapped()` — Task 3 and 4 tests are appended to this file and reuse them.

- [ ] **Step 1: Capture the live scrape**

Run (from the worktree root; the host is reachable and key-auth works):

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 steve@192.168.68.63 \
  'curl -s --max-time 5 http://192.168.68.63:9100/metrics' > /tmp/strix-full.prom
wc -l /tmp/strix-full.prom   # expect thousands of lines
```

- [ ] **Step 2: Reduce to the series the mapper reads, then append the GPU contract**

Write `Tests/StatsyKitTests/Fixtures/strix.prom` with this header, the filtered scrape, then the contract block:

```
# Captured from strix with `curl http://192.168.68.63:9100/metrics`, reduced
# to the series RemoteMapper reads, in the manner of homelab-ai-1.prom.
# The GPU series at the end are NOT on this host yet: they are the contract
# for the fleet collector's amdgpu stage (homelab/observability), with
# values captured from /sys/class/drm/card0/device at fixture time. The
# memory figures are GTT — the shared pool the model is served from — not
# the 512 MiB VRAM carveout. No power limit is published: this kernel's
# amdgpu exposes no cap.
```

Keep these lines from the capture (drop everything else, including `# HELP`/`# TYPE` and other `node_*` series, matching the ai-1 fixture's reduction):

```bash
grep -E '^(homelab_|node_cpu_seconds_total|node_load[0-9]|node_boot_time_seconds|node_uname_info|node_hwmon_temp_celsius|node_hwmon_chip_names|node_disk_read_bytes_total|node_disk_written_bytes_total|node_netstat_IpExt_|node_filesystem_|node_memory_|node_scrape_collector_success)' /tmp/strix-full.prom > /tmp/strix-reduced.prom
```

Append the contract block, substituting the live sysfs values (read them now, they change):

```bash
ssh -o BatchMode=yes steve@192.168.68.63 '
cat /sys/class/drm/card0/device/gpu_busy_percent
cat /sys/class/drm/card0/device/mem_info_gtt_total
cat /sys/class/drm/card0/device/mem_info_gtt_used
cat /sys/class/drm/card0/device/mem_info_vram_used
cat /sys/class/drm/card0/device/hwmon/hwmon*/power1_average
cat /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input'
```

```prometheus
homelab_collector_success{asset_host="strix",collector="gpu"} 1
homelab_gpu_utilization_percent{asset_host="strix",gpu="0"} <gpu_busy_percent>
homelab_gpu_memory_total_bytes{asset_host="strix",gpu="0"} <gtt_total>
homelab_gpu_memory_used_bytes{asset_host="strix",gpu="0"} <gtt_used + vram_used>
homelab_gpu_power_watts{asset_host="strix",gpu="0"} <power1_average / 1000000>
homelab_gpu_temperature_celsius{asset_host="strix",gpu="0"} <temp1_input / 1000>
```

Sanity-check the reduction before writing the fixture file (all must hold; if one fails, the filter dropped something — fix the filter, not the test):

```bash
grep -c '^node_cpu_seconds_total' <fixture>         # 256 (32 threads x 8 modes)
grep -c '^node_hwmon_chip_names' <fixture>          # 6 (amdgpu, mt7925_phy0, nvme, k10temp, r8169, acpitz)
grep -c '^node_memory_' <fixture>                   # dozens, MemTotal present
grep -q 'mountpoint="/"' <fixture>                                # node_filesystem for /
! grep -E '^node_filesystem_[a-z_]+\{[^}]*mountpoint="/mnt/coldstore"' <fixture>   # automount: absent from node_filesystem_*
grep -q 'homelab_storage_available_bytes{asset_host="strix",mountpoint="/mnt/coldstore"' <fixture>
grep -q 'homelab_service_http_ready{asset_host="strix",service="flash-next"}' <fixture>
```

Note the fixture's `homelab_collection_timestamp_seconds` value: use it (integer part) as `captured` in the test file so collection-age assertions are sane.

- [ ] **Step 3: Write the baseline tests**

Create `Tests/StatsyKitTests/RemoteMapperStrixTests.swift`:

```swift
import Foundation
import Testing
@testable import StatsyKit

/// The strix target, exercised against a scrape the host actually produced.
///
/// Strix is the unified-memory shape: a Strix Halo serving a model out of a
/// GTT pool `/proc/meminfo` does not see, with GPU figures arriving from the
/// fleet collector's amdgpu-stage contract pinned into this fixture. The
/// readings that break here are the ones ai-1 cannot produce — a lone GPU
/// whose memory is system memory, an NFS automount, GPU temperature arriving
/// from the textfile beside an amdgpu hwmon chip the cluster map must ignore.
@Suite("Remote mapper — strix")
struct RemoteMapperStrixTests {
    static let metrics = MetricSet(text: fixture())
    static let target = TargetRegistry.strix.remote!
    /// Just after the fixture's textfile stamp, so ages come out sane.
    static let captured = Date(timeIntervalSince1970: 1_790_195_583)

    static func fixture() -> String {
        let url = Bundle.module.url(
            forResource: "strix", withExtension: "prom", subdirectory: "Fixtures"
        )
        return (try? String(contentsOf: url!, encoding: .utf8)) ?? ""
    }

    private func mapped() -> Snapshot {
        var mapper = RemoteMapper(target: Self.target)
        return mapper.snapshot(from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live))
    }

    // MARK: - Fixture

    @Test("the fixture parses")
    func fixtureLoads() {
        #expect(Self.metrics.samples("node_cpu_seconds_total").count == 256)
    }

    // MARK: - CPU and identity

    @Test("reads all 32 threads")
    func coreCount() {
        #expect(RemoteMapper.ticks(from: Self.metrics).count == 32)
    }

    @Test("names the host, platform and GPU as declared")
    func identity() {
        let machine = mapped().machine
        #expect(machine.host == "strix")
        #expect(machine.platformVersion == "Linux 7.0.0-34-generic")
        #expect(machine.summary.contains("RADEON 8060S 128 GB (UNIFIED)"))
        // MemTotal, not the 128 GiB on the sticker.
        #expect(machine.memoryBytes > 120 << 30)
        #expect(!machine.ranksProcesses)
    }

    // MARK: - Memory buckets (the GPU fold arrives in a later task)

    @Test("anonymous and shared pages are active, kernel memory is wired")
    func linuxBuckets() {
        func value(_ name: String) -> Double {
            Self.metrics.value("node_memory_\(name)_bytes") ?? 0
        }
        let memory = mapped().memory
        #expect(memory.active == UInt64(value("AnonPages")) + UInt64(value("Shmem")))
        #expect(
            memory.wired
                == UInt64(value("SUnreclaim")) + UInt64(value("KernelStack"))
                    + UInt64(value("PageTables")) + UInt64(value("Percpu"))
        )
        #expect(memory.total == UInt64(value("MemTotal")))
    }

    // MARK: - Thermal

    @Test("finds the CPU package through k10temp and the NVMe through nvme")
    func hwmonClusters() throws {
        let cpu = try #require(mapped().thermal[.cpu])
        #expect(cpu.count >= 1)
        let storage = try #require(mapped().thermal[.storage])
        #expect(storage.count >= 1)
    }

    @Test("GPU temperature comes from the textfile alone, not the amdgpu hwmon chip")
    func gpuTemperatureIsSingleSource() throws {
        let gpu = try #require(mapped().thermal[.gpu])
        let expected = try #require(Self.metrics.value("homelab_gpu_temperature_celsius"))
        #expect(gpu.count == 1)
        #expect(gpu.average == expected)
    }

    @Test("sensors that belong to no cluster are dropped")
    func unrelatedSensors() {
        // The WiFi NIC and the ACPI zone would drag an average somewhere
        // meaningless; strix has both, in quantity.
        #expect(mapped().thermal[.battery] == nil)
        #expect(mapped().thermal.fans.isEmpty)
    }

    // MARK: - Storage

    @Test("shows Root and Coldstore, the automount through the collector")
    func volumes() throws {
        let volumes = mapped().storage.volumes
        #expect(volumes.map(\.name) == ["Root", "Coldstore"])
        let coldstore = try #require(volumes.last)
        #expect(coldstore.fraction >= 0 && coldstore.fraction <= 1)
    }

    @Test("headline capacity covers local storage only")
    func capacityExcludesTheNAS() {
        let storage = mapped().storage
        // Root alone is ~915 GiB; BabyNas's coldstore must stay out of it.
        #expect(storage.total > 900 << 30)
        #expect(storage.total < 1 << 40)
    }

    // MARK: - Services and link

    @Test("reads the flash-next endpoint and the declared units")
    func services() {
        let services = mapped().services
        #expect(services.totalUnits == 7)
        #expect(services.allUnitsActive)
        #expect(services.endpoints == [EndpointReadiness(name: "flash-next", ready: true)])
    }

    @Test("reports how old the collector's run is")
    func collectionAge() throws {
        let age = try #require(mapped().services.collectionAge)
        #expect(age >= 0 && age < 120)
    }

    @Test("reads uptime and host-wide traffic")
    func uptimeAndNetwork() {
        #expect(mapped().uptime > 0)
        #expect(mapped().network.lifetimeIn > 0)
        #expect(mapped().network.lifetimeOut > 0)
    }

    // MARK: - Filtering

    @Test("the declared series cover everything the mapper reads")
    func wantedSeries() {
        var mapper = RemoteMapper(target: Self.target)
        let filtered = MetricSet(text: Self.fixture(), wanted: mapper.wants)
        let declared = mapper.snapshot(
            from: filtered, now: Self.captured, link: LinkStatus(state: .live)
        )
        #expect(declared == mapped())
    }
}
```

If any assertion contradicts what the capture actually contains (chip counts, endpoint name, units), fix the assertion to the captured reality and record the deviation in the report — the host is the authority, not this plan. Do not edit captured values.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RemoteMapperStrixTests`
Expected: PASS for every test. (These pin current behaviour against a real fixture; nothing was implemented, so there is no red phase — the suite's value is as the regression floor for Tasks 3 and 4.)

- [ ] **Step 5: Run the full suite and commit**

Run: `swift build && swift test`
Expected: PASS.

```bash
git add Tests/StatsyKitTests/Fixtures/strix.prom Tests/StatsyKitTests/RemoteMapperStrixTests.swift
git commit -m "test(remote): pin the strix fixture and its amdgpu-stage contract"
```

---

### Task 3: The gpuShared fold — model, mapper, pane, invariant

**Files:**
- Modify: `Sources/StatsyKit/Models/MemoryModels.swift`
- Modify: `Sources/StatsyKit/Remote/RemoteMapper+Resources.swift`
- Modify: `Sources/StatsyKit/Remote/RemoteMapper.swift:41`
- Modify: `Sources/Statsy/Views/MemoryPane.swift`
- Modify: `AGENTS.md`
- Test: `Tests/StatsyKitTests/RemoteMapperStrixTests.swift`, `Tests/StatsyKitTests/RemoteMapperTests.swift`

**Interfaces:**
- Consumes: `RemoteTarget.unifiedMemory` (Task 1), the strix fixture suite (Task 2).
- Produces: `MemoryMetrics.gpuShared: UInt64` (init parameter `gpuShared: UInt64 = 0` after `active`); `RemoteMapper.memory(from:)` as an instance method (`Self.memory` → `memory`). `inUse` includes `gpuShared` on unified targets.

- [ ] **Step 1: Write the failing tests**

Append to `RemoteMapperStrixTests.swift`:

```swift
    // MARK: - Unified memory fold

    @Test("GPU-held memory is counted as in use, because no bucket counts it")
    func unifiedFold() {
        let memory = mapped().memory
        let gpuShared = Self.metrics.samples("homelab_gpu_memory_used_bytes")
            .reduce(UInt64(0)) { $0 + RemoteMapper.bytes($1.value) }
        #expect(memory.gpuShared == gpuShared)
        #expect(memory.gpuShared > 0)
        #expect(
            memory.inUse
                == memory.active + memory.wired + memory.compressed + memory.gpuShared
        )
    }

    @Test("non-finite or negative GPU memory contributes nothing")
    func unifiedFoldDiscardsNonFiniteValues() {
        let samples = Self.metrics.samples("homelab_gpu_memory_used_bytes").map { sample in
            MetricSample(name: sample.name, labels: sample.labels, value: -1)
        }
        let poisoned = MetricSet(Self.metrics.samples.filter { $0.name != "homelab_gpu_memory_used_bytes" } + samples)
        var mapper = RemoteMapper(target: Self.target)
        #expect(mapper.snapshot(from: poisoned, now: Self.captured, link: LinkStatus(state: .live)).memory.gpuShared == 0)
    }

    @Test("no GPU series on a unified host means no fold, not zero memory")
    func foldAbsentSeries() {
        let bare = MetricSet(
            Self.metrics.samples.filter { !$0.name.hasPrefix("homelab_gpu_") }
        )
        var mapper = RemoteMapper(target: Self.target)
        let snapshot = mapper.snapshot(from: bare, now: Self.captured, link: LinkStatus(state: .live))
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.memory.gpuShared == 0)
        #expect(snapshot.memory.total > 120 << 30)
    }

    @Test("a discrete host folds nothing even when GPU series are present")
    func noUnifiedFoldOnDiscreteHosts() {
        // The gate is the target's declaration, never the series' presence:
        // mapped through ai-1's target, this fixture's GPU figures are
        // discrete VRAM that the card's own bar already accounts for.
        var mapper = RemoteMapper(target: TargetRegistry.homelabAI1.remote!)
        let snapshot = mapper.snapshot(from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live))
        #expect(!snapshot.gpus.isEmpty)
        #expect(snapshot.memory.gpuShared == 0)
    }
```

Append to `RemoteMapperTests.swift` (ai-1 suite), after `swap()`:

```swift
    @Test("a discrete host folds no GPU memory into the system totals")
    func noUnifiedFold() {
        let memory = mapped().memory
        #expect(memory.gpuShared == 0)
        #expect(memory.inUse == memory.active + memory.wired + memory.compressed)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RemoteMapperStrixTests`
Expected: FAIL — `unifiedFold` (no `gpuShared`), and the file does not compile, which is the failing state.

- [ ] **Step 3: Implement the model**

In `MemoryModels.swift`, add to `MemoryMetrics` after `active`:

```swift
    /// GPU-resident memory on a unified host, which no bucket counts.
    ///
    /// Strix Halo serves its model out of the GTT pool: TTM pages sit off
    /// the LRU lists, so `/proc/meminfo` reports an 89 GiB model as nothing
    /// at all. Counted into in use and drawn as its own segment, because a
    /// machine that full must not read as 7 GiB used. Zero everywhere else:
    /// a discrete card's VRAM is its own bar, and Apple Silicon's GPU memory
    /// is ordinary process memory that already lands in the buckets.
    public let gpuShared: UInt64
```

Add init parameter `gpuShared: UInt64 = 0,` after `active: UInt64,`, assignment `self.gpuShared = gpuShared` after `self.active = active`, and `gpuShared: 0` to `static let zero`.

- [ ] **Step 4: Implement the fold**

In `RemoteMapper+Resources.swift`, change `static func memory(from metrics: MetricSet) -> MemoryMetrics` to `func memory(from metrics: MetricSet) -> MemoryMetrics` (drop `static`), and inside, after the `swapTotal`/`swapFree` lines and before `return`:

```swift
        // A unified host's model memory never reaches these buckets, so it
        // is added rather than mapped: the GTT pool holds what the GPU has
        // taken of system memory, and in use must include it to be true.
        var gpuShared: UInt64 = 0
        if target.unifiedMemory {
            gpuShared = metrics.samples(collector("gpu_memory_used_bytes"))
                .reduce(UInt64(0)) { $0 + Self.bytes($1.value) }
        }
```

Change the return to pass `inUse: active + wired + compressed + gpuShared,` and add `gpuShared: gpuShared,` after `active: active,`. Update the method's doc comment to end with: `On a unified-memory target, GPU-held memory joins in use as its own category, because no /proc/meminfo bucket contains it.`

In `RemoteMapper.swift` line 41, change `memory: Self.memory(from: metrics),` to `memory: memory(from: metrics),`.

- [ ] **Step 5: Implement the pane**

In `MemoryPane.swift`, replace the `SegmentedBar(segments: [...])` initializer and the legend `HStack` with:

```swift
                SegmentedBar(segments: segments)
                HStack(spacing: 0) {
                    legend("WIRE", memory.wired, Theme.channelWhite)
                    Spacer(minLength: 2)
                    legend("CMPR", memory.compressed, Theme.purple)
                    Spacer(minLength: 2)
                    if memory.gpuShared > 0 {
                        legend("GPU", memory.gpuShared, Theme.purpleLight)
                        Spacer(minLength: 2)
                    }
                    legend("ACTV", memory.active, Theme.yellow)
                    Spacer(minLength: 2)
                    legend("RECL", memory.reclaimable, Theme.yellowDim)
                    Spacer(minLength: 2)
                    legend("FREE", memory.free, Theme.textTertiary)
                }
                .font(Theme.mono(9))
```

And add the computed property (beside `share(_:)`):

```swift
    /// The composition bar, with the unified host's GPU-held segment between
    /// compressed and active: the model's residency, in the bucket list's
    /// least-to-most-reclaimable order. Purple-light so it cannot blur into
    /// the yellow of the buckets around it; every non-unified target, which
    /// has no such memory, draws the pane exactly as before.
    private var segments: [SegmentedBar.Segment] {
        var segments = [
            SegmentedBar.Segment(fraction: share(memory.wired), color: Theme.channelWhite),
            SegmentedBar.Segment(fraction: share(memory.compressed), color: Theme.purple),
        ]
        if memory.gpuShared > 0 {
            segments.append(
                SegmentedBar.Segment(fraction: share(memory.gpuShared), color: Theme.purpleLight)
            )
        }
        segments += [
            SegmentedBar.Segment(fraction: share(memory.active), color: Theme.yellow),
            SegmentedBar.Segment(fraction: share(memory.reclaimable), color: Theme.yellowDim),
        ]
        return segments
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter RemoteMapperStrixTests && swift test --filter RemoteMapperTests && swift test --filter MemoryCalculatorTests`
Expected: PASS.

- [ ] **Step 7: Update the invariant in AGENTS.md**

In the first invariant bullet (Memory In Use), add a platform line after the Linux one:

```markdown
  - A unified-memory target (strix, Strix Halo) adds a fourth in-use
    category, GPU: GTT/TTM pages sit off the LRU lists and appear in no
    `/proc/meminfo` bucket, so an 89 GiB model resident would otherwise read
    as 7 GiB in use. The fold keys off the target's declared
    `unifiedMemory`, never a series' presence — ai-1 publishes GPU memory
    figures that are discrete VRAM its own card already accounts for.
    `gpuShared` is zero on every other target, and the pane's GPU segment
    and legend appear only when it is non-zero.
```

- [ ] **Step 8: Run the full suite and commit**

Run: `swift build && swift test`
Expected: PASS.

```bash
git add Sources/StatsyKit/Models/MemoryModels.swift Sources/StatsyKit/Remote/RemoteMapper+Resources.swift Sources/StatsyKit/Remote/RemoteMapper.swift Sources/Statsy/Views/MemoryPane.swift AGENTS.md Tests/StatsyKitTests/RemoteMapperStrixTests.swift Tests/StatsyKitTests/RemoteMapperTests.swift
git commit -m "feat(memory): count GPU-held memory as in use on unified targets"
```

---

### Task 4: The lone GTT card — label, width, capless power

**Files:**
- Modify: `Sources/StatsyKit/Models/GPUModels.swift`
- Modify: `Sources/StatsyKit/Remote/RemoteMapper+Hardware.swift`
- Modify: `Sources/Statsy/Views/Remote/GPUBand.swift`
- Modify: `AGENTS.md`
- Test: `Tests/StatsyKitTests/RemoteMapperStrixTests.swift`, `Tests/StatsyKitTests/RemoteMapperTests.swift`

**Interfaces:**
- Consumes: `RemoteTarget.unifiedMemory` (Task 1), strix fixture suite (Task 2).
- Produces: `GPUReading.memoryLabel: String` (init parameter `memoryLabel: String = "VRAM"` after `celsius`). `GPUBand.cardWidth: CGFloat` (static, 420).

- [ ] **Step 1: Write the failing tests**

Append to `RemoteMapperStrixTests.swift`:

```swift
    // MARK: - The lone GTT card

    @Test("reads one card from the GTT pool, not the VRAM carveout")
    func loneGpu() throws {
        let gpus = RemoteMapper(target: Self.target).gpus(from: Self.metrics)
        #expect(gpus.map(\.id) == [0])
        let gpu = try #require(gpus.first)
        #expect(gpu.memoryLabel == "GTT")
        // 128 GiB shared pool; the 512 MiB carveout would read 1 << 29.
        #expect(gpu.memoryTotal > 120 << 30)
        #expect(gpu.memoryUsed == Self.metrics.value("homelab_gpu_memory_used_bytes").map(RemoteMapper.bytes))
        #expect(gpu.utilization >= 0 && gpu.utilization <= 1)
        // This kernel's amdgpu publishes no power cap.
        #expect(gpu.wattLimit == 0)
        #expect(gpu.watts > 0)
        #expect(gpu.celsius == Self.metrics.value("homelab_gpu_temperature_celsius"))
    }
```

In `RemoteMapperTests.swift` (ai-1 suite), extend `gpuFields()` with:

```swift
        #expect(first.memoryLabel == "VRAM")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RemoteMapperStrixTests`
Expected: FAIL — compile error on `memoryLabel` (the failing state).

- [ ] **Step 3: Implement**

In `GPUModels.swift`, add to `GPUReading` after `celsius`:

```swift
    /// What the memory figures are called on this card: `VRAM` on a discrete
    /// card, `GTT` where the GPU draws from system memory.
    public let memoryLabel: String
```

Add init parameter `memoryLabel: String = "VRAM"` after `celsius: Double = 0,`, assignment after `self.celsius = celsius`. Update the type's doc comment: replace `as nvidia-smi reports it through the fleet collector` with `as the fleet collector reports it: nvidia-smi on a discrete host, the amdgpu sysfs contract on a unified one`.

In `RemoteMapper+Hardware.swift`, `gpus(from:)`'s `GPUReading(...)` gains a final argument:

```swift
                memoryLabel: target.unifiedMemory ? "GTT" : "VRAM"
```

In `GPUBand.swift`:

```swift
    var body: some View {
        HStack(spacing: 9) {
            ForEach(gpus) { gpu in
                GPUCard(gpu: gpu)
                    // A lone card keeps the width it would have had as one of
                    // three and centres: stretched across 1280 its figures
                    // float apart and the pane reads as broken.
                    .frame(maxWidth: gpus.count == 1 ? Self.cardWidth : .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: gpus.count == 1 ? .center : .leading)
    }

    /// The share of a three-card band, which a lone card keeps for itself.
    static let cardWidth: CGFloat = 420
```

In `GPUCard`, change `subtitle: "VRAM"` to `subtitle: gpu.memoryLabel`, change the Power `MeterCell`'s `value:` to `powerText`, and add:

```swift
    /// amdgpu publishes no power cap, so a unified card renders its draw
    /// alone rather than against a limit of zero.
    private var powerText: String {
        gpu.wattLimit > 0
            ? "\(Format.decimal(gpu.watts, decimals: 0)) / \(Format.decimal(gpu.wattLimit, decimals: 0)) W"
            : "\(Format.decimal(gpu.watts, decimals: 0)) W"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RemoteMapperStrixTests && swift test --filter RemoteMapperTests`
Expected: PASS.

- [ ] **Step 5: Update AGENTS.md**

Add a bullet to Invariants, after the volume-colours/remote-capacity bullets:

```markdown
- **A unified-memory GPU is reported from the GTT pool, not the VRAM
  carveout.** Strix Halo's 512 MiB carveout answers nothing; the model lives
  in the shared pool, so the collector contract's `homelab_gpu_memory_*` are
  GTT figures there and the card's subtitle reads GTT. The lone card keeps
  the width of one of three and centres, and renders power without a limit —
  this kernel's amdgpu publishes no cap. The stage that publishes them lands
  with the homelab collector later; until it deploys, strix draws no band and
  folds no memory, pinned by `RemoteMapperStrixTests`.
```

- [ ] **Step 6: Run the full suite and commit**

Run: `swift build && swift test`
Expected: PASS.

```bash
git add Sources/StatsyKit/Models/GPUModels.swift Sources/StatsyKit/Remote/RemoteMapper+Hardware.swift Sources/Statsy/Views/Remote/GPUBand.swift AGENTS.md Tests/StatsyKitTests/RemoteMapperStrixTests.swift Tests/StatsyKitTests/RemoteMapperTests.swift
git commit -m "feat(panel): draw the strix GPU card from the GTT pool"
```

---

### Task 5: Fixture rendering, live probe, docs

**Files:**
- Modify: `Sources/Statsy/main.swift`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: everything from Tasks 1–4; `MetricSet(text:wanted:)`, `RemoteMapper` (both public).
- Produces: `--fixture <path>` argument to `Statsy --render`, usable only with a remote `--target`.

- [ ] **Step 1: Implement the fixture path in the render block**

In `Sources/Statsy/main.swift`, replace the `if let renderIndex ...` block with:

```swift
if let renderIndex = arguments.firstIndex(of: "--render") {
    let path = arguments[arguments.index(after: renderIndex)]

    let snapshot: Snapshot
    if let fixtureIndex = arguments.firstIndex(of: "--fixture") {
        // A fixture renders the remote layout with no host attached: the
        // mapper is pure, so the same transformation that reads a live
        // scrape reads a captured one. Two identical scrapes a second apart
        // leave the cores idle, which is fine — this mode checks layout.
        let fixturePath = arguments[arguments.index(after: fixtureIndex)]
        guard let remote = selected.remote,
              let text = try? String(contentsOfFile: fixturePath, encoding: .utf8)
        else {
            FileHandle.standardError.write(
                Data(("--fixture needs a remote --target and a readable file\n").utf8)
            )
            exit(1)
        }
        var mapper = RemoteMapper(target: remote)
        let metrics = MetricSet(text: text, wanted: mapper.wants)
        let now = Date()
        _ = mapper.snapshot(from: metrics, now: now, link: LinkStatus(state: .live))
        snapshot = mapper.snapshot(
            from: metrics, now: now.addingTimeInterval(2), link: LinkStatus(state: .live)
        )
    } else {
        let provider = SnapshotProviderFactory.provider(for: selected)
        snapshot = await provider.primedSample()
        await provider.stop()
    }
    try PanelRender.write(snapshot: snapshot, to: path)
    print("wrote \(path)")
    exit(0)
}
```

- [ ] **Step 2: Render both layouts and inspect them**

```bash
swift build
swift run Statsy --render /tmp/strix-layout.png --target strix --fixture Tests/StatsyKitTests/Fixtures/strix.prom
swift run Statsy --render /tmp/ai1-layout.png --target homelab-ai-1 --fixture Tests/StatsyKitTests/Fixtures/homelab-ai-1.prom
```

Expected: both write PNGs. Inspect `/tmp/strix-layout.png`: lone centred GTT card at ~420 pt with capless power, five memory segments including a purple-light GPU legend between CMPR and ACTV, remote ribbon with `flash-next`. Inspect `/tmp/ai1-layout.png`: three VRAM cards with `x / y W` power, four memory segments, no GPU legend — visually identical to the panel before this branch. Any crowding in the six-legend row is a finding to report, not to silently shrink type against the panel's geometry rule.

- [ ] **Step 3: Probe the live host and verify against its own tools**

```bash
swift run statsy-probe --target strix | tee /tmp/strix-probe.txt
ssh -o BatchMode=yes steve@192.168.68.63 'free -b | head -2; df -B1 / /mnt/coldstore; cat /sys/class/drm/card0/device/mem_info_gtt_used'
```

Expected: probe runs over the tunnel, prints memory/storage/thermal consistent with `free` and `df` within the documented bucket semantics. Until the collector stage deploys, the probe's GPU list is empty — that is the pinned degradation, not a failure. Record both outputs in the report.

- [ ] **Step 4: Documentation**

`README.md` — after the homelab-ai-1 paragraph (line ~46–50), add:

```markdown
The third is `strix`, a Strix Halo whose GPU serves a model out of system
memory. Nothing in `/proc/meminfo` sees that memory, so its pane carries a
GPU segment in the memory bar and its lone card reads the shared pool (GTT)
rather than VRAM.
```

And in the commands/usage area where `--render` is described (if it is), add the fixture form; if `--render` is not documented in README, skip this sentence.

`AGENTS.md` — in Commands, after the `--render` line:

```markdown
swift run Statsy --render out.png --target strix --fixture Tests/StatsyKitTests/Fixtures/strix.prom   # remote layout from a captured scrape, no host needed
```

Update the `swift build && swift test` comment's test count to the actual count from Step 5.

- [ ] **Step 5: Run the full suite and commit**

Run: `swift build && swift test`
Expected: PASS. Record the test count for the AGENTS.md edit (re-edit if you wrote it before running).

```bash
git add Sources/Statsy/main.swift README.md AGENTS.md
git commit -m "feat(panel): render the remote layout from a captured scrape"
```
