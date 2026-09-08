;;; map-extras.el --- More configuration for built-in map.el -*- lexical-binding: t -*-
;;
;; Copyright (C) 2025 Daniel Nagy
;;
;; Author: Daniel Nagy <https://github.com/nagy>
;; Maintainer: Daniel Nagy <danielnagy@posteo.de>
;; Created: January 31, 2025
;; Version: 0.1
;; Homepage: https://github.com/nagy/emacs-map-extras
;; Package-Requires: ((emacs "27.1") dash eieio)
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
;;  More configuration for built-in map.el .
;;
;;; Code:

(require 'map)

(require 'dash)
(require 'eieio)

(defun map-extras--elt (key map default)
  (catch 'map-extras--found
    (map-do (lambda (k v)
              (when (eq k key)
                (throw 'map-extras--found v)))
            map)
    default))

;;; Buffer

(cl-defmethod mapp ((_map buffer))
  t)

(cl-defmethod map-do (function (map buffer))
  (funcall function 'name (buffer-name map))
  (funcall function 'file-name (buffer-file-name map))
  (funcall function 'point (with-current-buffer map (point)))
  (funcall function 'size (buffer-size map))
  (funcall function 'window (get-buffer-window map t))
  (funcall function 'process (get-buffer-process map))
  (funcall function 'narrowed (with-current-buffer map (buffer-narrowed-p)))
  (funcall function 'directory (buffer-local-value 'default-directory map))
  (funcall function 'major-mode (buffer-local-value 'major-mode map))
  (funcall function 'hash (buffer-hash map)))


(cl-defmethod map-elt ((map buffer) key &optional default)
  (map-extras--elt key map default))

;;; Window

(cl-defmethod mapp ((_map window))
  t)

(cl-defmethod map-do (function (map window))
  (funcall function 'buffer (window-buffer map))
  (funcall function 'left (window-left map))
  (funcall function 'right (window-right map))
  (funcall function 'point (window-point map))
  (funcall function 'parameters (window-parameters map))
  (funcall function 'start (window-start map))
  (funcall function 'end (window-end map)))
;; (funcall function 'display-table (window-display-table map))


(cl-defmethod map-elt ((map window) key &optional default)
  (map-extras--elt key map default))

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
  (funcall function 'attributes (and (process-id map)
                                     (process-attributes (process-id map))))
  (funcall function 'mark (process-mark map)))
;; (funcall function 'environment
;;          (--map (let ((splitted (string-split it "=")))
;;                   (cons (car splitted)
;;                         (substring it (1+ (length (car splitted))))))
;;                 (pcase-buffer--get-environment map))
;;          )


(cl-defmethod map-elt ((map process) key &optional default)
  (map-extras--elt key map default))

;;; Keymaps

;; ...

;;; Marker

(cl-defmethod mapp ((_marker marker))
  t)

(cl-defmethod map-do (function (marker marker))
  (funcall function 'position (marker-position marker))
  (funcall function 'buffer (marker-buffer marker)))


(cl-defmethod map-elt ((marker marker) key &optional default)
  (map-extras--elt key marker default))

;;; URL

(require 'url-parse)

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
;; ...


(cl-defmethod map-elt ((map url) key &optional default)
  (map-extras--elt key map default))

(cl-defmethod map-put! ((map url) key value &optional _testfn)
  (pcase key
    ('type (setf (url-type map) value))
    ('user (setf (url-user map) value))
    ('password (setf (url-password map) value))
    ('host (setf (url-host map) value))
    ('portspec (setf (url-portspec map) value))
    ('filename (setf (url-filename map) value))
    ('target (setf (url-target map) value))
    ('attributes (setf (url-attributes map) value))))


;;; sqlitep
;;; sqlite-statements seq integration

;;; obarray

;; Non-Emacs
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

  (cl-defmethod map-elt ((map ts) key &optional default)
    (map-extras--elt key map default)))

;; macros

(defmacro map-extras-define-for-struct (struct keys)
  "Define `map.el' methods for cl-defstruct STRUCT with slots KEYS.
Each slot must have a STRUCT-<slot> accessor."
  `(progn
     (cl-defmethod mapp ((_map ,struct))
       t)
     (cl-defmethod map-do (function (map ,struct))
       ,@(--map `(funcall function ',it (,(intern (format "%s-%s" struct it)) map))
                keys))
     (cl-defmethod map-elt ((map ,struct) key &optional default)
       (map-extras--elt key map default))))

(cl-defstruct map-transformer -inner key-to key-from)
(defun map-transformer-get-map (map)
  (let ((inner (map-transformer--inner map)))
    (if (symbolp inner)
        (symbol-value inner)
      inner)))
(cl-defmethod mapp ((_map map-transformer))
  t)
(cl-defmethod map-elt ((map map-transformer) key &optional default)
  (map-elt (map-transformer-get-map map)
           (funcall (map-transformer-key-from map) map key)
           default))
(cl-defmethod map-keys ((map map-transformer))
  (mapcar (lambda (key)
            (funcall (map-transformer-key-to map) map key))
          (map-keys (map-transformer-get-map map))))

(cl-defmethod map-do (function (map map-transformer))
  (map-do (lambda (key value)
            (funcall function
                     (funcall (map-transformer-key-from map) map key)
                     value))
          (map-transformer-get-map map)))

(defun make-map-transformer-via-extension (map extension)
  (make-map-transformer
   :-inner map
   :key-from (lambda (_map key)
               (string-remove-suffix extension key))
   :key-to (lambda (_map key)
             (concat key extension))))


;;; seq.el integrations

;; frame -> list of windows
;; `elfeed-feed-p' -> list of `elfeed-feed-entries'

(provide 'map-extras)
;;; map-extras.el ends here
