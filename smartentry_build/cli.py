import argparse
import os
from typing import List, Optional

from .builder import (
    DockerHubClient,
    calc_build_budget,
    decide_builds,
    docker_login,
    parse_bool_env,
    parse_platform_map,
    build_one,
    compute_hub_repo,
)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Smartentry differential build orchestrator")
    parser.add_argument("--images", type=str, default=os.getenv("IMAGES", "alpine,centos,debian,fedora,ubuntu,archlinux"), help="Comma separated base images to track")
    parser.add_argument("--push", action="store_true", default=parse_bool_env("DOCKER_PUSH", False), help="Whether to push built images")
    parser.add_argument("--pull-budget", type=int, default=int(os.getenv("PULL_BUDGET", "90")), help="Approximate max Docker pulls available this run")
    parser.add_argument("--skip-login", action="store_true", default=os.getenv("SKIP_LOGIN", "").lower() == "true")
    parser.add_argument("--source-image", type=str, default=os.getenv("SOURCE_IMAGE", ""), help="Override base image repository (namespace/name)")
    parser.add_argument("--platform-map", type=str, default=os.getenv("PLATFORM_MAP_JSON", ""), help="JSON mapping of image=>platforms")
    parser.add_argument("--prune", action="store_true", default=os.getenv("SKIP_REMOVE", "false").lower() != "true")

    args = parser.parse_args(argv)

    username = os.getenv("DOCKER_USER")
    password = os.getenv("DOCKER_PASS")
    docker_login(username, password, args.skip_login)

    platform_map = parse_platform_map(args.platform_map)

    default_platforms = {
        "alpine": "linux/amd64,linux/arm64",
        "centos": "linux/amd64,linux/arm64",
        "debian": "linux/amd64,linux/arm64",
        "fedora": "linux/amd64,linux/arm64",
        "ubuntu": "linux/amd64,linux/arm64",
        "archlinux": "linux/amd64",
    }

    images = [i.strip() for i in args.images.split(",") if i.strip()]
    hub = DockerHubClient(username=username, password=password)
    remaining_pulls = max(0, int(args.pull_budget))

    for image in images:
        platforms = platform_map.get(image, default_platforms.get(image, "linux/amd64"))
        budget_for_image = calc_build_budget(remaining_pulls, platforms)
        if budget_for_image <= 0:
            break

        base_repo = compute_hub_repo(args.source_image or image)
        derived_repo = f"smartentry/{image}"

        candidates = decide_builds(
            hub=hub,
            base_repo=base_repo,
            derived_repo=derived_repo,
            image=image,
            platforms=platforms,
            source_image=args.source_image or image,
            max_builds=budget_for_image,
        )

        for (img, tag, plats, _up, _mine) in candidates:
            build_one(
                image=img,
                tag=tag,
                platforms=plats,
                source_image=args.source_image or img,
                push=args.push,
                prune=args.prune,
            )
            remaining_pulls -= max(1, len([p for p in plats.split(",") if p.strip()]))
            if remaining_pulls <= 0:
                break

        if remaining_pulls <= 0:
            break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())


