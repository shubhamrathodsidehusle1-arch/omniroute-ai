import json
import os
import subprocess
import time
import sys
import signal

COMPOSE_PROJECT = os.environ.get('COMPOSE_PROJECT_NAME', 'omniroute-ai')
PROJECT_DIR = os.environ.get('COMPOSE_PROJECT_DIR', '/root/omniroute-ai')
COMPOSE_FILE = os.environ.get('COMPOSE_FILE', os.path.join(PROJECT_DIR, 'docker-compose.yml'))
WATCH_PATH = os.environ.get('WATCH_FILE', os.path.join(PROJECT_DIR, 'service_run.json'))
POLL_INTERVAL = 10


def get_desired():
    with open(WATCH_PATH) as f:
        data = json.load(f)
    return {k: bool(v) for k, v in data.items()}


def container_labels():
    """Return set of docker-compose service names for running containers."""
    result = subprocess.run(
        ['docker', 'ps', '--format', '{{.Label "com.docker.compose.service"}}', '--filter', 'status=running'],
        capture_output=True, text=True, cwd=PROJECT_DIR
    )
    if result.returncode != 0:
        print(f'[ctrl] docker ps failed: {result.stderr.strip()}', flush=True)
    return set(line.strip() for line in result.stdout.split('\n') if line.strip())


def run_compose(args):
    """Run a docker compose command and surface failures instead of swallowing them."""
    result = subprocess.run(
        ['docker', 'compose', '-p', COMPOSE_PROJECT, '-f', COMPOSE_FILE, *args],
        capture_output=True, text=True, cwd=PROJECT_DIR
    )
    if result.returncode != 0:
        print(f'[ctrl] compose {" ".join(args)} FAILED:', flush=True)
        print(result.stderr.strip(), flush=True)
    return result


def reconcile():
    desired = get_desired()
    current = container_labels()
    for service, enabled in desired.items():
        is_running = service in current
        if enabled and not is_running:
            print(f'[ctrl] starting {service}...', flush=True)
            run_compose(['up', '-d', '--no-recreate', service])
        elif not enabled and is_running:
            print(f'[ctrl] stopping {service}...', flush=True)
            run_compose(['stop', service])


def main():
    last_mtime = 0
    print(f'[ctrl] watching {WATCH_PATH} (project={COMPOSE_PROJECT})', flush=True)
    while True:
        try:
            if not os.path.exists(WATCH_PATH):
                time.sleep(POLL_INTERVAL)
                continue
            mtime = os.path.getmtime(WATCH_PATH)
            # Reconcile whenever the file changed ...
            if mtime > last_mtime:
                last_mtime = mtime
                reconcile()
            else:
                # ... and also periodically, so services that finish starting
                # AFTER the initial reconcile (or that get restarted by the
                # daemon/host) are still enforced against service_run.json.
                reconcile()
        except Exception as e:
            print(f'[ctrl] error: {e}', flush=True)
        time.sleep(POLL_INTERVAL)


def handle_sigterm(*_):
    sys.exit(0)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, handle_sigterm)
    main()
