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
    isDirectory
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
        theme = "jandedobbeleer";
      };
      configFile = "${wrapper}/config.json";
    in
    [
      (isFile configFile)
      (fileContains "${wrapper}/bin/oh-my-posh" "--config.*${configFile}")
    ];

  "config chains" =
    let
      baseWrapper = wm.wrap {
        inherit pkgs;
        theme = [
          "aliens"
          "agnoster"
        ];
        settings.foo = "foo";
        configFile = writeText "file-settings.yaml" "bar: bar";
      };
    in
    {
      "theme > file > settings (default order)" =
        let
          wrapper = baseWrapper;
          configChainDir = "${wrapper}/config-chain";

          nixSettingsFile = "${wrapper}/config.json";
          fileSettingsFile = "${configChainDir}/file-settings.json";
          agnosterFile = "${configChainDir}/agnoster.omp.json";
        in
        [
          (fileContains nixSettingsFile ''"extends": "${fileSettingsFile}"'')
          (fileContains fileSettingsFile ''"extends": "${agnosterFile}"'')
          (fileContains agnosterFile ''"extends": "/nix/store/.*aliens.omp.json"'')
        ];

      "file > theme > settings" =
        let
          wrapper = baseWrapper.wrap {
            order = [
              "file"
              "theme"
              "settings"
            ];
          };
          configChainDir = "${wrapper}/config-chain";

          nixSettingsFile = "${wrapper}/config.json";
          fileSettingsFile = "${configChainDir}/file-settings.json";
          agnosterFile = "${configChainDir}/agnoster.omp.json";
          aliensFile = "${configChainDir}/aliens.omp.json";
        in
        [
          (fileContains nixSettingsFile ''"extends": "${agnosterFile}"'')
          (fileContains agnosterFile ''"extends": "${aliensFile}"'')
          (fileContains aliensFile ''"extends": "/nix/store/.*file-settings.json"'')
        ];

      "file > settings > theme" =
        let
          wrapper = baseWrapper.wrap {
            order = [
              "file"
              "settings"
              "theme"
            ];
          };
          configChainDir = "${wrapper}/config-chain";

          agnosterFile = "${wrapper}/config.json";
          aliensFile = "${configChainDir}/aliens.omp.json";
          nixSettingsFile = "${configChainDir}/settings.json";
          fileSettingsFile = "${configChainDir}/file-settings.json";
        in
        [
          (fileContains agnosterFile ''"extends": "${aliensFile}"'')
          (fileContains aliensFile ''"extends": "${nixSettingsFile}"'')
          (fileContains nixSettingsFile ''"extends": "/nix/store/.*file-settings.json"'')
        ];

      "settings > theme > file" =
        let
          wrapper = baseWrapper.wrap {
            order = [
              "settings"
              "theme"
              "file"
            ];
          };
          configChainDir = "${wrapper}/config-chain";

          fileSettingsFile = "${wrapper}/config.json";
          agnosterFile = "${configChainDir}/agnoster.omp.json";
          aliensFile = "${configChainDir}/aliens.omp.json";
        in
        [
          (fileContains fileSettingsFile ''"extends": "${agnosterFile}"'')
          (fileContains agnosterFile ''"extends": "${aliensFile}"'')
          (fileContains aliensFile ''"extends": "/nix/store/.*settings.json"'')
        ];

      "theme > settings > file" =
        let
          wrapper = baseWrapper.wrap {
            order = [
              "theme"
              "settings"
              "file"
            ];
          };
          configChainDir = "${wrapper}/config-chain";

          fileSettingsFile = "${wrapper}/config.json";
          nixSettingsFile = "${configChainDir}/settings.json";
          agnosterFile = "${configChainDir}/agnoster.omp.json";
        in
        [
          (fileContains fileSettingsFile ''"extends": "${nixSettingsFile}"'')
          (fileContains nixSettingsFile ''"extends": "${agnosterFile}"'')
          (fileContains agnosterFile ''"extends": "/nix/store/.*aliens.omp.json"'')
        ];

      "settings > file > theme" =
        let
          wrapper = baseWrapper.wrap {
            order = [
              "settings"
              "file"
              "theme"
            ];
          };
          configChainDir = "${wrapper}/config-chain";

          agnosterFile = "${wrapper}/config.json";
          aliensFile = "${configChainDir}/aliens.omp.json";
          fileSettingsFile = "${configChainDir}/file-settings.json";
        in
        [
          (fileContains agnosterFile ''"extends": "${aliensFile}"'')
          (fileContains aliensFile ''"extends": "${fileSettingsFile}"'')
          (fileContains aliensFile ''"extends": "/nix/store/.*settings.json"'')
        ];
    };

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
