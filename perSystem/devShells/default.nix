{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    cardano-parts.shell = {
      global = {
        defaultShell = "test";
        enableVars = false;
        defaultHooks = ''
          # CURRENTLY BROKEN!
          alias cardano-node=cardano-node-ng
          alias cardano-cli=cardano-cli-ng
        '';
      };
      test = {
        enableVars = true;
        defaultVars = {
          CARDANO_NODE_SOCKET_PATH = "./node.socket";
          USE_ENCRYPTION = false;
          UNSTABLE = true;
        };
        extraPkgs = [config.packages.run-cardano-node pkgs.asciinema pkgs.fx config.packages.govQuery];
      };
    };
    #cardano-parts.pkgs.cardano-cli = flake.inputs.cardano-cli-ng.legacyPackages.${system}.cardano-cli;
    #cardano-parts.pkgs.cardano-node = flake.inputs.cardano-node-ng.legacyPackages.${system}.cardano-node;
  };
}
