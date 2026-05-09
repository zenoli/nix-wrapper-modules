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

  config =
    let
      nixSettingsFile = pkgs.writeText "settings.json" (builtins.toJSON config.settings);

      stripStoreHash =
        name:
        let
          m = builtins.match "[a-z0-9]{32}-(.*)" name;
        in
        if m != null then builtins.head m else name;

      normalizedConfigFile =
        if config.configFile == null then
          null
        else
          let
            path = toString config.configFile;
            baseName = stripStoreHash (builtins.baseNameOf path);
            isJson = lib.hasSuffix ".json" baseName;
            isToml = lib.hasSuffix ".toml" baseName;
            isYaml = lib.hasSuffix ".yaml" baseName || lib.hasSuffix ".yml" baseName;
            configFileName =
              lib.pipe baseName [
                (lib.removeSuffix ".toml")
                (lib.removeSuffix ".yaml")
                (lib.removeSuffix ".yml")
              ] + ".json";
          in
          if isJson then
            config.configFile
          else if isToml || isYaml then
            pkgs.runCommand configFileName { } ''
              ${pkgs.yq-go}/bin/yq -o=json '.' ${lib.escapeShellArg "${config.configFile}"} > $out
            ''
          else
            throw "oh-my-posh: configFile must have a .json, .toml, .yaml, or .yml extension, got: ${path}";

      # List of { srcPath, name } in precedence order (lowest to highest)
      orderedConfigs = lib.concatMap (key: {
        ${themeKey} = map (p: {
          srcPath = "${config.package}/share/oh-my-posh/themes/${p}.omp.json";
          name = "${p}.omp.json";
        }) config.theme;
        ${fileKey} = lib.optional (config.configFile != null) {
          srcPath = "${normalizedConfigFile}";
          name = stripStoreHash (builtins.baseNameOf (toString normalizedConfigFile));
        };
        ${settingsKey} = lib.optional (config.settings != { }) {
          srcPath = "${nixSettingsFile}";
          name = "settings.json";
        };
      }.${key}) config.order;

      n = builtins.length orderedConfigs;
      jq = "${pkgs.jq}/bin/jq";

      # Build a constructFile entry for index i, extending prevPath
      mkEntry = i: prevPath:
        let
          cfg = builtins.elemAt orderedConfigs i;
          relPath = if i == n - 1 then "config.json" else "config-chain/${cfg.name}";
        in
        {
          inherit relPath;
          builder = ''
            mkdir -p "$(dirname "$2")"
            ${jq} --arg ext ${lib.escapeShellArg prevPath} '. + {extends: $ext}' ${lib.escapeShellArg cfg.srcPath} > "$2"
          '';
        };

      # Recursively build constructFile entries for indices i..n-1
      buildChain = i: prevPath:
        let
          entry = mkEntry i prevPath;
          thisPath = "${builtins.placeholder "out"}/${entry.relPath}";
        in
        { ${entry.relPath} = entry; }
        // (if i < n - 1 then buildChain (i + 1) thisPath else { });

      chainFiles =
        if n == 0 then
          { "config.json" = { relPath = "config.json"; content = "{}"; }; }
        else if n == 1 then
          let cfg = builtins.head orderedConfigs;
          in {
            "config.json" = {
              relPath = "config.json";
              builder = ''
                mkdir -p "$(dirname "$2")"
                cp ${lib.escapeShellArg cfg.srcPath} "$2"
              '';
            };
          }
        else
          buildChain 1 (builtins.head orderedConfigs).srcPath;
    in
    {
      package = lib.mkDefault pkgs.oh-my-posh;
      constructFiles = chainFiles;
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
