;;; mime.el --- MIME library module

;; Copyright (C) 1998 Free Software Foundation, Inc.

;; Author: MORIOKA Tomohiko <morioka@jaist.ac.jp>
;; Keywords: MIME, multimedia, mail, news

;; This file is part of FLIM (Faithful Library about Internet Message).

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Code:

(require 'alist)
(require 'std11)
(require 'mime-def)
(require 'eword-decode)

(autoload 'eword-encode-field "eword-encode"
  "Encode header field STRING, and return the result.")
(autoload 'eword-encode-header "eword-encode"
  "Encode header fields to network representation, such as MIME encoded-word.")


(autoload 'mime-parse-Content-Type "mime-parse"
  "Parse STRING as field-body of Content-Type field.")
(autoload 'mime-read-Content-Type "mime-parse"
  "Read field-body of Content-Type field from current-buffer,
and return parsed it.")

(autoload 'mime-parse-Content-Disposition "mime-parse"
  "Parse STRING as field-body of Content-Disposition field.")
(autoload 'mime-read-Content-Disposition "mime-parse"
  "Read field-body of Content-Disposition field from current-buffer,
and return parsed it.")

(autoload 'mime-parse-Content-Transfer-Encoding "mime-parse"
  "Parse STRING as field-body of Content-Transfer-Encoding field.")
(autoload 'mime-read-Content-Transfer-Encoding "mime-parse"
  "Read field-body of Content-Transfer-Encoding field from
current-buffer, and return it.")

(autoload 'mime-parse-message "mime-parse"
  "Parse current-buffer as a MIME message.")

(autoload 'mime-parse-buffer "mime-parse"
  "Parse BUFFER as a MIME message.")


;;; @ Entity as node of message
;;;

(defun mime-find-entity-from-number (entity-number &optional message)
  "Return entity from ENTITY-NUMBER in MESSAGE.
If MESSAGE is not specified, `mime-message-structure' is used."
  (or message
      (setq message mime-message-structure))
  (let ((sn (car entity-number)))
    (if (null sn)
	message
      (let ((rc (nth sn (mime-entity-children message))))
	(if rc
	    (mime-find-entity-from-number (cdr entity-number) rc)
	  ))
      )))

(defsubst mime-find-entity-from-node-id (entity-node-id &optional message)
  "Return entity from ENTITY-NODE-ID in MESSAGE.
If MESSAGE is not specified, `mime-message-structure' is used."
  (mime-find-entity-from-number (reverse entity-node-id) message))

(defsubst mime-entity-parent (entity &optional message)
  "Return mother entity of ENTITY.
If MESSAGE is not specified, `mime-message-structure' in the buffer of
ENTITY is used."
  (mime-find-entity-from-node-id
   (cdr (mime-entity-node-id entity))
   (or message
       (save-excursion
	 (set-buffer (mime-entity-buffer entity))
	 mime-message-structure))))

(defsubst mime-root-entity-p (entity)
  "Return t if ENTITY is root-entity (message)."
  (null (mime-entity-node-id entity)))


;;; @ Entity Header
;;;

(defun mime-fetch-field (field-name &optional entity)
  (or (symbolp field-name)
      (setq field-name (intern (capitalize (capitalize field-name)))))
  (or entity
      (setq entity mime-message-structure))
  (let* ((header (mime-entity-original-header entity))
	 (field-body (cdr (assq field-name header))))
    (or field-body
	(progn
	  (if (save-excursion
		(set-buffer (mime-entity-buffer entity))
		(save-restriction
		  (narrow-to-region (mime-entity-header-start entity)
				    (mime-entity-header-end entity))
		  (setq field-body
			(std11-fetch-field (symbol-name field-name)))
		  ))
	      (mime-entity-set-original-header
	       entity (put-alist field-name field-body header))
	    )
	  field-body))))

(defun mime-read-field (field-name &optional entity)
  (or (symbolp field-name)
      (setq field-name (capitalize (capitalize field-name))))
  (or entity
      (setq entity mime-message-structure))
  (cond ((eq field-name 'Content-Type)
	 (mime-entity-content-type entity)
	 )
	((eq field-name 'Content-Disposition)
	 (mime-entity-content-disposition entity)
	 )
	((eq field-name 'Content-Transfer-Encoding)
	 (mime-entity-encoding entity)
	 )
	(t
	 (let* ((header (mime-entity-parsed-header entity))
		(field (cdr (assq field-name header))))
	   (or field
	       (let ((field-body (mime-fetch-field field-name entity)))
		 (when field-body
		   (cond ((memq field-name '(From Resent-From
					     To Resent-To
					     Cc Resent-Cc
					     Bcc Resent-Bcc
					     Reply-To Resent-Reply-To))
			  (setq field (std11-parse-addresses
				       (eword-lexical-analyze field-body)))
			  )
			 ((memq field-name '(Sender Resent-Sender))
			  (setq field (std11-parse-address
				       (eword-lexical-analyze field-body)))
			  )
			 ((memq field-name eword-decode-ignored-field-list)
			  (setq field field-body))
			 ((memq field-name eword-decode-structured-field-list)
			  (setq field (eword-decode-structured-field-body
				       field-body)))
			 (t
			  (setq field (eword-decode-unstructured-field-body
				       field-body))
			  ))
		   (mime-entity-set-parsed-header
		    entity (put-alist field-name field header))
		   field)))))))


;;; @ Entity Content
;;;

(defun mime-entity-content (entity)
  (save-excursion
    (set-buffer (mime-entity-buffer entity))
    (mime-decode-string (buffer-substring (mime-entity-body-start entity)
					  (mime-entity-body-end entity))
			(mime-entity-encoding entity))))


;;; @ Another Entity Information
;;;

(defun mime-entity-uu-filename (entity)
  (if (member (mime-entity-encoding entity) mime-uuencode-encoding-name-list)
      (save-excursion
	(set-buffer (mime-entity-buffer entity))
	(goto-char (mime-entity-body-start entity))
	(if (re-search-forward "^begin [0-9]+ "
			       (mime-entity-body-end entity) t)
	    (if (looking-at ".+$")
		(buffer-substring (match-beginning 0)(match-end 0))
	      )))))

(defun mime-entity-filename (entity)
  "Return filename of ENTITY."
  (or (mime-entity-uu-filename entity)
      (mime-content-disposition-filename
       (mime-entity-content-disposition entity))
      (cdr (let ((param (mime-content-type-parameters
			 (mime-entity-content-type entity))))
	     (or (assoc "name" param)
		 (assoc "x-name" param))
	     ))))


;;; @ end
;;;

(provide 'mime)

;;; mime.el ends here
