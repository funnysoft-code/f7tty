#!/usr/bin/env python3
"""Buffered macOS benchmark of a disposable F7TTY build; stores raw evidence."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import statistics
import subprocess
import time


def run(*args):
    return subprocess.check_output(args)


def processes():
    result = {}
    for line in run('ps', '-axo', 'pid=,ppid=,time=,comm=').decode().splitlines():
        pid, parent, clock, command = line.strip().split(None, 3)
        days = 0
        if '-' in clock:
            day, clock = clock.split('-', 1)
            days = int(day)
        seconds = 0.0
        for part in clock.split(':'):
            seconds = seconds * 60 + float(part)
        result[pid] = dict(parent=int(parent), seconds=seconds + days * 86400, command=command)
    return result


def gpu():
    devices = plistlib.loads(run('ioreg', '-r', '-c', 'IOAccelerator', '-a'))
    return [dict(model=d.get('model'), statistics=d['PerformanceStatistics'])
            for d in devices if 'PerformanceStatistics' in d]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New evidence directory')
    parser.add_argument('--scenario', choices=['idle', 'animate', 'titles'], default='animate')
    parser.add_argument('--legacy-composition', action='store_true')
    parser.add_argument('--square-panes', action='store_true')
    parser.add_argument('--async-redraw', action='store_true')
    parser.add_argument('--seconds', type=int, default=60)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 90:
        parser.error('--seconds must be between 1 and 90')
    exe = args.app.resolve() / 'Contents/MacOS/F7TTY'
    if not exe.is_file():
        parser.error(f'No F7TTY executable at {exe}')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    helper = output / 'measurement-context'
    subprocess.run(['swiftc', str(Path(__file__).with_name('measurement-context.swift')), '-o', str(helper)], check=True)
    profile = output / 'profile.json'
    ready = Path(str(profile) + '.ready')
    env = os.environ.copy()
    for key in ['F7TTY_LEGACY_COMPOSITION', 'F7TTY_SQUARE_PANES', 'F7TTY_ASYNC_REDRAW']:
        env.pop(key, None)
    env.update(F7TTY_PROFILE='1', F7TTY_BENCHMARK_REPORT=str(profile), F7TTY_BENCHMARK_SCENARIO=args.scenario)
    for enabled, key in [(args.legacy_composition, 'F7TTY_LEGACY_COMPOSITION'),
                         (args.square_panes, 'F7TTY_SQUARE_PANES'), (args.async_redraw, 'F7TTY_ASYNC_REDRAW')]:
        if enabled:
            env[key] = '1'
    with (output / 'app.log').open('wb') as log:
        app = subprocess.Popen([str(exe), '--benchmark'], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 30
            while not ready.is_file():
                if app.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(f'Benchmark failed to become ready; see {output / "app.log"}')
                time.sleep(0.1)
            power_before = run('pmset', '-g', 'batt').decode()
            power_settings = run('pmset', '-g', 'custom').decode()
            started = datetime.datetime.now().astimezone().isoformat()
            before = processes()
            t0 = time.monotonic()
            samples = []
            sample_times = list(range(0, args.seconds, 5)) + [args.seconds]
            for target in sample_times:
                time.sleep(max(0, t0 + target - time.monotonic()))
                samples.append(dict(elapsed=time.monotonic()-t0, gpu=gpu(), context=json.loads(run(str(helper)))))
            after = processes()
            elapsed = time.monotonic() - t0
            power_after = run('pmset', '-g', 'batt').decode()
            app.send_signal(signal.SIGUSR1)
            app.wait(timeout=15)
            if app.returncode != 0 or not profile.is_file():
                raise RuntimeError(f'Benchmark failed to finish; see {output / "app.log"}')
        finally:
            if app.poll() is None:
                # Only the disposable child is signalled. Its watchdog also exits.
                app.send_signal(signal.SIGUSR1)
                try:
                    app.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    app.terminate()
                    app.wait(timeout=5)
    deltas = []
    for pid, previous in before.items():
        if pid in after and after[pid]['command'] == previous['command']:
            deltas.append(dict(pid=int(pid), command=previous['command'],
                               cpuPercent=100*(after[pid]['seconds']-previous['seconds'])/elapsed))
    values = [s['gpu'][0]['statistics']['Device Utilization %'] for s in samples]
    ticks0, ticks1 = samples[0]['context']['cpuTicks'], samples[-1]['context']['cpuTicks']
    delta = [(b-a) % (2**32) for a,b in zip(ticks0,ticks1)]
    profile_data = json.loads(profile.read_text())
    title = profile_data.get('title', '')
    workload_valid = (title.startswith('Benchmark title ') if args.scenario == 'titles' else title == 'F7TTY benchmark')
    summary = dict(seconds=elapsed, gpuMean=statistics.mean(values), gpuRange=[min(values),max(values)],
                   gpuSamples=values, systemCPUBusy=100*(1-delta[2]/sum(delta)),
                   terminalCPU=next(r['cpuPercent'] for r in deltas if r['pid']==app.pid),
                   windowServerCPU=sum(r['cpuPercent'] for r in deltas if r['command'].endswith('/WindowServer')),
                   foregroundValid=all(s['context']['frontmostPID']==app.pid for s in samples),
                   workloadValid=workload_valid and profile_data.get('columns', 0) > 0 and profile_data.get('rows', 0) > 0,
                   cpuCounterValid=all(s['context']['cpuStatus']==0 for s in samples))
    resources = args.app.resolve() / 'Contents/Resources/F7TTY_F7TTY.bundle/Resources'
    report = dict(started=started, scenario=args.scenario, executableSHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),
                  resourceSHA256={name: hashlib.sha256((resources/name).read_bytes()).hexdigest()
                                  for name in ['terminal.conf', 'render-workload.py']},
                  legacyComposition=args.legacy_composition, squarePanes=args.square_panes, asyncRedraw=args.async_redraw,
                  summary=summary, profile=profile_data, samples=samples,
                  processesBefore=before, processesAfter=after, topCPU=sorted(deltas,key=lambda r:r['cpuPercent'],reverse=True)[:15],
                  powerBefore=power_before, powerAfter=power_after, powerSettings=power_settings,
                  note='GPU is system-wide sampled utilization, not watts. Process CPU uses one core = 100%.')
    path = output / 'measurement.json'
    path.write_text(json.dumps(report, indent=2))
    # Re-read the persisted report before reporting its result.
    stored = json.loads(path.read_text())
    print(json.dumps(dict(summary=stored['summary'], profile=stored['profile'], evidence=str(path)), indent=2))
    if not all(summary[key] for key in ['foregroundValid', 'cpuCounterValid', 'workloadValid']):
        raise SystemExit('Capture invalid: foreground, CPU counter, or workload validation failed.')


if __name__ == '__main__':
    main()
