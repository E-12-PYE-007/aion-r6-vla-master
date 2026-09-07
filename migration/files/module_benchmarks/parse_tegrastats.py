#!/usr/bin/env python3
"""Parse a tegrastats log and report peak/avg CPU, GPU, RAM, and power."""
import argparse
import csv
import os
import re
import statistics as stats

RAM_RE = re.compile(r"RAM (\d+)/(\d+)MB")
CPU_RE = re.compile(r"CPU \[([^\]]+)\]")
CPU_CORE_RE = re.compile(r"(\d+)%@")
GPU_RE = re.compile(r"GR3D_FREQ (\d+)%")
POWER_RE = re.compile(r"VDD_IN (\d+)mW/(\d+)mW")


def parse_log(path):
    ram_used, cpu_avg, cpu_peak_core, gpu, power = [], [], [], [], []
    with open(path) as f:
        for line in f:
            m = RAM_RE.search(line)
            if m:
                ram_used.append(int(m.group(1)))

            m = CPU_RE.search(line)
            if m:
                cores = [int(c) for c in CPU_CORE_RE.findall(m.group(1))]
                if cores:
                    cpu_avg.append(sum(cores) / len(cores))
                    cpu_peak_core.append(max(cores))

            m = GPU_RE.search(line)
            if m:
                gpu.append(int(m.group(1)))

            m = POWER_RE.search(line)
            if m:
                power.append(int(m.group(1)))

    return ram_used, cpu_avg, cpu_peak_core, gpu, power


def summarize(values):
    if not values:
        return None, None
    return max(values), round(stats.mean(values), 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logfile")
    ap.add_argument("--label", default=None)
    ap.add_argument("--csv", default=None)
    args = ap.parse_args()
    label = args.label or os.path.basename(args.logfile)

    ram_used, cpu_avg, cpu_peak_core, gpu, power = parse_log(args.logfile)

    ram_peak, ram_mean = summarize(ram_used)
    cpu_peak, cpu_mean = summarize(cpu_avg)
    core_peak, _ = summarize(cpu_peak_core)
    gpu_peak, gpu_mean = summarize(gpu)
    pwr_peak, pwr_mean = summarize(power)

    print(f"\n=== {label} ({len(ram_used)} samples) ===")
    print(f"RAM (MB):        peak {ram_peak}   avg {ram_mean}")
    print(f"CPU avg-core %:  peak {cpu_peak}   avg {cpu_mean}   (busiest single core peak: {core_peak}%)")
    print(f"GPU (GR3D) %:    peak {gpu_peak}   avg {gpu_mean}")
    print(f"Power VDD_IN mW: peak {pwr_peak}   avg {pwr_mean}")

    if args.csv:
        write_header = not os.path.exists(args.csv)
        with open(args.csv, "a", newline="") as f:
            w = csv.writer(f)
            if write_header:
                w.writerow(["label", "logfile", "ram_peak_mb", "ram_avg_mb",
                            "cpu_avg_peak_pct", "cpu_avg_mean_pct", "cpu_core_peak_pct",
                            "gpu_peak_pct", "gpu_avg_pct", "power_peak_mw", "power_avg_mw"])
            w.writerow([label, os.path.basename(args.logfile), ram_peak, ram_mean,
                        cpu_peak, cpu_mean, core_peak, gpu_peak, gpu_mean, pwr_peak, pwr_mean])
        print(f"Appended to {args.csv}")


if __name__ == "__main__":
    main()
