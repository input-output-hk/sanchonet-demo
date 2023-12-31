{
  description = "Cardano New Parts Project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cardano-parts.url = "github:input-output-hk/cardano-parts/sl/8.6.0-scripts";
    cardano-node-ng.url = "github:input-output-hk/cardano-node/td/8.6";
    cardano-cli-ng.url = "github:input-output-hk/cardano-cli/cardano-cli-8.13.0.0";
  };

  outputs = inputs: let
    inherit (inputs.cardano-parts.lib) recursiveImports;
  in
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports =
        recursiveImports [
          ./flake
          ./perSystem
        ]
        ++ [
          inputs.cardano-parts.flakeModules.pkgs
          inputs.cardano-parts.flakeModules.shell
          inputs.cardano-parts.flakeModules.entrypoints
          inputs.cardano-parts.flakeModules.jobs
        ];
      systems = ["x86_64-linux" "aarch64-darwin"];
      debug = true;
    };

  nixConfig = {
    extra-substituters = ["https://cache.iog.io"];
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
    allow-import-from-derivation = "true";
  };
}
