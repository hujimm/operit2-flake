{
  lib,
  stdenvNoCC,
  gitMinimal,
  nodejs,
  python3,
  typescript_5,
  callPackage,
}:
# 内置插件资源。上游把它当构建期产物：`core/crates/runtime/application/build.rs`
# 在编译时读取 `assets/plugins/{buildin,external}` 并嵌进二进制，所以 CLI、bridge、
# GUI 三者都需要同一份输出。单独做一个 derivation 是为了只生成一次、三处复用。
let
  source = callPackage ./source.nix { };
in
stdenvNoCC.mkDerivation {
  pname = "operit2-plugin-assets";
  inherit (source) version src;

  patches = [ ./patches/0001-nix-runtime.patch ];

  nativeBuildInputs = [
    gitMinimal
    nodejs
    python3
    # 同步脚本用 PATH 上的 `tsc` 预编译 TypeScript 插件；nixpkgs 默认的 typescript
    # 主版本与上游不兼容，这里固定 5.x。
    typescript_5
  ];

  # 让同步脚本走沙箱模式：跳过 pnpm/Corepack 联网安装、跳过 SDK 类型代码生成
  # （那一步要 `cargo run`），并把 ZIP 条目的时间戳固定住。
  env.OPERIT_NIX_BUILD = "1";

  buildPhase = ''
    runHook preBuild

    # 同步脚本用 `git ls-files --exclude-standard` 枚举要打包的文件，
    # 而源码归档里没有 .git，所以临时建一个工作区。
    git init --quiet
    git add --force --all

    python3 plugins/tools/sync_plugin_packages.py --source runtime --no-hot-reload

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -d "$out/plugins"
    cp -a core/crates/runtime/application/assets/plugins/. "$out/plugins/"

    runHook postInstall
  '';

  meta = source.meta // {
    description = "Operit2 内置插件资源（buildin + external）";
    platforms = lib.platforms.linux;
  };
}
