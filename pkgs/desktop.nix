{
  lib,
  flutter341,
  callPackage,
  gitMinimal,
  clang,
  cmake,
  ninja,
  pkg-config,
  copyDesktopItems,
  makeDesktopItem,
  gtk3,
  webkitgtk_4_1,
  gst_all_1,
  # gstreamer 的 .pc 在 Requires 里列了这些，pkg-config 会递归查找，
  # 但 buildInputs 不传播，必须显式列出。
  libunwind,
  libayatana-appindicator,
  orc,
  elfutils,
  glib-networking,
  glib,
  gsettings-desktop-schemas,
  libsecret,
  xz,
  # GUI 通过 hosts/linux 在运行时调用的外部命令。
  xrandr,
  libnotify,
  xdg-utils,
  procps,
  coreutils,
  bash,
  iproute2,
  inetutils,
  alsa-utils,
  bluez,
  espeak-ng,
  tesseract,
  gnome-screenshot,
}:
# Flutter 桌面 GUI。上游的 Linux runner 会自己调 CMake，所以禁用 stdenv 的
# CMake configure hook（dontUseCmakeConfigure），其余交给 buildFlutterApplication。
let
  source = callPackage ./source.nix { };
  flutterBridge = callPackage ./flutter-bridge.nix { };

  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-libav
  ];

  runtimeTools = [
    xrandr
    libnotify
    xdg-utils
    glib
    procps
    coreutils
    bash
    iproute2
    inetutils
    alsa-utils
    bluez
    espeak-ng
    tesseract
    gnome-screenshot
  ];
in
flutter341.buildFlutterApplication {
  pname = "operit2-desktop";
  inherit (source) version src;

  patches = [ ./patches/0002-nix-flutter-linux.patch ];

  sourceRoot = "${source.src.name}/apps/flutter/app";

  # 直接读上游的 pubspec.lock（IFD）。nixpkgs 不允许这样做，但个人 flake 可以，
  # 好处是升级时不必再维护一份 pubspec.lock.json。
  autoPubspecLock = source.src + "/apps/flutter/app/pubspec.lock";

  # 上游 pubspec 引用同一个 openharmony flutter_packages 提交上的三个包。
  gitHashes = {
    path_provider_ohos = "sha256-KQ1NB3eVVLRPZfl5eYMfMcg98su4kzYE8Iv4x6PkHu8=";
    url_launcher_ohos = "sha256-KQ1NB3eVVLRPZfl5eYMfMcg98su4kzYE8Iv4x6PkHu8=";
    video_player_ohos = "sha256-KQ1NB3eVVLRPZfl5eYMfMcg98su4kzYE8Iv4x6PkHu8=";
  };

  nativeBuildInputs = [
    clang
    cmake
    copyDesktopItems
    gitMinimal
    ninja
    pkg-config
  ];

  # Flutter 在 buildPhase 里自己调 CMake。
  dontUseCmakeConfigure = true;

  buildInputs = [
    flutterBridge
    glib-networking
    gsettings-desktop-schemas
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    libunwind
    libayatana-appindicator
    orc
    elfutils
    gtk3
    libsecret
    webkitgtk_4_1
    xz
  ];

  env.OPERIT_FLUTTER_BRIDGE_LIB = "${flutterBridge}/lib/liboperit_flutter_bridge.so";

  postPatch = ''
    # bridge 的 build.rs 生成的 Dart 代理代码，GUI 侧需要。
    install -d lib/core/proxy/generated
    install -m644 \
      ${flutterBridge}/share/operit2/dart-proxy/CoreProxyClients.g.dart \
      ${flutterBridge}/share/operit2/dart-proxy/CoreProxyModels.g.dart \
      lib/core/proxy/generated/
  '';

  postInstall = ''
    mv "$out/bin/operit2" "$out/bin/operit2-desktop"
    install -Dm644 \
      "${source.src}/apps/flutter/app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
      "$out/share/icons/hicolor/192x192/apps/operit2.png"
  '';

  # OPERIT_DESKTOP_LAUNCHER 让 my_application.cc 写 D-Bus 激活文件时指向
  # 本 wrapper（而不是被改名成 .operit2-desktop-wrapped 的真二进制）。
  extraWrapProgramArgs = ''
    --prefix PATH : "${lib.makeBinPath runtimeTools}" \
    --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}" \
    --set GST_PLUGIN_SCANNER "${gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner" \
    --set OPERIT_DESKTOP_LAUNCHER "$out/bin/operit2-desktop"
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "operit2-desktop";
      exec = "operit2-desktop";
      icon = "operit2";
      desktopName = "Operit2";
      genericName = "AI Agent Desktop Application";
      categories = [ "Utility" ];
      terminal = false;
    })
  ];

  passthru = { inherit flutterBridge; };

  meta = source.meta // {
    description = "Operit2 AI Agent 桌面客户端（Flutter GUI）";
    mainProgram = "operit2-desktop";
    platforms = lib.platforms.linux;
  };
}
