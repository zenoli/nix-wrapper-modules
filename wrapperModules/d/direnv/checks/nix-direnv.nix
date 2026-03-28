{
  pkgs,
  self,
  runTest,
  runTests,
}:

let
  getDotdir =
    wrapper:
    let
      cfg = (wrapper.eval { }).config;
      dotdir = "${wrapper}/${cfg.configDirname}";
    in
    dotdir;
in
runTests "nix-direnv" [
  (runTest "if nix-direnv is enabled then lib/nix-direnv.sh exists" (
    let
      wrapper = self.wrappers.direnv.wrap {
        inherit pkgs;
        nix-direnv.enable = true;
      };
    in
    ''
      "${wrapper}/bin/direnv" --version | grep -q "${wrapper.version}"
      is_directory "${getDotdir wrapper}"
      is_file "${getDotdir wrapper}/lib/nix-direnv.sh"
    ''
  ))
  (runTest "if nix-direnv is diabled then lib/nix-direnv.sh does not exist" (
    let
      wrapper = self.wrappers.direnv.wrap {
        inherit pkgs;
        nix-direnv.enable = false;
      };
    in
    ''
      "${wrapper}/bin/direnv" --version | grep -q "${wrapper.version}"
      is_directory "${getDotdir wrapper}"
      ! is_file "${getDotdir wrapper}/lib/nix-direnv.sh"
    ''
  ))
]
