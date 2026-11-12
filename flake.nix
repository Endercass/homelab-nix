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
    nixos-jellyfin = {
      url = "github:matt1432/nixos-jellyfin";
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
    nixos-jellyfin,
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

    mkSopsApp = pkgsForLocal: action: hostname: {
      type = "app";
      program = toString (pkgsForLocal.lib.getExe (pkgsForLocal.writeShellApplication {
          name = "sops-${action}-${hostname}";
          runtimeInputs = with pkgsForLocal; [ coreutils git sops ];
          text = ''
            set -eu

            repo="$(git rev-parse --show-toplevel)"
            secrets_dir="$repo/secrets/${hostname}"

            find "$secrets_dir" -type f -print0 |
              while IFS= read -r -d "" secret; do
                sops --${action} --in-place "$secret"
              done
          '';
        }));
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
      decrypt-eiji = mkSopsApp pkgsForLocal "decrypt" "eiji";
      encrypt-eiji = mkSopsApp pkgsForLocal "encrypt" "eiji";
      decrypt-ash = mkSopsApp pkgsForLocal "decrypt" "ash";
      encrypt-ash = mkSopsApp pkgsForLocal "encrypt" "ash";
      decrypt-charlotte = mkSopsApp pkgsForLocal "decrypt" "charlotte";
      encrypt-charlotte = mkSopsApp pkgsForLocal "encrypt" "charlotte";
      decrypt-gyaruko = mkSopsApp pkgsForLocal "decrypt" "gyaruko";
      encrypt-gyaruko = mkSopsApp pkgsForLocal "encrypt" "gyaruko";
      decrypt-relay = mkSopsApp pkgsForLocal "decrypt" "relay";
      encrypt-relay = mkSopsApp pkgsForLocal "encrypt" "relay";
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