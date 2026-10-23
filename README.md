# operit2-flake

[Operit2](https://github.com/AAswordman/Operit2) 的 Nix 打包。同一个上游提交构建出两个产物：

| 产物 | 说明 |
| --- | --- |
| `operit2-desktop` | Flutter 桌面 GUI（含 Rust bridge） |
| `operit2-cli` | CLI / TUI，以及可常驻的无界面 Link 节点 |

仅 `x86_64-linux`。License 见 [LICENSE](./LICENSE)（与上游一致，AGPL-3.0）。

本 flake 只负责把 Operit2 构建出来、并提供一个可选的常驻 Link 节点模块。**节点之间的网络可达性不在范围内**：局域网、公网、WireGuard/Tailscale 或其它 overlay 由使用者自行决定，只需把 Link 端口在对应网卡上放行。

## 构建图

上游是 Flutter + Rust 的 monorepo，构建期还会生成插件资源，所以打包被拆成四个 derivation：

```
                     ┌── cli.nix ──────────────→ operit2-cli
source.nix ──┬───────┤
             │       └── flutter-bridge.nix ──→ desktop.nix ──→ operit2-desktop
             └────────→ plugin-assets.nix ──┬─→ (cli)
                                             └─→ (flutter-bridge)
```

- `plugin-assets` 是 `cli` 和 `flutter-bridge` 的共同输入：上游的
  `core/crates/runtime/application/build.rs` 会把 `assets/plugins/` 嵌进二进制，
  所以三者必须用同一份输出，单独做一次比在每个产物里各跑一遍同步脚本省事。
- `flutter-bridge` 是 `desktop` 的输入：上游 GUI 的 CMake 里直接 `cargo build`，
  拆出来之后 GUI 的配置就不必关心 Rust 工具链。

每个文件顶部的注释说明了它为什么存在；改动前先读 [AGENTS.md](./AGENTS.md)。

## 快速开始

```nix
# flake.nix
inputs.operit2 = {
  url = "github:liyinuo2006/operit2-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 服务器：常驻无界面 Link 节点

```nix
{ inputs, ... }: {
  imports = [ inputs.operit2.nixosModules.link ];

  services.operit2-link = {
    enable = true;
    user = "root";   # 默认 root；节点数据写在该用户 HOME 的默认目录
    # 需要外部可达时，在承载流量的网卡上放行（名字按你自己的网络方案填）：
    # openFirewallOn = [ "wg0" ];
    # 或者显式暴露公网（不推荐）：
    # openFirewallPublic = true;
  };
}
```

节点以 `user`（默认 root）身份常驻运行，数据就在该用户的默认目录（`~/.local/share/operit2`、`~/.config/operit2`）。本模块会把 `operit2` 装进系统，所以以同一用户登录后，用普通命令配置的就是服务那份实例：

```sh
sudo operit2 cli link token show
sudo operit2 cli link pair-start <node-id> <address> tcp --token <token>
```

同一数据目录同时只应有一个运行中的 Core；与常驻服务并行执行配对类命令时，先 `systemctl stop operit2-link`，完成后再启动。

只想装 CLI（不跑服务，自己写 systemd 单元）：

```nix
imports = [ inputs.operit2.nixosModules.cli ];
programs.operit2-cli.enable = true;
```

### 桌面：安装 GUI

系统级（所有用户）：

```nix
{ inputs, ... }: {
  imports = [ inputs.operit2.nixosModules.desktop ];
  programs.operit2-desktop.enable = true;
}
```

或 Home Manager（把模块加进 `home-manager.sharedModules` 后）：

```nix
{ ... }: {
  programs.operit2-desktop.enable = true;
}
```

也可以直接用包：`inputs.operit2.packages.${system}.operit2-desktop`。

## 手机

手机装上游 release 的 Operit2 APK。它需要与服务器 CLI、桌面端来自同一上游提交，否则 Link 协议可能不匹配。

## 模块与输出

- `nixosModules.default` / `nixosModules.link`：`services.operit2-link`（CLI 常驻节点，含 CLI 安装）
- `nixosModules.cli`：`programs.operit2-cli.enable`（仅安装 CLI）
- `nixosModules.desktop`：`programs.operit2-desktop.enable`（系统级 GUI）
- `homeModules.default` / `homeModules.desktop`：`programs.operit2-desktop.enable`（Home Manager GUI）
- `packages.x86_64-linux.{operit2-desktop,operit2-cli,default}`
- `overlays.default`：注入 `pkgs.operit2-desktop` / `pkgs.operit2-cli`
- `formatter.x86_64-linux`：`nix fmt` 用 nixfmt

## 已知限制

- 桌面 GUI 单进程，关闭即退出，没有后台常驻；需要 7×24 在线时用服务器上的 `services.operit2-link`。
- 上游 FVM 固定的是 `3.41.10-ohos` 分支，本包用 nixpkgs 的 `flutter341`（3.41.9），差异是否影响 Linux 构建以实际构建为准。
- 脚本式 ToolPkg（如 `workflow`）在 Nix 构建中按普通目录打包，不运行 pnpm；其 `dist/` 已随上游提交。
- GUI 用 `autoPubspecLock` 直接读上游 `pubspec.lock`（依赖 import-from-derivation，nixpkgs 不允许，个人 flake 可以用）。

维护、升级与补丁说明见 [AGENTS.md](./AGENTS.md)。
