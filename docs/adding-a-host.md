# Adding a host

How to point Statsy at another machine. A host that already runs node_exporter and accepts your SSH key takes one registry entry, one captured fixture and a probe run. A host on a new operating system takes a platform case as well; see [A new operating system](#a-new-operating-system).

Statsy installs nothing on a host. It opens two SSH sessions while the panel is pointed there: a `-L` forward to node_exporter, holding a remote `cat` so the forward dies with the panel, and a streamed `top` for the process lists. Anything the host needs, node_exporter above all, is deployed from the homelab repository (`~/dev/homelab/hosts/<host>/`) under that host's own rules. Strix, for one, admits no new services.

## On the host

| Needs | Check from the workstation |
| --- | --- |
| Key-based SSH from the workstation | `ssh -o BatchMode=yes user@address true` exits 0 |
| The host key already in `known_hosts` | the same command; an unknown key fails with "Host key verification failed", and the panel would only ever show NO DATA |
| node_exporter, with the collectors the platform reads (below) | `ssh user@address "curl -s -o /dev/null -w '%{http_code}' 'http://LISTEN:9100/metrics?collect[]=cpu&collect[]=meminfo'"` prints 200 |
| `top` and `cat` on the login user's `PATH` | true of every Linux distribution and macOS |
| Optionally, the fleet collector's textfile | `homelab_*` series labelled with the host's `asset_host` |

Find where the exporter listens before writing anything down, because a forward to the wrong address connects to nothing: `ss -ltn | grep :9100` on Linux, `lsof -nP -iTCP:9100 -sTCP:LISTEN` on macOS, or the `--web.listen-address` in the host's unit, compose file or plist. `0.0.0.0` and `127.0.0.1` both mean the forward can target `127.0.0.1`; a LAN address means it must target that address.

The collectors each platform asks for are `RemotePlatform.liveCollectors` plus `filesystem` every 30 s:

| Platform | Collectors |
| --- | --- |
| Linux | `cpu`, `loadavg`, `stat`, `uname`, `hwmon`, `diskstats`, `netstat`, `meminfo`, `textfile`, `filesystem` |
| macOS | `cpu`, `loadavg`, `boottime`, `uname`, `os`, `diskstats`, `netdev`, `meminfo`, `textfile`, `filesystem` |

An exporter with one of these disabled answers the whole scrape with 400, which the panel shows as a failed link. Collectors left out of the list can stay disabled; the minis run without `thermal`.

## 1. Gather the facts

Every field of `RemoteTarget`, where its value comes from, and what goes wrong if it is wrong.

| Field | Where it comes from | If wrong |
| --- | --- | --- |
| `sshUser`, `sshHost` | the account you log in with and the host's reserved address (`docs/01-hosts.md` in the homelab repo) | no data |
| `exporterHost` | the listen address found above | the forward connects to nothing |
| `localPort` | `19100` plus the address's last octet (strix at `.63` is 19163); ai-1's 19100 predates the rule. `TargetRegistryTests.distinctPorts` rejects a clash | a second target's tunnel collides |
| `platform` | `.linux` or `.macOS` | memory, network and the header are read from the wrong series |
| `hostName` | the `asset_host` label on the host's fleet series, lowercase. It is also the header name and, through the factories, the target id | the host's own units, GPUs and collector age are dropped as another host's |
| `model`, `gpuDescription` | header text; `lscpu` or `system_profiler`, and the card's own name | cosmetic |
| `clusters` | only for mixed cores, in core-index order (see [Heterogeneous cores](#heterogeneous-cores)) | the grid's divider sits in the wrong place |
| `volumes` | the mounts worth a row, each with a role (see [Storage](#storage)) | a missing or meaningless row |
| `diskDevices` | the physical block devices from `node_disk_read_bytes_total`, never `dm-*` | throughput double-counts or reads zero |
| `unifiedMemory` | true only for a GPU that serves from system memory (see [GPUs](#gpus)) | memory headline off by the size of a model |
| `collectorPrefix` | `homelab_` for the fleet collector | no GPUs, units or collector age |
| `ranksProcesses` | leave the default, true | no process lists |

Grab a raw scrape now; the next steps use it:

```bash
ssh user@address "curl -s http://LISTEN:9100/metrics" > /tmp/host.prom
grep -E '^node_disk_read_bytes_total|^node_filesystem_size_bytes|^node_hwmon_chip_names|asset_host=' /tmp/host.prom | head -40
```

## 2. Register it

Add the target to `Sources/StatsyKit/Targets/TargetRegistry.swift` and to `TargetRegistry.all`. The menu, the probe and `--target` all read that list, so nothing else needs to learn the new id.

A Linux host goes through the `linux()` factory, which names the target, the menu entry and the `asset_host` scope with one string:

```swift
public static let homelab3 = linux(
    id: "homelab-3", address: "192.168.68.75", localPort: 19175,
    // Why the forward targets this address: what the listener binds.
    exporterHost: "127.0.0.1",
    model: "Ryzen 9 7950X 16C/32T", gpuDescription: "RTX 4090 24 GB",
    volumes: [
        RemoteVolume(mountPoint: "/", name: "Root", role: .system),
        RemoteVolume(mountPoint: "/srv", name: "Srv", role: .data),
    ],
    diskDevices: ["nvme0n1"]
)
```

Another M1 mini goes through `macMini()`. A Mac that is not an M1 mini, with different cores, GPU or user, gets a `RemoteTarget` written out in full, or a second factory once there are two of it.

`mac-mini-m6` is the explicit M6 example: `stephenbrandon@192.168.70.165`, a loopback-only exporter owned by root launchd, workstation port 19265, one internal APFS container plus Models and Backups NAS rows. Its three tiers are declared from CPU node indices, not `hw.perflevel` order; see [Heterogeneous cores](#heterogeneous-cores).

## 3. Capture a fixture and test

A fixture is the host's scrape cut down to what the mapper reads. It is what the tests map and what `--render --fixture` draws.

```bash
swift run statsy-probe --target homelab-3 --reduce /tmp/host.prom > body.prom
```

Write `Tests/StatsyKitTests/Fixtures/homelab-3.prom` as a short `#` comment saying when and how it was captured and anything unusual about the host, followed by `body.prom`. Then, in the tests:

- Add a `FleetFixture` for it in `RemoteMapperFleetTests.swift` and put it in `FleetFixture.all`. That alone runs the shared checks against it: the declared series cover everything the mapper reads, reduction loses nothing, the fixture carries the host's own collector series, and the target ranks processes.
- Add its row to the `exporterBinding` arguments in `TargetRegistryTests.swift`.
- Add a test for anything particular to this host: a GPU count, a volume list, a disk sum, foreign series it must ignore.

`swift test` must pass before going further.

## 4. Verify against the host

```bash
swift run statsy-probe --target homelab-3
```

The probe waits for the first process block, then prints everything the panel would draw. Compare it with the host's own tools, run at the same moment where the figure moves:

| Probe line | Linux | macOS |
| --- | --- | --- |
| memory | `free -g`, or the `/proc/meminfo` sum in CLAUDE.md | `vm_stat` |
| storage rows | `df -B1` | `df` for available space; `diskutil apfs list` for internal container usage |
| io lifetime | `/sys/block/<dev>/stat`, sectors times 512 | `iostat -I -d disk0`, read and written combined, in MB |
| network | `/proc/net/netstat` IpExt octets | `netstat -ib` |
| temperatures | `sensors`, `nvidia-smi` | none published |
| processes | `top -b -n 1 -o %CPU` and `-o RES` | `top -l 2 -o cpu` |

Then look at it:

```bash
swift run Statsy --render live.png --target homelab-3
swift run Statsy --render fixture.png --target homelab-3 --fixture Tests/StatsyKitTests/Fixtures/homelab-3.prom
```

Check that nothing is cut off and that the frame sits where every other target's does, with the same margin above the header and below the ribbon as a render of strix. An overfull pane pushes the whole frame up instead of clipping, so a header jammed against the top edge is the sign. The fixture render refuses a capture without the host's own collector series, so a host with no fleet collector can only be rendered live.

Finally, measure what watching the host costs it. With the panel pointed there for a minute, difference the CPU time of its `top` and its exporter:

```bash
ssh user@address 'p=$(pgrep -n -x top); a=$(ps -o time= -p $p); sleep 60; ps -o time= -p $p; echo "was $a"'
```

Record the figures beside the others in CLAUDE.md's cost-budget invariant. The M6 qualification on 2026-10-08 measured `top` at 4.46% and node_exporter at 0.55% of one core over an 84-second CPU-time delta while the installed panel watched it, at about 1,160 processes. The exporter figure includes other fleet polling.

## 5. Install

```bash
./make-app.sh
```

Quit both apps, `trash` the two bundles in `/Applications`, copy the new ones in, and relaunch Statsy Menu. The new host appears in its Target submenu.

Update the CHANGELOG, and add an invariant to CLAUDE.md if the host needed a rule the others did not.

## By operating system

### Linux

The default. Memory comes from `/proc/meminfo` into the panel's buckets as CLAUDE.md defines them, network from the netstat collector's IP totals (which work even where the netdev collector fails, as on ai-1), the header from the kernel release, and processes from procps `top -b`. `/proc` shows every user's processes to an unprivileged `top`, unless the host mounts it with `hidepid`, in which case the lists show only the login user's processes.

### macOS

`platform: .macOS`. Memory comes from the Darwin exporter's Mach buckets, read as the local panel reads `host_statistics64`; network sums every interface but loopback; the header shows the product version from `node_os_info`; units are LaunchAgents. Processes come from the same `top` the local panel runs, which is setuid and sees everything. The Darwin exporter has no working thermal collector on the minis, so the ribbon says no sensors are published. APFS reports one container's capacity for every volume in it, so declare `/System/Volumes/Data` alone as the disk; every other volume in the container would repeat its figures.

The remote internal disk's used figure is container capacity minus available space, including other volumes and snapshots. Compare it with `diskutil apfs list`, rather than `df`'s per-volume Used column. On the M6, 61% used was the container's 148.8 GB while `df` showed 53% for Data alone. Its readiness collector publishes age/success without the M1 minis' LaunchAgent/container series, so the panel leaves service counts absent.

The homelab repo's mini README says the Darwin exporter exposes no host memory, but node_exporter 1.12.1 on both minis publishes `node_memory_*`, which is what the panel reads. Check for those series in the raw scrape: an exporter without them draws an empty memory pane.

### A new operating system

FreeBSD, TrueNAS, Windows or anything else node_exporter runs on needs a new `RemotePlatform` case. Every switch over the enum is exhaustive with no `default`, so adding the case makes the compiler list each place that needs an answer:

| Site | Decides |
| --- | --- |
| `RemotePlatform.name` | the header's platform word |
| `RemotePlatform.liveCollectors` | which collectors each scrape asks for |
| `RemoteMapper.memory(from:)` | how the exporter's memory series fill active, wired, compressed, reclaimable and free |
| `RemoteMapper.network(from:)` | where lifetime traffic comes from |
| `RemoteMapper.platformWants(_:)` | series only this platform's readers use |
| `RemoteMapper.osVersion(from:)` | the header's version |
| `RemotePlatform.topCommand`, `.topDialect` | the streamed `top` and which parser reads it; a new `top` format needs a parser beside `TopParser` and `ProcpsTopParser`, with a `TopDialect` case |
| `RemotePlatform.processMemory` | what the memory list's figure measures, and so its caption |

Write the memory mapping down as a sub-bullet of CLAUDE.md's memory invariant before trusting it, with the tool it was checked against.

## By hardware

### GPUs

Discrete cards come from the fleet collector's `homelab_gpu_*` series, keyed on `memory_total_bytes`, and get the fourth column automatically. A host with discrete cards and no collector GPU stage shows no cards; add the stage in the homelab repo.

Set `unifiedMemory: true` only for a GPU that serves from system memory and whose collector stage reports that pool, as strix's amdgpu stage reports GTT. The fold then adds the GPU's memory to the memory headline and draws no column. Never set it because GPU series are present: ai-1 publishes the same series for discrete VRAM.

An APU with no collector stage, like Legion's Radeon 780M, still reports its temperature through the `amdgpu` hwmon chip, which maps to the GPU sensor cluster. A remote Apple silicon GPU publishes nothing.

### Heterogeneous cores

node_exporter publishes no performance levels, so mixed cores are declared in `clusters`, in core-index order. Check the order. On a Mac, run a few busy loops at background QoS (`taskpolicy -b sh -c 'while :; do :; done'`, killed by PID afterwards) and see which core indices go busy: background work runs only on the lowest tier, which on M1 is cpu0–3. On Linux, `lscpu -e=CPU,CORE,MAXMHZ` shows the tiers by clock. Clusters count logical CPUs and the header prints the counts, so a P-core cluster with SMT reads as "12P" on a 6P+4E chip; homelab-1 declares none for that reason.

The core grid wraps onto two rows by itself when its bars would narrow below 7 px.

### Sensors

hwmon chips map to sensor clusters by driver name in `RemoteMapper.cluster(forChip:)`: `k10temp`, `coretemp` and `zenpower` to CPU, `nvme` and `drivetemp` to SSD, `amdgpu` to GPU. A new driver needs a line there, checked against `sensors`. Leave `acpitz` out: ACPI zones on desktop boards are often unconnected, and ai-1's reads a constant 16.8 °C.

On M6, `ioreg -p IODeviceTree -n cpus -r -l` identifies cpu0–5 as `E`, cpu6–7 as `P`, and cpu8–11 as `M`. Together with `sysctl hw.perflevel0.name hw.perflevel0.physicalcpu hw.perflevel1.name hw.perflevel1.physicalcpu hw.perflevel2.name hw.perflevel2.physicalcpu`, that maps to Efficiency 6, Super 2, Performance 4. `powermetrics --samplers cpu_power -n 1` independently confirms CPU0–5 in E and CPU6–11 in the combined PS cluster. Do not copy the sysctl tier order into the index-based grid.

### Storage

Each volume needs a capacity source: `node_filesystem_*` for the mount, or the collector's `homelab_storage_*` as a fallback for autofs mounts that only appear when something touches them. Roles decide colour and whether a row counts toward the headline; `.network` rows are drawn but never counted, so a roomy NAS cannot hide a full NVMe. Leave out a hard NFS mount that nothing stats: strix's coldstore has no capacity series at all, and no safe way to get one. Names must be unique within a target.

`diskDevices` lists every physical disk that holds a declared local volume (homelab-1 sums two NVMe drives). Never list `dm-*` mappers, which repeat their underlying disk's traffic.

## Renaming or removing a host

The target id is what the menu writes to the selection file. If a running panel's recorded id disappears from the registry, `TargetSelection` falls back to this Mac. Renaming `hostName` only works if the fleet collector's `asset_host` label changes with it, and the fixture has to be recaptured, because the renderer and the fleet tests check that a fixture carries the target's own label.
