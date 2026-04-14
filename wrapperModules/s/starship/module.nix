{
  wlib,
  lib,
  config,
  pkgs,
  ...
}:
let
  presets = [
    "bracketed-segments"
    "catppuccin-powerline"
    "gruvbox-rainbow"
    "jetpack"
    "nerd-font-symbols"
    "no-empty-icons"
    "no-nerd-font"
    "no-runtime-versions"
    "pastel-powerline"
    "plain-text-symbols"
    "pure-preset"
    "tokyo-night"
  ];
  tomlFmt = pkgs.formats.toml { };
  tomlSettings = tomlFmt.generate "starship.toml" config.settings;
  # presetToml = pkgs.runCommand "starship-preset-${config.preset}.toml" { } ''
  #   ${lib.getExe pkgs.starship} preset ${config.preset} > $out
  # '';
  presetToml = config.package.src + "/docs/public/presets/toml/${config.preset}.toml";
  configFile = if config.preset != null then presetToml else tomlSettings;
in
{
  imports = [ wlib.modules.default ];

  options = {
    preset = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum presets);
      default = null;
      description = ''
        A built-in starship preset to use as configuration.
        See <https://starship.rs/presets/>.
      '';
    };
    settings = lib.mkOption {
      inherit (tomlFmt) type;
      default = { };
      description = ''
        Configuration of starship.toml.
        See <https://direnv.net/man/direnv.toml.1.html>
      '';
    };
  };
  config = {
    package = lib.mkDefault pkgs.starship;
    preset = "tokyo-night";
    constructFiles."starship.toml" = {
      content = builtins.readFile configFile;
      relPath = "starship.toml";
    };
    settings = lib.mkIf (config.preset == null) {
      add_newline = true;
      character.success_symbol = "[➜](bold green)";
    };
    env.STARSHIP_CONFIG = config.constructFiles."starship.toml".path;
    meta.maintainers = [ wlib.maintainers.zenoli ];
  };
}
