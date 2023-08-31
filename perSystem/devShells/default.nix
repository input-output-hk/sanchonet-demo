{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    cardano-parts.shell.global.defaultShell = "test";
    cardano-parts.shell.global.enableVars = false;
    cardano-parts.shell.test.extraPkgs = [config.packages.run-cardano-node pkgs.asciinema];
    #cardano-parts.pkgs.cardano-cli = flake.inputs.cardano-cli.legacyPackages.${system}.cardano-cli;
  };
}
