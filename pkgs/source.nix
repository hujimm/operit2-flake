{
  fetchFromGitHub,
  lib,
}:
# 唯一的上游版本锁定点：CLI、bridge、插件资源和 GUI 都从这里取同一个提交。
# 升级用 `python3 pkgs/update.py`（会同步 rev / hash / version）。
let
  rev = "c331c8d334d99fb4f39849ffb7c7512753e4d37e";
  version = "2.0.0-preview.18";
in
{
  inherit rev version;

  src = fetchFromGitHub {
    owner = "AAswordman";
    repo = "Operit2";
    inherit rev;
    # 由 pkgs/update.py 用 `nix hash path` 对新归档计算，不要手改。
    hash = "sha256-hjxyN+S2hTHYSLMpT0kYIjdkCzXYA0llBB/LzHCzcBY=";
  };

  meta = {
    description = "Operit2 AI Agent（Flutter GUI + Rust CLI + 无界面 Link 节点）";
    homepage = "https://github.com/AAswordman/Operit2";
    license = lib.licenses.agpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
