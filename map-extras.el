;;; map-extras.el --- More configuration for built-in map.el -*- lexical-binding: t -*-
;;
;; Copyright (C) 2025-2026 Daniel Nagy
;;
;; Author: Daniel Nagy <https://github.com/nagy>
;; Maintainer: Daniel Nagy <danielnagy@posteo.de>
;; Created: January 31, 2025
;; Version: 0.1
;; Homepage: https://github.com/nagy/emacs-map-extras
;; Package-Requires: ((emacs "27.1"))
;;
;; This file is NOT part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;;  More configuration for built-in map.el.
;;
;;  Teaches the map.el protocol to buffers, overlays, windows,
;;  processes, frames, threads, keymaps, markers, `url' objects,
;;  `ts' timestamps and EIEIO objects.  Lookups default to `eq'
;;  because every exposed key is a symbol or integer; pass TESTFN
;;  explicitly for anything else.
;;
;;; Code:

(require 'map)
(require 'eieio)

(defun map-extras--elt (key map default &optional testfn)
  "Look up KEY in MAP, returning DEFAULT when absent.
Keys are compared with TESTFN, defaulting to `eq'.

Unlike map.el, which picks the test function per map type (`equal'
for alists, `eq' for plists), this package always defaults to `eq':
all keys it exposes are symbols or small integers, for which `eq' is
both correct and fast.  Pass an explicit TESTFN (typically
`equal') for exotic keys such as string overlay properties."
  (let ((match (or testfn #'eq)))
    (catch 'map-extras--found
      (map-do (lambda (k v)
                (when (funcall match k key)
                  (throw 'map-extras--found v)))
              map)
      default)))

;;;
;;; Writability and supported operations, per type:
;;;
;;; | type    | map-elt keys                     | map-put!        |
;;; |---------+----------------------------------+-----------------|
;;; | buffer  | name file-name point size window | name directory  |
;;; |         | process narrowed directory       |                 |
;;; |         | major-mode                       |                 |
;;; | overlay | start end buffer properties      | structural keys;|
;;; |         |                                  | others = overlay-put |
;;; | window  | buffer left right point          | read-only       |
;;; |         | parameters start                 |                 |
;;; | process | name id plist status buffer      | filter sentinel |
;;; |         | filter sentinel contact command  |                 |
;;; |         | mark                             |                 |
;;; | frame   | name title visible width height  | read-only       |
;;; |         | selected                         |                 |
;;; | thread  | name live                        | read-only       |
;;; | keymap  | single events (shallow)          | define-key      |
;;; | marker  | position buffer                  | read-only       |
;;; | url     | type user password host portspec | all keys        |
;;; |         | filename target attributes       |                 |
;;; | ts      | year month day hour minute second| read-only       |
;;; | EIEIO   | public bound slots               | public slots    |
;;; | struct  | slots via macro                  | opt-in :writable|
;;;
;;; `map-copy' and `map-delete' are intentionally unsupported: these
;;; objects are identities (copying a buffer makes no sense) and their
;;; attributes are not deletable.  Use `map-pairs' for an alist
;;; snapshot of the current state.
;;;
;;; Buffer

(cl-defmethod mapp ((_map buffer))
  t)

(cl-defmethod map-do (function (map buffer))
  ;; Only cheap keys here: `map-elt' and `map-keys' iterate this, so
  ;; expensive attributes (e.g. `buffer-hash') must not be computed on
  ;; every query.  Call `buffer-hash' directly when needed.
  (funcall function 'name (buffer-name map))
  (funcall function 'file-name (buffer-file-name map))
  (funcall function 'point (with-current-buffer map (point)))
  (funcall function 'size (buffer-size map))
  (funcall function 'window (get-buffer-window map t))
  (funcall function 'process (get-buffer-process map))
  (funcall function 'narrowed (with-current-buffer map (buffer-narrowed-p)))
  (funcall function 'directory (buffer-local-value 'default-directory map))
  (funcall function 'major-mode (buffer-local-value 'major-mode map)))


(cl-defmethod map-elt ((map buffer) key &optional default testfn)
  ;; Direct dispatch for the default `eq' lookup; a custom TESTFN
  ;; falls back to the generic scan in `map-extras--elt', which sees
  ;; every key.  This avoids computing all accessors for one lookup.
  (if testfn
      (map-extras--elt key map default testfn)
    (pcase key
      ('name (buffer-name map))
      ('file-name (buffer-file-name map))
      ('point (with-current-buffer map (point)))
      ('size (buffer-size map))
      ('window (get-buffer-window map t))
      ('process (get-buffer-process map))
      ('narrowed (with-current-buffer map (buffer-narrowed-p)))
      ('directory (buffer-local-value 'default-directory map))
      ('major-mode (buffer-local-value 'major-mode map))
      (_ (map-extras--elt key map default)))))

(cl-defmethod map-put! ((map buffer) key value &optional _testfn)
  ;; Keys are matched by `pcase'; TESTFN is accepted for protocol
  ;; compatibility but unused, as in the `url' methods.
  (pcase key
    ('name (with-current-buffer map (rename-buffer value)))
    ('directory (with-current-buffer map (cd value)))
    ;; Unknown keys would otherwise be silently dropped.
    (_ (user-error "Cannot write key %S to buffer %S" key (buffer-name map)))))

;;; Overlay

(cl-defmethod mapp ((_map overlay))
  t)

(cl-defmethod map-do (function (map overlay))
  (funcall function 'start (overlay-start map))
  (funcall function 'end (overlay-end map))
  (funcall function 'buffer (overlay-buffer map))
  (funcall function 'properties (overlay-properties map)))

(cl-defmethod map-elt ((map overlay) key &optional default testfn)
  (if testfn
      (map-extras--elt key map default testfn)
    (pcase key
      ('start (overlay-start map))
      ('end (overlay-end map))
      ('buffer (overlay-buffer map))
      ('properties (overlay-properties map))
      (_ (map-extras--elt key map default)))))

(cl-defmethod map-put! ((map overlay) key value &optional _testfn)
  (pcase key
    ('start (move-overlay map value (overlay-end map)))
    ('end (move-overlay map (overlay-start map) value))
    ('buffer (move-overlay map (overlay-start map) (overlay-end map) value))
    ;; Anything else is an overlay property, stored on the overlay itself.
    (_ (overlay-put map key value))))

;;; Window

(cl-defmethod mapp ((_map window))
  t)

(cl-defmethod map-do (function (map window))
  ;; `window-end' may force redisplay, so it is deliberately excluded
  ;; from the iteration; call `window-end' directly when needed.
  (funcall function 'buffer (window-buffer map))
  (funcall function 'left (window-left map))
  (funcall function 'right (window-right map))
  (funcall function 'point (window-point map))
  (funcall function 'parameters (window-parameters map))
  (funcall function 'start (window-start map)))

(cl-defmethod map-elt ((map window) key &optional default testfn)
  (if testfn
      (map-extras--elt key map default testfn)
    (pcase key
      ('buffer (window-buffer map))
      ('left (window-left map))
      ('right (window-right map))
      ('point (window-point map))
      ('parameters (window-parameters map))
      ('start (window-start map))
      (_ (map-extras--elt key map default)))))

;;; Process

(cl-defmethod mapp ((_map process))
  t)

(cl-defmethod map-do (function (map process))
  (funcall function 'name (process-name map))
  (funcall function 'id (process-id map))
  (funcall function 'plist (process-plist map))
  (funcall function 'status (process-status map))
  (funcall function 'buffer (process-buffer map))
  (funcall function 'filter (process-filter map))
  (funcall function 'sentinel (process-sentinel map))
  (funcall function 'contact (process-contact map))
  (funcall function 'command (process-command map))
  ;; `process-attributes' is a system call, deliberately excluded from
  ;; the iteration; call it directly when needed.
  (funcall function 'mark (process-mark map)))

(cl-defmethod map-elt ((map process) key &optional default testfn)
  (if testfn
      (map-extras--elt key map default testfn)
    (pcase key
      ('name (process-name map))
      ('id (process-id map))
      ('plist (process-plist map))
      ('status (process-status map))
      ('buffer (process-buffer map))
      ('filter (process-filter map))
      ('sentinel (process-sentinel map))
      ('contact (process-contact map))
      ('command (process-command map))
      ('mark (process-mark map))
      (_ (map-extras--elt key map default)))))

(cl-defmethod map-put! ((map process) key value &optional _testfn)
  (pcase key
    ('filter (set-process-filter map value))
    ('sentinel (set-process-sentinel map value))
    (_ (user-error "Cannot write key %S to process %S" key (process-name map)))))

;;; Frame

(cl-defmethod mapp ((_map frame))
  t)

(cl-defmethod map-do (function (map frame))
  ;; Cheap keys only: skip `frame-parameters', `frame-position',
  ;; `frame-monitor-attributes' and the *pixel-* geometries, which can
  ;; force a round-trip with the window system.
  (funcall function 'name (frame-parameter map 'name))
  (funcall function 'title (frame-parameter map 'title))
  (funcall function 'visible (frame-visible-p map))
  (funcall function 'width (frame-width map))
  (funcall function 'height (frame-height map))
  (funcall function 'selected (eq map (selected-frame))))

(cl-defmethod map-elt ((map frame) key &optional default testfn)
  (if testfn
      (map-extras--elt key map default testfn)
    (pcase key
      ('name (frame-parameter map 'name))
      ('title (frame-parameter map 'title))
      ('visible (frame-visible-p map))
      ('width (frame-width map))
      ('height (frame-height map))
      ('selected (eq map (selected-frame)))
      (_ (map-extras--elt key map default)))))

;;; Thread

(cl-defmethod mapp ((_map thread))
  t)

(cl-defmethod map-do (function (map thread))
  (funcall function 'name (thread-name map))
  (funcall function 'live (thread-live-p map)))

(cl-defmethod map-elt ((map thread) key &optional default testfn)
  (if testfn
      (map-extras--elt key map default testfn)
    (pcase key
      ('name (thread-name map))
      ('live (thread-live-p map))
      (_ (map-extras--elt key map default)))))

;;; Keymaps

;; A keymap is a list, so a separate type specializer cannot give it
;; its own dispatch tag without colliding with map.el's `list' tag.
;; Instead, wrap the list methods: keymaps are detected at runtime and
;; everything else falls through via `cl-call-next-method'.
;;
;; All keymap operations are SHALLOW: iteration yields prefix keys
;; bound to subkeymaps, `map-elt' looks up single events only, and
;; `map-put!' defines single-event bindings.  Use `map-nested-elt'
;; with a list of events for prefix paths, or `lookup-key' directly.

(cl-defmethod mapp :around ((map list))
  (or (keymapp map) (cl-call-next-method)))

(cl-defmethod map-do :around (function (map list))
  (if (keymapp map)
      ;; Shallow iteration: prefix keys appear with a subkeymap binding.
      (map-keymap (lambda (event binding)
                    (funcall function event binding))
                  map)
    (cl-call-next-method)))

(cl-defmethod map-elt :around ((map list) key &optional default testfn)
  (if (keymapp map)
      (map-extras--elt key map default testfn)
    (cl-call-next-method)))

(cl-defmethod map-put! :around ((map list) key value &optional _testfn)
  (if (keymapp map)
      (define-key map (vector key) value)
    (cl-call-next-method)))

;;; Marker

(cl-defmethod mapp ((_marker marker))
  t)

(cl-defmethod map-do (function (marker marker))
  (funcall function 'position (marker-position marker))
  (funcall function 'buffer (marker-buffer marker)))


(cl-defmethod map-elt ((marker marker) key &optional default testfn)
  (if testfn
      (map-extras--elt key marker default testfn)
    (pcase key
      ('position (marker-position marker))
      ('buffer (marker-buffer marker))
      (_ (map-extras--elt key marker default)))))

;;; URL

;; Deferred like `ts': only define the methods once `url-parse' is
;; loaded, so requiring `map-extras' stays cheap for users who never
;; touch `url' objects.
(eval-when-compile
  (require 'url-parse))
(with-eval-after-load 'url-parse
  (declare-function url-type "url-parse")
  (declare-function url-user "url-parse")
  (declare-function url-password "url-parse")
  (declare-function url-host "url-parse")
  (declare-function url-portspec "url-parse")
  (declare-function url-filename "url-parse")
  (declare-function url-target "url-parse")
  (declare-function url-attributes "url-parse")

  (cl-defmethod mapp ((_map url))
    t)

  (cl-defmethod map-do (function (map url))
    (funcall function 'type (url-type map))
    (funcall function 'user (url-user map))
    (funcall function 'password (url-password map))
    (funcall function 'host (url-host map))
    (funcall function 'portspec (url-portspec map))
    (funcall function 'filename (url-filename map))
    (funcall function 'target (url-target map))
    (funcall function 'attributes (url-attributes map)))

  (cl-defmethod map-elt ((map url) key &optional default testfn)
    (if testfn
        (map-extras--elt key map default testfn)
      (pcase key
        ('type (url-type map))
        ('user (url-user map))
        ('password (url-password map))
        ('host (url-host map))
        ('portspec (url-portspec map))
        ('filename (url-filename map))
        ('target (url-target map))
        ('attributes (url-attributes map))
        (_ (map-extras--elt key map default)))))

  (cl-defmethod map-put! ((map url) key value &optional _testfn)
    ;; Keys are matched by `pcase' on symbols; TESTFN is accepted for
    ;; protocol compatibility but the write is a direct accessor setf.
    (pcase key
      ('type (setf (url-type map) value))
      ('user (setf (url-user map) value))
      ('password (setf (url-password map) value))
      ('host (setf (url-host map) value))
      ('portspec (setf (url-portspec map) value))
      ('filename (setf (url-filename map) value))
      ('target (setf (url-target map) value))
      ('attributes (setf (url-attributes map) value))
      (_ (user-error "Cannot write key %S to url %S" key (url-host map))))))


;;; Ts
(with-eval-after-load 'ts
  (declare-function ts-second "ts")
  (declare-function ts-minute "ts")
  (declare-function ts-hour "ts")
  (declare-function ts-day "ts")
  (declare-function ts-month "ts")
  (declare-function ts-year "ts")
  (cl-defmethod mapp ((_map ts))
    t)
  (cl-defmethod map-do (function (map ts))
    (funcall function 'year (ts-year map))
    (funcall function 'month (ts-month map))
    (funcall function 'day (ts-day map))
    (funcall function 'hour (ts-hour map))
    (funcall function 'minute (ts-minute map))
    (funcall function 'second (ts-second map)))

  (cl-defmethod map-elt ((map ts) key &optional default testfn)
    (if testfn
        (map-extras--elt key map default testfn)
      (pcase key
        ('year (ts-year map))
        ('month (ts-month map))
        ('day (ts-day map))
        ('hour (ts-hour map))
        ('minute (ts-minute map))
        ('second (ts-second map))
        (_ (map-extras--elt key map default))))))

;; macros

(defmacro map-extras-define-for-struct (struct keys &optional writable)
  "Define `map.el' methods for cl-defstruct STRUCT with slots KEYS.
Each slot must have a STRUCT-<slot> accessor.

With WRITABLE non-nil, also define `map-put!' writing through the
same accessors; unknown keys signal `user-error'.  Without it the
struct stays read-only."
  `(progn
     (cl-defmethod mapp ((_map ,struct))
       t)
     (cl-defmethod map-do (function (map ,struct))
       ,@(mapcar (lambda (slot)
                   `(funcall function ',slot (,(intern (format "%s-%s" struct slot)) map)))
                 keys))
     (cl-defmethod map-elt ((map ,struct) key &optional default testfn)
       (map-extras--elt key map default testfn))
     ,@(when writable
         `((cl-defmethod map-put! ((map ,struct) key value &optional _testfn)
             (cl-case key
               ,@(mapcar (lambda (slot)
                           `(,slot (setf (,(intern (format "%s-%s" struct slot)) map)
                                         value)))
                         keys)
               (t (user-error "Cannot write key %S to %s" key ',struct))))))))

(cl-defstruct map-extras-transformer -inner key-to key-from)

(defun map-extras--transformer-map (transformer)
  "Return the inner map of TRANSFORMER.
An inner map given as a symbol is dereferenced via `symbol-value'."
  (let ((inner (map-extras-transformer--inner transformer)))
    (if (symbolp inner)
        (symbol-value inner)
      inner)))
(cl-defmethod mapp ((_map map-extras-transformer))
  t)
(cl-defmethod map-elt ((map map-extras-transformer) key &optional default testfn)
  (map-elt (map-extras--transformer-map map)
           (funcall (map-extras-transformer-key-from map) map key)
           default testfn))
(cl-defmethod map-keys ((map map-extras-transformer))
  (mapcar (lambda (key)
            (funcall (map-extras-transformer-key-to map) map key))
          (map-keys (map-extras--transformer-map map))))

(cl-defmethod map-do (function (map map-extras-transformer))
  (map-do (lambda (key value)
            (funcall function
                     (funcall (map-extras-transformer-key-from map) map key)
                     value))
          (map-extras--transformer-map map)))

(defun map-extras-make-transformer-via-extension (map extension)
  (make-map-extras-transformer
   :-inner map
   ;; Strip EXTENSION without `string-remove-suffix' (subr-x), which
   ;; is not available at runtime in byte-compiled installs.
   :key-from (lambda (_map key)
               (if (string-suffix-p extension key)
                   (substring key 0 (- (length key) (length extension)))
                 key))
   :key-to (lambda (_map key)
             (concat key extension))))


;;; Generic EIEIO objects

;; One set of methods for any EIEIO object: slots become keys.  More
;; specific methods (e.g. a class defining its own map-do) always win,
;; since eieio-default-superclass is the root of the class hierarchy.
(cl-defmethod mapp ((_map eieio-default-superclass))
  t)

(cl-defmethod map-do (function (map eieio-default-superclass))
  (dolist (slot (eieio-class-slots (eieio-object-class map)))
    (let ((name (cl--slot-descriptor-name slot)))
      ;; Slots named --* are internal and unbound until set.
      (unless (string-prefix-p "--" (symbol-name name))
        (when (slot-boundp map name)
          (funcall function name (eieio-oref map name)))))))

(cl-defmethod map-elt ((map eieio-default-superclass) key &optional default testfn)
  ;; Fast path: a bound, public slot is read directly.  Internal
  ;; `--*' slots and unknown names fall to the scan, which skips them
  ;; exactly like `map-do' does.
  (if (and (not testfn)
           (slot-exists-p map key)
           (not (string-prefix-p "--" (symbol-name key)))
           (slot-boundp map key))
      (eieio-oref map key)
    (map-extras--elt key map default testfn)))

(cl-defmethod map-put! ((map eieio-default-superclass) key value &optional _testfn)
  ;; Mirror the read path: `map-do' never exposes `--*' slots or
  ;; unknown slot names, so writing them through `map-put!' is an
  ;; error too.
  (if (and (slot-exists-p map key)
           (not (string-prefix-p "--" (symbol-name key))))
      (setf (eieio-oref map key) value)
    (user-error "Cannot write key %S to %s" key (eieio-object-class map))))

;;; seq.el integrations

;; frame -> list of windows
;; `elfeed-feed-p' -> list of `elfeed-feed-entries'

(provide 'map-extras)
;;; map-extras.el ends here
