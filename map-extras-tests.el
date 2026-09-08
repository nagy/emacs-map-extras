;;; map-extras-tests.el --- ERT tests for map-extras.el -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; Code:

(require 'ert)
(require 'map-extras)

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
    (should (equal (map-elt (current-buffer) 'name nil #'equal)
                   (buffer-name)))
    ;; TESTFN comparison runs against the key symbols.
    (let* ((keys nil)
           (seen (map-elt (current-buffer) 'size
                          :sentinel
                          (lambda (k _key)
                            (push k keys) nil))))
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

(ert-deftest map-extras-struct-do-keys ()
  "`map-extras-define-for-struct' defines `map-do'."
  (let ((thing (make-map-extras-tests-thing :alpha 1 :beta 2))
        (kv nil))
    (map-do (lambda (k v) (push (cons k v) kv)) thing)
    (should (equal kv '((beta . 2) (alpha . 1))))))

;;; map-transformer

(ert-deftest map-extras-transformer-keys ()
  "`map-transformer' appends the extension to inner keys."
  (let ((transformer
         (make-map-transformer-via-extension
          (list (cons "foo-bar" 1) (cons "foo-baz" 2)) "-bar")))
    (should (equal (map-keys transformer)
                   '("foo-bar-bar" "foo-baz-bar")))))

(ert-deftest map-extras-transformer-elt ()
  "`map-transformer' translates lookup keys via key-from."
  (let ((transformer
         (make-map-transformer-via-extension
          (list (cons "foo-bar" 1)) "-bar")))
    (should (= (map-elt transformer "foo-bar-bar") 1))
    (should (eq (map-elt transformer "nope" :dflt) :dflt))))

(ert-deftest map-extras-transformer-do ()
  "`map-do' over a map-transformer translates keys."
  (let ((transformer
         (make-map-transformer-via-extension
          (list (cons "foo-bar" 1)) "-bar"))
        (kv nil))
    (map-do (lambda (k v) (push (cons k v) kv)) transformer)
    (should (equal kv '(("foo" . 1))))))

(ert-deftest map-extras-transformer-mapp ()
  "`mapp' recognizes map-transformer objects."
  (should (mapp (make-map-transformer :-inner (list (cons "a" 1))
                                       :key-from #'identity
                                       :key-to #'identity))))

;;; map-put!

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
