;;; latexdiff.el --- Latexdiff integration in Emacs

;; Copyright (C) 2016-2017 Launay Gaby

;; Author: Launay Gaby <gaby.launay@tutanota.com>
;; Maintainer: Launay Gaby <gaby.launay@tutanota.com>
;; Version: 0.1.0
;; Keywords: latex, diff
;; URL: http://github.com/galaunay/emacs-latexdiff

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; See README.md

;;; Code:

(require 'vc-git)
(require 'subr-x)
(require 'f)


;; Faces and variables
;;;;;;;;;;;;;;;;;;;;;;;;

(defcustom latexdiff-args
  "--force --pdf"
  "Argument passed to 'latexdiff' (modify at your own risk).

You may want to add '--flatten' if you have project with
multiple files."
  :type 'string
  :group 'latexdiff)

(defcustom latexdiff-vc-args
  "--force --pdf"
  "Argument passed to 'latexdiff-vc' (modify at your own risk).

You may want to add '--flatten' if you have project with
multiple files."
  :type 'string
  :group 'latexdiff)

(defcustom latexdiff-auto-display-pdf
  t
  "If set to `t`, generated diff pdf are automatically displayed after generation."
  :type 'boolean
  :group 'latexdiff)

(defcustom latexdiff-auto-clean-aux
  t
  "If set to `t`, automatically clean the auxilliary files (.aux, .log, ...)
after generating the diff pdf.

Warning: file removal is based on regular expressions and could possibly
remove files that you want to keep."
  :type 'boolean
  :group 'latexdiff)

(defcustom latexdiff-pdf-viewer
  "Emacs"
  "Command use to view PDF diffs.

If set to 'Emacs', open the PDF within Emacs."
  :type 'string
  :group 'latexdiff)

(defvar-local latexdiff-runningp nil
  "t when a latexdiff process is running for the current buffer")

(defface latexdiff-ref-labels-face
  '((t (:inherit helm-grep-match)))
  "Face for the ref-labels"
  :group 'latexdiff)

(when (featurep 'helm)
  (defface helm-latexdiff-date-face
    '((t (:inherit helm-prefarg)))
    "Face for the date"
    :group 'latexdiff)

  (defface helm-latexdiff-author-face
    '((t (:inherit helm-ff-file)))
    "Face for the author"
    :group 'latexdiff)

  (defface helm-latexdiff-message-face
    '((t (:inherit default)))
    "Face for the message"
    :group 'latexdiff))

(defgroup latexdiff nil
  "latexdiff integration in Emacs."
  :prefix "latexdiff-"
  :group 'convenience
  :link `(url-link :tag "latexdiff homepage" "https://github.com/muahah/emacs-latexdiff"))


;; Internal functions
;;;;;;;;;;;;;;;;;;;;;;;

(defun latexdiff--check-if-installed ()
  "Check if latexdiff is installed."
  (with-temp-buffer
    (call-process "/bin/bash" nil t nil "-c"
                  "hash latexdiff-vc 2>/dev/null || echo 'NOT INSTALLED'")
    (goto-char (point-min))
    (if (re-search-forward "NOT INSTALLED" (point-max) t)
        (error "'latexdiff' is not installed, please install it"))))

(defun latexdiff--check-if-pdf-produced (diff-file)
  "Check if DIFF-FILE has been produced."
  (let ((size (car (last (file-attributes diff-file) 5))))
    (not (or (eq size 0) (not (file-exists-p diff-file))))))

(defun latexdiff-vc--latexdiff-sentinel (proc msg)
  "Sentinel for latexdiff executions.

PROC is the process to watch and MSG the message to
display when the process ends"
  (setq latexdiff-runningp t)
  (let ((diff-file (process-get proc 'diff-file))
        (file (process-get proc 'file))
        (REV1 (process-get proc 'rev1))
        (REV2 (process-get proc 'rev2)))
    (kill-buffer " *latexdiff*")
    ;; Clean if asked
    (when latexdiff-auto-clean-aux
      (call-process "/bin/bash" nil 0 nil "-c"
                    (format "GLOBIGNORE='*.pdf' ; rm -r %s* ; GLOBIGNORE='' ;" diff-file)))
    ;; Check if pdf has been produced
    (if (not (latexdiff--check-if-pdf-produced (format "%s.pdf" diff-file)))
        (progn
          (find-file-noselect "latexdiff.log")
          (with-current-buffer (get-buffer-create "*latexdiff-log*")
            (erase-buffer)
            (insert-buffer-substring "latexdiff.log"))
          (kill-buffer "latexdiff.log")
          (message "[%s] PDF file has not been produced, check `%s' buffer for more informations" file "*latexdiff-log*"))
      ;; Display the pdf if asked
      (when latexdiff-auto-display-pdf
        (message "[%s] Displaying PDF diff between %s and %s" file REV1 REV2)
        (if (string= latexdiff-pdf-viewer "Emacs")
            (find-file (format "%s.pdf" diff-file))
          (call-process "/bin/bash" nil 0 nil "-c"
                        (format "%s %s.pdf" latexdiff-pdf-viewer diff-file))))))
  (setq latexdiff-runningp nil))

(defun latexdiff--latexdiff-sentinel (proc msg)
  "Sentinel for latexdiff executions.

PROC is the process to watch and MSG the message to
display when the process ends"
  (let* ((diff-file (process-get proc 'diff-file))
         (file1 (process-get proc 'file1))
         (file2 (process-get proc 'file2))
         (dir2 (f-dirname file2))
         (filename1 (file-name-nondirectory (file-name-sans-extension file1)))
         (filename2 (file-name-nondirectory (file-name-sans-extension file2))))
    (kill-buffer " *latexdiff*")
    ;; Clean if asked
    (when latexdiff-auto-clean-aux
      (call-process "/bin/bash" nil 0 nil "-c"
                    (format "GLOBIGNORE='*.pdf' ; cd %s ; rm -r %s.{aux,out,tex} ; GLOBIGNORE='' ;" dir2 diff-file)))
    ;; Check if pdf has been produced
    (if (not (latexdiff--check-if-pdf-produced (format "%s.pdf" diff-file)))
        (progn
          (find-file-noselect "latexdiff.log")
          (with-current-buffer (get-buffer-create "*latexdiff-log*")
            (erase-buffer)
            (insert-buffer-substring "latexdiff.log"))
          (kill-buffer "latexdiff.log")
          (message "[%s] PDF file has not been produced, check `%s' buffer for more informations" filename1 "*latexdiff-log*"))
      ;; Display the pdf if asked
      (when latexdiff-auto-display-pdf
        (message "[%s] Displaying PDF diff with %s" filename1 filename2)
        (if (string= latexdiff-pdf-viewer "Emacs")
            (find-file (format "%s.pdf" diff-file))
          (call-process "/bin/bash" nil 0 nil "-c"
                        (format "%s %s.pdf" latexdiff-pdf-viewer diff-file))))))
  (setq latexdiff-runningp nil))

(defun latexdiff--compile-diff (file1 file2)
  "Use latexdiff to compile a pdf diff between FILE1 and FILE2.

Return the diff file name"
  (let* ((dir1 (f-dirname file1))
         (dir2 (f-dirname file2))
         (filename1 (file-name-nondirectory (file-name-sans-extension file1)))
         (filename2 (file-name-nondirectory (file-name-sans-extension file2)))
         (diff-dir dir2)
         (diff-file (format "%s-diff" (concat (file-name-as-directory diff-dir) filename2)))
         (process nil))
    (latexdiff--check-if-installed)
    (message "[%s] Generating latex diff with %s" filename1 filename2)
    (setq process (start-process "latexdiff" " *latexdiff*"
                                 "/bin/bash" "-c"
                                 (format "cd %s; rm -r latexdiff.log ; yes X | latexdiff-vc %s %s %s &> latexdiff.log ;" dir2 latexdiff-args file1 file2)))
    (setq latexdiff-runningp t)
    (process-put process 'diff-file diff-file)
    (process-put process 'file1 file1)
    (process-put process 'file2 file2)
    (set-process-sentinel process 'latexdiff--latexdiff-sentinel)
    diff-file))

(defun latexdiff-vc--compile-diff (REV1 REV2)
  "Use latexdiff to compile a pdf file of the difference between REV1 and REV2."
  (let* ((file (file-name-base))
         (diff-file (format "%s-diff%s-%s" file REV1 REV2))
         (process nil))
    (latexdiff--check-if-installed)
    (message "[%s] Generating latex diff between %s and %s" file REV1 REV2)
    (setq process (start-process "latexdiff" " *latexdiff*"
                                 "/bin/bash" "-c"
                                 (format "rm -r latexdiff.log ; yes X | latexdiff-vc %s -r %s -r %s %s.tex &> latexdiff.log ;" latexdiff-vc-args REV1 REV2 file)))
    (process-put process 'diff-file diff-file)
    (process-put process 'file file)
    (process-put process 'rev1 REV1)
    (process-put process 'rev2 REV2)
    (setq latexdiff-runningp t)
    (set-process-sentinel process 'latexdiff-vc--latexdiff-sentinel)
    diff-file))

(defun latexdiff-vc--compile-diff-with-current (REV)
  "Use latexdiff to compile a pdf file of the difference between the current state and REV."
  (let* ((file (file-name-base))
         (diff-file (format "%s-diff%s" file REV))
         (process nil))
    (latexdiff--check-if-installed)
    (message "[%s] Generating latex diff with %s" file REV)
    (let* ((command (format "rm -r latexdiff.log ; yes X | latexdiff-vc %s -r %s %s.tex &> latexdiff.log ;" latexdiff-vc-args REV file))
           (process (start-process "latexdiff" " *latexdiff*" "/bin/bash" "-c" command)))
      (process-put process 'diff-file diff-file)
      (process-put process 'file file)
      (process-put process 'rev1 "current")
      (process-put process 'rev2 REV)
      (setq latexdiff-runningp t)
      (set-process-sentinel process 'latexdiff-vc--latexdiff-sentinel))
    diff-file))

(defun latexdiff--get-commits-infos ()
  "Return a list with all commits informations."
  (let ((infos nil))
    (with-temp-buffer
      (vc-git-command t nil nil "log" "--format=%h---%cr---%cn---%s---%d" "--abbrev-commit" "--date=short")
      (goto-char (point-min))
      (while (re-search-forward "^.+$" nil t)
        (push (split-string (match-string 0) "---") infos)))
    infos))

(defun latexdiff--get-commits-description ()
  "Return a list of commits description strings."
  (let ((descriptions ())
        (infos (latexdiff--get-commits-infos))
        (tmp-desc nil)
        (lengths '((l1 . 0) (l2 . 0) (l3 . 0) (l4 . 0))))
    ;; Get lengths
    (dolist (tmp-desc infos)
      (pop tmp-desc)
      (when (> (length (nth 0 tmp-desc)) (cdr (assoc 'l1 lengths)))
        (add-to-list 'lengths `(l1 . ,(length (nth 0 tmp-desc)))))
      (when (> (length (nth 1 tmp-desc)) (cdr (assoc 'l2 lengths)))
        (add-to-list 'lengths `(l2 . ,(length (nth 1 tmp-desc)))))
      (when (> (length (nth 2 tmp-desc)) (cdr (assoc 'l3 lengths)))
        (add-to-list 'lengths `(l3 . ,(length (nth 2 tmp-desc)))))
      (when (> (length (nth 3 tmp-desc)) (cdr (assoc 'l4 lengths)))
        (add-to-list 'lengths `(l4 . ,(length (nth 3 tmp-desc))))))
    ;; Get infos
    (dolist (tmp-desc infos)
      (pop tmp-desc)
      (push (string-join
             (list
              (propertize (format
                           (format "%%-%ds "
                                   (cdr (assoc 'l2 lengths)))
                           (nth 1 tmp-desc))
                          'face 'latexdiff-author-face)
              (propertize (format
                           (format "%%-%ds "
                                   (cdr (assoc 'l1 lengths)))
                           (nth 0 tmp-desc))
                          'face 'latexdiff-date-face)
              (propertize (format "%s"
                                  (nth 3 tmp-desc))
                          'face 'latexdiff-ref-labels-face)
              (propertize (format "%s"
                                  (nth 2 tmp-desc))
                          'face 'latexdiff-message-face))
             " ")
            descriptions))
    descriptions))

(defun latexdiff--get-commits-hashes ()
  "Return the list of commits hashes."
  (let ((hashes ())
        (infos (latexdiff--get-commits-infos))
        (tmp-desc nil))
    (dolist (tmp-desc infos)
      (push (pop tmp-desc) hashes))
    hashes))

(defun latexdiff--update-commits ()
  "Return the alist of (HASH . COMMITS-DESCRIPTION)."
  (let ((descr (latexdiff--get-commits-description))
        (hash (latexdiff--get-commits-hashes))
        (list ()))
    (while (not (equal (length descr) 0))
      (setq list (cons (cons (pop descr) (pop hash)) list)))
    (reverse list)))


;; User function
;;;;;;;;;;;;;;;;;;

(defun latexdiff-clean (&optional file)
  "Remove all files generated by latexdiff.

If FILE is specified, delete all files generated from FILE,
else, delete all files gernated by the current buffer.

Warning: file removal is based on regular expressions,
and could possibly remove some file you want to keep."
  (interactive)
  (if (and (not file)
           (not (buffer-file-name (current-buffer))))
      (error "Not FILE specified and current buffer has no associated file"))
  (let ((filename (if file (file-name-base file)
                    (file-name-base)))
        (dir (if file (file-name-directory file)
               (file-name-directory (buffer-file-name)))))
    (call-process "/bin/bash" nil 0 nil "-c"
                  (format "cd %s ;
                           rm -f %s-diff* ;
                           rm -f %s-oldtmp* ;
                           rm -f latexdiff.log"
                          dir filename filename))
    (message "[%s] Removed latexdiff generated files" filename)))

(defun latexdiff ()
  "Ask for two tex files and make the difference between them."
  (interactive)
  (let ((file1 (read-file-name "Base file: " nil nil t nil))
        (file2 (read-file-name "Base file: " nil nil t nil)))
    (latexdiff--compile-diff file1 file2)))

(defun latexdiff-vc ()
  "Ask for a commit and make the difference with the current version."
  (interactive)
  (latexdiff--check-if-installed)
  (let* ((commits (latexdiff--update-commits))
         (commit (completing-read "Choose a commit:" commits))
         (commit-hash (cdr (assoc commit commits))))
    (latexdiff-vc--compile-diff-with-current commit-hash)))


;; Helm
;;;;;;;;;

(when (featurep 'helm)

  (defun helm-latexdiff-vc ()
    "Ask for a commit and make the difference with the current version."
    (interactive)
    (latexdiff--check-if-installed)
    (helm :sources 'helm-source-latexdiff-choose-commit
          :buffer "*latexdiff*"
          :nomark t
          :prompt "Choose a commit: "))

  (defvar helm-source-latexdiff-choose-commit
    (helm-build-sync-source "Latexdiff choose commit"
      :candidates 'latexdiff--update-commits
      ;; :mode-line helm-read-file-name-mode-line-string
      :action '(("Choose this commit" . latexdiff-vc--compile-diff-with-current)))
    "Helm source for modified projectile projects.")

  (defun helm-latexdiff-vc-range ()
    "Ask for two commits and make the difference between them."
    (interactive)
    (latexdiff--check-if-installed)
    (let* ((commits (latexdiff--update-commits))
           (rev1 (helm-comp-read "Base commit: " commits))
           (rev2 (helm-comp-read "Revised commit: " commits)))
      (latexdiff-vc--compile-diff rev1 rev2)))

  (defun latexdiff-vc-range ()
    "Ask for two commits and make the difference between them."
    (interactive)
    (latexdiff--check-if-installed)
    (let* ((commits (latexdiff--update-commits))
           (commit1 (completing-read "Base commit:" commits))
           (commit1-hash (cdr (assoc commit1 commits)))
           (commit2 (completing-read "Revised commit:" commits))
           (commit2-hash (cdr (assoc commit2 commits))))
      (latexdiff-vc--compile-diff commit1-hash commit2-hash)))
  )

(provide 'latexdiff)
;;; latexdiff.el ends here
