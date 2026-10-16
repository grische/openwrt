# xRX500 release build

`.github/workflows/xrx500.yml` builds OpenWrt for the Intel MIPS xRX500 target
(AVM FRITZ!Box 7560, 7580 and 7590) on every push to `intel-mips-xrx500-ci`.
A run produces the images for all three boards, every kernel module, the SDK,
the ImageBuilder and every package of the base, packages, luci, routing,
telephony and video feeds, all signed with one key.

The packages have to come from this build. This tree builds without MIPS16,
while upstream's `mips_24kc` packages use it, so those die with a bus error on
these boards.

## Repository settings

| Kind     | Name              | Value                                                                  |
| -------- | ----------------- | ---------------------------------------------------------------------- |
| Secret   | `XRX500_APK_KEY`  | The apk signing key, a PEM-encoded P-256 private key                   |
| Variable | `XRX500_REPO_URL` | The URL the download tree is served from, e.g. `https://example.org/xrx500/snapshots` |
| Variable | `XRX500_SHARDS`   | Optional. The number of package jobs, 20 by default                    |

A run fails in its first minute if either of the first two is missing.

Create the key once and keep a copy somewhere safe. Every image trusts exactly
this key, so a new key means users have to reflash or install the new public
key by hand.

```sh
openssl ecparam -name prime256v1 -genkey -noout -out xrx500-apk-key.pem
gh secret set XRX500_APK_KEY -R grische/openwrt < xrx500-apk-key.pem
gh variable set XRX500_REPO_URL -R grische/openwrt --body https://example.org/xrx500/snapshots
```

`XRX500_REPO_URL` becomes `CONFIG_VERSION_REPO`, so it is baked into the images.
They fetch packages from `<url>/targets/intel-mips/xrx500/packages/` and
`<url>/packages/mips_24kc/<feed>/`, the same layout as downloads.openwrt.org.

## How a run is split

1. **target** builds the host tools, the toolchain, the kernel, all kernel
   modules (`CONFIG_ALL_KMODS`), the target-specific packages
   (`CONFIG_ALL_NONSHARED`), the images, the SDK and the ImageBuilder. It also
   splits the shared packages into shards with `scripts/plan-shards.py`.
2. **packages** builds one shard per job in the SDK. Each shard installs every
   feed and selects its own packages. It also selects every package of each
   source these need at build time or at runtime, because the build of a source
   can depend on which of its packages are selected. A full build selects them
   all as well. libpcap only supports remote capture if rpcapd is selected, for
   example, and the variants of libwebsockets install the same library. Kconfig
   adds the rest, such as hidden packages. The SDK turns every package the
   target job built into a default, so a shard drops those defaults first. Only
   the kernel's own modules keep theirs, because nothing else defines them in
   the SDK. The shard then turns off every other package that is on but not in
   its list, while package options keep their defaults. Every shard rebuilds
   the dependencies of its packages, so the planner packs packages that share
   expensive builds (Rust, Go, Python and so on) into the same shard. OpenWrt's
   source mirror sometimes fails for a while, so a failed source download gets
   three more attempts after growing pauses. A source that still fails is
   listed as failed to download. A shard stops after 300 minutes so that what
   it built is still uploaded, and the run summary names any shard that ran out
   of time. `shard.config` holds settings that every shard applies on top of
   the target configuration. It turns off Mesa's LLVM drivers, because LLVM
   alone takes about four hours of a runner and these boards have no GPU. It
   also turns off two Vulkan drivers that would pull in Mesa's Vulkan build
   regardless.
3. **assemble** merges everything, indexes and signs every feed, and fails
   unless `apk verify` accepts each index with the public key. Most packages
   arrive from several jobs, and their build options can depend on what else
   their job selected. A package that a board's image holds comes from the
   target job, because the images were built with it. The rootfs tarball of
   each board lists these packages. Any other package comes from the shard
   that owns its source, because that shard selects all of the source's
   packages. The target job only selects what the images and the kernel
   modules need, so its copy of tc-tiny lacks libmnl, for example. After the
   upload assemble unpacks the ImageBuilder, points it at the assembled tree
   and builds an image with LuCI for every board, as a user would.

The target job takes about three hours and the shards up to five and a half
more. Packages that fail to build do not fail the run. The summary of the
assemble job lists them by job, including failed host builds.

## Output

| Artifact                                     | Contents                                                     |
| -------------------------------------------- | ------------------------------------------------------------ |
| `openwrt-<rev>-intel-mips-xrx500-targets`    | `targets/intel-mips/xrx500/` with the images, `packages/` (kernel modules and target packages), the SDK, the ImageBuilder, `profiles.json` and `sha256sums` |
| `openwrt-<rev>-intel-mips-xrx500-packages`   | `packages/mips_24kc/<feed>/` for every feed                   |
| `openwrt-<rev>-intel-mips-xrx500-report`     | `failed.txt`, `packages.tsv` with the job each feed package comes from, `weights.tsv` and `public-key.pem`, not meant for hosting |

The first two unpack side by side into the directory `XRX500_REPO_URL` points
at. Replace the previous tree rather than merging into it, or packages from
older runs pile up next to the index.

```sh
gh run download <run-id> -R grische/openwrt -p 'openwrt-*-targets' -p 'openwrt-*-packages' -D dl
rsync -a --delete dl/*-targets/targets/ host:/srv/xrx500/snapshots/targets/
rsync -a --delete dl/*-packages/packages/ host:/srv/xrx500/snapshots/packages/
```

Artifacts expire after the repository's retention period, 90 days by default.

## Shard weights

Without measurements the planner estimates build times from a short list of
known heavy sources. Every run measures the real CPU time of each build step
and the report artifact carries the result as `weights.tsv`. Copy it to
`.github/xrx500/weights.tsv` and commit it, and the next plan balances the
shards on measured times. Sources a run did not reach keep their estimate, so
refreshing the file after a run with timed-out shards still improves the plan.
The planner divides CPU time by 3.3, the number of CPUs a 4-core runner kept
busy on average in the first measured run.

## Keeping the branch current

The workflow only runs on a push, and that is deliberate.

- The feeds are pinned to the date of the upstream commit the core is based
  on, so a rebuild of an unchanged branch produces the same content.
- Moving the feeds ahead of the core risks packages that no longer fit it.
- A scheduled workflow only runs on the default branch of the fork, which is
  not this one.

`intel-mips-xrx500-ci` is the main line `intel-mips-xrx500` plus the CI
commits. A maintenance cycle starts when the main line moves.

1. Rebase the CI commits onto the new main line.
2. Re-pin the feeds to the upstream commit the main line is based on.
3. Optionally copy `weights.tsv` from the report artifact of the last run to
   `.github/xrx500/weights.tsv` and commit it, so the plan uses fresh build
   times.
4. Push, which starts the run.
5. Verify the run. Its summary lists failed packages and shards that ran out
   of time.
6. Publish the run with freifunkMUC's `xrx500-downloader <run-id>`, or as
   described under Output.

```sh
git rebase --onto intel-mips-xrx500 <old-main-line-tip> intel-mips-xrx500-ci
.github/xrx500/scripts/update-feeds.sh <upstream-base-commit>
```

Two of the commits change things outside `.github/xrx500/`. One drops
`DEFAULT := n` from the three boards in `target/linux/intel-mips/image/seale.mk`,
because the ImageBuilder refuses to build a board that is off by default. The
other lists `intel-mips-xrx500-ci` in `branches-ignore` of upstream's push
workflows, so a push here does not start their generic builds as well.

## Files

| File                          | Purpose                                                            |
| ----------------------------- | ------------------------------------------------------------------ |
| `config.seed`                 | The target build's configuration, checked line by line after `make defconfig` |
| `feeds.conf`                  | The feeds, pinned to commits                                       |
| `shard.config`                | Settings every package shard applies on top of the target's        |
| `weights.tsv`                 | Optional. Measured build times for the shard plan                  |
| `scripts/prepare-runner.sh`   | Frees disk space and installs the build dependencies               |
| `scripts/setup-key.sh`        | Installs the signing key where the build expects it                |
| `scripts/configure-target.sh` | Writes and checks the target `.config`                             |
| `scripts/plan-shards.py`      | Splits the shared packages into shards                             |
| `scripts/build-shard.sh`      | Builds one shard in the SDK                                        |
| `scripts/collect-weights.py`  | Turns the shards' build times into `weights.tsv`                   |
| `scripts/check-images.sh`     | Fails unless every board has all of its images                     |
| `scripts/assemble.sh`         | Merges, indexes, signs and verifies the download tree              |
| `scripts/pick-packages.py`    | Picks the copy of every package that goes into the feeds           |
| `scripts/ib-smoke.sh`         | Builds every board in the ImageBuilder against the assembled tree  |
| `scripts/report-errors.sh`    | Prints the logs of failed packages                                 |
| `scripts/update-feeds.sh`     | Re-pins `feeds.conf`                                               |
