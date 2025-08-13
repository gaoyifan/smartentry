import datetime as dt
from dataclasses import dataclass
from typing import Iterator, Optional

import requests


DOCKER_HUB_API = "https://registry.hub.docker.com/v2/repositories"


@dataclass
class TagInfo:
    name: str
    tag_last_pushed: Optional[dt.datetime]


class DockerHubClient:
    def __init__(self, username: Optional[str] = None, password: Optional[str] = None) -> None:
        self.session = requests.Session()
        if username and password:
            self.session.auth = (username, password)

    def _parse_time(self, value: Optional[str]) -> Optional[dt.datetime]:
        if not value:
            return None
        try:
            if value.endswith("Z"):
                value = value[:-1] + "+00:00"
            return dt.datetime.fromisoformat(value)
        except Exception:
            return None

    def iter_tags(self, repo: str, page_size: int = 100) -> Iterator[TagInfo]:
        url = f"{DOCKER_HUB_API}/{repo}/tags/?page_size={page_size}"
        while url:
            resp = self.session.get(url, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            for r in data.get("results", []):
                yield TagInfo(
                    name=r.get("name", ""),
                    tag_last_pushed=self._parse_time(r.get("tag_last_pushed") or r.get("last_updated")),
                )
            url = data.get("next")


