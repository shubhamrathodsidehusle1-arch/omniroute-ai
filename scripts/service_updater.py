#!/usr/bin/env python3
"""
Service auto-updater.

Periodically checks every enabled service (per service_run.json) for a newer
version and updates it automatically:

  - image service         -> docker registry digest change  -> compose pull + up
  - build FROM <img>      -> base image digest change       -> compose build --pull + up
  - build git clone       -> remote HEAD vs pin/state       -> rebuild + up
                             (pinned Dockerfiles get the pin bumped automatically)
  - build npm install -g  -> npm registry vs installed      -> rebuild + up

Only services enabled in service_run.json are managed. The updater never
touches itself, one-shot init containers, or disabled services.
"""

import json
import os
import re
import subprocess
import time

WORKSPACE = os.environ.get("COMPOSE_PROJECT_DIR", "/root/omniroute-ai")
COMPOSE_FILE = os.environ.get("COMPOSE_FILE", os.path.join(WORKSPACE, "docker-compose.yml"))
ENV_FILE = os.path.join(WORKSPACE, ".env")
RUN_FILE = os.path.join(WORKSPACE, "service_run.json")
STATE_FILE = os.environ.get("UPDATER_STATE_FILE", os.path.join(WORKSPACE, "docker-data", "updater-state.json"))
INTERVAL = int(os.environ.get("UPDATER_INTERVAL", "3600"))
SELF = "service-updater"
EXCLUDE = {s.strip() for s in os.environ.get("UPDATER_EXCLUDE", "").split(",") if s.strip()}

GIT_RE = re.compile(r"git clone(?: --depth \d+)?\s+(\S+)\s+(\S+)")
PIN_RE = re.compile(r"checkout\s+([0-9a-f]{40})")
NPM_RE = re.compile(r"npm install -g\s+([\w@./-]+)")
FROM_RE = re.compile(r"^FROM\s+(\S+)", re.M)


def log(msg):
    print(f"[updater] {msg}", flush=True)


def sh(args, timeout=900):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def compose(*args, timeout=900):
    cmd = ["docker", "compose", "-f", COMPOSE_FILE, "--env-file", ENV_FILE]
    cmd += list(args)
    return sh(cmd, timeout=timeout)


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def enabled_services():
    data = load_json(RUN_FILE) or {}
    wanted = {k for k, v in data.items() if v and k != SELF}
    if EXCLUDE:
        wanted = {k for k in wanted if k not in EXCLUDE}
        log(f"excluded from updates: {', '.join(sorted(EXCLUDE))}")
    return wanted


def compose_config():
    r = compose("config", "--format", "json", timeout=120)
    if r.returncode != 0:
        raise RuntimeError(f"compose config failed: {r.stderr.strip()}")
    return json.loads(r.stdout)


def dockerfile_for(build, name):
    df = build.get("dockerfile") or f"Dockerfile.{name}"
    return os.path.join(WORKSPACE, build.get("context", "."), df)


def dockerfile_text(build, name):
    try:
        with open(dockerfile_for(build, name)) as f:
            return f.read()
    except Exception:
        return ""


def git_ls_remote(repo):
    r = sh(["git", "ls-remote", repo, "HEAD"], timeout=120)
    if r.returncode != 0:
        raise RuntimeError(f"git ls-remote failed for {repo}: {r.stderr.strip()}")
    return r.stdout.split()[0] if r.stdout.split() else ""


def npm_latest(pkg):
    r = sh(["curl", "-fsS", f"https://registry.npmjs.org/{pkg}/latest"], timeout=60)
    if r.returncode != 0:
        raise RuntimeError(f"npm registry query failed for {pkg}: {r.stderr.strip()}")
    return json.loads(r.stdout).get("version", "")


def image_digest(image):
    r = sh(["docker", "image", "inspect", "--format", "{{index .RepoDigests 0}}", image], timeout=60)
    return r.stdout.strip() if r.returncode == 0 else ""


def current_image_id(image):
    r = sh(["docker", "image", "inspect", "--format", "{{.Id}}", image], timeout=60)
    return r.stdout.strip() if r.returncode == 0 else ""


def container_image_id(name):
    r = sh(["docker", "inspect", "--format", "{{.Image}}", name], timeout=60)
    return r.stdout.strip() if r.returncode == 0 else ""


def state_get(key, default=None):
    s = load_json(STATE_FILE) or {}
    return s.get(key, default)


def state_set(key, value):
    s = load_json(STATE_FILE) or {}
    s[key] = value
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(s, f, indent=2)


def check_and_update(name, spec):
    if "build" in spec:
        return handle_build(name, spec)
    return handle_image(name, spec.get("image", ""))


def handle_image(name, image):
    if not image:
        return False
    if not current_image_id(image):
        log(f"{name}: image {image} not present locally, skipping")
        return False
    r = compose("pull", "-q", name, timeout=1800)
    if r.returncode != 0:
        log(f"{name}: pull failed: {r.stderr.strip()[:300]}")
        return False
    run_img = container_image_id(name)
    cur_img = current_image_id(image)
    if run_img and cur_img and run_img != cur_img:
        log(f"{name}: new image available ({cur_img[:19]})")
        return apply_update(name)
    log(f"{name}: already up to date")
    return False


def handle_build(name, spec):
    build = spec.get("build", {})
    text = dockerfile_text(build, name)
    if not text:
        log(f"{name}: no Dockerfile found, skipping")
        return False

    m = GIT_RE.search(text)
    if m:
        repo, _dest = m.groups()
        remote = git_ls_remote(repo)
        pin = PIN_RE.search(text)
        if pin:
            cur = pin.group(1)
            if remote and remote != cur:
                log(f"{name}: upstream {repo} HEAD {remote} != pin {cur}, bumping pin and rebuilding")
                bump_pin(dockerfile_for(build, name), cur, remote)
                state_set(f"build_sha:{name}", remote)
                return apply_build_update(name)
            log(f"{name}: pinned at {cur}, upstream unchanged")
            return False
        prev = state_get(f"build_sha:{name}")
        if not prev:
            state_set(f"build_sha:{name}", remote)
            log(f"{name}: baseline HEAD {remote}")
            return False
        if remote and remote != prev:
            log(f"{name}: upstream {repo} moved {prev} -> {remote}, rebuilding")
            state_set(f"build_sha:{name}", remote)
            return apply_build_update(name)
        log(f"{name}: upstream unchanged ({remote})")
        return False

    n = NPM_RE.search(text)
    if n:
        pkg = n.group(1)
        latest = npm_latest(pkg)
        prev = state_get(f"npm_ver:{name}")
        if not prev:
            state_set(f"npm_ver:{name}", latest)
            log(f"{name}: npm {pkg} baseline {latest}")
            return False
        if latest and latest != prev:
            log(f"{name}: npm {pkg} {prev} -> {latest}, rebuilding")
            state_set(f"npm_ver:{name}", latest)
            return apply_build_update(name)
        log(f"{name}: npm {pkg} at {latest}")
        return False

    base = FROM_RE.search(text)
    if base:
        img = base.group(1)
        before = image_digest(img)
        if not before:
            return False
        r = sh(["docker", "pull", "-q", img], timeout=1800)
        after = image_digest(img) if r.returncode == 0 else before
        if after and after != before:
            log(f"{name}: base image {img} changed, rebuilding")
            return apply_build_update(name)
        log(f"{name}: base image {img} unchanged")
        return False

    log(f"{name}: no update source detected (skipped)")
    return False


def bump_pin(path, old, new):
    with open(path) as f:
        text = f.read()
    if old not in text:
        log(f"WARN: pin {old} not found in {path}, skipping pin bump")
        return
    with open(path, "w") as f:
        f.write(text.replace(old, new))


def apply_build_update(name):
    r = compose("build", "--pull", name, timeout=3600)
    if r.returncode != 0:
        log(f"{name}: build failed: {r.stderr.strip()[:500]}")
        return False
    return apply_update(name)


def apply_update(name):
    r = compose("up", "-d", "--no-deps", name, timeout=600)
    if r.returncode != 0:
        log(f"{name}: up failed: {r.stderr.strip()[:500]}")
        return False
    log(f"{name}: updated and recreated")
    return True


def run_once():
    services = enabled_services()
    cfg = compose_config().get("services", {})
    for name in sorted(services):
        if name not in cfg:
            log(f"{name}: not in compose config, skipping")
            continue
        try:
            check_and_update(name, cfg[name])
        except Exception as e:
            log(f"{name}: error: {e}")


def main():
    log(f"Service updater started (interval={INTERVAL}s)")
    while True:
        try:
            run_once()
        except Exception as e:
            log(f"run failed: {e}")
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
