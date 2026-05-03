{
  wlib,
  lib,
  config,
  pkgs,
  ...
}:
let
  jsonFmt = pkgs.formats.json { };

  themeKey = "theme";
  fileKey = "file";
  settingsKey = "settings";

  defaultOrder = [
    themeKey
    fileKey
    settingsKey
  ];
in
{
  imports = [ wlib.modules.default ];

  options = {
    settings = lib.mkOption {
      inherit (jsonFmt) type;
      default = { };
      description = ''
        Pure nix configuration oh-my-posh.
        See <https://ohmyposh.dev/docs/configuration/general>
      '';
      example = {
        console_title_template = "{{ .Folder }}";
      };
    };
    configFile = lib.mkOption {
      type = with lib.types; nullOr (either path package);
      default = null;
      description = ''
        Path to an oh-my-posh configuration file.
        Supported formats are JSON (`.json`), TOML (`.toml`), and YAML (`.yaml`, `.yml`).
        See <https://ohmyposh.dev/docs/configuration/general>
      '';
      example = lib.literalExpression "./config.yaml";
    };
    theme = lib.mkOption {
      type = with lib.types; either str (listOf str);
      default = [ ];
      apply = lib.toList;
      description = ''
        One or more built-in oh-my-posh themes to use as configuration.
        When a list is provided, themes later in the list take precedence.
        See <https://ohmyposh.dev/docs/themes/>.
      '';
      example = [
        "1_shell"
        "agnoster"
      ];
    };
    order = lib.mkOption {
      type = with lib.types; wlib.types.fixedList 3 (enum defaultOrder);
      default = defaultOrder;
      description = ''
        The order in which the specified settings are merged.
        Values later in the list will take precedence.

        The allowed keys are:

        - "${themeKey}": Settings from the the specified theme (`config.theme`)
        - "${fileKey}": Settings from the specified config file (`config.configFile`)
        - "${settingsKey}": Settings specified as a nix attrs (`config.settings`)
      '';
    };
  };
  config = {
    package = lib.mkDefault pkgs.oh-my-posh;
    constructFiles."config.json" = {
      content = builtins.toJSON config.settings;
      relPath = "config.json";
      builder =
        let
          jsonNormalizationScript = lib.optionalString (config.configFile != null) (
            let
              path = toString config.configFile;
              isToml = lib.hasSuffix ".toml" path;
              isYaml = lib.hasSuffix ".yaml" path || lib.hasSuffix ".yml" path;
              isJson = lib.hasSuffix ".json" path;
            in
            if isJson then
              "_omp_config_json=${config.configFile}"
            else if isToml || isYaml then
              ''
                _omp_config_json=$(mktemp --suffix=.json)
                ${pkgs.yq-go}/bin/yq -o=json '.' ${lib.escapeShellArg path} > "$_omp_config_json"
              ''
            else
              throw "oh-my-posh: configFile must have a .json, .toml, .yaml, or .yml extension, got: ${path}"
          );

          orderedSettings =
            let
              jsonSettingsMap = {
                ${themeKey} = map (
                  p: lib.escapeShellArg "${config.package}/share/oh-my-posh/themes/${p}.omp.json"
                ) config.theme;
                ${fileKey} = lib.optional (config.configFile != null) ''"$_omp_config_json"'';
                ${settingsKey} = lib.optional (config.settings != { }) ''"$1"'';
              };
            in
            lib.concatMap (key: jsonSettingsMap.${key}) config.order;
        in
        # Merges all specified JSON theme files, config file, and nix settings JSON using jq
        ''
          mkdir -p "$(dirname "$2")"
          ${jsonNormalizationScript}
          ${pkgs.jq}/bin/jq -s 'reduce .[] as $item ({}; . * $item)' \
          ${lib.concatStringsSep " " orderedSettings} > "$2"
        '';
    };
    flags."--config" = config.constructFiles."config.json".path;
    meta = {
      maintainers = with wlib.maintainers; [
        zenoli
      ];
      description = ''
        Wrapper Module for the [Oh-My-Posh Prompt](https://ohmyposh.dev/).

        Oh-My-Posh is configured via a [JSON/YAML/TOML file](https://ohmyposh.dev/docs/configuration/general).
        This module provides three ways to do this:

        - By specifying one (or many) of the built-in preset configurations.
        - By pointing to a JSON, TOML, or YAML configuration file.
        - By using pure Nix to write an attribute set that gets converted to JSON.

        These options are not mutually exclusive. If multiple are defined,
        they will be merged according to the order specified in `config.order`.
      '';
    };
  };
}
