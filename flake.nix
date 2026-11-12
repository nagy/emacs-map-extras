{
  description = "Treat Emacs Lisp objects as maps (map.el protocol via cl-defmethod)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Single formatter entry point for the repo: `nix fmt' formats every
    # tracked file with the configured programs.
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      # Date of the last commit as YYYY-MM-DD, folded into the version
      # string.  Flake source info gives it as e.g. "20260922133522";
      # slice out the year, month and day.  A plain path import has no
      # git metadata, so fall back to the epoch instead of failing.
      sourceInfo = inputs.self.sourceInfo or { };
      lastModifiedDate = sourceInfo.lastModifiedDate or "19700101000000";
      commitDate = "${builtins.substring 0 4 lastModifiedDate}-${
        builtins.substring 4 2 lastModifiedDate
      }-${builtins.substring 6 2 lastModifiedDate}";
      version = "0.1-unstable-${commitDate}";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ treefmt-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          pkgs,
          config,
          ...
        }:
        let
          # The package stays overridable, so a consumer can swap the
          # Emacs or the package set:
          #   inputs.map-extras.packages.${system}.map-extras.override {
          #     emacs = pkgs.emacs-nox;
          #   }
          # The flake passes the version, because a plain import of the
          # expression cannot know it.
          map-extras = pkgs.lib.makeOverridable (
            {
              # One Emacs package set supplies the build tools.  An
              # override of this argument moves them all.
              emacs ? pkgs.emacs,
              emacsPackages ? pkgs.emacsPackagesFor emacs,
              melpaBuild ? emacsPackages.melpaBuild,
              # Emacs with `ts' on the load path, for the test suite.
              # `melpaBuild' closes over the Emacs of its package set, so
              # the check phase gets its own wrapper.
              emacsForTests ? emacsPackages.emacsWithPackages (epkgs: [ epkgs.ts ]),
              # The flake passes this, so a plain import stays explicit.
              version,
            }:
            melpaBuild {
              pname = "map-extras";
              inherit version;

              src = pkgs.lib.cleanSource ./.;

              # Built-ins only: no external package dependencies.
              packageRequires = [ ];

              # A byte-compile warning fails the build.  This is the
              # cheapest lint the package gets.
              turnCompilationWarningToError = true;

              doCheck = true;
              nativeCheckInputs = [ emacsForTests ];
              checkPhase = ''
                runHook preCheck
                # `melpaBuild' stages only the root `*.el' files, so the
                # test tree must come back before it can be loaded.
                cp -r ${./test} ./test
                # `printf' repeats "-l %s" per match, which turns the glob
                # into `-l <file>' pairs.  `failglob' makes an empty glob a
                # shell error, so the `||' guard fires even without `set -e'.
                # Restore the default right after: later commands need
                # default glob semantics.  The unquoted $test_args splits on
                # purpose; test file names never contain spaces.
                shopt -s failglob
                test_args=$(printf -- "-l %s " test/*-test.el) || { echo 'no tests matched test/*-test.el' >&2; exit 1; }
                shopt -u failglob
                ${emacsForTests}/bin/emacs --batch -Q \
                  -L . -L test \
                  $test_args \
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
                longDescription = ''
                  More configuration for the built-in map.el.  Adds the
                  map.el generic functions `mapp', `map-do', `map-elt' and
                  `map-put!' to buffers, overlays, windows, frames,
                  processes, threads, keymaps, markers, `url' objects and
                  `ts' timestamps, plus an EIEIO object helper.

                  All lookups default to `eq', because every exposed key is
                  a symbol or an integer.  Pass TESTFN explicitly for any
                  other key type.  The package also defines
                  `map-extras-transformer', a map that translates keys
                  before it reaches an underlying map.
                '';
                license = pkgs.lib.licenses.agpl3Plus;
                homepage = "https://github.com/nagy/emacs-map-extras";
                maintainers = with pkgs.lib.maintainers; [ nagy ];
                # Pure Elisp with built-in dependencies only.
                platforms = pkgs.lib.platforms.linux;
              };
            }
          ) { inherit version; };

          # checkdoc and package-lint catch style and packaging problems
          # that byte-compilation does not.  Keep this in `checks', not in
          # the package: lint findings must not block an otherwise
          # buildable package forever.
          mkLint =
            { src }:
            pkgs.runCommand "map-extras-lint"
              {
                nativeBuildInputs = [
                  (pkgs.emacsPackages.emacsWithPackages (epkgs: [
                    epkgs.package-lint
                  ]))
                ];
                inherit src;
                meta.description = "map-extras checkdoc and package-lint checks";
              }
              ''
                export HOME=$TMPDIR
                cp "$src/map-extras.el" .

                # package-lint exits non-zero on any finding.  The package
                # names no external dependency, so it needs no stubs.
                emacs --batch -l package-lint -f package-lint-batch-and-exit map-extras.el

                # checkdoc exits 0 even when it reports problems, so gate
                # on its output instead.
                report=$(emacs --batch -l checkdoc \
                  --eval "(checkdoc-file \"map-extras.el\")" 2>&1)
                if [ -n "$report" ]; then
                  printf '%s\n' "$report"
                  exit 1
                fi

                touch $out
              '';
        in
        {
          packages = {
            map-extras = map-extras;
            default = map-extras;
          };

          checks = {
            # melpaBuild byte-compiles with warnings as errors and runs
            # the ERT suite in checkPhase, so the package is the check.
            default = map-extras;
            lint = pkgs.callPackage mkLint { inherit (map-extras) src; };
          };

          devShells.default = pkgs.mkShell {
            packages = [
              (pkgs.emacsPackages.emacsWithPackages (epkgs: [ epkgs.ts ]))
              config.treefmt.build.wrapper
            ];
          };

          # nixfmt only.  Elisp has no formatter in this stack, so the
          # sources stay untouched and checkdoc plus package-lint guard
          # their style.
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };
        };
    };
}
