import datetime as dt
from smartentry_build import builder as build


class DummyHub:
    def __init__(self, upstream_tags, ours_tags, upstream_archs=None):
        # dict tag->tag_last_pushed iso str
        self.upstream_tags = upstream_tags
        self.ours_tags = ours_tags
        self.upstream_archs = upstream_archs or {}

    def iter_tags(self, repo):
        if str(repo).startswith("smartentry/"):
            items = self.ours_tags.items()
            for name, ts in items:
                yield build.TagInfo(name=name, tag_last_pushed=dt.datetime.fromisoformat(ts), architectures=set())
        else:
            items = self.upstream_tags.items()
            for name, ts in items:
                archs = set(self.upstream_archs.get(name, {"amd64", "arm64"}))
                yield build.TagInfo(name=name, tag_last_pushed=dt.datetime.fromisoformat(ts), architectures=archs)

    def get_single_tag(self, repo, tag):
        ts = self.ours_tags.get(tag)
        if ts is None:
            return None
        return build.TagInfo(name=tag, tag_last_pushed=dt.datetime.fromisoformat(ts))


def test_date_filtering_skips_tags_with_8_digits():
    assert build.tag_has_date_yyyyMMdd("20250811")
    assert build.should_skip_tag("debian", "bookworm-20250811-slim")
    assert build.should_skip_tag("debian", "rc-buggy-20250811")


def test_should_skip_rules_for_ubuntu_and_archlinux_dash():
    assert build.should_skip_tag("ubuntu", "22.04-lts")
    assert build.should_skip_tag("archlinux", "base-20240101")


def test_decide_builds_differential_logic():
    hub = DummyHub(
        upstream_tags={
            "bookworm": "2025-08-13T09:00:00+00:00",
            "bookworm-20250811-slim": "2025-08-13T09:00:00+00:00",  # will be skipped by date filter
            "stable": "2025-08-12T10:00:00+00:00",
        },
        ours_tags={
            "bookworm": "2025-08-12T09:00:00+00:00",  # older -> should build
            "stable": "2025-08-13T10:00:00+00:00",    # newer or equal -> skip
        },
        upstream_archs={
            "bookworm": {"amd64", "arm64"},
            "stable": {"amd64", "arm64"},
        }
    )
    cands = build.decide_builds(
        hub=hub,
        base_repo="library/debian",
        derived_repo="smartentry/debian",
        image="debian",
        platforms="linux/amd64,linux/arm64",
        source_image=None,
        max_builds=10,
    )

    assert len(cands) == 1
    assert cands[0][1] == "bookworm"


def test_budget_per_platform():
    assert build.calc_build_budget(remaining_pulls=10, platforms="linux/amd64,linux/arm64") == 5
    assert build.calc_build_budget(remaining_pulls=1, platforms="linux/amd64,linux/arm64") == 0
    assert build.calc_build_budget(remaining_pulls=3, platforms="linux/amd64") == 3


def test_generate_dockerfile_syntax_and_package_manager():
    dockerfile = build.generate_dockerfile(image="fedora", tag="26-modular", base_image="fedora")
    assert 'LABEL maintainer="Yifan Gao <docker@yfgao.com>"' in dockerfile
    assert 'RUN dnf -y install tar && dnf clean all' in dockerfile
    dockerfile_alpine = build.generate_dockerfile(image="alpine", tag="3.19", base_image="alpine")
    assert 'apk --update add bash tar' in dockerfile_alpine


