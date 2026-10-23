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
        default = operit2-desktop;
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

      # 仓库没有 CI，`nix flake check` 是唯一的信号来源。
      checks.${system} = {
        inherit (self.packages.${system}) operit2-cli operit2-desktop;
      };
    };
}
