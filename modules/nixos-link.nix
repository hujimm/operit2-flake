# Operit2 Link 节点的 NixOS 模块。
#
# 本仓库只提供这一个模块，因为只有它做了 systemd 才知道的事：
#   * 以指定用户常驻运行 `operit2 cli link listen`；
#   * systemd 默认不设 HOME，而 operit2 依赖 HOME 决定数据目录；
#   * 上游 `listen` 只在收到 SIGINT 时正常退出，systemd 默认发 SIGTERM；
#   * 端口放行。
# 只装 CLI 或 GUI 不需要模块：`pkgs.operit2-cli` / `pkgs.operit2-desktop` 一行即可。
#
# 设备互联不在这里声明：配对需要两端人工确认六位验证码，加入 Space 需要另一台
# 设备上的审批人批准，凭据存在该用户 HOME 下的数据目录里。这些都是运行时状态，
# 见 README 的「配对与组网」。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.operit2-link;

  # user 可能是调用者忘了定义的用户；这里给一个类型正确的兜底值，真正的
  # 拦截交给下面的 assertions（否则会在求值期抛 attribute missing）。
  userHome = lib.attrByPath [ cfg.user "home" ] "/var/lib/operit2" config.users.users;

  listenArgs =
    [
      "cli"
      "link"
      "listen"
      (lib.concatStringsSep "," cfg.transports)
      "--bind"
      "${cfg.bindAddress}:${toString cfg.port}"
      # 固定端口，方便防火墙规则与配对地址稳定；代价是端口被占用时启动失败。
      "--fixed-port"
    ]
    ++ lib.optional (!cfg.discovery) "--no-discovery";
in
{
  options.services.operit2-link = {
    enable = lib.mkEnableOption "Operit2 Link 无界面常驻节点";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/cli.nix { };
      defaultText = lib.literalExpression "pkgs.operit2-cli";
      description = "提供 `operit2` CLI 的包。";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        运行节点的用户，该用户必须已存在。节点数据写在该用户 HOME 下的默认目录
        （`~/.local/share/operit2`、`~/.config/operit2`），所以用同一用户执行
        `operit2 cli ...` 时操作的就是服务那份实例。
      '';
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      example = "10.144.144.1";
      description = ''
        监听地址。设备间是否可达由底层网络决定（EasyTier / WireGuard / 同机房），
        因此组网场景通常绑定虚拟网卡地址，而不是 0.0.0.0。
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 37195;
      description = "Link 监听端口（固定端口）。";
    };

    transports = lib.mkOption {
      type = lib.types.nonEmptyListOf (
        lib.types.enum [
          "tcp"
          "http"
          "ws"
        ]
      );
      # 上游 GUI 的手动配对只提供 HTTP/WebSocket 两种 carrier。
      default = [
        "http"
        "ws"
      ];
      description = "监听哪些传输。`tcp` 不能与 `http`/`ws` 共用同一端口。";
    };

    discovery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "是否开启 mDNS 局域网发现。服务器通常关闭。";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "在所有接口上放行 Link 端口。直接暴露公网时才需要。";
    };

    firewallInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "tun0" ];
      description = "只在这些网卡上放行 Link 端口。";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.user config.users.users;
        message = ''
          services.operit2-link.user = "${cfg.user}" 不存在。
          节点数据会写在该用户 HOME 下的默认目录，请先用 users.users.${cfg.user} 定义该用户。
        '';
      }
      {
        assertion = !(builtins.elem "tcp" cfg.transports) || builtins.length cfg.transports == 1;
        message = "services.operit2-link.transports：tcp 不能与 http/ws 共用同一端口。";
      }
    ];

    systemd.services.operit2-link = {
      description = "Operit2 Link node";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # systemd 服务默认没有 HOME，而 operit2 靠它决定数据目录。
      environment.HOME = userHome;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = userHome;
        ExecStart = lib.escapeShellArgs ([ "${cfg.package}/bin/operit2" ] ++ listenArgs);
        # `listen` 只在 SIGINT（Ctrl-C）时正常收尾；systemd 默认发 SIGTERM。
        KillSignal = "SIGINT";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # 把 CLI 装进系统，方便以该用户登录后直接操作同一个实例。
    environment.systemPackages = [ cfg.package ];

    networking.firewall = {
      allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
      interfaces = lib.genAttrs cfg.firewallInterfaces (_: {
        allowedTCPPorts = [ cfg.port ];
      });
    };
  };
}
