# map-extras

Treat Emacs Lisp objects as maps: `map-extras` teaches the built-in
[`map.el`](https://www.gnu.org/software/emacs/manual/html_node/elisp/Mapping-Functions.html)
protocol (`mapp`, `map-do`, `map-elt`, `map-put!`, and everything
derived from them) to object types that map.el does not know about.

```elisp
(map-elt (current-buffer) 'size)          ; => 1234
(map-do (lambda (k v) ...) some-process)  ; iterate process attributes
(map-put! an-overlay 'face 'bold)         ; write through the protocol
```

## Supported types and keys

|Type          |Keys (`map-elt`)                                                        |Writable via `map-put!`                                   |
|--------------|------------------------------------------------------------------------|----------------------------------------------------------|
|buffer        |`name file-name point size window process narrowed directory major-mode`|`name`, `directory`                                       |
|overlay       |`start end buffer properties`                                           |structural keys; any other key becomes an overlay property|
|window        |`buffer left right point parameters start`                              |read-only                                                 |
|process       |`name id plist status buffer filter sentinel contact command mark`      |`filter`, `sentinel`                                      |
|frame         |`name title visible width height selected`                              |read-only                                                 |
|thread        |`name live`                                                             |read-only                                                 |
|keymap        |bound events (single events only, shallow)                              |`define-key`                                              |
|marker        |`position buffer`                                                       |read-only                                                 |
|`url`         |`type user password host portspec filename target attributes`           |all keys                                                  |
|`ts`          |`year month day hour minute second`                                     |read-only                                                 |
|EIEIO         |public, bound slots                                                     |public slots                                              |
|`cl-defstruct`|slots, via `map-extras-define-for-struct`                               |opt-in (`writable` argument)                              |

Deliberately excluded from iteration because they are expensive to
compute: `buffer-hash`, `window-end`, `process-attributes`,
`frame-parameters`, `frame-position`, `frame-monitor-attributes` and
the frame `*pixel-*` geometries.  Call those accessors directly when
you need them.

## Semantics

- **Lookup keys are compared with `eq` by default.**  Every key this
  package exposes is a symbol or a small integer, so `eq` is correct
  and fast.  Pass an explicit `testfn` (typically `equal`) for exotic
  keys such as string overlay properties; custom-testfn lookups scan
  all keys.
- **Keymap operations are shallow.**  Iteration yields prefix keys
  bound to subkeymaps; `map-elt` looks up single events; `map-put!`
  defines single-event bindings.  Use `map-nested-elt` with a list of
  events (or `lookup-key`) for prefix paths.
- **`map-copy` and `map-delete` are unsupported.**  These objects are
  identities, not snapshots: copying a buffer makes no sense and
  buffer attributes are not deletable.  Use `map-pairs` for an alist
  snapshot of the current state.
- Writing an unknown key signals `user-error` rather than silently
  doing nothing.

## Defining maps for structs

```elisp
(map-extras-define-for-struct my-thing (alpha beta))
;; read-only: map-elt, map-do, mapp

(map-extras-define-for-struct my-thing (alpha beta) writable)
;; additionally defines map-put! writing through the slot accessors
```

Each slot needs a `STRUCT-<slot>` accessor (the `cl-defstruct`
default).  EIEIO objects need no declaration: all public, bound slots
are visible as keys automatically.

## Key-translating maps

`map-extras-transformer` wraps any map and translates keys on the way
in and out:

```elisp
(map-extras-make-transformer-via-extension alist "-bar")
;; iteration keys: "foo-bar-bar", "foo-baz-bar"
;; lookup of "foo" strips the "-bar" suffix before reading the alist
```

`map-extras-make-transformer-via-extension` returns a transformer
over MAP that appends EXTENSION to every key on iteration and strips
a trailing EXTENSION from lookup keys.  For full control, build one
directly with `make-map-extras-transformer`, passing `:-inner`,
`:key-from` (outer → inner key) and `:key-to` (inner → outer key).
The inner map may also be a symbol, which is dereferenced via
`symbol-value` at read time.

Supported operations: `mapp`, `map-elt`, `map-keys`, `map-do` and
everything derived from them.  `map-put!` is not supported.

## Installation

Only built-in libraries are required (`map`, `eieio`); Emacs 27.1 or
later.

- With Nix: `nix build .#map-extras` (a flake is provided).
- Otherwise: put `map-extras.el` on your `load-path` and
  `(require 'map-extras)`.

## Tests

```sh
emacs --batch -L . -l map-extras-tests.el -f ert-run-tests-batch-and-exit
```

## License

AGPL-3.0-or-later.  See the header of `map-extras.el` or the `LICENSE`
file.
