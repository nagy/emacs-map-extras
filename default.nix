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
  version = "0.1";   # matches the Version: header in map-extras.el
  src = lib.cleanSource ./.;
  # dash: external dependency.
  # eieio: builtin since Emacs 24 — no emacsPackages attribute exists.
  packageRequires = [
    dash
  ];
  turnCompilationWarningToError = true;
}
