# Strix Target Design

## Goal

Point the Statsy panel at `strix`, a Strix Halo model-serving host, with an
honest memory headline on its unified-memory architecture and a GPU band
that answers "is the model loaded, and does it fit".

## The machine, verified live

`strix` (`steve@192.168.68.63`, SSH key auth works) runs Linux
`7.0.0-34-generic` on a Ryzen AI Max 395 (16C/32T, `k10temp`), one
`nvme0n1` 1 TB, `node_memory_MemTotal_bytes` ≈ 125 GiB. Its exporter
(`strix-node-exporter.service`) is active and bound to `192.168.68.63:9100`
— the same bind-LAN-address pattern as ai-1, so the existing
`SSHTunnel` → `RemoteSnapshotProvider` path needs no changes. The fleet
collector (`homelab-collector.timer`) is deployed and publishing
`storage`, `units`, `local_health` under the `homelab_` prefix (including a
`flash-next` HTTP endpoint and an NFS `/mnt/coldstore` mount), but has **no
GPU stage**: the collector's GPU stage is `nvidia-smi`-only.

amdgpu telemetry is entirely in sysfs on this host:

| Reading | Source | Value at probe time |
|---|---|---|
| Utilisation | `/sys/class/drm/card0/device/gpu_busy_percent` | 0% |
| Shared pool used | `mem_info_gtt_used` (+ `mem_info_vram_used`) | 88.7 GiB of 128 GiB |
| VRAM carveout | `mem_info_vram_total` | 512 MiB |
| Temperature | amdgpu hwmon `temp1_input` | 40 °C |
| Power | amdgpu hwmon `power1_average` | 6.0 W (no `power1_cap` on this kernel) |

## Why the memory model is the design centre

With a model loaded: `AnonPages` 3.5 GB, `Shmem` 3.0 GB, `Cached` 31 GB,
`MemFree` 2.5 GB — and GTT used **88.7 GiB**. GPU-resident (TTM/GTT) pages
sit off the LRU lists and appear in **no** `/proc/meminfo` bucket. The
current Linux mapping (`RemoteMapper+Resources.memory(from:)`) would show
~7 GiB in use of 125 GiB on a nearly full machine — a confident wrong
answer, which is the failure this panel exists not to give.

**Decision (Steve, 2026-09-23):** fold GPU-resident memory into the
memory pane as a visible, separate "GPU" category. In use = active +
wired + compressed **+ gpuShared** on a unified-memory target. The fold is
keyed off a **declared** `RemoteTarget.unifiedMemory` flag, never off the
presence of a series: ai-1 publishes `homelab_gpu_memory_used_bytes` too
(discrete VRAM), and folding that into system totals would double-count
memory its own GPU bar already accounts for.

## Collector contract (defined here, implemented later)

The homelab repos are mid-refactor in another session and must not be
touched now. This repo pins the contract the future amdgpu stage must
meet; statsy ships against it using a fixture, and behaves sanely until
deploy day. The stage reuses the existing `homelab_gpu_*` series names and
label shapes, so `RemoteMapper.gpus(from:)` parses strix unchanged:

```
homelab_gpu_utilization_percent{asset_host="strix",gpu="0"}   ← gpu_busy_percent
homelab_gpu_memory_total_bytes{asset_host="strix",gpu="0"}    ← mem_info_gtt_total + mem_info_vram_total
homelab_gpu_memory_used_bytes{asset_host="strix",gpu="0"}     ← mem_info_gtt_used + mem_info_vram_used
homelab_gpu_power_watts{asset_host="strix",gpu="0"}           ← power1_average / 1e6
homelab_gpu_temperature_celsius{asset_host="strix",gpu="0"}   ← temp1_input / 1e3
```

Only the `gpu` label is required (the mapper groups on it); `bus`/`uuid`
are optional and ignored. **No `power_limit_watts`**: the amdgpu sysfs on
this kernel exposes no cap, so the panel must render limit-less power.
The memory figures are the GTT pool the model lives in plus the 512 MiB VRAM carveout, in used and total alike, so used never exceeds total. The GTT total is the kernel's configured 128 GiB ceiling, which exceeds physical RAM, so it does not answer "does it fit"; available system memory does. A `homelab_collector_success{collector="amdgpu"}` row accompanies the stage.

Until the stage is deployed, a panel pointed at strix draws no GPU band
(`gpus` empty) and no GPU memory segment — graceful degradation, pinned by
tests. The statsy-side work is complete and verified independently of the
collector change.

## Statsy changes

### 1. Target registry (`Sources/StatsyKit/Targets/Target.swift`)

`RemoteTarget` gains `unifiedMemory: Bool = false`. New
`TargetRegistry.strix`: id/name `strix`, `sshUser: "steve"`,
`sshHost: "192.168.68.63"`, `exporterHost: "192.168.68.63"` (default
port 9100), `localPort: 19163` (ai-1 owns 19100), `hostName: "strix"`,
`model: "Ryzen AI Max 395 16C/32T"`, `gpuDescription: "Radeon 8060S
128 GB (unified)"`, volumes `/` → `Root`/`.system` and `/mnt/coldstore` →
`Coldstore`/`.network` (NFS from BabyNas; network volumes stay excluded
from the storage headline), `diskDevice: "nvme0n1"`, `unifiedMemory: true`.
Registry `all` becomes `[local, homelabAI1, strix]`. Menu, selection,
watcher, probe and render all derive from the registry — no other wiring.

### 2. Memory model and pane

- `MemoryMetrics` (StatsyKit) gains `gpuShared: UInt64 = 0`; `inUse`
  includes it. macOS `MemoryCalculator` is untouched (Apple Silicon's GPU
  memory is ordinary process memory — it already lands in the buckets).
- `RemoteMapper+Resources.memory(from:)` becomes an instance method and,
  when `target.unifiedMemory`, sets `gpuShared` = Σ
  `homelab_gpu_memory_used_bytes` (byte-guarded like every other counter).
- `MemoryPane` draws a fifth segment and a `GPU` legend (colour
  `Theme.purpleLight`, positioned between CMPR and ACTV) only when
  `memory.gpuShared > 0`. On every other target the pane is pixel-identical.

### 3. GPU band

- `GPUReading` gains `memoryLabel: String = "VRAM"`; the remote mapper
  sets `"GTT"` for unified targets. `GPUCard` uses it as the subtitle —
  "VRAM" would be a lie about a shared pool.
- `GPUBand` caps a lone card at the width it would have had as one of
  three (~420 pt) and centres it: a single `Pane` stretched to 1280 pt
  floats its headline figures apart and reads as broken.
- `GPUCard` renders power without a limit as `"6 W"`, not `"6 / 0 W"`
  (`powerFraction` already guards zero). ai-1, which always has limits,
  renders unchanged.

### 4. Fixture-driven verification

- New fixture `Tests/StatsyKitTests/Fixtures/strix.prom`: a real scrape
  captured over SSH, reduced like ai-1's, with the contract GPU series
  appended at their live sysfs values and clearly marked as the pending
  stage's contract.
- New `Tests/StatsyKitTests/RemoteMapperStrixTests.swift`, mirroring the
  ai-1 suite: 32-thread CPU, memory buckets and the gpuShared fold
  (inUse == active + wired + compressed + gpuShared), k10temp/nvme hwmon
  clusters with GPU temperature arriving from the textfile (the amdgpu
  hwmon chip stays unclustered — no double count), Root/Coldstore volumes
  with the automount falling back to the collector, `flash-next`
  endpoint, identity, `wantedSeries` equivalence, and the no-GPU-stage
  degradation case.
- ai-1's suite gains assertions that it is unchanged by all of this:
  `gpuShared == 0`, `memoryLabel == "VRAM"`.

### 5. Render tooling and docs

- `swift run Statsy --render out.png --target strix --fixture <path>`: a
  fixture path renders a snapshot through the same pure mapper without a
  host, extending `--render`'s stated purpose (layout checks without the
  display) to layout checks without the machine. Identical scrapes fed
  twice render idle cores — acceptable for layout checks.
- `AGENTS.md`: extend the Memory In Use invariant with the unified-memory
  clause; add the strix GPU-band invariants (GTT not carveout, capped lone
  card, capless power); note the deferred collector dependency and the
  pre-deploy degradation; refresh the test count and the fixture-render
  command.
- `README.md`: name strix alongside ai-1 as a target and its reason to
  exist (shared-pool residency), and document the fixture render.

## Out of scope

The homelab/observability amdgpu collector stage, `config/strix.json`
changes, UFW rules, deploy, and `make-app.sh` packaging — all deferred to
the homelab session. Nothing in this repo requires them to be correct;
only day-one GPU visibility on strix does.

## Success criteria

1. `swift build && swift test` green, including the strix suite.
2. `swift run statsy-probe --target strix` runs against the live host and
   agrees with `free`, `df`, and sysfs GTT counters on what it prints.
3. Fixture render of strix shows: lone centred GTT card, capless power,
   five-segment memory bar with a purple GPU legend, remote ribbon with
   `flash-next`; ai-1's fixture render is unchanged.

## Addendum — what changed when the collector landed (2026-09-23)

The amdgpu stage shipped in `homelab` branch `strix-amdgpu-collector` and was merged to `main` on 2026-09-24 (`ea24425`, `98d4fa8`), when review added the carveout to the memory total and required the edge temperature sensor
(`observability/collectors/collect.py`): utilisation, GTT-pool memory, power,
temperature, no limit — deployed to strix via `install-strix-monitoring.sh`
with every stage green, and the fixture was re-captured from the live scrape,
replacing the contract block with real series. One design point fell to a
contract this spec did not know about: the fleet checks `/mnt/coldstore`'s
presence but never stats it — a stalled hard NFS mount would wedge the
collector past every timeout (`test_strix_contract_watches_its_standing_roles`)
— and node_exporter publishes no capacity for it either. No safe source can
ever fill a Coldstore row, so the volume was dropped from the target rather
than declared dead.
