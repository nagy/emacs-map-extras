# map-extras.el

Single-file Emacs Lisp package extending `map.el` to treat Emacs Lisp
objects as maps: buffers, windows, processes, markers, URLs (`url-parse`),
timestamps (`ts`), plus EIEIO/struct support helpers
(`map-extras-define-for-struct`, `map-transformer`).

## Conventions

- Lexical binding, `;;;` section headers, `map-extras--` prefix for internals.
- Optional dependencies (`ts`, etc.) go inside `with-eval-after-load` with
  `declare-function` for each accessor.

## Checks

- Byte-compile before committing:

  ```sh
  emacs --batch -L . -f batch-byte-compile map-extras.el && rm -f map-extras.elc
  ```
