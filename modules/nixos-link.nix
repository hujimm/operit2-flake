# Operit2 无界面 Link 节点：以指定用户常驻运行 `operit2 cli link listen`。
# 与上游模型一致：节点数据就在该用户 HOME 的默认目录（~/.local/share/operit2、
# ~/.config/operit2），管理用同一个用户的普通 `operit2` 命令即可，无需额外包装或隔离。
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
      "--fixed-port"
    ]
    ++ lib.optional (!cfg.discovery) "--no-discovery"
    ++ cfg.extraArgs;
in
{
  options.services.operit2-link = {
    enable = lib.mkEnableOption "Operit2 CLI Link 节点";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/cli.nix { };
      defaultText = lib.literalExpression "operit2-cli";
      description = "提供 operit2 CLI 的包。";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        运行节点的用户。节点数据就写在该用户 HOME 下的默认目录，因此
        用同一用户执行 `operit2 cli ...` 时操作的是同一个实例。
      '';
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "监听地址。可达性由防火墙与承载网络决定。";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 37195;
      description = "Link 监听端口（固定端口，便于防火墙规则与配对地址稳定）。";
    };

    transports = lib.mkOption {
      type = lib.types.nonEmptyListOf (
        lib.types.enum [
          "tcp"
          "http"
          "ws"
        ]
      );
      # 上游 GUI 的手动配对只提供 HTTP/WebSocket 两种 carrier，默认用它们才连得上。
      default = [
        "http"
        "ws"
      ];
      description = "Link 传输。TCP 不能与 http/ws 共用同一端口。";
    };

    discovery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "是否开启 mDNS 局域网发现。服务器通常关闭。";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "追加到 `link listen` 之后的额外参数。";
    };

    openFirewallOn = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "wg0" ];
      description = "只在这些网卡上放行 Link 端口。";
    };

    openFirewallPublic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "是否在所有网卡放行 Link 端口（直接暴露公网时才需要）。";
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
        message = ''
          services.operit2-link.transports：tcp 不能与 http/ws 共用同一端口。
        '';
      }
    ];

    systemd.services.operit2-link = {
      description = "Operit2 CLI Link node";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # systemd 服务默认没有 HOME，而 operit2 需要一个 HOME 来决定存储目录。
      environment.HOME = userHome;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = userHome;
        ExecStart = lib.escapeShellArgs ([ "${cfg.package}/bin/operit2" ] ++ listenArgs);
        # listen 只在收到 Ctrl-C（SIGINT）时停止监听；systemd 默认发 SIGTERM。
        KillSignal = "SIGINT";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # 把 CLI 装进系统，方便以该用户登录后直接 `operit2 cli ...` 配置同一个实例。
    environment.systemPackages = [ cfg.package ];

    networking.firewall = {
      allowedTCPPorts = lib.optional cfg.openFirewallPublic cfg.port;
      interfaces = lib.genAttrs cfg.openFirewallOn (_: {
        allowedTCPPorts = [ cfg.port ];
      });
    };
  };
}
