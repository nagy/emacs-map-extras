# map-extras.el

Single-file Emacs Lisp package extending `map.el` to treat Emacs Lisp
objects as maps: buffers, windows, processes, markers, URLs (`url-parse`),
timestamps (`ts`), plus EIEIO/struct support helpers
(`map-extras-define-for-struct`, `map-extras-transformer`).

## Conventions

- Lexical binding, `;;;` section headers, `map-extras--` prefix for internals.
- Optional dependencies (`ts`, etc.) load with `(when (require 'lib nil t)
  ...)` around the methods, plus `declare-function` for each accessor.
  Do not use `with-eval-after-load`: `package-lint' rejects it in
  packages, and that warning fails `checks.lint'.

## Issue tracking

Open recommendations live in git-bug (embedded tracker, `refs/bugs/*`),
not in an Org file. Use `nix-shell -p git-bug --run 'git-bug bug'` to
list them. See the "Tracker conventions and sync" issue.

## Tests

ERT tests live in `test/`, one `<unit>-test.el` per source file. Name each
`ert-deftest` with the package prefix (`map-extras-<unit>-<behavior>`).
The flake `checkPhase` loads `test/*-test.el` through a `failglob` glob,
so a new test file needs no flake edit. Shared fixtures go in
`map-extras-test-helper.el`.

## Checks

- Byte-compile before committing:

  ```sh
  emacs --batch -L . -f batch-byte-compile map-extras.el && rm -f map-extras.elc
  ```
