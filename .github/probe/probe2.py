#!/usr/bin/env python3
"""Probe 2: does a burst of sandbox denials blind `log show` for the denials that follow?
usage: probe2.py BURST SPREAD_S DURATION_S INTERVAL_S
Emits BURST denied curls spread over SPREAD_S seconds, then one denied curl every INTERVAL_S for
DURATION_S seconds; polls `log show` once a second and watches a live `log stream` too."""
import datetime, json, os, re, subprocess, sys, tempfile, threading, time

burst, spread, duration, interval = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
PRED = 'eventMessage CONTAINS "Sandbox" AND (eventMessage CONTAINS "network-outbound" OR eventMessage CONTAINS "dnssd" OR eventMessage CONTAINS "nsurlsessiond")'
PROFILE = """(version 1)
(allow default)
(deny network-outbound (remote ip))
(allow network-outbound (remote ip "localhost:*"))
(deny network-outbound (remote ip "localhost:9") (remote ip "localhost:10"))
"""
work = tempfile.mkdtemp(prefix="probe2.")
prof = os.path.join(work, "p.sb"); open(prof, "w").write(PROFILE)
stream_f = open(os.path.join(work, "stream.txt"), "w")
stream = subprocess.Popen(["/usr/bin/log", "stream", "--info", "--debug", "--predicate", PRED], stdout=stream_f, stderr=subprocess.STDOUT)
time.sleep(3)
start = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S%z") or ""
start = time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime())
RX = re.compile(r"Sandbox: curl\((\d+)\) deny\(1\) network-outbound remote:\*:9$")
t0 = time.time()
events = {}   # pid -> {kind, emitted}
lock = threading.Lock()

def emit(kind):
    p = subprocess.Popen(["/usr/bin/sandbox-exec", "-f", prof, "/usr/bin/curl", "-s", "-m", "2", "-o", "/dev/null", "http://127.0.0.1:9/"])
    with lock:
        events[str(p.pid)] = {"kind": kind, "emitted": time.time() - t0}
    p.wait()

def do_burst():
    threads = []
    for i in range(burst):
        th = threading.Thread(target=emit, args=("burst",)); th.start(); threads.append(th)
        if spread: time.sleep(spread / burst)
    for th in threads: th.join()

def canaries():
    n = 0
    end = time.time() + duration
    while time.time() < end:
        emit("canary"); n += 1
        time.sleep(interval)

def tiers():
    out = []
    for d in ("Persist", "Special", "HighVolume"):
        try:
            names = sorted(os.listdir("/var/db/diagnostics/" + d), key=lambda n: os.path.getmtime("/var/db/diagnostics/%s/%s" % (d, n)), reverse=True)
            if names:
                out.append("%s newest %s age %.0fs" % (d, names[0], time.time() - os.path.getmtime("/var/db/diagnostics/%s/%s" % (d, names[0]))))
        except OSError as e:
            out.append("%s: %s" % (d, e))
    return "; ".join(out)

time.sleep(10)
if burst:
    do_burst()
burst_end = time.time() - t0
th = threading.Thread(target=canaries); th.start()
first_seen = {}
timeline = []
while th.is_alive() or time.time() - t0 < burst_end + duration + 30:
    p = subprocess.run(["/usr/bin/log", "show", "--start", start, "--info", "--debug", "--predicate", PRED], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    now = time.time() - t0
    seen = set(m.group(1) for line in p.stdout.splitlines() for m in [RX.search(line)] if m)
    with lock:
        for pid in seen:
            if pid in events and pid not in first_seen:
                first_seen[pid] = now
    timeline.append((round(now, 1), len(seen)))
    if int(now) % 20 < 1.5:
        print("t=%.0f show lists %d denials; %s" % (now, len(seen), tiers()), flush=True)
    time.sleep(1)
    if now > burst_end + duration + 60: break
th.join()
time.sleep(2)
stream.terminate(); stream.wait()
stext = open(os.path.join(work, "stream.txt")).read()
live = set(re.findall(r"Sandbox: curl\((\d+)\) deny\(1\) network-outbound remote:\*:9$", stext, re.M))
print("burst=%d spread=%.0fs duration=%.0fs interval=%.0fs burst_end=%.1fs" % (burst, spread, duration, interval, burst_end))
print("stream gaps:", stext.count("Messages dropped"))
rows = sorted(events.items(), key=lambda kv: kv[1]["emitted"])
for kind in ("burst", "canary"):
    sel = [(pid, e) for pid, e in rows if e["kind"] == kind]
    print("%s: %d emitted, %d seen by stream, %d seen by show" % (kind, len(sel), sum(1 for pid, _ in sel if pid in live), sum(1 for pid, _ in sel if pid in first_seen)))
print("canary timeline (emitted s, stream, show latency s):")
for pid, e in rows:
    if e["kind"] == "canary":
        print("  %6.1f  stream=%-5s show=%s" % (e["emitted"], pid in live, ("%.1f" % (first_seen[pid] - e["emitted"])) if pid in first_seen else "NEVER"))
