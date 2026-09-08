"""Deterministic, disposable PTY workload for F7TTY's opt-in benchmark mode."""
import os
import sys
import time

scenario = sys.argv[1] if len(sys.argv) > 1 else "animate"
os.write(1, b"\x1b[?25l\x1b[2J\x1b[H\x1b]2;F7TTY benchmark\x07")
for row in range(1, 45):
    line = f"\x1b[{row};1H{row:02d}  Deterministic terminal replay  " + ("0123456789 abcdef " * 6)
    os.write(1, line.encode())
started = time.monotonic()
frame = 0
while True:
    if scenario == "idle":
        time.sleep(3600)
        continue
    if scenario != "idle":
        position = frame % 80
        bar = " " * position + "#" + " " * (79 - position)
        output = f"\x1b[2;1HFrame {frame:06d} [{bar}]\x1b[K"
        if scenario == "titles":
            output += f"\x1b]2;Benchmark title {frame // 4}\x07"
        os.write(1, output.encode())
    frame += 1
    time.sleep(max(0, started + frame * 0.05 - time.monotonic()))
