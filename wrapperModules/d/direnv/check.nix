{
  pkgs,
  self,
}:

let
  lib = pkgs.lib;
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
    name: script:
    pkgs.runCommand name { } ''
      ${testUtils}

      ${script}

      touch $out
    '';

  runTests =
    name: tests:
    runTest "test-group-${name}" ''
      # "${lib.concatStringsSep " " tests}"
    '';

  runCheck =
    name:
    (import ./checks/${name}) {
      inherit
        pkgs
        self
        runTest
        runTests
        ;
    };
  checks = lib.pipe ./checks [
    builtins.readDir
    (lib.filterAttrs (name: type: type == "regular"))
    (lib.mapAttrsToList (name: _: (runCheck name)))
  ];
in
runTests "direnv-all" checks
