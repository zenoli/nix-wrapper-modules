{
  pkgs,
  self,
  runTest,
}:

let
  wrapper = self.wrappers.direnv.wrap {
    inherit pkgs;
    nix-direnv.enable = true;
  };
  # TODO: This seems dumb. Is there no better way to do this?
  cfg = (wrapper.eval { }).config;
  dotdir = "${wrapper}/${cfg.configDirname}";

  test = runTest "direnv-test" { } ''
    "${wrapper}/bin/direnv" --version | grep -q "${wrapper.version}"
    is_directory "${dotdir}"
    is_file "${dotdir}/lib/nix-direnv.sh"
  '';
in
test
