flake: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    packages = {
      govQuery = pkgs.python311Packages.buildPythonApplication {
        pname = "gov-query";
        version = "0.0.0";
        src = ./gov-query;
        propagatedBuildInputs = [pkgs.python311Packages.docopt];
      };
      inherit (flake.inputs.credential-manager.packages.${system}) orchestrator-cli;
    };
  };
}
