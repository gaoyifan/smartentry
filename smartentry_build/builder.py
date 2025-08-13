import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import tempfile
from typing import Dict, Iterator, List, Optional, Tuple

from .hub import DockerHubClient, TagInfo


def compute_hub_repo(image: str) -> str:
    return image if "/" in image else f"library/{image}"


def tag_has_date_yyyyMMdd(tag: str) -> bool:
    return re.search(r"\d{8}", tag) is not None


def should_skip_tag(image: str, tag: str) -> bool:
    if tag_has_date_yyyyMMdd(tag):
        return True
    if image in ("ubuntu", "archlinux") and "-" in tag:
        return True
    return False


def get_git_version_suffix() -> str:
    try:
        res = subprocess.run(["git", "tag", "--contains"], capture_output=True, text=True, check=False)
        first = res.stdout.strip().splitlines()[0] if res.stdout.strip() else ""
        if not first:
            return ""
        return first.replace("v", "-")
    except Exception:
        return ""


def docker_login(username: Optional[str], password: Optional[str], skip_login: bool) -> None:
    if skip_login or not username or not password:
        return
    subprocess.run(["docker", "login", "-u", username, "--password-stdin"], input=password.encode(), check=True)


def generate_dockerfile(image: str, tag: str, base_image: str) -> str:
    extra_cmd = ""
    if image == "fedora":
        extra_cmd = (
            "RUN (command -v dnf >/dev/null 2>&1 && dnf -y install tar && dnf clean all) || "
            "(command -v yum >/dev/null 2>&1 && yum install -y tar && yum clean all) || "
            "(command -v microdnf >/dev/null 2>&1 && microdnf -y install tar && microdnf clean all) || true"
        )
    elif image == "alpine":
        extra_cmd = "RUN apk --update add bash tar && rm -rf /var/cache/apk/*"
    parts = [
        f"FROM {base_image}:{tag}",
        'LABEL maintainer="Yifan Gao <docker@yfgao.com>"',
        'ENV ASSETS_DIR="/opt/smartentry/HEAD"',
    ]
    if extra_cmd:
        parts.append(extra_cmd)
    parts.extend([
        "COPY smartentry.sh /sbin/smartentry.sh",
        'ENTRYPOINT ["/sbin/smartentry.sh"]',
        'CMD ["run"]',
    ])
    return "\n".join(parts)


def build_one(image: str, tag: str, platforms: str, source_image: Optional[str], push: bool, prune: bool) -> None:
    base_image = source_image or image
    version_suffix = get_git_version_suffix()
    workdir = tempfile.mkdtemp(prefix="smartentry-build-")
    try:
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
        shutil.copy2(os.path.join(repo_root, "smartentry.sh"), os.path.join(workdir, "smartentry.sh"))

        dockerfile = generate_dockerfile(image=image, tag=tag, base_image=base_image)
        with open(os.path.join(workdir, "Dockerfile"), "w") as f:
            f.write(dockerfile + "\n")

        tags: List[str] = [f"smartentry/{image}:{tag}"]
        if version_suffix:
            tags.append(f"smartentry/{image}:{tag}{version_suffix}")

        cmd: List[str] = ["docker", "buildx", "build", "--platform", platforms]
        for t in tags:
            cmd.extend(["-t", t])
        if push:
            cmd.append("--push")
        cmd.append(".")

        subprocess.run(cmd, cwd=workdir, check=True)
        if prune:
            subprocess.run(["docker", "buildx", "prune", "-a", "-f"], check=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def decide_builds(
    hub: DockerHubClient,
    base_repo: str,
    derived_repo: str,
    image: str,
    platforms: str,
    source_image: Optional[str],
    max_builds: int,
) -> List[Tuple[str, str, str, Optional[dt.datetime], Optional[dt.datetime]]]:
    candidates: List[Tuple[str, str, str, Optional[dt.datetime], Optional[dt.datetime]]] = []
    ours_index: Dict[str, Optional[dt.datetime]] = {ti.name: ti.tag_last_pushed for ti in hub.iter_tags(derived_repo)}
    for tag_info in hub.iter_tags(base_repo):
        tag = tag_info.name
        if should_skip_tag(image, tag):
            continue
        upstream_time = tag_info.tag_last_pushed
        ours_time = ours_index.get(tag)
        if ours_time and upstream_time and ours_time >= upstream_time:
            continue
        # Intersect requested platforms with upstream-supported architectures
        req_archs = [p.split("/")[-1] for p in platforms.split(",") if p]
        supported = set()
        for a in tag_info.architectures:
            # normalize 386 vs i386 naming: docker uses 386
            supported.add("386" if a == "i386" else a)
        allowed_platforms = []
        for p in platforms.split(","):
            p = p.strip()
            if not p:
                continue
            arch = p.split("/")[-1]
            if arch in supported:
                allowed_platforms.append(p)
        if not allowed_platforms:
            continue
        eff_platforms = ",".join(allowed_platforms)
        candidates.append((image, tag, eff_platforms, upstream_time, ours_time))
    candidates.sort(key=lambda x: x[3] or dt.datetime.fromtimestamp(0, tz=dt.timezone.utc), reverse=True)
    return candidates[:max_builds]


def parse_platform_map(value: Optional[str]) -> Dict[str, str]:
    if not value:
        return {}
    try:
        return json.loads(value)
    except Exception:
        return {}


def calc_build_budget(remaining_pulls: int, platforms: str) -> int:
    num_platforms = max(1, len([p for p in platforms.split(",") if p.strip()]))
    return max(0, remaining_pulls // num_platforms)


def parse_bool_env(name: str, default: bool = False) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    v = v.strip().lower()
    if v in {"1", "true", "yes", "on"}:
        return True
    if v in {"0", "false", "no", "off", ""}:
        return False
    return default



