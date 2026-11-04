"""Memory and CPU of Briefly's processes against the §13 budgets (plan 1.2).

    jac run bench/mem.jac [desktop|lean|both] [--runs N] [--settle S] [--window S] [--phase idle|meeting]
                          [--label NAME]

Each run starts the profile fresh, waits until it is up, lets it settle, measures CPU over a window,
then memory, and stops it the normal way (the desktop window is closed through X11, the lean server
gets SIGTERM). Memory is summed per category: `host` (the desktop binary, which also runs the
server in-process), `webkit` (its web and network processes), `server` (the lean `jac run`
processes) and `postgres` (the profile's cluster). PSS is the budget figure: summed RSS counts every
shared page once per process, so it overstates a multi-process app (11 PostgreSQL processes share
most of their memory); RSS is reported beside it. PSS also shifts with what else on the machine maps
the same libraries, so USS (private memory only) is reported as the floor that does not. CPU is
normalised over all cores.

Writes bench/results/mem-<profile>-<phase>[-<label>]-<UTC time>.json with every run, the median and
the range (and JAC_SERVE_WORKERS when it is set, e.g. to measure a one-worker lean server),
and exits 1 when a median misses its budget. The `meeting` phase is run by the owner during a real
call with Meet and VS Code open (§13); this script only labels and budgets it.
Before the desktop profile: `jac build desktop`. Before the lean profile: `jac build lean`.
"""
import json;
import os;
import platform;
import shutil;
import signal;
import statistics;
import subprocess;
import sys;
import tempfile;
import time;
import urllib.request;

glob ROOT: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
     DESKTOP_DIR: str = os.path.join(ROOT, ".jac", "client", "desktop", "desktop"),
     DESKTOP_DATA: str = os.path.expanduser(
         "~/.local/share/io.github.dennisovich254.briefly.lean"
     ),
     LEAN_JAB: str = os.path.join(ROOT, "dist", "briefly.jab"),
     LEAN_PORT: int = 8040,
     # signal.SIGKILL is <Unknown> to the type checker, which then refuses the file (JD-021).
     KILL: int = signal.Signals.SIGKILL,
     TICKS: int = os.sysconf("SC_CLK_TCK"),
     CORES: int = os.cpu_count() or 1;

obj Budget {
    has pss_mb: float,
        cpu_percent: float;
}

glob BUDGETS: dict[str, Budget] = {
         "idle/desktop": Budget(pss_mb=300, cpu_percent=2),
         "idle/lean": Budget(pss_mb=200, cpu_percent=2),
         "meeting/desktop": Budget(pss_mb=600, cpu_percent=15),
         "meeting/lean": Budget(pss_mb=500, cpu_percent=15)
     };

obj Proc {
    has pid: int,
        ppid: int,
        cmd: str;
}

obj Group {
    has processes: int,
        pss_mb: float,
        rss_mb: float,
        uss_mb: float;
}

obj Run {
    has cpu_percent: float,
        pss_mb: float,
        rss_mb: float,
        uss_mb: float,
        groups: dict[str, Group],
        startup_s: float = 0.0,
        stop_s: float = 0.0,
        postgres_stop_s: float | None = None,
        note: str = "";

    def to_json -> dict[str, object] {
        return {
            "cpu_percent": self.cpu_percent,
            "pss_mb": self.pss_mb,
            "rss_mb": self.rss_mb,
            "uss_mb": self.uss_mb,
            "groups": {
                name: {
                    "processes": g.processes,
                    "pss_mb": g.pss_mb,
                    "rss_mb": g.rss_mb,
                    "uss_mb": g.uss_mb
                } for (name, g) in self.groups.items()
            },
            "startup_s": self.startup_s,
            "stop_s": self.stop_s,
            "postgres_stop_s": self.postgres_stop_s,
            "note": self.note
        };
    }
}

def processes -> dict[int, Proc] {
    found: dict[int, Proc] = {};
    for name in os.listdir("/proc") {
        if not name.isdigit() {
            continue;
        }
        try {
            with open(f"/proc/{name}/stat") as fh {
                stat = fh.read();
            }
            with open(f"/proc/{name}/cmdline", "rb") as fh {
                cmd = fh.read().replace(b"\0", b" ").decode(errors="replace").strip();
            }
            found[int(name)] = Proc(
                pid=int(name), ppid=int(stat.rsplit(")", 1)[1].split()[1]), cmd=cmd
            );
        } except OSError {
            continue;
        }
    }
    return found;
}

def descendants(roots: list[int], table: dict[int, Proc]) -> list[int] {
    seen = set(roots);
    grew = True;
    while grew {
        grew = False;
        for proc in table.values() {
            if proc.ppid in seen and proc.pid not in seen {
                seen.add(proc.pid);
                grew = True;
            }
        }
    }
    return sorted(
        pid
        for pid in seen
        if pid in table
    );
}

"""PostgreSQL processes of the cluster whose data directory contains `data_dir`."""
def cluster(data_dir: str, table: dict[int, Proc]) -> list[int] {
    leaders = [
        proc.pid
        for proc in table.values()
        if "/postgres -D " in proc.cmd and data_dir in proc.cmd
    ];
    return descendants(leaders, table);
}

"""(RSS, PSS, USS) of one process in kB, from /proc/<pid>/smaps_rollup."""
def rollup(pid: int) -> tuple[int, int, int] {
    rss = 0;
    pss = 0;
    uss = 0;
    try {
        with open(f"/proc/{pid}/smaps_rollup") as fh {
            for line in fh {
                if line.startswith("Rss:") {
                    rss = int(line.split()[1]);
                } elif line.startswith("Pss:") {
                    pss = int(line.split()[1]);
                } elif line.startswith("Private_Clean:")
                    or line.startswith("Private_Dirty:") {
                    uss += int(line.split()[1]);
                }
            }
        }
    } except OSError {}
    return (rss, pss, uss);
}

def cpu_ticks(pid: int) -> int {
    try {
        with open(f"/proc/{pid}/stat") as fh {
            fields = fh.read().rsplit(")", 1)[1].split();
        }
        return int(fields[11]) + int(fields[12]);
    } except OSError {
        return 0;
    }
}

"""CPU over `window` seconds (normalised over all cores), then memory per group."""
def measure(groups: dict[str, list[int]], window: float) -> Run {
    pids = [pid for members in groups.values() for pid in members];
    before = {pid: cpu_ticks(pid) for pid in pids};
    time.sleep(window);
    used = sum(max(0, cpu_ticks(pid) - before[pid]) for pid in pids);
    sized: dict[str, Group] = {};
    for (name, members) in groups.items() {
        sizes = [rollup(pid) for pid in members];
        sized[name] = Group(
            processes=len(members),
            rss_mb=round(sum(s[0] for s in sizes) / 1024, 1),
            pss_mb=round(sum(s[1] for s in sizes) / 1024, 1),
            uss_mb=round(sum(s[2] for s in sizes) / 1024, 1)
        );
    }
    return Run(
        cpu_percent=round(100 * used / TICKS / window / CORES, 2),
        pss_mb=round(sum(g.pss_mb for g in sized.values()), 1),
        rss_mb=round(sum(g.rss_mb for g in sized.values()), 1),
        uss_mb=round(sum(g.uss_mb for g in sized.values()), 1),
        groups=sized
    );
}

def wait_until(check: Callable[[], bool], timeout: float, what: str) {
    deadline = time.monotonic() + timeout;
    while time.monotonic() < deadline {
        if check() {
            return;
        }
        time.sleep(1);
    }
    raise RuntimeError(f"timed out after {timeout:.0f} s waiting for {what}");
}

def desktop_up(app_pid: int) -> bool {
    table = processes();
    kids = descendants([app_pid], table);
    has_webkit = any("WebKitWebProcess" in table[pid].cmd for pid in kids);
    return has_webkit and len(cluster(DESKTOP_DATA, table)) > 0;
}

def run_desktop(settle: float, window: float) -> Run {
    launcher = os.path.join(DESKTOP_DIR, "briefly-launch.sh");
    if not os.path.exists(launcher) {
        raise RuntimeError(
            f"no desktop artifact at {DESKTOP_DIR}: run jac build desktop"
        );
    }
    started = time.monotonic();
    app = subprocess.Popen(
        [launcher],
        cwd=DESKTOP_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        start_new_session=True
    );
    wait_until(
        lambda -> bool { return desktop_up(app.pid); },
        120,
        "the desktop window and its PostgreSQL"
    );
    startup_s = round(time.monotonic() - started, 1);
    time.sleep(settle);
    table = processes();
    kids = descendants([app.pid], table);
    run = measure(
        {
            "host": [
                pid
                for pid in kids
                if "WebKit" not in table[pid].cmd
            ],
            "webkit": [
                pid
                for pid in kids
                if "WebKit" in table[pid].cmd
            ],
            "postgres": cluster(DESKTOP_DATA, table)
        },
        window
    );
    run.startup_s = startup_s;
    stop_desktop(app, run);
    return run;
}

def cluster_gone -> bool {
    return not cluster(DESKTOP_DATA, processes());
}

"""Close the window the normal way and record how long the host and its PostgreSQL took."""
def stop_desktop(app: subprocess.Popen[bytes], run: Run) {
    requested = time.monotonic();
    subprocess.run(
        ["jac", "run", os.path.join(ROOT, "bench", "x11_close.jac")],
        env=dict(os.environ, WINDOW_TITLE="Briefly"),
        capture_output=True,
        timeout=120
    );
    try {
        app.wait(timeout=60);
    } except subprocess.TimeoutExpired {
        os.killpg(app.pid, KILL);
        app.wait();
        run.note = "the window close did not stop the host within 60 s; killed";
    }
    run.stop_s = round(time.monotonic() - requested, 1);
    try {
        wait_until(cluster_gone, 60, "the desktop PostgreSQL to stop");
        run.postgres_stop_s = round(time.monotonic() - requested, 1);
    } except RuntimeError {
        run.note = (run.note + "; " if run.note else "")
            + "PostgreSQL still running 60 s after the close; stopped with pg_ctl";
        subprocess.run(
            [
                os.path.join(DESKTOP_DIR, "pgdist", "bin", "pg_ctl"),
                "stop",
                "-D",
                os.path.join(DESKTOP_DATA, "pg", "main"),
                "-m",
                "fast"
            ],
            capture_output=True,
            timeout=120
        );
    }
}

def http_ok(url: str, body: bytes | None = None) -> bool {
    try {
        request = urllib.request.Request(
            url, data=body, headers={"Content-Type": "application/json"}
        );
        with urllib.request.urlopen(request, timeout=5) as resp {
            return resp.status == 200;
        }
    } except Exception {
        return False;
    }
}

def run_lean(settle: float, window: float) -> Run {
    if not os.path.exists(LEAN_JAB) {
        raise RuntimeError(f"no lean artifact at {LEAN_JAB}: run jac build lean");
    }
    workdir = tempfile.mkdtemp(prefix="briefly-mem-");
    shutil.copy(LEAN_JAB, workdir);
    base = f"http://127.0.0.1:{LEAN_PORT}";
    started = time.monotonic();
    server = subprocess.Popen(
        ["jac", "run", "--port", str(LEAN_PORT), "briefly.jab"],
        cwd=workdir,
        env=dict(os.environ, JAC_SERVE_HOST="127.0.0.1"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        start_new_session=True
    );
    try {
        wait_until(
            lambda -> bool { return http_ok(f"{base}/healthz"); },
            180,
            "the lean server"
        );
        startup_s = round(time.monotonic() - started, 1);
        # What a browser tab does on load: the page, then app_info.
        http_ok(f"{base}/");
        http_ok(f"{base}/function/app_info", b"{}");
        time.sleep(settle);
        run = measure({"server": descendants([server.pid], processes())}, window);
        run.startup_s = startup_s;
        run.note = "PostgreSQL not counted: the lean app does not touch the graph yet, so no cluster starts for it";
    } finally {
        requested = time.monotonic();
        os.killpg(server.pid, signal.SIGTERM);
        try {
            server.wait(timeout=90);
        } except subprocess.TimeoutExpired {
            os.killpg(server.pid, KILL);
            server.wait();
        }
        shutil.rmtree(workdir, ignore_errors=True);
    }
    run.stop_s = round(time.monotonic() - requested, 1);
    return run;
}

def spread(values: list[float]) -> dict[str, float] {
    return {
        "median": round(statistics.median(values), 1),
        "min": min(values),
        "max": max(values)
    };
}

def first_value(path: str, prefix: str) -> str {
    try {
        with open(path) as fh {
            for line in fh {
                if line.startswith(prefix) {
                    return line.split(":", 1)[1].strip();
                }
            }
        }
    } except OSError {}
    return "";
}

def machine -> dict[str, str] {
    sha = subprocess.run(
        ["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True
    ).stdout.strip();
    jac_version = subprocess.run(
        ["jac", "--version"], capture_output=True, text=True
    ).stdout.split();
    return {
        "cpu": first_value("/proc/cpuinfo", "model name"),
        "cores": str(CORES),
        "ram": first_value("/proc/meminfo", "MemTotal"),
        "kernel": platform.release(),
        "session": os.environ.get("XDG_SESSION_TYPE", ""),
        "jac": jac_version[1] if len(jac_version) > 1 else "",
        "commit": sha
    };
}

def option(args: list[str], name: str, fallback: str) -> str {
    if name in args {
        return args[args.index(name) + 1];
    }
    return fallback;
}

"""Run one profile `count` times, write the results file, and return the budget misses."""
def bench_profile(
    name: str, phase: str, label: str, count: int, settle: float, window: float
) -> list[str] {
    runs: list[Run] = [];
    for n in range(count) {
        run = run_desktop(settle, window)
            if name == "desktop"
            else run_lean(settle, window);
        runs.append(run);
        parts = ", ".join(f"{g} {v.pss_mb} MB" for (g, v) in run.groups.items());
        print(
            f"{name} run {n + 1}/{count}: PSS {run.pss_mb} MB (RSS {run.rss_mb}, USS {run.uss_mb} MB), CPU {run.cpu_percent} %, {parts}"
        );
    }
    budget = BUDGETS[f"{phase}/{name}"];
    pss = spread([r.pss_mb for r in runs]);
    cpu = spread([r.cpu_percent for r in runs]);
    results = {
        "profile": name,
        "phase": phase,
        "label": label,
        "env": {
            key: os.environ[key]
            for key in ["JAC_SERVE_WORKERS"]
            if key in os.environ
        },
        "settle_s": settle,
        "window_s": window,
        "machine": machine(),
        "budget": {"pss_mb": budget.pss_mb, "cpu_percent": budget.cpu_percent},
        "pss_mb": pss,
        "rss_mb": spread([r.rss_mb for r in runs]),
        "uss_mb": spread([r.uss_mb for r in runs]),
        "cpu_percent": cpu,
        "runs": [r.to_json() for r in runs]
    };
    out_dir = os.path.join(ROOT, "bench", "results");
    os.makedirs(out_dir, exist_ok=True);
    stamp = time.strftime("%Y%m%dT%H%MZ", time.gmtime());
    suffix = f"-{label}" if label else "";
    out = os.path.join(out_dir, f"mem-{name}-{phase}{suffix}-{stamp}.json");
    with open(out, "w") as fh {
        json.dump(results, fh, indent=2);
        fh.write("\n");
    }
    print(
        f"{name} {phase}: median PSS {pss['median']} MB (budget {budget.pss_mb}), median CPU {cpu[
            'median'
        ]} % (budget {budget.cpu_percent}) -> {out}"
    );
    missed: list[str] = [];
    if pss["median"] > budget.pss_mb {
        missed.append(f"{name} {phase} memory {pss['median']} MB > {budget.pss_mb} MB");
    }
    if cpu["median"] > budget.cpu_percent {
        missed.append(f"{name} {phase} CPU {cpu['median']} % > {budget.cpu_percent} %");
    }
    return missed;
}

"""Run the requested profiles; returns the exit code (1 when a budget is missed)."""
def main(args: list[str]) -> int {
    profile = args[0] if args and not args[0].startswith("--") else "both";
    phase = option(args, "--phase", "idle");
    missed: list[str] = [];
    for name in (["desktop", "lean"] if profile == "both" else [profile]) {
        missed.extend(
            bench_profile(
                name,
                phase,
                option(args, "--label", ""),
                int(option(args, "--runs", "5")),
                float(option(args, "--settle", "60")),
                float(option(args, "--window", "30"))
            )
        );
    }
    if missed {
        print("Budget missed: " + "; ".join(missed));
        return 1;
    }
    print("Within budget.");
    return 0;
}

with entry {
    sys.exit(main(sys.argv[1:]));
}
