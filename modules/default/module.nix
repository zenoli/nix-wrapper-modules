{ wlib, lib, ... }:
{
  imports = [
    wlib.modules.symlinkScript
    wlib.modules.constructFiles
    wlib.modules.makeWrapper
  ];
  config.meta.maintainers = [ wlib.maintainers.birdee ];
  config.meta.description = ''
    `wlib.modules.default` is a convenience module that simply imports the following three helper modules:

    - `wlib.modules.symlinkScript`
    - `wlib.modules.constructFiles`
    - `wlib.modules.makeWrapper`

    Each of these is documented in its own subchapter.
  '';
}
