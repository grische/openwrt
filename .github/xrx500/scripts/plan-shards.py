#!/usr/bin/env python3
"""Split the shared packages into shards for parallel SDK builds.

Reads tmp/.packageinfo from a tree with every feed installed and writes, per
shard, <out>/shard-NN.packages (the binary packages the shard selects, which
are all packages of its own sources and of every source they need) and
<out>/shard-NN.list (the sources it owns, whose packages pick-packages.py
prefers from this shard), plus <out>/matrix.json (the job matrix) and
<out>/plan.txt (a summary).

Only shared packages are planned. Kernel modules and target-specific
(nonshared) packages come from the target build.

A shard builds the dependencies of its own packages as well, so its cost is
everything in the dependency closure of its packages: their sources, the
sources of the packages they depend on, and the target and host builds those
sources need. A shard selects every package of each source in the closure, so
the dependencies of those packages are part of it too. Sources go, largest
closure first, to the shard where they add the least cost on top of what the
shard already builds. Packages that share an expensive toolchain, such as
Rust, Go or Python, end up together that way.

Costs are minutes on one runner. --weights names a file written by
collect-weights.py from a previous run, which replaces the estimates below for
every source it measured. Its CPU times are divided by the CPUs a runner keeps
busy, which also accounts for the time a shard spends waiting on serial
builds.
"""

import argparse
import json
import os
import re
import sys

# Rough minutes for a target build. Everything not listed costs DEFAULT_SRC.
HEAVY_SRC = {
    "wpewebkit": 300, "llvm": 150, "gcc": 90, "qt5base": 60, "boost": 60,
    "mariadb": 60, "freeswitch": 60, "node": 60, "samba4": 45, "erlang": 40,
    "asterisk": 40, "qemu": 40, "grpc": 40, "mesa": 40, "php8": 30,
    "python3": 30, "gtk": 30, "gzdoom": 30, "ruby": 25, "postgresql": 25,
    "frr": 25, "kamailio": 25, "gdb": 25, "ffmpeg": 20, "protobuf": 20,
    "spirv-tools": 20, "glslang": 20, "assimp": 20, "dockerd": 20,
    "perl": 15, "icu": 15, "binutils": 15, "strongswan": 15, "squid": 15,
    "hostapd": 15, "weston": 15, "openvswitch": 15, "zabbix": 15,
}
DEFAULT_SRC = 2

# Rough minutes for a host build. Everything not listed costs DEFAULT_HOST.
HEAVY_HOST = {
    "rust": 120, "node": 50, "llvm": 60, "golang": 15, "python3": 10,
    "qt5base": 20, "perl": 5, "ruby": 10, "erlang": 15, "php8": 10,
}
DEFAULT_HOST = 1

# Minutes of extra work below which an item joins a shard regardless of its
# load, because the shard already builds nearly all of it.
SMALL = 10

# Core packages of the SDK itself, never installed from a feed.
CORE = {"linux", "toolchain"}

TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*(/host)?$")
KCONFIG_ENTRY = re.compile(
    r"^\s*(?:(?:menu)?config\s+(\S+)|choice|endchoice|menu|endmenu|if|endif|comment)\b")
KCONFIG_DEFAULT_ON = re.compile(r"^\s*default\s+[ym]\b")
KCONFIG_SOURCE = re.compile(r'^\s*source\s+"([^"]+)"')

# Package options that can default to on, such as PACKAGE_TAR_XZ, filled in
# by parse() from the packages' Config blocks.
OPTIONS = set()

# The names of all packages and of what they provide, filled in by parse().
PACKAGES = set()


def scan_config(lines, root):
    """Add the package options in Kconfig lines that can default to on."""
    option = ""
    for line in lines:
        match = KCONFIG_SOURCE.match(line)
        if match:
            try:
                with open(os.path.join(root, match.group(1)), errors="replace") as f:
                    scan_config(f.read().splitlines(), root)
            except OSError:
                pass
            continue
        match = KCONFIG_ENTRY.match(line)
        if match:
            option = match.group(1) or ""
        elif option.startswith("PACKAGE_") and KCONFIG_DEFAULT_ON.match(line):
            OPTIONS.add(option)


def parse(path):
    sources = {}
    src = None
    pkg = None
    # Config blocks source their files relative to the top of the tree.
    root = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    config = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line == "Config:":
                config = []
                continue
            if config is not None:
                if line == "@@":
                    scan_config(config, root)
                    config = None
                else:
                    config.append(line)
                continue
            key, _, value = line.partition(": ")
            if key == "Source-Makefile":
                name = os.path.basename(os.path.dirname(value))
                src = sources.setdefault(name, {
                    "name": name, "bdeps": set(), "hdeps": set(), "packages": []})
                pkg = None
            elif src is None:
                continue
            elif line == "@@":
                pkg = None
            elif key == "Build-Depends" and pkg is None:
                src["bdeps"].update(value.split())
            elif key == "Build-Depends/host" and pkg is None:
                src["hdeps"].update(value.split())
            elif key == "Package":
                pkg = {"name": value.strip(), "src": src["name"], "repo": None,
                       "buildonly": False, "hidden": False, "depends": [],
                       "provides": []}
                src["packages"].append(pkg)
            elif pkg is not None:
                if key == "Repository":
                    pkg["repo"] = value.strip()
                elif key == "Build-Only":
                    pkg["buildonly"] = True
                elif key == "Hidden":
                    pkg["hidden"] = True
                elif key == "Depends":
                    pkg["depends"] = value.split()
                elif key == "Provides":
                    pkg["provides"] = [p.lstrip("@") for p in value.split()]
    # Some Config blocks declare the symbols of packages, such as boost's.
    OPTIONS.difference_update("PACKAGE_" + p["name"]
                              for s in sources.values() for p in s["packages"])
    PACKAGES.update(n for s in sources.values() for p in s["packages"]
                    for n in [p["name"]] + p["provides"])
    return sources


# Symbols shard.config turns off, filled in by main().
DISABLED = set()


def shared(pkg):
    """Whether a shard builds this package."""
    return (pkg["repo"] and not pkg["buildonly"] and not pkg["hidden"]
            and "PACKAGE_" + pkg["name"] not in DISABLED)


def optional_dep(token):
    """Whether a dependency token has the form PACKAGE_foo:foo."""
    cond, _, name = token.lstrip("+").rpartition(":")
    return cond.lstrip("+") == "PACKAGE_" + name.lstrip("+")


def dep_name(token):
    """The package or source a dependency token names, if it can apply.

    Returns the name and the package whose selection the dependency waits
    for, or None for both. A conditional dependency such as
    MESA_USE_LLVM:llvm counts unless shard.config turns its symbol off. One on
    PACKAGE_foo applies once foo is selected, so it waits for foo. Package
    options such as PACKAGE_TAR_XZ share that prefix, but the shard keeps them
    at their defaults, so those that can default to on count like any other
    symbol. PACKAGE_foo:foo counts at once, because a package uses that form
    for a feature it enables only if foo is selected. A full build selects
    foo, so the shard selects it too.

    @foo makes a package selectable only once foo is selected. If foo is
    exactly the name of a package or of what a package provides, a full build
    selects it, so the shard selects it too unless shard.config turns it off.
    Every other @ token names a config symbol or an expression, such as
    @TARGET_x or @!SMALL_FLASH, and does not count.
    """
    if token.startswith("@"):
        name = token[1:]
        if name in PACKAGES and "PACKAGE_" + name not in DISABLED:
            return name, None
        return None, None
    token = token.lstrip("+")
    if not token or token.startswith("@") or "(" in token:
        return None, None
    after = None
    if ":" in token:
        optional = optional_dep(token)
        cond, token = token.rsplit(":", 1)
        cond = cond.lstrip("+")
        if cond in DISABLED or "@" in cond:
            return None, None
        if cond.startswith("PACKAGE_") and cond not in OPTIONS and not optional:
            after = cond[len("PACKAGE_"):]
            if not TOKEN.match(after):
                return None, None
    token = token.lstrip("+")
    return (token, after) if TOKEN.match(token) else (None, None)


class Graph:
    def __init__(self, sources, weights):
        self.sources = sources
        self.weights = weights
        self.pkgs = {}
        for src in sources.values():
            for p in src["packages"]:
                self.pkgs.setdefault(p["name"], p)
        for src in sources.values():
            for p in src["packages"]:
                for v in p["provides"]:
                    self.pkgs.setdefault(v, p)
        self.memo = {}

    def cost(self, node):
        kind, name = node
        if (kind, name) in self.weights:
            return self.weights[(kind, name)]
        if kind == "host":
            return HEAVY_HOST.get(name, DEFAULT_HOST)
        return HEAVY_SRC.get(name, DEFAULT_SRC)

    def build_deps(self, node):
        kind, name = node
        src = self.sources.get(name)
        if src is None:
            return []
        out = []
        for token in src["hdeps"] if kind == "host" else src["bdeps"]:
            dep, after = dep_name(token)
            if not dep or after:
                continue
            if dep.endswith("/host"):
                out.append(("host", dep[:-5]))
            elif "/" not in dep and kind == "src":
                out.append(("src", dep))
        return [d for d in out if d[1] in self.sources and d[1] not in CORE]

    def selectable(self, name):
        src = self.sources.get(name)
        if src is None:
            return []
        return [p["name"] for p in src["packages"] if shared(p)]

    def closure(self, start_nodes, start_pkgs):
        """Build nodes and packages needed for the given nodes and packages.

        A full build selects every package, and the build of a source can
        depend on which of its packages are selected. libpcap only supports
        remote capture if rpcapd is selected, for example, and a source whose
        variants install the same library leaves whichever was built last. So
        every source in the closure gets all of its packages selected, whether
        it is a build dependency or only a runtime one. Their dependencies join
        the closure in turn. A dependency on PACKAGE_foo joins once foo is in
        the closure.
        """
        nodes = set()
        pkgs = set()
        waiting = {}
        stack = list(start_nodes)
        pstack = list(start_pkgs)
        while stack or pstack:
            while pstack:
                p = self.pkgs.get(pstack.pop())
                if p is None or p["name"] in pkgs:
                    continue
                pkgs.add(p["name"])
                pstack.extend(waiting.pop(p["name"], ()))
                if p["src"] not in CORE:
                    stack.append(("src", p["src"]))
                for token in p["depends"]:
                    dep, after = dep_name(token)
                    if not dep:
                        continue
                    if after is None or after in pkgs:
                        pstack.append(dep)
                    else:
                        waiting.setdefault(after, []).append(dep)
            while stack:
                node = stack.pop()
                if node in nodes:
                    continue
                nodes.add(node)
                if node[0] == "src":
                    pstack.extend(self.selectable(node[1]))
                stack.extend(self.build_deps(node))
        return nodes, pkgs


def load_disabled(path):
    if not path:
        return set()
    with open(path) as f:
        return set(re.findall(r"^# CONFIG_(\S+) is not set", f.read(), re.M))


def load_weights(path, cores):
    weights = {}
    if not path:
        return weights
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            name, kind, cpu = line.split()
            # CPU seconds over the CPUs a runner keeps busy, as minutes.
            weights[(kind, name)] = float(cpu) / cores / 60
    return weights


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("packageinfo")
    ap.add_argument("out")
    ap.add_argument("--shards", type=int, default=20)
    ap.add_argument("--weights")
    ap.add_argument("--config", help="shard.config, for the symbols it disables")
    ap.add_argument("--cores", type=float, default=3.3,
                    help="CPUs a runner keeps busy, measured at 3.3 on a 4-core runner")
    args = ap.parse_args()

    DISABLED.update(load_disabled(args.config))
    sources = parse(args.packageinfo)
    graph = Graph(sources, load_weights(args.weights, args.cores))

    items = []
    for src in sources.values():
        if src["name"] in CORE:
            continue
        own = [p for p in src["packages"] if shared(p)]
        if not own:
            continue
        names = [p["name"] for p in own]
        nodes, _ = graph.closure([("src", src["name"])], names)
        # The shard selects every package of every source in the closure.
        # Kconfig adds the rest, such as hidden packages.
        select = {q for n in nodes if n[0] == "src" for q in graph.selectable(n[1])}
        items.append({"name": src["name"], "feed": own[0]["repo"],
                      "packages": names, "select": sorted(select),
                      "nodes": nodes, "cost": sum(graph.cost(n) for n in nodes)})
    if not items:
        sys.exit("no shared packages found in " + args.packageinfo)

    n = max(1, args.shards)
    order = sorted(items, key=lambda i: (-i["cost"], i["name"]))
    for item in order:
        item["costs"] = {x: graph.cost(x) for x in item["nodes"]}

    def pack(cap):
        """Place every item, reusing builds first, without passing cap.

        An item may always open an empty shard, and may join a shard that
        already builds nearly all of it, even past the cap.
        """
        shards = [{"nodes": set(), "load": 0.0, "items": []} for _ in range(n)]
        for item in order:
            added = [sum(c for x, c in item["costs"].items() if x not in s["nodes"])
                     for s in shards]
            fits = [j for j in range(n)
                    if not shards[j]["items"] or added[j] <= SMALL
                    or shards[j]["load"] + added[j] <= cap]
            if not fits:
                return None
            j = min(fits, key=lambda j: (added[j], shards[j]["load"], j))
            shards[j]["load"] += added[j]
            shards[j]["nodes"] |= item["nodes"]
            shards[j]["items"].append(item)
        return shards

    # The smallest cap at which everything fits keeps the longest shard short
    # while builds are still shared wherever that is possible.
    lo, hi = 0.0, sum(i["cost"] for i in items)
    shards = pack(hi)
    while hi - lo > 1:
        mid = (lo + hi) / 2
        packed = pack(mid)
        if packed:
            hi, shards = mid, packed
        else:
            lo = mid

    os.makedirs(args.out, exist_ok=True)
    matrix = []
    summary = []
    heavy = sorted(set(HEAVY_HOST) | {"python3", "perl"})
    for j, s in enumerate(shards):
        if not s["items"]:
            continue
        sid = "%02d" % (j + 1)
        with open(os.path.join(args.out, "shard-%s.list" % sid), "w") as f:
            f.writelines(i["name"] + "\n" for i in sorted(s["items"], key=lambda i: i["name"]))
        with open(os.path.join(args.out, "shard-%s.packages" % sid), "w") as f:
            f.writelines(p + "\n" for p in sorted({p for i in s["items"] for p in i["select"]}))
        tags = [h for h in heavy if ("host", h) in s["nodes"]]
        label = sid + (" (" + ", ".join(tags) + ")" if tags else "")
        matrix.append({"shard": sid, "name": label})
        summary.append("shard %s: %4d sources, %4d packages, ~%4.0f min%s" % (
            sid, len(s["items"]), sum(len(i["packages"]) for i in s["items"]),
            s["load"], "  [" + ", ".join(tags) + "]" if tags else ""))

    with open(os.path.join(args.out, "matrix.json"), "w") as f:
        json.dump(matrix, f, separators=(",", ":"))
    feeds = {}
    for item in items:
        feeds[item["feed"]] = feeds.get(item["feed"], 0) + 1
    unique = set().union(*(i["nodes"] for i in items))
    header = ("%d sources with shared packages (%s), %s weights\n"
              "~%.0f min of distinct builds, ~%.0f min with each shard's duplicates") % (
        len(items), ", ".join("%s %d" % kv for kv in sorted(feeds.items())),
        "measured" if graph.weights else "estimated",
        sum(graph.cost(x) for x in unique), sum(s["load"] for s in shards))
    with open(os.path.join(args.out, "plan.txt"), "w") as f:
        f.write(header + "\n" + "\n".join(summary) + "\n")
    print(header)
    print("\n".join(summary))


if __name__ == "__main__":
    main()
