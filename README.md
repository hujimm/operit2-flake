# operit2-flake

[Operit2](https://github.com/AAswordman/Operit2) 的 Nix 打包。同一个上游提交构建出两个产物：

| 产物 | 说明 |
| --- | --- |
| `operit2-desktop` | Flutter 桌面 GUI（含 Rust bridge） |
| `operit2-cli` | CLI / TUI，以及可常驻的无界面 Link 节点 |

仅 `x86_64-linux`。License 见 [LICENSE](./LICENSE)（与上游一致，AGPL-3.0）。

仓库只做两件事：把上游构建出来；把「常驻 Link 节点」的 systemd 样板固化成一个模块。
**设备之间怎么互通、怎么配对，不是 Nix 能声明的东西**，见「配对与组网」。

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
  所以三者必须用同一份输出。
- `flutter-bridge` 是 `desktop` 的输入：上游 GUI 的 CMake 里直接 `cargo build`，
  拆出来之后 GUI 的配置就不必关心 Rust 工具链。

改动前先读 [AGENTS.md](./AGENTS.md)。

## 快速开始

```nix
# flake.nix
inputs.operit2 = {
  url = "github:liyinuo2006/operit2-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 安装 GUI 或 CLI（不需要模块）

```nix
{ inputs, pkgs, ... }: {
  nixpkgs.overlays = [ inputs.operit2.overlays.default ];
  environment.systemPackages = [ pkgs.operit2-desktop pkgs.operit2-cli ];
  # Home Manager 里同样：home.packages = [ pkgs.operit2-desktop ];
}
```

不想用 overlay 就直接写 `inputs.operit2.packages.x86_64-linux.operit2-desktop`。

### 服务器：常驻无界面 Link 节点

```nix
{ inputs, ... }: {
  imports = [ inputs.operit2.nixosModules.link ];

  services.operit2-link = {
    enable = true;
    user = "orion";                  # 必填：以你的用户身份运行，数据写你的 HOME
    bindAddress = "10.144.144.1";    # 组网场景绑虚拟网卡地址
    firewallInterfaces = [ "tun0" ]; # 只对组网网卡放行
  };
}
```

模块负责四件 systemd 层面的事，不会替你配对：

- 以 `user` 身份常驻运行 `operit2 cli link listen <transports> --bind ... --fixed-port`
- 补上 `HOME`（systemd 默认不设，而 operit2 靠它决定数据目录）
- 用 `SIGINT` 停止（上游只在这个信号下正常收尾）
- 按 `firewallInterfaces` 只在对组网的网卡上放行端口，并固定关闭 mDNS 发现

节点数据写在该用户 HOME 的默认目录（`~/.local/share/operit2`、`~/.config/operit2`），
模块会把 `operit2` 装进系统，所以以同一用户登录后执行的就是服务那份实例：

```sh
operit2 cli link peers     # 查看已配对设备
```

同一数据目录同时只应有一个运行中的 Core；与常驻服务并行执行配对类命令时，
先 `sudo systemctl stop operit2-link`，完成后再启动。

## 配对与组网

这两件事**只能运行时做**，因为上游协议要求人工参与，且状态存在数据目录里：

```sh
# 1. 在 A 上发起，B 上会显示六位验证码
operit2 cli link pair-start <B-node-id> <B-address>:37195 http
# 2. 把 B 显示的验证码填回来
operit2 cli link pair-finish <pairing-id> 123456
# 3. 配对只授予通信授权，加入同一个 Space 还要对方审批
operit2 cli link space join <B-node-id>
```

- **配对**：接收端显示六位码，人工确认，无法声明式完成。
- **Space**：`space join` 只是发申请，要在对方设备上 `space approve`。
- **可达性**：Operit2 不做 NAT 穿透，它把物理路径交给外部 carrier（EasyTier、
  WireGuard、Tailscale，或同机房）。所以 `bindAddress` 通常填虚拟网卡地址，
  防火墙只对这些网卡放行，和上面的例子一致。

## 输出

- `packages.x86_64-linux.{operit2-cli,operit2-desktop,default}`
- `overlays.default`：注入 `pkgs.operit2-cli` / `pkgs.operit2-desktop`
- `nixosModules.link` / `nixosModules.default`：`services.operit2-link`
- `formatter.x86_64-linux`：`nix fmt` 用 nixfmt
- `checks.x86_64-linux`：`nix flake check` 会构建两个产物

## 已知限制

- 桌面 GUI 单进程，关闭即退出，没有后台常驻；需要 7×24 在线时用服务器上的
  `services.operit2-link`。
- 同一用户下 GUI 与 `services.operit2-link` 会共用同一份监听配置（`listen` 每次启动
  都会写回），端口冲突时只能跑一个。
- 上游 FVM 固定的是 `3.41.10-ohos` 分支，本包用 nixpkgs 的 `flutter341`（3.41.9），
  差异是否影响 Linux 构建以实际构建为准。
- 脚本式 ToolPkg（如 `workflow`）在 Nix 构建中按普通目录打包，不运行 pnpm；
  其 `dist/` 已随上游提交。
- GUI 用 `autoPubspecLock` 直接读上游 `pubspec.lock`（依赖 import-from-derivation，
  nixpkgs 不允许，个人 flake 可以用）。
- `services.operit2-link` 未做 systemd 硬化：上游会 `exec` 系统工具，硬化过紧会让
  节点静默失效，需实际构建验证后再加。

维护、升级与补丁说明见 [AGENTS.md](./AGENTS.md)。
