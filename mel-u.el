;;; mel-u.el: uuencode encoder/decoder for GNU Emacs

;; Copyright (C) 1995,1996,1997,1998 Free Software Foundation, Inc.

;; Author: MORIOKA Tomohiko <morioka@jaist.ac.jp>
;; Created: 1995/10/25
;; Keywords: uuencode

;; This file is part of MEL (MIME Encoding Library).

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

(require 'emu)
(require 'mime-def)


;;; @ variables
;;;

(defvar uuencode-external-encoder '("uuencode" "-")
  "*list of uuencode encoder program name and its arguments.")

(defvar uuencode-external-decoder '("sh" "-c" "uudecode")
  "*list of uuencode decoder program name and its arguments.")


;;; @ uuencode encoder/decoder for region
;;;

(defun uuencode-external-encode-region (start end)
  "Encode current region by unofficial uuencode format.
This function uses external uuencode encoder which is specified by
variable `uuencode-external-encoder'."
  (interactive "*r")
  (save-excursion
    (as-binary-process (apply (function call-process-region)
			      start end (car uuencode-external-encoder)
			      t t nil (cdr uuencode-external-encoder))
		       )
    ;; for OS/2
    ;;   regularize line break code
    (goto-char (point-min))
    (while (re-search-forward "\r$" nil t)
      (replace-match "")
      )
    ))

(defun uuencode-external-decode-region (start end)
  "Decode current region by unofficial uuencode format.
This function uses external uuencode decoder which is specified by
variable `uuencode-external-decoder'."
  (interactive "*r")
  (save-excursion
    (let ((filename (save-excursion
		      (save-restriction
			(narrow-to-region start end)
			(goto-char start)
			(if (re-search-forward "^begin [0-9]+ " nil t)
			    (if (looking-at ".+$")
				(buffer-substring (match-beginning 0)
						  (match-end 0))
			      )))))
	  (default-directory mime-temp-directory))
      (if filename
	  (as-binary-process
	   (apply (function call-process-region)
		  start end (car uuencode-external-decoder)
		  t nil nil (cdr uuencode-external-decoder))
	   (as-binary-input-file (insert-file-contents filename))
	   ;; The previous line causes the buffer to be made read-only, I
	   ;; do not pretend to understand the control flow leading to this
	   ;; but suspect it has something to do with image-mode. -slb
	   ;;	Use `inhibit-read-only' to avoid to force
	   ;;	buffer-read-only nil. - tomo.
	   (let ((inhibit-read-only t))
	     (delete-file filename)
	     )
	   ))
      )))

(defalias 'uuencode-encode-region 'uuencode-external-encode-region)
(defalias 'uuencode-decode-region 'uuencode-external-decode-region)


;;; @ uuencode encoder/decoder for file
;;;

(defun uuencode-insert-encoded-file (filename)
  "Insert file encoded by unofficial uuencode format.
This function uses external uuencode encoder which is specified by
variable `uuencode-external-encoder'."
  (interactive (list (read-file-name "Insert encoded file: ")))
  (call-process (car uuencode-external-encoder) filename t nil
		(file-name-nondirectory filename))
  )

(defun uuencode-write-decoded-region (start end filename)
  "Decode and write current region encoded by uuencode into FILENAME.
START and END are buffer positions."
  (interactive
   (list (region-beginning) (region-end)
	 (read-file-name "Write decoded region to file: ")))
  (save-excursion
    (let ((file (save-excursion
		  (save-restriction
		    (narrow-to-region start end)
		    (goto-char start)
		    (if (re-search-forward "^begin [0-9]+ " nil t)
			(if (looking-at ".+$")
			    (buffer-substring (match-beginning 0)
					      (match-end 0))
			  )))))
	  (default-directory mime-temp-directory))
      (if file
	  (as-binary-process
	   (apply (function call-process-region)
		  start end (car uuencode-external-decoder)
		  nil nil nil (cdr uuencode-external-decoder))
	   (rename-file file filename 'overwrites)
	   )))))


;;; @ end
;;;

(provide 'mel-u)

;;; mel-u.el ends here
