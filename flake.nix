{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bc-250.url = "github:TesseractCat/bc250-nixos";
  };

  outputs = {
    self,
    nixpkgs,
    bc-250,
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
      eiji = mkHost "eiji" [];
      ash = mkHost "ash" [];
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