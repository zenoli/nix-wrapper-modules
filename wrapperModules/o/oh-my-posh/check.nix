{
  pkgs,
  self,
  tlib,
  writeText,
  ...
}:

let
  inherit (tlib)
    fileContains
    isFile
    test
    ;
  wm = self.wrappers.oh-my-posh;
in
test { wrapper = "oh-my-posh"; } {

  "wrapper should output correct version" =
    let
      wrapper = wm.wrap {
        inherit pkgs;
      };
    in
    ''
      "${wrapper}/bin/oh-my-posh" --version |
      grep -q "${wrapper.version}"
    '';

  "config.json is properly configured" =
    let
      wrapper = wm.wrap {
        inherit pkgs;
      };
      configFile = "${wrapper}/config.json";
    in
    [
      (isFile configFile)
      (fileContains "${wrapper}/bin/oh-my-posh" "--config.*${configFile}")
    ];

  "default settings order is respected" =
    let
      # See here for theme values: https://github.com/JanDeDobbeleer/oh-my-posh/blob/main/themes/jandedobbeleer.omp.json
      wrapper = wm.wrap {
        inherit pkgs;
        theme = "jandedobbeleer";
        settings.console_title_template = "nix-setting";
        configFile = writeText "config.yaml" ''
          console_title_template: file-setting
          final_space: false
        '';
      };
      configFile = "${wrapper}/config.json";
    in
    [
      (isFile configFile)
      # Set by 'theme'
      (fileContains configFile ''"version": 4'')
      # Set by 'configFile'
      (fileContains configFile ''"final_space": false'')
      # Set by 'settings'
      (fileContains configFile ''"console_title_template": "nix-setting"'')
    ];

  "custom settings order is respected" =
    let
      # See here for theme values: https://github.com/JanDeDobbeleer/oh-my-posh/blob/main/themes/jandedobbeleer.omp.json
      wrapper = wm.wrap {
        inherit pkgs;
        order = [
          "settings"
          "file"
          "theme"
        ];
        theme = "jandedobbeleer";
        configFile = writeText "config.yaml" ''
          console_title_template: will-be-overridden-by-theme
          custom_config_file_setting: will-be-included
        '';
        settings.console_title_template = "will-be-overridden-by-theme";
        settings.custom_nix_setting_1 = "will-be-overridden-by-configFile";
        settings.custom_nix_setting_2 = "will-be-included";
      };
      configFile = "${wrapper}/config.json";
    in
    [
      (isFile configFile)
      # Set by 'theme'
      (fileContains configFile ''"console_title_template": "{{ .Shell }} in {{ .Folder }}"'')
      # Set by 'configFile'
      (fileContains configFile ''"custom_config_file_setting": "will-be-included"'')
      # Set by 'settings'
      (fileContains configFile ''"custom_nix_setting_2": "will-be-included"'')
    ];

  "theme list is merged in order" =
    let
      wrapper = wm.wrap {
        inherit pkgs;
        theme = [
          "1_shell"
          "jandedobbeleer"
        ];
      };
      configFile = "${wrapper}/config.json";
    in
    [
      (isFile configFile)
      # value exclusive to 1_shell
      (fileContains configFile ''"transient_prompt"'')
      # 1_shell sets it to "{{ .Folder }}", jandedobbeleer overrides it to "{{ .Shell }} in {{ .Folder }}"
      (fileContains configFile ''"console_title_template": "{{ .Shell }} in {{ .Folder }}"'')
    ];

  "config file formats" =
    let
      key = "dummy_key";
      value = "dummy_value";
    in
    {
      "json configFile is loaded" =
        let
          wrapper = wm.wrap {
            inherit pkgs;
            configFile = writeText "config.json" ''{"${key}": "${value}"}'';
          };
          generatedConfig = "${wrapper}/config.json";
        in
        [
          (isFile generatedConfig)
          (fileContains generatedConfig key)
          (fileContains generatedConfig value)
        ];

      "yaml configFile is loaded" =
        let
          wrapper = wm.wrap {
            inherit pkgs;
            configFile = writeText "config.yaml" "${key}: ${value}";
          };
          generatedConfig = "${wrapper}/config.json";
        in
        [
          (isFile generatedConfig)
          (fileContains generatedConfig key)
          (fileContains generatedConfig value)
        ];

      "toml configFile is loaded" =
        let
          wrapper = wm.wrap {
            inherit pkgs;
            configFile = writeText "config.toml" ''${key} = "${value}"'';
          };
          generatedConfig = "${wrapper}/config.json";
        in
        [
          (isFile generatedConfig)
          (fileContains generatedConfig key)
          (fileContains generatedConfig value)
        ];
    };
}
