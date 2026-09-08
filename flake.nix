{
  description = "Treat Emacs Lisp objects as maps (map.el protocol via cl-defmethod)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          system,
          pkgs,
          lib,
          config,
          ...
        }:
        let
          emacsPackages = pkgs.emacsPackages;
          inherit (emacsPackages) melpaBuild;
        in
        {
          packages.map-extras = melpaBuild {
            pname = "map-extras";
            version = "0.1";

            src = lib.cleanSource ./.;

            # Built-ins only: no external package dependencies.
            packageRequires = [ ];

            turnCompilationWarningToError = true;

            doCheck = true;
            nativeCheckInputs = [ pkgs.emacs ];
            checkPhase = ''
              runHook preCheck
              emacs --batch -Q \
                -L . \
                -l map-extras-tests.el \
                -f ert-run-tests-batch-and-exit
              runHook postCheck
            '';

            meta = {
              description = ''
                More configuration for the built-in map.el: teaches the
                map.el protocol (mapp, map-do, map-elt, map-put!) to
                buffers, windows, processes, markers, URLs and
                timestamps, plus a key-translating map-transformer.
              '';
              license = lib.licenses.agpl3Plus;
              homepage = "https://github.com/nagy/emacs-map-extras";
              maintainers = with lib.maintainers; [ nagy ];
            };
          };

          packages.default = config.packages.map-extras;

          devShells.default = pkgs.mkShell {
            packages = [ pkgs.emacs ];
          };
        };
    };
}
