{
  lib,
  rustPlatform,
  callPackage,
}:
# GUI 的原生桥（liboperit_flutter_bridge.so）。上游在 GUI 的 CMake 里直接
# `cargo build` 这个 crate；在 Nix 里把它拆出来，一是让 GUI 的配置不用关心
# Rust 工具链，二是 CLI 与 GUI 复用同一份编译产物。
let
  source = callPackage ./source.nix { };
  pluginAssets = callPackage ./plugin-assets.nix { };
in
rustPlatform.buildRustPackage {
  pname = "operit2-flutter-bridge";
  inherit (source) version src;

  cargoRoot = "apps/flutter/native/operit-flutter-bridge";
  buildAndTestSubdir = "apps/flutter/native/operit-flutter-bridge";
  cargoLock.lockFile = "${source.src}/apps/flutter/native/operit-flutter-bridge/Cargo.lock";
  cargoBuildFlags = [ "--lib" ];
  doCheck = false;

  patches = [ ./patches/0001-nix-runtime.patch ];

  nativeBuildInputs = [ rustPlatform.bindgenHook ];

  postPatch = ''
    install -d core/crates/runtime/application/assets/plugins
    cp -a ${pluginAssets}/plugins/. core/crates/runtime/application/assets/plugins/
  '';

  # `core/crates/proxy/local/build.rs` 会把 Dart 侧的代理代码写进
  # apps/flutter/app/lib/core/proxy/generated/，GUI 构建需要这两个文件，
  # 所以随 bridge 一起导出。
  postInstall = ''
    install -d "$out/share/operit2/dart-proxy"
    install -m644 \
      apps/flutter/app/lib/core/proxy/generated/CoreProxyClients.g.dart \
      apps/flutter/app/lib/core/proxy/generated/CoreProxyModels.g.dart \
      "$out/share/operit2/dart-proxy/"
  '';

  meta = source.meta // {
    description = "Operit2 Flutter 原生桥";
    platforms = lib.platforms.linux;
  };
}
