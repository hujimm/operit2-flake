{
  lib,
  rustPlatform,
  callPackage,
  makeWrapper,
  coreutils,
  bash,
  iproute2,
  inetutils,
  procps,
  xdg-utils,
}:
# CLI / TUI，同时也是可常驻的无界面 Link 节点。
# 上游的 `apps/cli` 是自包含的 Cargo 项目，所以这里只需要 buildRustPackage
# 加一份预生成的插件资源。
let
  source = callPackage ./source.nix { };
  pluginAssets = callPackage ./plugin-assets.nix { };

  # 运行时由 `hosts/linux` 直接调用的外部命令。这些路径写进 wrapper 的 PATH 后
  # 就被 $out 引用，因此不需要再写进 buildInputs。
  runtimeTools = [
    coreutils
    bash
    iproute2
    inetutils
    procps
    xdg-utils
  ];
in
rustPlatform.buildRustPackage {
  pname = "operit2-cli";
  inherit (source) version src;

  cargoRoot = "apps/cli";
  buildAndTestSubdir = "apps/cli";
  cargoLock.lockFile = "${source.src}/apps/cli/Cargo.lock";
  cargoBuildFlags = [
    "--bin"
    "operit2"
  ];
  # 上游的 Linux 发布流程只构建、不跑 cargo test。
  doCheck = false;

  patches = [ ./patches/0001-nix-runtime.patch ];

  nativeBuildInputs = [
    makeWrapper
    rustPlatform.bindgenHook
  ];

  postPatch = ''
    install -d core/crates/runtime/application/assets/plugins
    cp -a ${pluginAssets}/plugins/. core/crates/runtime/application/assets/plugins/
  '';

  postInstall = ''
    wrapProgram "$out/bin/operit2" --prefix PATH : ${lib.makeBinPath runtimeTools}
    ln -s operit2 "$out/bin/operit"
  '';

  passthru = { inherit pluginAssets; };

  meta = source.meta // {
    description = "Operit2 Agent CLI / TUI 与无界面 Link 节点";
    mainProgram = "operit2";
  };
}
