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

;;; Marker maps

(ert-deftest map-extras-marker-elt ()
  "`map-elt' reads marker position and buffer."
  (with-temp-buffer
    (insert "0123456789")
    (goto-char 5)
    (let ((marker (point-marker)))
      (should (= (map-elt marker 'position) 5))
      (should (eq (map-elt marker 'buffer) (current-buffer))))))

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

(provide 'map-extras-tests)
;;; map-extras-tests.el ends here
