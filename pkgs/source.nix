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

  # 各包共用的元数据。CLI 理论上能跑 aarch64，但本 flake 只提供并验证过
  # x86_64-linux，因此这里不做未经验证的平台声明。
  meta = {
    homepage = "https://github.com/AAswordman/Operit2";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
