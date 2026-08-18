from __future__ import annotations

import os
import re

def in_container() -> bool:
    if os.path.exists("/.dockerenv"):
        return True
    try:
        with open("/proc/1/cgroup", "rt") as f:
            return any(x in f.read() for x in ("docker", "containerd", "kubepods"))
    except OSError:
        return False

def resolve_url(url: str | None = None) -> str:
    if url is None:
        from app.core.config import get_settings
        url = os.environ.get("DATABASE_URL") or get_settings().database_url

    if in_container():
        return url

    url = re.sub(r"@db:", "@127.0.0.1:", url).replace("@localhost:", "@127.0.0.1:")
   
    if "ssl=" not in url and "127.0.0.1" in url:
        url += ("&" if "?" in url else "?") + "ssl=disable"
    return url
