# Sampling reference

Where each number comes from, and the five places the obvious API is wrong.
Every figure below was verified against the system tool named beside it.

## Sources

| Metric | Source | Checked against |
|---|---|---|
| CPU per-core + aggregate | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | `top` |
| Load average | `getloadavg` | `uptime` |
| Core clusters | `hw.perflevelN.name` / `.physicalcpu` | `sysctl` |
| Memory | `host_statistics64(HOST_VM_INFO64)` | `top` PhysMem |
| Swap | `vm.swapusage` | `sysctl` |
| Capacity, device | `getmntinfo` | `df -h` |
| Capacity, per volume | `getattrlist(ATTR_VOL_SPACEUSED)` | `df -h` |
| Disk throughput | IOKit `IOBlockStorageDriver` → `Statistics` | `iostat` |
| Temperatures, fans | IOKit `AppleSMC` | Stats.app `smc` |
| Network | IF-MIB `IFMIB_IFDATA`/`IFDATA_GENERAL` | `netstat -ib` |
| Processes | streamed `/usr/bin/top` | itself |
| Uptime | `kern.boottime` | `uptime` |

## The five traps

### 1. Inactive pages are used memory

`active + wired + compressed` gives 69 GB where `top` says 114 GB. Activity
Monitor's "Memory Used" is `active + inactive + wired + compressed` — everything
except `free` and `speculative`.

Verified: 49.05 + 44.45 + 7.23 + 13.46 = 114.19 GiB against `top`'s 114G, and
`free + speculative` = 12.84 GiB against its 13G unused.

Note the two do not sum to installed RAM: ~0.97 GiB sits outside `vm_stat`'s
buckets. `top` shows the same gap (114 + 13 = 127 of 128), so a strict equality
assertion would be testing a false claim about the kernel.

### 2. Unprivileged libproc cannot see root processes

`proc_pidinfo(PROC_PIDTASKINFO)` and `proc_pid_rusage` return EPERM for
processes owned by other users — 180 of 1050 here. `proc_pidpath` still works,
so names are visible while numbers are not.

This is not an edge case: WindowServer was observed at 45.2% CPU and
kernel_task holding 20 GB, both invisible. `/usr/bin/top` and `/bin/ps` are
setuid root (`-r-sr-xr-x`), which is the only reason they see everything.

`ps` is not an alternative — its `%CPU` is a lifetime average, not an interval
delta. `top`'s *first* block has the same problem and is discarded.

A privileged `SMAppService` daemon would remove the dependency; it conforms to
`ProcessSource` and nothing above that protocol changes.

### 3. Swift reuses C tail padding

`SMCKeyData` must be 80 bytes. Its `KeyInfo` member is 9 bytes of fields that C
pads to 12; Swift packs the following fields into that slack, yielding a
76-byte request with `bytes` at offset 44 instead of 48. The SMC returns
garbage rather than an error. Fixed with explicit padding, pinned by a test.

### 4. statfs cannot see APFS volumes separately

Every volume in an APFS container reports the container's `f_blocks`/`f_bfree`,
so `/`, `/System/Volumes/Data` and `/System/Volumes/VM` all computed as
1322.7 GiB used. `getattrlist(ATTR_VOL_SPACEUSED)` gives per-volume figures
(11.7 / 1285.5 / 12.0 GiB) matching `df`.

Device-level "71% full" still comes from the container via `getmntinfo`; the two
answer different questions.

### 5. NET_RT_IFLIST2 wraps at 4 GiB

Despite declaring `if_data64`, it reported 27 MB for an interface that has
carried 34 GB — the value modulo 2^32. `getifaddrs` is worse (32-bit by
declaration). The IF-MIB returns true 64-bit counters: 32.2 GiB in / 12.6 GiB
out, matching `netstat -ib`.

## Why storage has no process list

Per-process disk I/O over a one-second window is almost always empty — a live
sample found one process writing 45 KB. Unlike CPU and memory, an SSD top-five
would be blank nearly always, so that pane leads with capacity and throughput.
