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
    # Target system for NixOS hosts (machines are x86_64)
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Helper to generate attributes for multiple local systems (host running the deploy)
    forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

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

    # Create a deploy app for a given pkgs set (local system), hostname and target
    mkDeployApp = pkgsForLocal: hostname: targetHost: {
      type = "app";
      program = toString (pkgsForLocal.writeShellScript "deploy-${hostname}" ''
        set -eu
        exec ${pkgsForLocal.nixos-rebuild}/bin/nixos-rebuild switch \
          --flake ${self}#${hostname} \
          --target-host ${targetHost} \
          --build-host ${targetHost} \
          "$@"
      '');
    };
  in {
    nixosConfigurations = {
      eiji = mkHost "eiji" [ ];
      ash = mkHost "ash" [ discord-role-bot.nixosModules.default ];
      charlotte = mkHost "charlotte" [ bc-250.nixosModules.bc250 ];
      gyaruko = mkHost "gyaruko" [ bc-250.nixosModules.bc250 ];
      relay = mkHost "relay" [ ];
    };

    apps = forAllSystems (localSystem: let
      pkgsForLocal = nixpkgs.legacyPackages.${localSystem};
    in {
      deploy-eiji = mkDeployApp pkgsForLocal "eiji" "eiji.home.endercass.me";
      deploy-ash = mkDeployApp pkgsForLocal "ash" "ash.home.endercass.me";
      deploy-charlotte = mkDeployApp pkgsForLocal "charlotte" "charlotte.home.endercass.me";
      deploy-gyaruko = mkDeployApp pkgsForLocal "gyaruko" "gyaruko.home.endercass.me";
      deploy-relay = mkDeployApp pkgsForLocal "relay" "relay.endercass.me";
    });

    devShells = forAllSystems (localSystem: let
      pkgsForLocal = nixpkgs.legacyPackages.${localSystem};
    in {
      default = pkgsForLocal.mkShell {
        packages = with pkgsForLocal; [ nixos-rebuild openssh ];
      };
    });
  };
}