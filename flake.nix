{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bc-250.url = "github:TesseractCat/bc250-nixos";
    authentik-nix = {
      url = "github:nix-community/authentik-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    discord-role-bot = {
      url = "github:Endercass/discord-role-bot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    bc-250,
    authentik-nix,
    microvm,
    sops-nix,
    discord-role-bot,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    mkHost = hostname: extraModules:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules =
          [
            sops-nix.nixosModules.sops
            ./hosts/${hostname}
          ]
          ++ extraModules;
      };

    mkDeployApp = hostname: targetHost: {
      type = "app";
      program = toString (pkgs.writeShellScript "deploy-${hostname}" ''
        set -eu
        exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
          --flake ${self}#${hostname} \
          --target-host ${targetHost} \
          "$@"
      '');
    };
  in {
    nixosConfigurations = {
      eiji = mkHost "eiji" [ ];
      ash = mkHost "ash" [ discord-role-bot.nixosModules.default ];
      charlotte = mkHost "charlotte" [ bc-250.nixosModules.bc250 ];
      gyaruko = mkHost "gyaruko" [ bc-250.nixosModules.bc250 ];
    };

    apps.${system} = {
      deploy-eiji = mkDeployApp "eiji" "eiji.home.endercass.me";
      deploy-ash = mkDeployApp "ash" "ash.home.endercass.me";
      deploy-charlotte = mkDeployApp "charlotte" "charlotte.home.endercass.me";
      deploy-gyaruko = mkDeployApp "gyaruko" "gyaruko.home.endercass.me";
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [nixos-rebuild openssh];
    };
  };
}