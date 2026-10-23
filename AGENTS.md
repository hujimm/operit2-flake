# AGENTS.md — operit2-flake

[Operit2](https://github.com/AAswordman/Operit2) 的 Nix 打包仓库。源码由 `fetchFromGitHub`
固定到具体提交。**本文件是维护入口**：结构、版本策略、补丁、升级流程、已知边界都在这。
用户向说明见 [README.md](./README.md)。

## 硬性规则

- 不要在本仓库运行 `nix build` / `nix flake check` / `nix eval` / `nix develop` 做验证：
  改动后由用户在自己机器上构建，`nixos-rebuild` 也由用户执行。`pkgs/update.py` 只用
  `gh` 和 `nix hash path`（本地哈希），不触发求值。
- 访问 GitHub 用 `gh`/`git`，禁止裸 `curl` 请求 GitHub API/raw。
- 注释用中文。
- 行为性改动（权限、Link 协议、UI）不要打进补丁，应提交上游；这里只做「让上游在 Nix
  沙箱里按同样语义构建」的替换。

## 仓库结构

```
flake.nix                 # packages / overlays / nixosModules / formatter / checks
pkgs/source.nix           # 唯一版本 pin：rev / version / hash，外加共享 meta
pkgs/plugin-assets.nix    # 内置插件资源（buildin + external），cli 与 bridge 共用
pkgs/cli.nix              # CLI / TUI / Link 节点（buildRustPackage）
pkgs/flutter-bridge.nix   # GUI 的 Rust 原生桥 + Dart 代理导出
pkgs/desktop.nix          # Flutter GUI（buildFlutterApplication）
pkgs/patches/*.patch      # Nix 专用源码适配，见下表
pkgs/update.py            # 升级：更新 pin + 校验补丁可应用
modules/nixos-link.nix    # services.operit2-link（唯一的模块）
```

**只保留一个模块**：只有它做了 systemd 才知道的事（用户、HOME、SIGINT、防火墙）。
只装 CLI/GUI 不需要模块，`environment.systemPackages = [ pkgs.operit2-cli ]` 即可。
配对、Space 成员、凭据是运行时状态，永远不要做成 option。

`packages.${system}` 用 `nixpkgs.legacyPackages`；模块用 `pkgs.callPackage ../pkgs/*.nix`
取默认包，用户可用选项 `package` 覆盖。

## 版本策略

- CLI、GUI、bridge、插件资源都绑定 `pkgs/source.nix` 的同一个提交。
- 手机 APK（上游 release）与服务器 CLI、桌面端必须来自同一提交，否则 Link 协议可能不匹配。
- Flutter 用 nixpkgs 的 `flutter341`（3.41.9）。上游 FVM 固定 `3.41.10-ohos` 分支；
  差异是否影响 Linux 构建以实际构建为准，若出现 Dart SDK/引擎错误优先查这一项。
- nixpkgs 只 follow `nixos-unstable`，不锁旧版。
- GUI 用 `autoPubspecLock` 直接读上游 `pubspec.lock`，因此仓库里不再保存
  `pubspec.lock.json`；代价是求值期有 IFD。

## 升级流程

```sh
python3 pkgs/update.py                  # 跟随 main 最新提交
python3 pkgs/update.py --rev <sha>      # 固定到指定提交
git diff                                # 然后由用户 nix build
```

脚本会：下载源码归档 → `nix hash path` 算 NAR 哈希 → 从 `apps/cli/Cargo.toml` 读版本 →
重写 `pkgs/source.nix` → 在临时目录 `git apply --check` 两个补丁。需要 `gh`（已认证）、
`tar`、`nix`。

若 pubspec 里 git 依赖的 `ref` 变化，还要同步 `pkgs/desktop.nix` 的 `gitHashes`
（缺了会报错并指出缺哪个）。补丁锚点失效时脚本会失败，需人工更新对应 `.patch`。

## Nix 专用源码适配（pkgs/patches）

| 补丁 | 替换 | 原因 |
| --- | --- | --- |
| `0001-nix-runtime.patch` | `xrandr` 直接调用，失败返回 `unknown` | 不依赖 `sh -lc` + `sed` 管道；纯 Wayland 下查不到分辨率不应阻止 Core 启动 |
| `0001-nix-runtime.patch` | `sync_plugin_packages.py`：`OPERIT_NIX_BUILD=1` 时跳过 SDK 类型生成、不走 pnpm | 沙箱无网络，且 SDK 生成要 `cargo run`；script 式 ToolPkg 按普通目录打包 |
| `0001-nix-runtime.patch` | ZIP 条目时间戳固定 1980 | Nix store 文件 mtime 为 1970，zipfile 不接受 |
| `0002-nix-flutter-linux.patch` | CMake 里的插件同步与 `cargo build` 改为空操作 | 资源与 bridge 由独立 derivation 提供 |
| `0002-nix-flutter-linux.patch` | bridge `.so` 路径改用 `OPERIT_FLUTTER_BRIDGE_LIB` | bridge 由 Nix 单独构建 |
| `0002-nix-flutter-linux.patch` | `hook/build.dart` 去掉插件同步调用 | Flutter native hook 不能在构建时访问 venv |
| `0002-nix-flutter-linux.patch` | `my_application.cc` 优先读 `OPERIT_DESKTOP_LAUNCHER` | `/proc/self/exe` 指向被 `wrapProgram` 改名后的真二进制，D-Bus 激活会丢 PATH |

`0001` 适用于所有 Rust 产物和插件资源；`0002` 只适用于 GUI。补丁由
`pkgs/update.py` 在升级时校验，锚点失效会直接失败而不是静默跳过。

## 与 nixpkgs 惯例的偏差（有意为之）

| 偏差 | 原因 |
| --- | --- |
| `meta` 定义在 `pkgs/source.nix`，各包 `source.meta // { ... }` | 四个产物同源同许可，避免重复；nixpkgs 里这种做法不常见 |
| 没有用 `finalAttrs`（RFC 0035） | 包内没有自引用（version/src 都来自 `source.nix`），套上只是噪音 |
| `doCheck = false`、无 `passthru.tests` | 上游 Linux 发布流程不跑 `cargo test`；没有可离线运行的测试 |
| `autoPubspecLock` 用 IFD | 换掉 1760 行 `pubspec.lock.json`；代价是 `nix eval`/`nix flake show` 会触发构建 |
| 没有 `meta.maintainers` | 个人 flake，暂不对外提 nixpkgs |
| `services.operit2-link` 未做 systemd 硬化 | 上游会 `exec` 系统工具（xrandr/xdg-open/终端），硬化过紧会让节点静默失效；需构建验证后增量加 |

补丁目前都只作用于本仓库，**没有提交上游**。若上游接受了同类改动（例如去掉
`.venv` 依赖、固定 ZIP 时间戳），应先删对应补丁再重新 `nix build` 验证。

## 已知边界

- **必须提交 `flake.lock`**：`nixpkgs` 跟的是 `nixos-unstable` 分支，不锁就是不可复现的。
  首次 `nix build` 会自动生成，之后请一并提交；改 input 后跑 `nix flake lock`。
- 桌面 GUI 单进程，关窗即退出；常驻在线能力由 `services.operit2-link` 提供。
- 节点之间的网络可达性（局域网/公网/overlay）不在本仓范围；`services.operit2-link`
  只负责监听与放行接口，怎么让设备互通由使用者决定。
- `services.operit2-link` 与上游模型一致：以 `user`（默认 root）运行 `link listen`，
  数据用该用户 HOME 的默认目录；不做专用账号/目录隔离，也没有额外包装脚本。
  权限即该用户的权限（root 就是 root）。
- 没有验证过两个进程同时打开同一 Operit2 数据目录的行为，与常驻服务并行执行配对
  类命令前先停服务。

## 验证（由用户执行）

```sh
nix build .#operit2-cli .#operit2-desktop
nix flake check
```

桌面启动后确认 `~/.local/share/dbus-1/services/org.operit.PluginSdk.service` 的 `Exec`
指向 wrapper；服务器上确认 `systemctl status operit2-link`、`journalctl -u operit2-link`。
