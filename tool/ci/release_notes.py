"""Validate the complete release asset set and generate traceable release notes."""

import hashlib
import json
import os
from pathlib import Path
import re


def changelog_section(text, version):
    match = re.search(
        rf"^## {re.escape(version)}(?:\s+-[^\n]*)?\n(.*?)(?=^## |\Z)",
        text, re.MULTILINE | re.DOTALL,
    )
    if not match or not match.group(1).strip():
        raise ValueError(f"No changelog entry for {version}")
    return match.group(1).strip()


def generate(directory, version, build, sha, run_url, changelog, jobs):
    expected = [
        f"epub-toolkit-android-v{version}+{build}.apk",
        f"epub-toolkit-macos-v{version}+{build}.zip",
        f"epub-toolkit-windows-v{version}+{build}-setup.exe",
        f"epub-toolkit-ios-v{version}+{build}-unsigned.zip",
    ]
    if sorted(p.name for p in directory.iterdir()) != sorted(expected):
        raise ValueError("Release requires exactly Android, macOS, Windows and iOS assets")
    changes = changelog_section(changelog, version)
    assets = []
    for name in expected:
        path = directory / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Empty or missing asset: {name}")
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        assets.append({"name": name, "bytes": path.stat().st_size, "sha256": digest.hexdigest()})
    (directory / "SHA256SUMS.txt").write_text(
        "".join(f"{item['sha256']}  {item['name']}\n" for item in assets),
        encoding="utf-8",
    )
    metadata = {
        "version": version, "build": build, "commit": sha, "run": run_url,
        "flutter": "3.44.0", "assets": assets, "jobs": jobs,
    }
    (directory / "build-metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    body = (
        f"# EPUB 工具箱 {version}\n\n{changes}\n\n"
        f"## 构建记录\n\n- 版本：`{version}+{build}`\n- 提交：`{sha}`\n"
        f"- Flutter：`3.44.0`（固定版本，依赖使用锁文件）\n"
        f"- [完整构建日志与耗时]({run_url})；各平台失败日志保留 14 天。\n"
        "- 附件包含四个平台产物、SHA256SUMS.txt 和 build-metadata.json。\n\n"
        "| 产物 | 字节数 |\n| --- | ---: |\n"
        + "".join(f"| `{a['name']}` | {a['bytes']} |\n" for a in assets)
        + "\nAndroid 使用正式签名。macOS 使用 ad-hoc 签名，未公证；"
        "Windows 安装程序未代码签名，可能触发系统提示。"
        "iOS 包未签名，不能直接安装到普通设备。\n"
    )
    return body


if __name__ == "__main__":
    body = generate(
        Path("release-assets"), os.environ["APP_VERSION"], os.environ["BUILD_NUMBER"],
        os.environ["GITHUB_SHA"],
        f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
        Path("CHANGELOG.md").read_text(encoding="utf-8"),
        json.loads(Path("release-jobs.json").read_text(encoding="utf-8")),
    )
    Path("release-notes.md").write_text(body, encoding="utf-8")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
        summary.write(body)
