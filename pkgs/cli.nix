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
  nodejs,
  python3,
}:
# CLI / TUI，同时也是可常驻的无界面 Link 节点。
# 上游的 `apps/cli` 是自包含的 Cargo 项目，所以这里只需要 buildRustPackage
# 加一份预生成的插件资源。
let
  source = callPackage ./source.nix { };
  pluginAssets = callPackage ./plugin-assets.nix { };

  # 运行时由 `hosts/linux` 直接调用的外部命令。这些路径写进 wrapper 的 PATH 后
  # 就被 $out 引用，因此不需要再写进 buildInputs。
  # node/python3 是 ManagedRuntimeProgram 的默认查找目标（ToolPkg 用），缺了会直接
  # 报 "Managed runtime executable not found"；uv/pnpm 不是必需，需要时装在系统里即可。
  runtimeTools = [
    coreutils
    bash
    iproute2
    inetutils
    procps
    xdg-utils
    nodejs
    python3
  ];
in
rustPlatform.buildRustPackage {
  pname = "operit2-cli";
  inherit (source) version src;

  cargoRoot = "apps/cli";
  buildAndTestSubdir = "apps/cli";
  # 上游提交里的 apps/cli/Cargo.lock 是过期的（缺 rustls-native-certs 0.8 等条目，
  # 因为他们本地构建不加 --locked，cargo 会静默补写）。沙箱里不能联网补写，
  # 所以用 pkgs/locks 下重新生成的 lock 供 vendor，并在 postPatch 里把同一份
  # 写回源码树，让 cargoSetupPostPatchHook 的一致性检查通过。
  cargoLock.lockFile = ./locks/apps-cli.Cargo.lock;
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
    # 覆盖上游那份过期的 lock（与 cargoLock.lockFile 同一份文件）。
    install -m644 ${./locks/apps-cli.Cargo.lock} apps/cli/Cargo.lock

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
