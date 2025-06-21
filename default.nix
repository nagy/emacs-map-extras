{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  emacs ? pkgs.emacs,
  emacsPackages ? emacs.pkgs,
  melpaBuild ? emacsPackages.melpaBuild,
  dash ? emacsPackages.dash,
}:

melpaBuild {
  pname = "map-extras";
  version = "0-unstable-2025-06-21";
  src = lib.cleanSource ./.;
  packageRequires = [
    dash
  ];
  turnCompilationWarningToError = true;
}
