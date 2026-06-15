#!/usr/bin/env python3
"""jarvis-core/sysmon.py — lightweight system resource snapshot."""
import time

try:
    import psutil
    _HAVE_PSUTIL = True
except ImportError:
    _HAVE_PSUTIL = False


def _uptime_str():
    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        h = int(secs // 3600)
        m = int((secs % 3600) // 60)
        return f"{h}h {m}m"
    except Exception:
        return "unknown"


class SystemMonitor:
    def snapshot(self):
        if _HAVE_PSUTIL:
            vm = psutil.virtual_memory()
            return {
                "cpu": round(psutil.cpu_percent(interval=None), 1),
                "mem": round(vm.percent, 1),
                "mem_used_gb": round(vm.used / 1e9, 2),
                "mem_total_gb": round(vm.total / 1e9, 2),
                "uptime": _uptime_str(),
                "procs": len(psutil.pids()),
                "net_up": round(psutil.net_io_counters().bytes_sent / 1e6, 1),
                "net_down": round(psutil.net_io_counters().bytes_recv / 1e6, 1),
                "ts": time.time(),
            }
        # /proc fallback
        return self._proc_snapshot()

    def _proc_snapshot(self):
        cpu = mem = 0.0
        try:
            with open("/proc/meminfo") as f:
                info = {}
                for line in f:
                    k, v = line.split(":")[0], line.split()[1]
                    info[k] = int(v)
            total = info.get("MemTotal", 1)
            avail = info.get("MemAvailable", total)
            mem = round((1 - avail / total) * 100, 1)
        except Exception:
            pass
        try:
            with open("/proc/loadavg") as f:
                cpu = round(float(f.read().split()[0]) * 100 / max(1, _ncpu()), 1)
        except Exception:
            pass
        return {"cpu": cpu, "mem": mem, "mem_used_gb": 0, "mem_total_gb": 0,
                "uptime": _uptime_str(), "procs": 0, "net_up": 0,
                "net_down": 0, "ts": time.time()}


def _ncpu():
    try:
        return len([1 for l in open("/proc/cpuinfo") if l.startswith("processor")])
    except Exception:
        return 1
