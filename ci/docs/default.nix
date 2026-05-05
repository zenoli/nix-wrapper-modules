{
  config,
  lib,
  wlib,
  pkgs,
  ...
}:
let
  inherit (import ./per-mod { inherit lib wlib; }) wrapperModuleMD normWrapperDocs;
  helperModules = removeAttrs wlib.modules [ "default" ];
  getImportedHelperModules =
    module:
    let
      evaluated = wlib.evalModule [
        module
        {
          _module.check = false;
          inherit pkgs;
        }
      ];
      normedFiles = map (v: toString v.file) (normWrapperDocs {
        options = evaluated.options;
        includeCore = false;
      });
    in
    lib.filterAttrs (n: path: builtins.elem (toString path) normedFiles) helperModules;
  buildModuleDocs =
    {
      prefix ? "",
      title ? null,
      package ? null,
      includeCore ? true,
      excludeFiles ? [ ],
      onlyFiles ? null,
      descriptionStartsOpen ? null,
      descriptionIncluded ? null,
      moduleStartsOpen ? null,
      warningsAreErrors ? true,
    }:
    name: module:
    (if title != null then "# ${title}\n\n" else "# `${prefix}${name}`\n\n")
    + wrapperModuleMD (
      wlib.evalModule [
        module
        {
          _module.check = false;
          inherit pkgs;
          ${if package != null then "package" else null} = package;
        }
      ]
      // {
        inherit includeCore warningsAreErrors excludeFiles;
        ${if onlyFiles != null then "onlyFiles" else null} = onlyFiles;
        ${if descriptionStartsOpen != null then "descriptionStartsOpen" else null} = descriptionStartsOpen;
        ${if descriptionIncluded != null then "descriptionIncluded" else null} = descriptionIncluded;
        ${if moduleStartsOpen != null then "moduleStartsOpen" else null} = moduleStartsOpen;
      }
    );

in
{
  imports = [
    wlib.wrapperModules.mdbook
    ./redirects.nix
  ];
  config.mainBook = "nix-wrapper-modules";
  config.outputs = [
    "out"
    "generated"
  ];
  options.warningsAreErrors = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether warnings in the docgen should be treated as errors (i.e. missing descriptions)";
  };
  config.drv.unsafeDiscardReferences.generated = true;
  config.drv.preBuild = ''
    mkdir -p "$generated/wrapper_docs"
    jq -r '.wrapper_docs | to_entries[] | @base64' "$NIX_ATTRS_JSON_FILE" | while read -r entry; do
      # decode base64 to get JSON safely
      decoded=$(echo "$entry" | base64 --decode)
      echo "$(echo "$decoded" | jq -r '.value')" > "$generated/wrapper_docs/$(echo "$decoded" | jq -r '.key').md"
    done
    mkdir -p "$generated/module_docs"
    jq -r '.module_docs | to_entries[] | @base64' "$NIX_ATTRS_JSON_FILE" | while read -r entry; do
      decoded="$(echo "$entry" | base64 --decode)"
      echo "$(echo "$decoded" | jq -r '.value')" > "$generated/module_docs/$(echo "$decoded" | jq -r '.key').md"
    done
    jq -r '.wrapper_helper_docs | to_entries[] | .key as $wrapper | .value | to_entries[] | {wrapper: $wrapper, helper: .key, content: .value} | @base64' "$NIX_ATTRS_JSON_FILE" | while read -r entry; do
      decoded="$(echo "$entry" | base64 --decode)"
      wrapper="$(echo "$decoded" | jq -r '.wrapper')"
      helper="$(echo "$decoded" | jq -r '.helper')"
      mkdir -p "$generated/wrapper_helper_docs/$wrapper"
      echo "$(echo "$decoded" | jq -r '.content')" > "$generated/wrapper_helper_docs/$wrapper/$helper.md"
    done
  '';
  config.drv.module_docs = builtins.mapAttrs (buildModuleDocs {
    prefix = "wlib.modules.";
    package = pkgs.hello;
    includeCore = false;
    inherit (config) warningsAreErrors;
    moduleStartsOpen = _: _: true;
    descriptionStartsOpen =
      _: _: _:
      true;
    descriptionIncluded =
      _: _: _:
      true;
  }) wlib.modules;
  config.drv.wrapper_docs = builtins.mapAttrs (buildModuleDocs {
    prefix = "wlib.wrapperModules.";
    includeCore = false;
    excludeFiles = builtins.attrValues wlib.modules;
    inherit (config) warningsAreErrors;
  }) wlib.wrapperModules;
  config.drv.wrapper_helper_docs =
    let
      helperModuleFiles = lib.mapAttrs (
        _: helperModule:
        map (v: toString v.file) (normWrapperDocs {
          options = (wlib.evalModule [
            helperModule
            {
              _module.check = false;
              inherit pkgs;
              package = pkgs.hello;
            }
          ]).options;
          includeCore = false;
        })
      ) helperModules;
    in
    lib.mapAttrs (
      wrapperName: wrapperModule:
      let
        importedHelpers = getImportedHelperModules wrapperModule;
        wrapperEval = wlib.evalModule [
          wrapperModule
          {
            _module.check = false;
            inherit pkgs;
          }
        ];
      in
      lib.mapAttrs (
        helperName: _:
        "# `wlib.modules.${helperName}`\n\n"
        + wrapperModuleMD (
          wrapperEval
          // {
            includeCore = false;
            onlyFiles = helperModuleFiles.${helperName};
            inherit (config) warningsAreErrors;
            moduleStartsOpen = _: _: true;
            descriptionStartsOpen = _: _: _: true;
            descriptionIncluded = _: _: _: true;
          }
        )
      ) importedHelpers
    ) wlib.wrapperModules;
  config.drv.core_docs = buildModuleDocs {
    package = pkgs.hello;
    inherit (config) warningsAreErrors;
    title = "Core (builtin) Options set";
  } "core" { };
  config.books.nix-wrapper-modules = {
    book = {
      book = {
        src = "src";
        authors = [ "BirdeeHub" ];
        language = "en";
        title = "nix-wrapper-modules";
        description = "Make wrapper derivations with the module system! Use the existing modules, or write your own!";
      };
      output.html = {
        git-repository-url = "https://github.com/BirdeeHub/nix-wrapper-modules";
        fold.enable = true;
        fold.level = 0;
      };
    };
    summary = [
      {
        data = "title";
        name = "nix-wrapper-modules";
      }
      {
        name = "Intro";
        data = "numbered";
        path = "md/intro.md";
        src = "${placeholder "out"}/wrappers-lib/intro.md";
        build = ''
          mkdir -p $out/wrappers-lib
          sed 's|# \[nix-wrapper-modules\](https://birdeehub.github.io/nix-wrapper-modules/)|# [nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules)|' < '${../../README.md}' > "$out/wrappers-lib/intro.md"
        '';
      }
      {
        name = "Getting Started";
        data = "numbered";
        path = "md/getting-started.md";
        src = ./md/getting-started.md;
      }
      {
        name = "Lib Functions";
        data = "numbered";
        path = "md/lib-intro.md";
        src = ./md/lib-intro.md;
        subchapters = [
          {
            name = "`wlib`";
            data = "numbered";
            path = "lib/wlib.md";
            src = "${placeholder "out"}/wrappers-lib/wlib.md";
            build = ''
              ${pkgs.nixdoc}/bin/nixdoc --category "" --description '`wlib` main set documentation' --file '${../../lib/lib.nix}' --prefix "wlib" >> $out/wrappers-lib/wlib.md
            '';
          }
          {
            name = "`wlib.types`";
            data = "numbered";
            path = "lib/types.md";
            src = "${placeholder "out"}/wrappers-lib/types.md";
            build = ''
              ${pkgs.nixdoc}/bin/nixdoc --category "types" --description '`wlib.types` set documentation' --file '${../../lib/types.nix}' --prefix "wlib" >> $out/wrappers-lib/types.md
            '';
          }
          {
            name = "`wlib.dag`";
            data = "numbered";
            path = "lib/dag.md";
            src = "${placeholder "out"}/wrappers-lib/dag.md";
            build = ''
              ${pkgs.nixdoc}/bin/nixdoc --category "dag" --description '`wlib.dag` set documentation' --file '${../../lib/dag.nix}' --prefix "wlib" >> $out/wrappers-lib/dag.md
            '';
          }
          {
            name = "`wlib.makeWrapper`";
            data = "numbered";
            path = "lib/makeWrapper.md";
            src = "${placeholder "out"}/wrappers-lib/makeWrapper.md";
            build = ''
              ${pkgs.nixdoc}/bin/nixdoc --category "makeWrapper" --description '`wlib.makeWrapper` set documentation' --file '${../../lib/makeWrapper/default.nix}' --prefix "wlib" >> $out/wrappers-lib/makeWrapper.md
            '';
          }
        ];
      }
      {
        name = "Core Options Set";
        data = "numbered";
        path = "lib/core.md";
        build = ''
          jq -r '.core_docs' "$NIX_ATTRS_JSON_FILE" > "$generated/core.md"
        '';
        src = "${placeholder "generated"}/core.md";
      }
      {
        name = "`wlib.modules.default`";
        data = "numbered";
        path = "modules/default.md";
        src = "${placeholder "generated"}/module_docs/default.md";
      }
      {
        name = "Helper Modules";
        data = "numbered";
        path = "md/helper-modules.md";
        src = ./md/helper-modules.md;
        subchapters = lib.pipe config.drv.module_docs [
          (v: removeAttrs v [ "default" ])
          builtins.attrNames
          (map (n: {
            name = n;
            data = "numbered";
            path = "modules/${n}.md";
            src = "${placeholder "generated"}/module_docs/${n}.md";
          }))
        ];
      }
      {
        name = "Wrapper Modules";
        data = "numbered";
        path = "md/wrapper-modules.md";
        src = ./md/wrapper-modules.md;
        subchapters = lib.mapAttrsToList (
          n: _:
          {
            name = n;
            data = "numbered";
            path = "wrapperModules/${n}.md";
            src = "${placeholder "generated"}/wrapper_docs/${n}.md";
            subchapters = lib.mapAttrsToList (m: _: {
              name = "`wlib.modules.${m}`";
              data = "numbered";
              path = "wrapperModules/${n}/${m}.md";
              src = "${placeholder "generated"}/wrapper_helper_docs/${n}/${m}.md";
            }) (getImportedHelperModules wlib.wrapperModules.${n});
          }
        ) wlib.wrapperModules;
      }
      {
        name = "Contributing";
        data = "numbered";
        path = "md/CONTRIBUTING.md";
        src = ../../CONTRIBUTING.md;
        subchapters = [
          {
            name = "tlib";
            data = "numbered";
            path = "tlib.md";
            src = "${placeholder "out"}/wrappers-lib/tlib.md";
            build = ''
              ${pkgs.nixdoc}/bin/nixdoc --category "" --description 'Testing library `tlib` documentation' --file '${../test-lib.nix}' --prefix "tlib" >> $out/wrappers-lib/tlib.md
            '';
          }
        ];
      }
    ];
  };
}
