{
  pkgs,
  self,
}:

let
  lib = pkgs.lib;
  # wrapperWithoutNixDirenv = self.wrappers.direnv.wrap {
  #   inherit pkgs;
  #   nix-direnv.enable = true;
  # };
  # wrapperWithNixDirenv = self.wrappers.direnv.wrap {
  #   inherit pkgs;
  #   nix-direnv.enable = true;
  # };
  # TODO: This seems dumb. Is there no better way to do this?
  # cfg = (wrapperWithNixDirenv.eval { }).config;
  # dotdir = "${wrapperWithNixDirenv}/${cfg.configDirname}";

  testUtils = ''
    is_directory() {
      local path="$1"
      if [ -d "$path" ]; then
        return 0
      else
        echo "No directory $path" >&2
        return 1
      fi
    }

    is_file() {
      local path="$1"
      if [ -f "$path" ]; then
        return 0
      else
        echo "No such file $path" >&2
        return 1
      fi
    }
  '';

  runTest =
    name: attrs: script:
    pkgs.runCommand name attrs ''
      ${testUtils}

      ${script}

      touch $out
    '';

  runCheck = name: (import ./checks/${name}) { inherit pkgs self runTest; };
  checks = lib.pipe ./checks [
    builtins.readDir
    (lib.filterAttrs (name: type: type == "regular"))
    (lib.mapAttrsToList (name: _: (runCheck name)))
  ];
in
# TODO: We need to return a derivation.
# Create a dummie derivation that references `checks` to
# ensure they are evaluated.
runTest "all-tests" { } ''
  # "${lib.concatStringsSep " " checks}"
''
