# Statsy

A system monitor for a small secondary display: CPU, memory and storage, each
above its five heaviest processes, over a strip of temperature and fan readings.

![Statsy on a mostly idle machine](docs/images/panel.png)

It targets a 7-inch 1280x480 panel running at 1:1 scale with no HiDPI backing.
At roughly 195 PPI text renders at about 56% of its usual physical size, which
is why the type is larger than it would be in a normal app.

The same panel with all 18 cores saturated and a load average of 44:

![Statsy with the machine under full load](docs/images/panel-under-load.png)

## Running

```bash
swift build && swift test
./make-app.sh
open .build/Statsy.app
```

Statsy has no Dock icon and no menu bar entry. It puts a borderless window on
whichever display measures 1280x480 and re-seats itself when the display
arrangement changes, falling back to any external display when that panel is
not attached.

To check the sampling layer without the UI:

```bash
swift run statsy-probe
```

That prints one snapshot in a form you can compare directly against `top`, `df`,
`netstat -ib` and `smc`.

## Where the numbers come from

| Reading | Source |
| --- | --- |
| CPU, per core and aggregate | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` |
| Load average | `getloadavg` |
| Core clusters | `hw.perflevelN.*` |
| Memory | `host_statistics64(HOST_VM_INFO64)` |
| Swap | `vm.swapusage` |
| Capacity, whole device | `getmntinfo` |
| Capacity, per volume | `getattrlist(ATTR_VOL_SPACEUSED)` |
| Disk throughput | IOKit, `IOBlockStorageDriver` statistics |
| Temperatures and fans | IOKit, `AppleSMC` |
| Network | IF-MIB, `IFMIB_IFDATA` |
| Processes | a streamed `/usr/bin/top` |
| Uptime | `kern.boottime` |

Five of those are not the obvious API, because the obvious API is wrong.

The memory headline is pressure-oriented rather than a copy of `top`'s "used"
total. It reports active + wired + compressed as **in use** and shows inactive
pages separately as **reclaimable**. On a representative sample that means a
70 GB in-use headline plus 44 GB reclaimable, while `top` combines both into
114 GB used. Free includes both free and speculative pages.

Process ranking needs `top` because unprivileged libproc cannot see other users'
processes. `proc_pidinfo` and `proc_pid_rusage` return EPERM for about 180 of
1050 processes here, including WindowServer and kernel_task, which are often the
largest consumers. `ps` is no substitute, since its `%CPU` column is a lifetime
average rather than an interval delta.

The SMC request struct has to be exactly 80 bytes. Swift packs later fields into
a nested struct's tail padding, producing a 76-byte request that the SMC answers
with garbage rather than an error. A test pins the layout.

`statfs` cannot tell APFS volumes apart. Every volume in a container reports the
container's block counts, so `/`, `/System/Volumes/Data` and
`/System/Volumes/VM` all compute identical usage. `getattrlist` with
`ATTR_VOL_SPACEUSED` gives per-volume figures that match `df`.

`NET_RT_IFLIST2` wraps at 4 GiB despite declaring 64-bit counters, and reported
27 MB for an interface that had carried 34 GB. The IF-MIB returns real totals.

`docs/sampling.md` has the measurements behind each of these.

## Cost

The panel refreshes at 1 Hz for about 0.2% of one core, plus roughly 1.2% for
its `top` child. Temperatures sample every five seconds instead: reading all 130
SMC sensors takes 17 ms of blocked hardware wait, and they move far more slowly
than that.

## Palette

The colours are the nonbinary pride flag: purple for CPU, yellow for memory,
white for storage, against a near-black ground. Temperatures ride a
purple-to-yellow ramp between 30 and 90 degrees.

## Requirements

macOS 14 or later, Swift 6. Built and run on 26.5.
