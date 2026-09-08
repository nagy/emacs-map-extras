;;; map-extras-tests.el --- ERT tests for map-extras.el -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; Code:

(require 'ert)
(require 'map-extras)

(declare-function ts-parse "ts")

;;; Protocol entry points

(ert-deftest map-extras-mapp-buffer ()
  "`mapp' recognizes buffers."
  (with-temp-buffer
    (should (mapp (current-buffer)))))

(ert-deftest map-extras-mapp-window ()
  "`mapp' recognizes windows."
  (should (mapp (selected-window))))

(ert-deftest map-extras-mapp-marker ()
  "`mapp' recognizes markers."
  (should (mapp (point-marker))))

(ert-deftest map-extras-mapp-process ()
  "`mapp' recognizes processes."
  (let ((proc (start-process "map-extras-tests" nil "true")))
    (unwind-protect
        (should (mapp proc))
      (delete-process proc))))

;;; Buffer maps

(ert-deftest map-extras-buffer-elt ()
  "`map-elt' reads buffer attributes."
  (with-temp-buffer
    (insert "hello")
    (rename-buffer "map-extras-test-buffer" t)
    (should (equal (map-elt (current-buffer) 'name)
                   "map-extras-test-buffer"))
    (should (= (map-elt (current-buffer) 'size) 5))
    (should (stringp (map-elt (current-buffer) 'directory)))))

(ert-deftest map-extras-buffer-elt-missing-default ()
  "`map-elt' returns DEFAULT for absent buffer keys."
  (with-temp-buffer
    (should (eq (map-elt (current-buffer) 'nonexistent-key :sentinel)
                :sentinel))))

(ert-deftest map-extras-buffer-elt-testfn ()
  "`map-elt' honors TESTFN, defaulting to `eq'."
  (with-temp-buffer
    ;; Default testfn: eq lookup of symbols.
    (should (equal (map-elt (current-buffer) 'name) (buffer-name)))
    ;; Explicit testfn.
    (should (equal (with-suppressed-warnings ((callargs map-elt))
                     (map-elt (current-buffer) 'name nil #'equal))
                   (buffer-name)))
    ;; TESTFN comparison runs against the key symbols.
    (let* ((keys nil)
           (seen (with-suppressed-warnings ((callargs map-elt))
                   (map-elt (current-buffer) 'size
                            :sentinel
                            (lambda (k _key)
                              (push k keys) nil)))))
      ;; Non-matching testfn falls back to DEFAULT but sees all keys.
      (should (eq seen :sentinel))
      (should (equal keys
                     (reverse '(name file-name point size window
                                     process narrowed directory
                                     major-mode)))))))

(ert-deftest map-extras-buffer-do-keys ()
  "`map-do' visits every documented buffer key."
  (with-temp-buffer
    (let (keys)
      (map-do (lambda (k _v) (push k keys)) (current-buffer))
      (should (member 'name keys))
      (should (member 'size keys))
      (should (member 'point keys))
      (should (member 'major-mode keys))
      (should (member 'directory keys)))))

(ert-deftest map-extras-buffer-elt-fast-path ()
  "`map-elt' with the default testfn reads one slot directly."
  (with-temp-buffer
    (cl-letf (((symbol-function 'buffer-narrowed-p)
               (lambda () (error "buffer-narrowed-p must not be called")))
              ((symbol-function 'buffer-file-name)
               (lambda (&optional _b) (error "buffer-file-name must not be called"))))
      (should (equal (map-elt (current-buffer) 'name)
                     (buffer-name))))))

(ert-deftest map-extras-buffer-do-skips-expensive-keys ()
  "`map-elt' on a buffer never computes `buffer-hash'."
  (with-temp-buffer
    (insert "x")
    (cl-letf (((symbol-function 'buffer-hash)
               (lambda (_buffer) (error "buffer-hash must not be called"))))
      (should (equal (map-elt (current-buffer) 'name) (buffer-name)))
      (should (= (map-elt (current-buffer) 'size) 1))
      (should-not (memq 'hash
                        (let (keys)
                          (map-do (lambda (k _v) (push k keys))
                                  (current-buffer))
                          keys))))))

(ert-deftest map-extras-window-do-skips-end ()
  "`map-do' on a window never calls `window-end'."
  (with-selected-window (selected-window)
    (cl-letf (((symbol-function 'window-end)
               (lambda (_window &optional _update) (error "window-end must not be called"))))
      (should (map-elt (selected-window) 'buffer))
      (should (integerp (map-elt (selected-window) 'start))))))

(ert-deftest map-extras-process-do-skips-attributes ()
  "`map-do' on a process never calls `process-attributes'."
  (let ((proc (start-process "map-extras-attr" nil "true")))
    (unwind-protect
        (cl-letf (((symbol-function 'process-attributes)
                   (lambda (_pid) (error "process-attributes must not be called"))))
          (should (equal (map-elt proc 'name) "map-extras-attr"))
          (should (symbolp (map-elt proc 'status))))
      (delete-process proc))))

;;; Marker maps

(ert-deftest map-extras-marker-elt ()
  "`map-elt' reads marker position and buffer."
  (with-temp-buffer
    (insert "0123456789")
    (goto-char 5)
    (let ((marker (point-marker)))
      (should (= (map-elt marker 'position) 5))
      (should (eq (map-elt marker 'buffer) (current-buffer))))))

;;; Keymap maps

(defvar map-extras-tests-keymap (make-sparse-keymap))
(define-key map-extras-tests-keymap "a" 'map-extras-test-command)
(define-key map-extras-tests-keymap (kbd "C-c x") 'map-extras-test-cmd2)

(ert-deftest map-extras-mapp-keymap ()
  "`mapp' recognizes keymaps."
  (should (mapp map-extras-tests-keymap)))

(ert-deftest map-extras-keymap-elt ()
  "`map-elt' looks up single-key bindings."
  (should (eq (map-elt map-extras-tests-keymap ?a)
              'map-extras-test-command))
  (should (eq (map-elt map-extras-tests-keymap ?z :sentinel) :sentinel)))

(ert-deftest map-extras-keymap-do-keys ()
  "`map-do' visits the defined keys."
  (let (pairs)
    (map-do (lambda (k v) (push (cons k v) pairs)) map-extras-tests-keymap)
    (should (equal (cdr (assq ?a pairs)) 'map-extras-test-command))
    (should (= (length pairs) 2))))

(ert-deftest map-extras-keymap-keys ()
  "`map-keys' returns the bound events (via the map-do default)."
  (should (equal (sort (map-keys map-extras-tests-keymap) #'<)
                '(3 97)))) ; C-c prefix (binding is a subkeymap), a

(ert-deftest map-extras-keymap-put ()
  "`map-put!' defines a binding, round-trip through map-elt."
  (let ((km (make-sparse-keymap)))
    (map-put! km ?g 'map-extras-g-command)
    (should (eq (map-elt km ?g) 'map-extras-g-command))
    (should (eq (lookup-key km (vector ?g)) 'map-extras-g-command))))

(ert-deftest map-extras-keymap-nested-elt ()
  "`map-nested-elt' reaches leaf bindings across prefix subkeymaps.
Iteration and `map-elt' stay shallow; this is the documented deep
lookup path."
  (should (eq (map-nested-elt map-extras-tests-keymap (list 3 ?x))
              'map-extras-test-cmd2))
  ;; Shallow `map-elt' only sees the prefix's subkeymap binding.
  (should (keymapp (map-elt map-extras-tests-keymap 3))))

(ert-deftest map-extras-window-put-errors ()
  "`map-put!' on a window signals `user-error' (read-only)."
  (should-error (map-put! (selected-window) 'buffer (current-buffer))
                :type 'user-error))

(ert-deftest map-extras-frame-put-errors ()
  "`map-put!' on a frame signals `user-error' (read-only)."
  (should-error (map-put! (selected-frame) 'name "x")
                :type 'user-error))

(ert-deftest map-extras-thread-put-errors ()
  "`map-put!' on a thread signals `user-error' (read-only)."
  (should-error (map-put! (car (all-threads)) 'name "x")
                :type 'user-error))

(ert-deftest map-extras-marker-put-errors ()
  "`map-put!' on a marker signals `user-error' (read-only)."
  (should-error (map-put! (point-marker) 'position 1)
                :type 'user-error))

;;; Thread maps

(ert-deftest map-extras-mapp-thread ()
  "`mapp' recognizes threads."
  (should (mapp (car (all-threads)))))

(ert-deftest map-extras-thread-elt ()
  "`map-elt' reads thread name and liveness."
  (let ((thread (make-thread #'ignore "map-extras-thread")))
    (should (equal (map-elt thread 'name) "map-extras-thread"))
    (should (eq (map-elt thread 'nonexistent :sentinel) :sentinel)))
  ;; The main thread has no name.
  (should (eq (map-elt (car (all-threads)) 'live) t))
  (should (eq (map-elt (car (all-threads)) 'nonexistent :sentinel) :sentinel)))

(ert-deftest map-extras-thread-do-keys ()
  "`map-do' visits every thread key."
  (let (keys)
    (map-do (lambda (k _v) (push k keys)) (car (all-threads)))
    (should (equal keys '(live name)))))

;;; Frame maps

(ert-deftest map-extras-mapp-frame ()
  "`mapp' recognizes frames."
  (should (mapp (selected-frame))))

(ert-deftest map-extras-frame-elt ()
  "`map-elt' reads cheap frame attributes."
  (let ((frame (selected-frame)))
    (should (stringp (map-elt frame 'name)))
    (should (integerp (map-elt frame 'width)))
    (should (integerp (map-elt frame 'height)))
    (should (eq (map-elt frame 'selected) t))
    (should (eq (map-elt frame 'nonexistent :sentinel) :sentinel))))

(ert-deftest map-extras-frame-do-skips-expensive-keys ()
  "`map-do' on a frame never hits the window-system-only accessors."
  (let ((frame (selected-frame)))
    (cl-letf (((symbol-function 'frame-position)
               (lambda (&optional _frame) (error "frame-position must not be called")))
              ((symbol-function 'frame-monitor-attributes)
               (lambda (&optional _frame) (error "frame-monitor-attributes must not be called")))
              ((symbol-function 'frame-pixel-width)
               (lambda (&optional _frame) (error "frame-pixel-width must not be called")))
              ((symbol-function 'frame-pixel-height)
               (lambda (&optional _frame) (error "frame-pixel-height must not be called"))))
      (should (stringp (map-elt frame 'name)))
      (should (integerp (map-elt frame 'width)))
      (should-not (memq 'parameters
                        (let (keys)
                          (map-do (lambda (k _v) (push k keys)) frame)
                          keys))))))

;;; Overlay maps

(ert-deftest map-extras-mapp-overlay ()
  "`mapp' recognizes overlays."
  (with-temp-buffer
    (should (mapp (make-overlay 1 2 (current-buffer))))))

(ert-deftest map-extras-overlay-elt ()
  "`map-elt' reads overlay bounds and buffer."
  (with-temp-buffer
    (insert "0123456789")
    (let ((ov (make-overlay 2 5 (current-buffer))))
      (should (= (map-elt ov 'start) 2))
      (should (= (map-elt ov 'end) 5))
      (should (eq (map-elt ov 'buffer) (current-buffer))))))

(ert-deftest map-extras-overlay-put-bounds ()
  "`map-put!' moves overlay bounds and switches buffers."
  (with-temp-buffer
    (insert "0123456789")
    (let ((ov (make-overlay 2 5 (current-buffer))))
      (map-put! ov 'start 1)
      (should (= (overlay-start ov) 1))
      (map-put! ov 'end 8)
      (should (= (overlay-end ov) 8))
      (let ((other (generate-new-buffer "map-extras-ov-dest")))
        (map-put! ov 'buffer other)
        (should (eq (overlay-buffer ov) other))
        (kill-buffer other)))))

(ert-deftest map-extras-overlay-put-properties ()
  "`map-put!' with a non-structural key sets an overlay property."
  (with-temp-buffer
    (let ((ov (make-overlay 1 2 (current-buffer))))
      (map-put! ov 'face 'bold)
      (should (eq (overlay-get ov 'face) 'bold)))))

;;; Process maps

(ert-deftest map-extras-process-elt ()
  "`map-elt' reads process name and command."
  (let ((proc (start-process "map-extras-proc" nil "true")))
    (unwind-protect
        (progn
          (should (equal (map-elt proc 'name) "map-extras-proc"))
          (should (equal (map-elt proc 'command) '("true")))
          (should (symbolp (map-elt proc 'status))))
      (delete-process proc))))

(ert-deftest map-extras-buffer-put-unknown-key-errors ()
  "`map-put!' on a buffer rejects unknown keys instead of ignoring them."
  (with-temp-buffer
    (should-error (map-put! (current-buffer) 'bogus 1) :type 'user-error)))

(ert-deftest map-extras-process-put-unknown-key-errors ()
  "`map-put!' on a process rejects unknown keys instead of ignoring them."
  (let ((proc (start-process "map-extras-put-err" nil "true")))
    (unwind-protect
        (should-error (map-put! proc 'bogus 1) :type 'user-error)
      (delete-process proc))))

(ert-deftest map-extras-url-put-unknown-key-errors ()
  "`map-put!' on a url object rejects unknown keys."
  (require 'url-parse)
  (should-error (map-put! (url-generic-parse-url "https://example.com") 'bogus 1)
                :type 'user-error))

;;; Derived map.el operations

(ert-deftest map-extras-map-copy-unsupported ()
  "`map-copy' is intentionally unimplemented for these types:
objects are identities, not snapshots; use `map-pairs' instead."
  (should-error (map-copy (point-marker)) :type 'cl-no-applicable-method)
  (with-temp-buffer
    (should-error (map-copy (current-buffer)) :type 'cl-no-applicable-method)))

(ert-deftest map-extras-map-pairs-snapshot ()
  "`map-pairs' returns an alist snapshot of an object's keys."
  (with-temp-buffer
    (insert "hi")
    (let ((snapshot (map-pairs (current-buffer))))
      (should (consp snapshot))
      (should (assq 'name snapshot))
      (should (= (cdr (assq 'size snapshot)) 2)))))

;;; Derived map.el operations across types

(ert-deftest map-extras-derived-buffer ()
  "Derived map.el functions work over buffers."
  (with-temp-buffer
    (insert "hello")
    (should (= (map-length (current-buffer)) 9))
    (should (equal (map-filter (lambda (k _) (memq k '(name size)))
                               (current-buffer))
                   (list (cons 'name (buffer-name)) '(size . 5))))
    (should (map-contains-key (current-buffer) 'size))
    (should-not (map-contains-key (current-buffer) 'bogus))
    (should (map-every-p (lambda (k _) (symbolp k)) (current-buffer)))
    (should (member 'major-mode (map-keys (current-buffer))))))

(ert-deftest map-extras-derived-marker ()
  "Derived map.el functions work over markers."
  (with-temp-buffer
    (insert "0123456789")
    (goto-char 5)
    (let ((marker (point-marker)))
      (should (equal (map-keys marker) '(position buffer)))
      (should (equal (map-values marker)
                     (list 5 (current-buffer))))
      (should (= (map-length marker) 2)))))

(ert-deftest map-extras-derived-thread ()
  "Derived map.el functions work over threads."
  (let ((thread (make-thread #'ignore "derived-thread")))
    (should (equal (sort (map-keys thread) #'string<)
                   '(live name)))
    (should (map-contains-key thread 'name))
    (should (map-every-p (lambda (_ _) t) thread))))

(ert-deftest map-extras-derived-frame ()
  "Derived map.el functions work over frames."
  (let ((frame (selected-frame)))
    (should (= (map-length frame) 6))
    (should (map-contains-key frame 'selected))
    (should (equal (map-filter (lambda (k _) (eq k 'selected)) frame)
                   (list (cons 'selected t))))))

(ert-deftest map-extras-derived-eieio ()
  "Derived map.el functions work over EIEIO objects."
  (let ((obj (map-extras-tests-person :name "ada" :age 36)))
    (should (= (map-length obj) 2))
    (should (equal (sort (map-keys obj) #'string<) '(age name)))
    (should (equal (map-filter (lambda (_k v) (stringp v)) obj)
                   '((name . "ada"))))))

;;; URL maps

(ert-deftest map-extras-url-elt-and-put ()
  "`map-elt' and `map-put!' work on url objects."
  (require 'url-parse)
  (let ((url (url-generic-parse-url "https://user@example.com:8443/a/b#frag")))
    (should (equal (map-elt url 'type) "https"))
    (should (equal (map-elt url 'user) "user"))
    (should (equal (map-elt url 'host) "example.com"))
    (should (equal (map-elt url 'target) "frag"))
    (should (equal (map-elt url 'portspec) 8443))
    (map-put! url 'host "nagy.example")
    (should (equal (map-elt url 'host) "nagy.example"))))

;;; cl-defstruct macro

(cl-defstruct map-extras-tests-thing alpha beta)

(map-extras-define-for-struct map-extras-tests-thing (alpha beta))

(cl-defstruct map-extras-tests-thing-w alpha beta)
(map-extras-define-for-struct map-extras-tests-thing-w (alpha beta) writable)

(ert-deftest map-extras-struct-mapp ()
  "`map-extras-define-for-struct' defines `mapp'."
  (let ((thing (make-map-extras-tests-thing :alpha 1 :beta 2)))
    (should (mapp thing))))

(ert-deftest map-extras-struct-elt ()
  "`map-extras-define-for-struct' defines `map-elt'."
  (let ((thing (make-map-extras-tests-thing :alpha "a" :beta :b)))
    (should (equal (map-elt thing 'alpha) "a"))
    (should (eq (map-elt thing 'beta) :b))
    (should (eq (map-elt thing 'gamma :dflt) :dflt))))

(ert-deftest map-extras-struct-elt-fast-path ()
  "`map-elt' on a struct reads a slot directly, without the scan."
  (let ((thing (make-map-extras-tests-thing :alpha 1 :beta 2)))
    (cl-letf (((symbol-function 'map-extras--elt)
               (lambda (&rest _) (error "map-extras--elt must not be called"))))
      (should (= (map-elt thing 'alpha) 1))
      (should (= (map-elt thing 'beta) 2)))))

(ert-deftest map-extras-struct-do-keys ()
  "`map-extras-define-for-struct' defines `map-do'."
  (let ((thing (make-map-extras-tests-thing :alpha 1 :beta 2))
        (kv nil))
    (map-do (lambda (k v) (push (cons k v) kv)) thing)
    (should (equal kv '((beta . 2) (alpha . 1))))))

;;; ts maps

(ert-deftest map-extras-ts-put-errors ()
  "`map-put!' on a ts timestamp signals `user-error' (read-only)."
  (require 'ts)
  (should-error (map-put! (ts-parse "2026-01-02 03:04:05") 'year 2000)
                :type 'user-error))

;;; map-extras-transformer

(ert-deftest map-extras-transformer-keys ()
  "`map-extras-transformer' appends the extension to inner keys."
  (let ((transformer
         (map-extras-make-transformer-via-extension
          (list (cons "foo-bar" 1) (cons "foo-baz" 2)) "-bar")))
    (should (equal (map-keys transformer)
                   '("foo-bar-bar" "foo-baz-bar")))))

(ert-deftest map-extras-transformer-elt ()
  "`map-extras-transformer' translates lookup keys via key-from."
  (let ((transformer
         (map-extras-make-transformer-via-extension
          (list (cons "foo-bar" 1)) "-bar")))
    (should (= (map-elt transformer "foo-bar-bar") 1))
    (should (eq (map-elt transformer "nope" :dflt) :dflt))))

(ert-deftest map-extras-transformer-do ()
  "`map-do' over a map-extras-transformer translates keys."
  (let ((transformer
         (map-extras-make-transformer-via-extension
          (list (cons "foo-bar" 1)) "-bar"))
        (kv nil))
    (map-do (lambda (k v) (push (cons k v) kv)) transformer)
    (should (equal kv '(("foo" . 1))))))

(ert-deftest map-extras-transformer-mapp ()
  "`mapp' recognizes map-extras-transformer objects."
  (should (mapp (make-map-extras-transformer
                 :-inner (list (cons "a" 1))
                 :key-from #'identity
                 :key-to #'identity))))

(ert-deftest map-extras-transformer-make ()
  "`make-map-extras-transformer' builds a working transformer."
  (let ((tr (make-map-extras-transformer
             :-inner (list (cons "foo-bar" 1))
             :key-from (lambda (_map key)
                         (if (string-suffix-p "-bar" key)
                             (substring key 0 (- (length key) 4))
                           key))
             :key-to (lambda (_map key) (concat key "-bar")))))
    (should (map-extras-transformer-p tr))
    (should (= (map-elt tr "foo-bar-bar") 1))
    (should (= (map-elt (map-extras--transformer-map tr) "foo-bar") 1))))

;;; Generic EIEIO maps

(defclass map-extras-tests-person ()
  ((name :initarg :name :initform "anon")
   (age :initarg :age :initform 0)
   (--internal :initform nil)))

(ert-deftest map-extras-eieio-mapp ()
  "`mapp' recognizes any EIEIO object."
  (should (mapp (map-extras-tests-person))))

(ert-deftest map-extras-eieio-elt ()
  "`map-elt' reads EIEIO slots; internal and unbound slots are invisible."
  (let ((obj (map-extras-tests-person :name "ada")))
    (should (equal (map-elt obj 'name) "ada"))
    (should (= (map-elt obj 'age) 0))
    (should-not (map-elt obj '--internal))
    (should (eq (map-elt obj 'missing :sentinel) :sentinel))))

(ert-deftest map-extras-eieio-do-keys ()
  "`map-do' visits public bound slots."
  (let (keys)
    (map-do (lambda (k _v) (push k keys)) (map-extras-tests-person))
    (should (equal keys '(age name)))))

(ert-deftest map-extras-eieio-put ()
  "`map-put!' writes EIEIO slots."
  (let ((obj (map-extras-tests-person)))
    (map-put! obj 'name "grace")
    (should (equal (eieio-oref obj 'name) "grace"))
    (should (equal (map-elt obj 'name) "grace"))))

(ert-deftest map-extras-eieio-put-rejects-hidden-and-unknown-slots ()
  "`map-put!' rejects internal `--*' and unknown slot names,
mirroring what `map-do' exposes."
  (let ((obj (map-extras-tests-person)))
    (should-error (map-put! obj '--internal 5) :type 'user-error)
    (should-error (map-put! obj 'no-such-slot 5) :type 'user-error)))

(defclass map-extras-tests-shaped ()
  ((x :initform 1)))
(cl-defmethod map-do (function (_obj map-extras-tests-shaped))
  (funcall function :custom t))

(ert-deftest map-extras-eieio-class-method-wins ()
  "A class-specific map-do beats the generic EIEIO method."
  (let (pairs)
    (map-do (lambda (k v) (push (cons k v) pairs)) (map-extras-tests-shaped))
    (should (equal pairs '((:custom . t))))))

;;; map-put!

(ert-deftest map-extras-struct-writable-put ()
  "`map-extras-define-for-struct :writable' defines `map-put!'."
  (let ((thing (make-map-extras-tests-thing-w :alpha 1 :beta 2)))
    (map-put! thing 'alpha 10)
    (should (= (map-elt thing 'alpha) 10))
    (should-error (map-put! thing 'gamma 3) :type 'user-error)))

(ert-deftest map-extras-struct-read-only-put-errors ()
  "Without :writable, `map-put!' on a struct signals an error."
  (let ((thing (make-map-extras-tests-thing :alpha 1)))
    (should-error (map-put! thing 'alpha 10))))

(ert-deftest map-extras-buffer-put-name ()
  "`map-put!' on buffer name renames the buffer."
  (with-temp-buffer
    (map-put! (current-buffer) 'name "map-extras-renamed")
    (should (equal (buffer-name) "map-extras-renamed"))
    (should (equal (map-elt (current-buffer) 'name)
                   "map-extras-renamed"))))

(ert-deftest map-extras-buffer-put-directory ()
  "`map-put!' on buffer directory changes `default-directory'."
  (with-temp-buffer
    (let ((dir (expand-file-name "/")))
      (map-put! (current-buffer) 'directory dir)
      (should (equal (map-elt (current-buffer) 'directory) dir)))))

(ert-deftest map-extras-process-put-filter-and-sentinel ()
  "`map-put!' installs a process filter and sentinel."
  (let ((proc (start-process "map-extras-put" nil "true")))
    (unwind-protect
        (progn
          (map-put! proc 'filter #'ignore)
          (should (eq (process-filter proc) #'ignore))
          (should (eq (map-elt proc 'filter) #'ignore))
          (map-put! proc 'sentinel #'ignore)
          (should (eq (process-sentinel proc) #'ignore))
          (should (eq (map-elt proc 'sentinel) #'ignore)))
      (delete-process proc))))

(provide 'map-extras-tests)
;;; map-extras-tests.el ends here
