import json
import os
import subprocess
import time
import sys
import signal

WATCH_PATH = '/workspace/service_run.json'
COMPOSE_DIR = '/workspace'
POLL_INTERVAL = 10


def get_desired():
    with open(WATCH_PATH) as f:
        data = json.load(f)
    return {k: bool(v) for k, v in data.items()}


def compose_ps():
    result = subprocess.run(
        ['docker', 'compose', 'ps', '--format', '{{.Name}}\t{{.State}}'],
        capture_output=True, text=True, cwd=COMPOSE_DIR
    )
    running = set()
    for line in result.stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split('\t')
        if len(parts) == 2 and parts[1] == 'running':
            running.add(parts[0])
    return running


def main():
    last_mtime = 0
    while True:
        try:
            if not os.path.exists(WATCH_PATH):
                time.sleep(POLL_INTERVAL)
                continue
            mtime = os.path.getmtime(WATCH_PATH)
            if mtime > last_mtime:
                last_mtime = mtime
                desired = get_desired()
                current = compose_ps()
                for service, enabled in desired.items():
                    should_run = enabled
                    is_running = f'{COMPOSE_DIR.split("/")[-1]}-{service}-1' in current or service in current
                    if should_run and not is_running:
                        print(f'[ctrl] starting {service}...', flush=True)
                        subprocess.run(
                            ['docker', 'compose', 'up', '-d', '--no-recreate', service],
                            cwd=COMPOSE_DIR, capture_output=True
                        )
                    elif not should_run and is_running:
                        print(f'[ctrl] stopping {service}...', flush=True)
                        subprocess.run(
                            ['docker', 'compose', 'stop', service],
                            cwd=COMPOSE_DIR, capture_output=True
                        )
        except Exception as e:
            print(f'[ctrl] error: {e}', flush=True)
        time.sleep(POLL_INTERVAL)


def handle_sigterm(*_):
    sys.exit(0)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, handle_sigterm)
    main()
