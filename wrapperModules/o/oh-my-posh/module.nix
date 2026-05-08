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
    #   "file"
    #   "settings"
    # ];
    # configFile = ./foo.omp.json;
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
              baseName = lib.removeSuffix ".toml" (
                lib.removeSuffix ".yaml" (lib.removeSuffix ".yml" (builtins.baseNameOf path))
              );
            in
            if isJson then
              "_omp_config_json=${config.configFile}"
            else if isToml || isYaml then
              ''
                _omp_config_json="$_omp_chain_dir/${baseName}.json"
                ${pkgs.yq-go}/bin/yq -o=json '.' ${lib.escapeShellArg path} > "$_omp_config_json"
              ''
            else
              throw "oh-my-posh: configFile must have a .json, .toml, .yaml, or .yml extension, got: ${path}"
          );

          settingsNormalizationScript = lib.optionalString (config.settings != { }) ''
            _omp_settings_json="$_omp_chain_dir/settings.json"
            cp "$1" "$_omp_settings_json"
          '';

          orderedSettings =
            let
              jsonSettingsMap = {
                ${themeKey} = map (
                  p: lib.escapeShellArg "${config.package}/share/oh-my-posh/themes/${p}.omp.json"
                ) config.theme;
                ${fileKey} = lib.optional (config.configFile != null) ''"$_omp_config_json"'';
                ${settingsKey} = lib.optional (config.settings != { }) ''"$_omp_settings_json"'';
              };
            in
            lib.concatMap (key: jsonSettingsMap.${key}) config.order;
          jq = "${pkgs.jq}/bin/jq";
          chainScript =
            if orderedSettings == [ ] then
              ''
                echo '{}' > "$2"
                rmdir "$_omp_chain_dir" 2>/dev/null || true
              ''
            else
              let
                n = builtins.length orderedSettings;
              in
              ''
                _omp_configs=(${lib.concatStringsSep " " orderedSettings})

                # Scan backwards to find the rightmost config with "extends" already set.
                # Configs before it are unreachable through our chain and can be skipped.
                _omp_start=0
                for (( _omp_i=${toString (n - 1)}; _omp_i>0; _omp_i-- )); do
                  if [ "$(${jq} 'has("extends")' "''${_omp_configs[$_omp_i]}")" = "true" ]; then
                    _omp_start=$_omp_i
                    break
                  fi
                done

                # Build the extends chain from _omp_start to the last config
                _omp_prev="''${_omp_configs[$_omp_start]}"
                for (( _omp_i=_omp_start+1; _omp_i<${toString n}; _omp_i++ )); do
                  _omp_cfg="''${_omp_configs[$_omp_i]}"
                  if [ "$_omp_i" -eq ${toString (n - 1)} ]; then
                    _omp_out="$2"
                  else
                    _omp_name=$(basename "$_omp_cfg")
                    if [[ "$_omp_name" =~ ^[a-z0-9]{32}-(.+)$ ]]; then _omp_name="''${BASH_REMATCH[1]}"; fi
                    _omp_out="$_omp_chain_dir/$_omp_name"
                  fi
                  _omp_tmp=$(mktemp "$_omp_chain_dir/.XXXXXXXXXX")
                  ${jq} --arg ext "$_omp_prev" '. + {extends: $ext}' "$_omp_cfg" > "$_omp_tmp"
                  mv "$_omp_tmp" "$_omp_out"
                  _omp_prev="$_omp_out"
                done

                # If the loop didn't run (last config already had "extends"), copy it directly
                if [ "$_omp_prev" != "$2" ]; then cp "$_omp_prev" "$2"; fi

                # Remove the chain dir if nothing was written to it
                rmdir "$_omp_chain_dir" 2>/dev/null || true
              '';
        in
        # Chains all specified JSON configs via oh-my-posh's native extends feature
        ''
          mkdir -p "$(dirname "$2")"
          _omp_chain_dir="$(dirname "$2")/config-chain"
          mkdir -p "$_omp_chain_dir"
          ${jsonNormalizationScript}
          ${settingsNormalizationScript}
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
