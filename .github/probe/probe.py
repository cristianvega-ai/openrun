#!/usr/bin/env python3
"""Probe: how fast / how reliably do sandbox denials of curl reach `log show` vs `log stream`?
usage: probe.py EVENTS SPACING_S POLL_TIMEOUT_S [BURNERS]"""
import datetime, json, os, re, subprocess, sys, tempfile, time

events = int(sys.argv[1]); spacing = float(sys.argv[2]); timeout = float(sys.argv[3])
burners = int(sys.argv[4]) if len(sys.argv) > 4 else 0
PRED = 'eventMessage CONTAINS "Sandbox" AND (eventMessage CONTAINS "network-outbound" OR eventMessage CONTAINS "dnssd" OR eventMessage CONTAINS "nsurlsessiond")'
PROFILE = """(version 1)
(allow default)
(deny network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))
(deny network-outbound (remote ip))
(allow network-outbound (remote ip "localhost:*"))
(deny network-outbound (remote ip "localhost:9") (remote ip "localhost:10"))
"""
work = tempfile.mkdtemp(prefix="probe.")
prof = os.path.join(work, "p.sb"); open(prof, "w").write(PROFILE)
burn = [subprocess.Popen(["/usr/bin/yes"], stdout=subprocess.DEVNULL) for _ in range(burners)]
stream_f = open(os.path.join(work, "stream.txt"), "w")
stream = subprocess.Popen(["/usr/bin/log", "stream", "--info", "--debug", "--predicate", PRED], stdout=stream_f, stderr=subprocess.STDOUT)
time.sleep(3)
start_dt = datetime.datetime.now()
start = start_dt.strftime("%Y-%m-%d %H:%M:%S")
ev = {}
RX = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)([+-]\d{4}) .*Sandbox: curl\((\d+)\) deny\(1\) network-outbound remote:\*:9$")
def epoch(ts, tz):
    return datetime.datetime.strptime(ts + tz, "%Y-%m-%d %H:%M:%S.%f%z").timestamp()
def poll():
    t = time.time()
    p = subprocess.run(["/usr/bin/log", "show", "--start", start, "--info", "--debug", "--predicate", PRED], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    dur = time.time() - t
    found = {}
    for line in p.stdout.splitlines():
        m = RX.match(line)
        if m: found[m.group(3)] = epoch(m.group(1), m.group(2))
    return dur, found
emit_end = None
t_begin = time.time()
polls = []
nxt = 0
seen_first = {}
while True:
    now = time.time()
    if len(ev) < events and now >= t_begin + len(ev) * spacing:
        t0 = time.time()
        p = subprocess.Popen(["/usr/bin/sandbox-exec", "-f", prof, "/usr/bin/curl", "-s", "-m", "2", "-o", "/dev/null", "http://127.0.0.1:9/"])
        p.wait(); t1 = time.time()
        ev[str(p.pid)] = {"t0": t0, "t1": t1, "rc": p.returncode}
        continue
    if len(ev) == events and emit_end is None:
        emit_end = time.time()
    dur, found = poll()
    tnow = time.time()
    polls.append((tnow, dur, len(found)))
    for pid, ts in found.items():
        if pid in ev and pid not in seen_first:
            seen_first[pid] = tnow
            ev[pid]["logged"] = ts
    if emit_end is not None and (len(seen_first) == events or tnow - emit_end > timeout):
        break
    time.sleep(0.3)
time.sleep(2)
stream.terminate(); stream.wait()
for b in burn: b.terminate()
stext = open(os.path.join(work, "stream.txt")).read()
live = set(re.findall(r"Sandbox: curl\((\d+)\) deny\(1\) network-outbound remote:\*:9$", stext, re.M))
dropped = stext.count("Messages dropped")
rows = []
for pid, e in ev.items():
    rows.append({"pid": pid, "show_latency_s": round(seen_first[pid] - e["t1"], 2) if pid in seen_first else None,
                 "stream": pid in live, "skew_before_s": round(e["logged"] - e["t0"], 4) if "logged" in e else None,
                 "skew_after_s": round(e["t1"] - e["logged"], 4) if "logged" in e else None, "rc": e["rc"]})
lat = sorted(r["show_latency_s"] for r in rows if r["show_latency_s"] is not None)
summary = {"events": events, "burners": burners, "show_seen": len(lat), "stream_seen": len(live & set(ev)), "stream_dropped_markers": dropped,
           "latency_min": lat[0] if lat else None, "latency_median": lat[len(lat)//2] if lat else None, "latency_max": lat[-1] if lat else None,
           "poll_dur_median": sorted(p[1] for p in polls)[len(polls)//2], "poll_dur_max": max(p[1] for p in polls), "polls": len(polls),
           "min_skew_before": min((r["skew_before_s"] for r in rows if r["skew_before_s"] is not None), default=None),
           "min_skew_after": min((r["skew_after_s"] for r in rows if r["skew_after_s"] is not None), default=None),
           "uptime": subprocess.run(["uptime"], stdout=subprocess.PIPE, text=True).stdout.strip()}
print(json.dumps(summary, indent=1))
print(subprocess.run("sw_vers; sysctl -n hw.ncpu; ps -axo pid,pcpu,comm | sort -k2 -nr | head -8", shell=True, stdout=subprocess.PIPE, text=True).stdout)
print("never seen by show:", [r["pid"] for r in rows if r["show_latency_s"] is None])
print("not seen live (stream):", [r["pid"] for r in rows if not r["stream"]])
print("latencies:", lat)
