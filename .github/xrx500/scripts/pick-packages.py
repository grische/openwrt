#!/usr/bin/env python3
"""Pick one copy of every shared package for the download tree.

Usage: pick-packages.py <apk> <root> <plan-dir> <image-dir> <out-dir> <tree>... > packages.tsv

Each <tree> is <name>=<dir>, where <dir> holds one directory of .apk files per
feed. The first tree is the target job's. The others are the shards', named
like their files in <plan-dir>, such as shard-06. <image-dir> is the target
job's image directory, whose *-targz-rootfs.tar.gz files hold the rootfs of
each board.

Every shard also builds the dependencies of its own packages, so most packages
arrive several times. Their build options can depend on what else their job
selected. iproute2 only links tc-tiny against libmnl if devlink, rdma or dcb
is selected, for example. The shard that owns a source in the plan selects all
of its packages, as a full build does, so that shard's copy is the most
complete. The target job selects only what the images and the kernel modules
need.

The target job's copy of a package that is installed in a board's image wins,
because the images were built with it. For every other package the copy of
the shard that owns its source wins. The target job's copy comes next, then
the copies of the other shards in the given order.

The chosen copies go to <out-dir>/<feed>/. Each output line names the file of
one chosen copy, relative to <out-dir>, and the tree it came from.
"""

import glob
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile


def read_feed(apk, root, path):
    """The name, source and file of every package in one feed directory."""
    files = sorted(f for f in os.listdir(path) if f.endswith(".apk"))
    if not files:
        return []
    # One index of the whole directory is much faster than reading every
    # package on its own, and it holds the metadata of each.
    with tempfile.TemporaryDirectory() as tmp:
        index = os.path.join(tmp, "packages.adb")
        subprocess.run([apk, "mkndx", "--root", root, "--allow-untrusted",
                        "--output", index] + files,
                       cwd=path, check=True, stdout=subprocess.DEVNULL)
        dump = subprocess.run([apk, "adbdump", "--format", "json", index],
                              check=True, stdout=subprocess.PIPE).stdout
    out = []
    for pkg in json.loads(dump).get("packages", []):
        # OpenWrt names every package file <name>-<version>.apk, which is
        # also the file an apk client asks a feed for. The origin is the
        # source's directory, whose last part is the source name in the plan.
        fname = "%s-%s.apk" % (pkg["name"], pkg["version"])
        src = os.path.basename(pkg.get("origin", ""))
        out.append((pkg["name"], src, fname))
    named = {f for _, _, f in out}
    for f in files:
        if f not in named:
            print("::warning::%s is not named after its package and is left out."
                  % os.path.join(path, f), file=sys.stderr)
    present = set(files)
    return [p for p in out if p[2] in present]


def image_packages(path):
    """The names of the packages installed in the image of any board."""
    rootfs = sorted(glob.glob(os.path.join(path, "*-targz-rootfs.tar.gz")))
    if not rootfs:
        sys.exit("No *-targz-rootfs.tar.gz in %s, so the image packages are unknown."
                 % path)
    names = set()
    for f in rootfs:
        with tarfile.open(f) as tar:
            for member in tar:
                if member.name.lstrip("./") == "lib/apk/db/installed":
                    for line in tar.extractfile(member):
                        if line.startswith(b"P:"):
                            names.add(line[2:].strip().decode())
                    break
            else:
                sys.exit("%s holds no lib/apk/db/installed." % f)
    return names


def main():
    if len(sys.argv) < 7:
        sys.exit(__doc__.strip().splitlines()[2])
    apk, root, plan, images, out = sys.argv[1:6]
    trees = [arg.partition("=")[::2] for arg in sys.argv[6:]]
    in_image = image_packages(images)

    owner = {}
    for f in sorted(os.listdir(plan)):
        if f.startswith("shard-") and f.endswith(".list"):
            with open(os.path.join(plan, f)) as lines:
                for line in lines:
                    owner[line.strip()] = f[:-len(".list")]

    best = {}
    for i, (tree, path) in enumerate(trees):
        if not os.path.isdir(path):
            continue
        for feed in sorted(os.listdir(path)):
            d = os.path.join(path, feed)
            if not os.path.isdir(d):
                continue
            # Even a feed without packages gets its directory, so that
            # assemble.sh warns about it.
            os.makedirs(os.path.join(out, feed), exist_ok=True)
            for name, src, f in read_feed(apk, root, d):
                rank = (i > 0 or name not in in_image, owner.get(src) != tree, i)
                if name not in best or rank < best[name][0]:
                    best[name] = (rank, feed, d, f, tree)

    count = {"image": 0, "owner": 0, "target": 0, "other": 0}
    for name in sorted(best):
        rank, feed, d, f, tree = best[name]
        shutil.copy2(os.path.join(d, f), os.path.join(out, feed, f))
        print("%s/%s\t%s" % (feed, f, tree))
        count["image" if not rank[0] else "owner" if not rank[1]
              else "target" if not rank[2] else "other"] += 1
    print("%d packages, %d from the target job because an image holds them, "
          "%d from the shard owning their source, %d more from the target job "
          "and %d from another shard" % (
              len(best), count["image"], count["owner"], count["target"],
              count["other"]),
          file=sys.stderr)


if __name__ == "__main__":
    main()
