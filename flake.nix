{
  description = "Operit2 的 Nix 打包：Flutter GUI、Rust CLI 与无界面 Link 节点（x86_64-linux）";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      nixosModules = {
        # 无界面 Link 节点：services.operit2-link。
        link = import ./modules/nixos-link.nix;
        # 仅安装 CLI：programs.operit2-cli.enable。
        cli = import ./modules/nixos-cli.nix;
        # 系统级安装 GUI：programs.operit2-desktop.enable。
        desktop = import ./modules/nixos-desktop.nix;
      };

      homeModules = {
        # 用户级安装 GUI：programs.operit2-desktop.enable。
        desktop = import ./modules/home-desktop.nix;
      };
    in
    {
      packages.${system} = rec {
        operit2-cli = pkgs.callPackage ./pkgs/cli.nix { };
        operit2-desktop = pkgs.callPackage ./pkgs/desktop.nix { };
        default = operit2-desktop;
      };

      # 想用 pkgs.operit2-cli / pkgs.operit2-desktop 时装它。
      overlays.default = final: _: {
        operit2-cli = final.callPackage ./pkgs/cli.nix { };
        operit2-desktop = final.callPackage ./pkgs/desktop.nix { };
      };

      nixosModules = nixosModules // {
        default = nixosModules.link;
      };

      homeModules = homeModules // {
        default = homeModules.desktop;
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
