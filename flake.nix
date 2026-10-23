{
  description = "Operit2 的 Nix 打包：Flutter GUI、Rust CLI，以及可选的 Link 常驻节点模块（x86_64-linux）";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = rec {
        operit2-cli = pkgs.callPackage ./pkgs/cli.nix { };
        operit2-desktop = pkgs.callPackage ./pkgs/desktop.nix { };
        # GUI 目前无法用 nixpkgs 的 Flutter 构建（上游 Linux 端要求定制引擎），
        # 默认产物因此是 CLI；原因见 README「已知限制」。
        default = operit2-cli;
      };

      # 装了这个之后，NixOS 和 Home Manager 里都能直接写
      # `environment.systemPackages = [ pkgs.operit2-desktop ]`。
      overlays.default = final: _: {
        operit2-cli = final.callPackage ./pkgs/cli.nix { };
        operit2-desktop = final.callPackage ./pkgs/desktop.nix { };
      };

      # 唯一的模块：systemd 服务 + 用户 HOME + 防火墙。配对与 Space 属于运行时。
      nixosModules = {
        link = import ./modules/nixos-link.nix;
        default = self.nixosModules.link;
      };

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixd
          nixfmt
          statix
          deadnix
        ];
      };

      # 仓库没有 CI 之外的信号来源：两个产物 + 一个模块求值检查。
      # 模块检查只求值、不构建整机，用来防「ExecStart / HOME / 停止信号」被改坏。
      checks.${system} = {
        inherit (self.packages.${system}) operit2-cli;

        module-eval =
          let
            node =
              (nixpkgs.lib.nixosSystem {
                system = system;
                modules = [
                  self.nixosModules.link
                  {
                    system.stateVersion = "26.05";
                    users.users.operit2 = {
                      isSystemUser = true;
                      group = "operit2";
                      home = "/home/operit2";
                    };
                    services.operit2-link = {
                      enable = true;
                      user = "operit2";
                      bindAddress = "10.0.0.1";
                      firewallInterfaces = [ "tun0" ];
                    };
                  }
                ];
              }).config.systemd.services.operit2-link;
          in
          pkgs.runCommand "operit2-link-module-check" { } ''
            test '${node.serviceConfig.User}' = operit2
            test '${node.serviceConfig.KillSignal}' = SIGINT
            test '${node.environment.HOME}' = /home/operit2
            grep -q -- '--no-discovery' <<'EOF'
            ${node.serviceConfig.ExecStart}
            EOF
            grep -q -- '--bind 10.0.0.1:37195' <<'EOF'
            ${node.serviceConfig.ExecStart}
            EOF
            touch $out
          '';
      };
    };
}
