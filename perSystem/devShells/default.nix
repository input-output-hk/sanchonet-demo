flake: {
  perSystem = {
    config,
    pkgs,
    system,
    ...
  }: {
    cardano-parts.shell.global.defaultShell = "test";
    cardano-parts.shell.global.enableVars = false;
    cardano-parts.shell.test.enableVars = true;
    cardano-parts.shell.test.defaultVars = {
      CARDANO_NODE_SOCKET_PATH = "./node.socket";
      USE_ENCRYPTION = false;
      UNSTABLE = true;
    };
    cardano-parts.shell.global.defaultHooks = ''
      alias cardano-node=cardano-node-ng
      alias cardano-cli=cardano-cli-ng
    '';

    cardano-parts.shell.test.extraPkgs = [config.packages.run-cardano-node pkgs.asciinema pkgs.fx];
    cardano-parts.pkgs.cardano-cli = flake.inputs.cardano-cli-ng.legacyPackages.${system}.cardano-cli;
    cardano-parts.pkgs.cardano-node = flake.inputs.cardano-node-ng.legacyPackages.${system}.cardano-node;
  };
}
