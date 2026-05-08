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
    # theme = [
    #   "1_shell"
    #   # "agnoster"
    #   "aliens"
    # ];
    # order = [
    #   "theme"
    #   "settings"
    #   "file"
    # ];
    # configFile = ./file-settings.json;
    # settings = {
    #   streaming = 40;
    #   # extends = "foo";
    #   blocks = [
    #     {
    #       alignment = "left";
    #       type = "prompt";
    #       segments = [
    #         {
    #           type = "root";
    #           template = "oli";
    #         }
    #       ];
    #     }
    #   ];
    # };
    constructFiles."config.json" = {
      relPath = "config.json";
      builder =
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
              in
              if isJson then
                config.configFile
              else if isToml || isYaml then
                let
                  configFileName = lib.pipe baseName [
                    (lib.removeSuffix ".toml")
                    (lib.removeSuffix ".yaml")
                    (lib.removeSuffix ".yml")
                  ];
                in
                pkgs.runCommand "${configFileName}.json" { } ''
                  ${pkgs.yq-go}/bin/yq -o=json '.' ${lib.escapeShellArg "${config.configFile}"} > $out
                ''
              else
                throw "oh-my-posh: configFile must have a .json, .toml, .yaml, or .yml extension, got: ${path}";

          orderedSettings =
            let
              jsonSettingsMap = {
                ${themeKey} = map (
                  p: lib.escapeShellArg "${config.package}/share/oh-my-posh/themes/${p}.omp.json"
                ) config.theme;
                ${fileKey} = lib.optional (config.configFile != null) "${normalizedConfigFile}";
                ${settingsKey} = lib.optional (config.settings != { }) "${nixSettingsFile}";
              };
            in
            lib.concatMap (key: jsonSettingsMap.${key}) config.order;

          jq = "${pkgs.jq}/bin/jq";
          chainScript =
            if orderedSettings == [ ] then
              ''
                echo '{}' > "$2"
                rmdir "$config_chain_dir" 2>/dev/null || true
              ''
            else
              let
                n = builtins.trace (lib.concatStringsSep "\n" orderedSettings) (builtins.length orderedSettings);
              in
              ''
                ordered_settings=(${lib.concatStringsSep " " orderedSettings})

                # Scan backwards to find the rightmost config with "extends" already set.
                # Configs before it are unreachable through our chain and can be skipped.
                start=0
                for (( i=${toString (n - 1)}; i>0; i-- )); do
                  if [ "$(${jq} 'has("extends")' "''${ordered_settings[$i]}")" = "true" ]; then
                    start=$i
                    break
                  fi
                done

                get_name() {
                  name=$(basename "$1")
                  if [[ "$name" =~ ^[a-z0-9]{32}-(.+)$ ]]; then name="''${BASH_REMATCH[1]}"; fi
                  echo $name
                }

                # Build the extends chain from start to the last config
                prev="''${ordered_settings[$start]}"
                for (( i=start+1; i<${toString n}; i++ )); do
                  curr="''${ordered_settings[$i]}"
                  if [ "$i" -eq ${toString (n - 1)} ]; then
                    dst="$2"
                  else
                    dst="$config_chain_dir/$(get_name $curr)"
                  fi
                  tmp=$(mktemp)
                  ${jq} --arg ext "$prev" '. + {extends: $ext}' "$curr" > "$tmp" && mv $tmp $dst
                  prev="$dst"
                done

                # If the loop didn't run (last config already had "extends"), copy it directly
                if [ "$start" -eq ${toString (n - 1)} ]; then cp "$prev" "$2"; fi

                # Remove the chain dir if nothing was written to it
                rmdir "$config_chain_dir" 2>/dev/null || true
              '';
        in
        # Chains all specified JSON configs via oh-my-posh's native extends feature
        ''
          mkdir -p "$(dirname "$2")"
          config_chain_dir="$(dirname "$2")/config-chain"
          mkdir -p "$config_chain_dir"
          ${chainScript}
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
