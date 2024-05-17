{
  description = "Cardano New Parts Project";

  inputs = rec {
    nixpkgs.follows = "cardano-parts/nixpkgs";
    nixpkgs-unstable.follows = "cardano-parts/nixpkgs-unstable";
    flake-parts.follows = "cardano-parts/flake-parts";
    cardano-parts.url = "github:input-output-hk/cardano-parts/next-2024-05-14";
    credential-manager.url = "github:intersectmbo/credential-manager";
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
          inputs.cardano-parts.flakeModules.lib
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
