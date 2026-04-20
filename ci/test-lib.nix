{
  self,
  lib,
  runCommand,
  stdenv,
  pkgs,
  ...
}:
let
  createAssertion =
    { cond, message }:
    ''
      (${cond}) || (echo "${message}" >&2; return 1)
    '';

  runTests2 =
    {
      name,
      context ? { },
      contextFn ? globalCtx: localCtx: globalCtx // localCtx,
      defaultContext ? null,
      cond ? (ctx: true),
    }:
    tests:
    let
      testsWithContext = lib.map (test: test (contextFn context) defaultContext) tests;
    in
    if cond context then
      lib.trace "Running test!" runCommand name { } ''
        ${lib.concatStringsSep "\n\n" testsWithContext}
        touch $out
      ''
    else
      lib.trace "Skipping test..." null;

  runWrapperTests2 =
    wrapperModule:
    tests:
    let
      name = "${wrapper.binName}-test";
      wrapper = wrapperModule.apply { inherit pkgs; };
      context = { inherit wrapperModule wrapper; };
      contextFn =
        globalCtx: localCtx:
        (
          let
            wrapper = globalCtx.wrapper.wrap localCtx.config;
            config = wrapper.passthru.configuration;
          in
          {
            inherit wrapper config;
            inherit (globalCtx) wrapperModule;
          }
        );
      cond = ctx: builtins.elem stdenv.hostPlatform.system ctx.wrapper.meta.platforms;
      
    in 
      runTests2 { 
        inherit name context contextFn cond;
        defaultContext = "wrapper";
      } tests;

  # generic runTest
  runTest2 =
    { name, context }:
    assertions: contextFn: defaultContext:
    let
      mergedContext = contextFn context;
      # assertions' = assertions 
      # (if defaultContext == null then 
      #   mergedContext
      # else
      #   mergedContext."${defaultContext}");
      assertions' =
        if lib.isFunction assertions then
          # Shorthand notation (wrapper: assertions)
          if lib.functionArgs assertions == { } && defaultContext != null then
            assertions mergedContext."${defaultContext}"
          else
            assertions mergedContext
        else
          assertions;
    in
    ''
      run() {
        ${lib.concatMapStringsSep " && " (a: "(${a})") (lib.toList assertions')}
      }

      run || (echo 'test "${name}" failed' >&2 && exit 1)
    '';

  # runTestWithConfig2 =
  #   {
  #     name,
  #     context ? { },
  #   }:
  #   assertions: wrapper:
  #   let
  #
  #     wrapperWithConfig = wrapper.wrap config;
  #     assertions' =
  #       if lib.isFunction assertions then
  #         # Shorthand notation (wrapper: assertions)
  #         if lib.functionArgs assertions == { } then
  #           assertions wrapperWithConfig
  #         else
  #           assertions {
  #             wrapper = wrapperWithConfig;
  #             config = wrapperWithConfig.passthru.configuration;
  #           }
  #       else
  #         assertions;
  #   in
  #   ''
  #     run() {
  #       ${lib.concatMapStringsSep " && " (a: "(${a})") (lib.toList assertions')}
  #     }
  #
  #     run || (echo 'test "${name}" failed' >&2 && exit 1)
  #   '';

  # runWrapperTests
  runTests =
    settings: tests:
    let
      wrapperModule = settings.wrapperModule;
      wrapper = wrapperModule.apply { inherit pkgs; };
      name = settings.name or "${wrapper.binName}-test";
      cond = ctx: (builtins.elem stdenv.hostPlatform.system ctx.wrapper.meta.platforms);
    in
    runTests2 {
      inherit name cond;
      context = { inherit wrapperModule wrapper; };
    } tests;

  runTest =
    nameOrSettings: assertions: wrapper:
    let
      settings =
        if (lib.isAttrs nameOrSettings) && (nameOrSettings ? name) then
          nameOrSettings
        else if lib.isString nameOrSettings then
          {
            name = nameOrSettings;
          }
        else
          throw ''
            Invalid argument for `runTest`.
            The first argument must be either a string (the test name) or an attrs
            matching { name, config ? { } }, but got:

            ${lib.toJSON nameOrSettings}
          '';
    in
    runTestWithConfig settings assertions wrapper;

  runTestWithConfig =
    {
      name,
      config ? { },
    }:
    assertions: wrapper:
    let
      wrapperWithConfig = wrapper.wrap config;
      assertions' =
        if lib.isFunction assertions then
          # Shorthand notation (wrapper: assertions)
          if lib.functionArgs assertions == { } then
            assertions wrapperWithConfig
          else
            assertions {
              wrapper = wrapperWithConfig;
              config = wrapperWithConfig.passthru.configuration;
            }
        else
          assertions;
    in
    ''
      run() {
        ${lib.concatMapStringsSep " && " (a: "(${a})") (lib.toList assertions')}
      }

      run || (echo 'test "${name}" failed' >&2 && exit 1)
    '';
in
{
  inherit
    createAssertion
    runTests
    runTest
    runWrapperTests2
    runTests2
    runTest2
    runTestWithConfig
    ;
  isDirectory =
    path:
    createAssertion {
      cond = ''[ -d "${path}" ]'';
      message = "No such directory ${path}";
    };

  isFile =
    path:
    createAssertion {
      cond = ''[ -f "${path}" ]'';
      message = "No such file ${path}";
    };

  notIsFile =
    path:
    createAssertion {
      cond = ''[ ! -f "${path}" ]'';
      message = "File ${path} should not exist";
    };

  fileContains =
    file: pattern:
    createAssertion {
      cond = ''grep -q '${pattern}' "${file}"'';
      message = "Pattern '${pattern}' not found in ${file}";
    };

}
