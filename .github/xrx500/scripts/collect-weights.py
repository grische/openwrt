#!/usr/bin/env python3
"""Turn the shards' timings.txt files into weights for plan-shards.py.

Usage: collect-weights.py <timings.txt>... > weights.tsv

Each output line is "<source> <src|host> <cpu-seconds>", the CPU time of the
target or host build of one source package. A source built in several shards
keeps its longest time, and the build variants of a source add up.
"""

import sys


def main():
    best = {}
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if not line.startswith("time: "):
                    continue
                # time: package/feeds/<feed>/<name>[/<variant>]/<step>#user#sys#real
                step, _, times = line[6:].strip().partition("#")
                try:
                    user, sys_, _real = (float(t) for t in times.split("#"))
                except ValueError:
                    continue
                # Everything the planner plans lives in a feed in the SDK.
                parts = step.split("/")
                if parts[:2] != ["package", "feeds"] or len(parts) < 5:
                    continue
                kind = {"compile": "src", "host-compile": "host"}.get(parts[-1])
                if not kind:
                    continue
                key = (parts[3], kind, "/".join(parts[4:-1]))
                best[key] = max(best.get(key, 0.0), user + sys_)

    total = {}
    for (name, kind, _variant), cpu in best.items():
        total[(name, kind)] = total.get((name, kind), 0.0) + cpu

    print("# source kind cpu-seconds, from collect-weights.py")
    for (name, kind), cpu in sorted(total.items()):
        print("%s %s %.0f" % (name, kind, cpu))


if __name__ == "__main__":
    main()
