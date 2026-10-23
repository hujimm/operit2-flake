#!/usr/bin/env python3
"""升级 Operit2 的版本 pin，并校验补丁仍然能应用到新提交。

用法（任意目录）：
  python3 pkgs/update.py                # 跟随 main 最新提交
  python3 pkgs/update.py --rev <sha>    # 固定到指定提交

做的事：
  1. 用 gh 下载该提交的源码归档；
  2. 解包后用 `nix hash path` 算 fetchFromGitHub 需要的 NAR 哈希；
  3. 从 apps/cli/Cargo.toml 读项目版本；
  4. 重写 pkgs/source.nix 里的 rev / version / hash；
  5. 在临时目录用 `git apply --check` 验证 pkgs/patches/*.patch。

不运行 nix build / nix eval；构建验证由用户执行。

依赖：gh（已认证）、tar、nix。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

OWNER_REPO = "AAswordman/Operit2"
REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_NIX = REPO_ROOT / "pkgs" / "source.nix"
PATCH_DIR = REPO_ROOT / "pkgs" / "patches"


def run(command: list[str], **kwargs) -> str:
    completed = subprocess.run(command, check=True, text=True, capture_output=True, **kwargs)
    return completed.stdout.strip()


def resolve_rev(rev: str | None) -> str:
    if rev:
        return rev
    return run(["gh", "api", f"repos/{OWNER_REPO}/commits/main", "--jq", ".sha"])


def fetch_tree(rev: str, workdir: Path) -> Path:
    """用 gh 下载归档并解包，避免裸 curl 撞 GitHub 的匿名限流。"""
    archive = workdir / "source.tar.gz"
    with archive.open("wb") as output:
        subprocess.run(
            ["gh", "api", f"repos/{OWNER_REPO}/tarball/{rev}"],
            check=True,
            stdout=output,
        )

    tree = workdir / "tree"
    tree.mkdir()
    with tarfile.open(archive) as tar:
        # GitHub 的归档顶层是 `<owner>-<repo>-<sha>/`。
        members = []
        for member in tar.getmembers():
            parts = member.name.split("/", 1)
            if len(parts) != 2:
                continue
            member.name = parts[1]
            members.append(member)
        tar.extractall(tree, members=members, filter="data")
    return tree


def read_version(tree: Path) -> str:
    cargo_toml = (tree / "apps" / "cli" / "Cargo.toml").read_text(encoding="utf-8")
    match = re.search(r'^version = "([^"]+)"', cargo_toml, re.MULTILINE)
    if match is None:
        raise SystemExit("apps/cli/Cargo.toml 里找不到 version")
    return match.group(1)


def rewrite_source_nix(rev: str, version: str, hash_: str) -> None:
    text = SOURCE_NIX.read_text(encoding="utf-8")
    text = re.sub(r'rev = "[0-9a-f]{40}";', f'rev = "{rev}";', text)
    text = re.sub(r'version = "[^"]*";', f'version = "{version}";', text)
    text = re.sub(r'hash = "sha256-[^"]*";', f'hash = "{hash_}";', text)
    SOURCE_NIX.write_text(text, encoding="utf-8")


def verify_patches(tree: Path) -> None:
    # GUI 补丁的路径相对 Flutter 应用根目录（sourceRoot = <src>/apps/flutter/app），
    # 其余补丁相对仓库根目录。
    patch_bases = {"0002-nix-flutter-linux.patch": "apps/flutter/app"}
    for patch in sorted(PATCH_DIR.glob("*.patch")):
        base = tree / patch_bases.get(patch.name, "")
        subprocess.run(
            ["git", "apply", "--check", "-p1", str(patch)],
            cwd=base,
            check=True,
        )
        print(f"补丁可用: {patch.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rev", help="固定到指定提交（默认跟随 main）")
    args = parser.parse_args()

    rev = resolve_rev(args.rev)
    print(f"上游提交: {rev}")

    with tempfile.TemporaryDirectory() as tmp:
        tree = fetch_tree(rev, Path(tmp))
        hash_ = run(["nix", "hash", "path", str(tree)])
        version = read_version(tree)
        print(f"版本: {version}")
        print(f"hash: {hash_}")

        verify_patches(tree)

    rewrite_source_nix(rev, version, hash_)
    print(f"已更新 {SOURCE_NIX.relative_to(REPO_ROOT)}")
    print("\n接着自查：git diff，然后由用户执行 nix build .#operit2-cli")
    return 0


if __name__ == "__main__":
    sys.exit(main())
