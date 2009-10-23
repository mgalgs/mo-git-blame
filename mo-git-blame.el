;;; mo-git-blame -- An interactive, interative 'git blame' mode for Emacs

;; Copyright (C) 2009  Moritz Bunkus <moritz@bunkus.org>
;;
;; mo-git-blame is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or (at
;; your option) any later version.
;;
;; mo-git-blame is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Installation:
;;;
;;; Put this file somewhere in your load-path or add the directory it
;;; is in to it, e.g.:
;;;
;;; (add-to-list 'load-path "~/.emacs.d/mo-git-blame")
;;;
;;; Then add two autoload definitions:
;;;
;;; (autoload 'mo-git-blame-file "mo-git-blame" nil t)
;;; (autoload 'mo-git-blame-current "mo-git-blame" nil t)

(require 'easymenu)

(defvar mo-git-blame-vars nil
  "Buffer-local plist that stores various variables needed for
interactive use, e.g. the file name, current revision etc.")

(defvar mo-git-blame-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    (define-key map (kbd "b") 'mo-git-blame-reblame-for-revision-at)
    (define-key map (kbd "c") 'mo-git-blame-content-for-revision-at)
    (define-key map (kbd "l") 'mo-git-blame-log-for-revision-at)
    (define-key map (kbd "L") 'mo-git-blame-log-for-current-revision)
    (define-key map (kbd "o") 'mo-git-blame-overwrite-file-with-revision-at)
    (define-key map (kbd "O") 'mo-git-blame-overwrite-file-with-current-revision)
    (define-key map (kbd "q") 'mo-git-blame-quit)
    (define-key map (kbd "s") 'mo-git-blame-show-revision-at)
    (define-key map (kbd "S") 'mo-git-blame-show-current-revision)
    (define-key map (kbd "RET") 'mo-git-blame-show-revision-at)
    (define-key map (kbd "TAB") 'mo-git-blame-display-content-buffer)
    (define-key map [?\C-x ?k] 'mo-git-blame-quit)
    (define-key map [?\C-x ?\C-l] 'mo-git-blame-goto-line)
    map)
  "The mode map for the blame output window of mo-git-blame-mode.")

(defvar mo-git-blame-content-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    (define-key map (kbd "q") 'mo-git-blame-quit)
    (define-key map [?\C-x ?k] 'mo-git-blame-quit)
    (define-key map [?\C-x ?\C-l] 'mo-git-blame-goto-line)
    map)
  "The mode map for the content window of mo-git-blame-mode.")

(easy-menu-define mo-git-blame-mode-menu mo-git-blame-mode-map
  "MoGitBlame menu"
  '("MoGitBlame"
    ["Re-blame for revision at point" mo-git-blame-reblame-for-revision-at t]
    ["Raw content for revision at point" mo-git-blame-content-for-revision-at t]
    ["Log for revision at point" mo-git-blame-log-for-revision-at t]
    ["Overwrite file with revision at point" mo-git-blame-overwrite-file-with-revision-at t]
    ["'git show' for revision at point" mo-git-blame-show-revision-at t]
    "---"
    ["Log for current revision" mo-git-blame-log-for-current-revision t]
    ["Overwrite file with current revision" mo-git-blame-overwrite-file-with-current-revision t]
    ["'git show' for current revision" mo-git-blame-show-current-revision t]
    "---"
    ["Display content buffer" mo-git-blame-display-content-buffer t]
    "---"
    ["Exit MoGitBlame" mo-git-blame-quit t]))

(defgroup mo-git-blame nil
  "Interactively use Git's 'blame' from Emacs."
  :prefix "mo-git-blame-"
  :group 'tools)

(defcustom mo-git-blame-git-executable "git"
  "The name of the Git executable."
  :group 'mo-git-blame
  :type 'string)

(defcustom mo-git-blame-blame-window-width 45
  "The width of the 'blame' window leaving the rest for the
'content' window."
  :group 'mo-git-blame
  :type 'integer)

(defcustom mo-git-blame-use-ido 'if-available
  "Controls whether or not ido will be used. Possible choices:

  `never'        -- do not use ido even if it is loaded
  `if-available' -- use ido if it has been loaded before
  `always'       -- automatically load ido and use it"
  :group 'mo-git-blame
  :type '(choice (const :tag "Always" always)
                 (const :tag "If available" if-available)
                 (const :tag "Never" never)))

;; This function was taken from magit (called 'magit-trim-line' there).
(defun mo-git-blame-trim-line (str)
  (cond ((string= str "")
         nil)
        ((equal (elt str (- (length str) 1)) ?\n)
         (substring str 0 (- (length str) 1)))
        (t str)))

;; This function was taken from magit (called 'magit-git-output' there).
(defun mo-git-blame-git-output (args)
  (with-output-to-string
    (with-current-buffer standard-output
      (apply #'process-file
             mo-git-blame-git-executable
             nil (list t nil) nil
             args))))

;; This function was taken from magit (called 'magit-git-string' there).
(defun mo-git-blame-git-string (&rest args)
  (mo-git-blame-trim-line (mo-git-blame-git-output args)))

(defun mo-git-blame-get-top-dir (cwd)
  (let ((cwd (expand-file-name cwd))
        git-dir)
    (setq git-dir
          (if (file-directory-p cwd)
              (let* ((default-directory cwd)
                     (dir (mo-git-blame-git-string "rev-parse" "--git-dir"))
                     (dir (if dir (file-name-directory (expand-file-name dir)) "")))
                (if (and dir (file-directory-p dir))
                    (file-name-as-directory dir)))))
    (or git-dir
        (error "No Git repository found"))))

(defun mo-git-blame-run (&rest args)
  (apply 'call-process mo-git-blame-git-executable nil (current-buffer) nil args))

(defun mo-git-blame-get-output-buffer ()
  (let* ((name "*mo-git-blame-output*")
         (buffer (get-buffer name)))
    (if (null buffer)
        (progn
          (setq buffer (get-buffer-create name))
          (with-current-buffer buffer
            (use-local-map mo-git-blame-mode-map))))
    buffer))

(defun mo-git-blame-parse-blame-line ()
  (save-excursion
    (save-match-data
      (beginning-of-line)
      (cond ((looking-at "^\\([a-f0-9]+\\) +\\(([^)]+)\\) *$")
             (list :hash (buffer-substring (match-beginning 1) (match-end 1))
                   :file-name (plist-get mo-git-blame-vars :file-name)
                   :timestamp (buffer-substring (match-beginning 2) (match-end 2))))
            ((looking-at "^\\([a-f0-9]+\\) +\\(([^)]+)\\) +\\(.+\\)")
             (list :hash (buffer-substring (match-beginning 1) (match-end 1))
                   :file-name (buffer-substring (match-beginning 3) (match-end 3))
                   :timestamp (buffer-substring (match-beginning 2) (match-end 2))))
            (t (error "Not a 'git blame' line"))))))

(defun mo-git-blame-revision-at-point ()
  (plist-get (mo-git-blame-parse-blame-line) :hash))

(defun mo-git-blame-log-for-revision (revision)
  (let ((file-name (plist-get mo-git-blame-vars :file-name))
        (buffer (mo-git-blame-get-output-buffer)))
    (with-current-buffer buffer
      (erase-buffer)
      (mo-git-blame-run "log" revision "--" file-name)
      (goto-char (point-min)))
    (display-buffer buffer)))

(defun mo-git-blame-log-for-revision-at ()
  "Calls 'git log' for revision in the current line."
  (interactive)
  (mo-git-blame-log-for-revision (mo-git-blame-revision-at-point)))

(defun mo-git-blame-log-for-current-revision ()
  "Calls 'git log' for the buffer's current revision and file."
  (interactive)
  (mo-git-blame-log-for-revision (plist-get mo-git-blame-vars :current-revision)))

(defun mo-git-blame-show-revision (revision)
  (let ((buffer (mo-git-blame-get-output-buffer)))
    (with-current-buffer buffer
      (erase-buffer)
      (mo-git-blame-run "show" revision)
      (goto-char (point-min)))
    (display-buffer buffer)))

(defun mo-git-blame-show-revision-at ()
  "Calls 'git show' for the revision in the current line."
  (interactive)
  (mo-git-blame-show-revision (mo-git-blame-revision-at-point)))

(defun mo-git-blame-show-current-revision ()
  "Calls 'git show' for the current revision."
  (interactive)
  (mo-git-blame-show-revision (plist-get mo-git-blame-vars :current-revision)))

(defun mo-git-blame-content-for-revision-at ()
  "Calls 'git cat-file' for the revision in the current line."
  (interactive)
  (let ((info (mo-git-blame-parse-blame-line))
        (buffer (mo-git-blame-get-output-buffer)))
    (with-current-buffer buffer
      (erase-buffer)
      (mo-git-blame-run "cat-file" "blob" (concat (plist-get info :hash) ":" (plist-get info :file-name)))
      (goto-char (point-min)))
    (display-buffer buffer)))

(defun mo-git-blame-overwrite-file-with-revision (revision)
  (let ((file-name (plist-get mo-git-blame-vars :original-file-name)))
    (if (yes-or-no-p (format "Do you really want to overwrite %s with revision %s " file-name revision))
        (progn
          (find-file (concat (plist-get mo-git-blame-vars :top-dir) file-name))
          (erase-buffer)
          (mo-git-blame-run "cat-file" "blob" (concat revision ":" file-name))
          (goto-char (point-min))))))

(defun mo-git-blame-overwrite-file-with-revision-at ()
  "Calls 'git cat-file' for the revision in the current line and overwrites
the original file's content. The file is not saved but left modified in an
open buffer."
  (interactive)
  (mo-git-blame-overwrite-file-with-revision (mo-git-blame-revision-at-point)))

(defun mo-git-blame-overwrite-file-with-current-revision ()
  "Calls 'git cat-file' for the current revision and overwrites
the original file's content. The file is not saved but left modified in an
open buffer."
  (interactive)
  (mo-git-blame-overwrite-file-with-revision (plist-get mo-git-blame-vars :current-revision)))

(defun mo-git-blame-reblame-for-revision-at ()
  "Calls 'git blame' for the revision in the current line."
  (interactive)
  (let* ((info (mo-git-blame-parse-blame-line))
         (revision (plist-get info :hash)))
    (if (string= revision (plist-get mo-git-blame-vars :current-revision))
        (error "Already showing this revision"))
    (mo-git-blame-file (concat (plist-get mo-git-blame-vars :top-dir) (plist-get info :file-name)) revision (plist-get mo-git-blame-vars :original-file-name))))

(defun mo-git-blame-mode ()
  "Show the output of 'git blame' and the content of the file in
two frames side-by-side. Allows iterative re-blaming for specific
revisions. Can show the output of 'git log' and 'git show'. Can
overwrite the file with the content of specific revisions by
calling 'git cat-file blob ...'.

Use 'mo-git-blame-current' interactively or 'mo-git-blame-file'
from elisp.

\\{mo-git-blame-mode-map}"
  (setq major-mode 'mo-git-blame-mode
        mode-name "MoGitBlame"
        mode-line-process ""
        truncate-lines t)
  (use-local-map mo-git-blame-mode-map))

(defun mo-git-blame-init-blame-buffer ()
  (mo-git-blame-run "blame" (plist-get mo-git-blame-vars :current-revision) "--" (plist-get mo-git-blame-vars :file-name))
  (goto-char (point-min))
  (save-match-data
    (while (re-search-forward "^\\([a-f0-9]+\\) +\\(([^)]+)\\) \\(.*\\)" nil t)
      (replace-match "\\1 \\2" nil nil))
    (goto-char (point-min))
    (while (re-search-forward "^\\([a-f0-9]+\\) +\\([^ ]+\\) +\\(([^)]+)\\) \\(.*\\)" nil t)
      (replace-match "\\1 \\3 \\2" nil nil))
    (goto-char (point-min))
    (while (re-search-forward " +[0-9]+)" nil t)
      (replace-match ")" nil nil)))
  (toggle-read-only t)
  (goto-char (point-min))
  (scroll-all-mode 1))

(defun mo-git-blame-init-content-buffer ()
  (rename-buffer (concat "*mo-git-blame:" (file-name-nondirectory (plist-get mo-git-blame-vars :full-file-name)) ":" (plist-get mo-git-blame-vars :current-revision) "*"))
  (setq buffer-file-name (file-name-nondirectory (plist-get mo-git-blame-vars :full-file-name))
        default-directory (plist-get mo-git-blame-vars :top-dir))
  (mo-git-blame-run "cat-file" "blob" (concat (plist-get mo-git-blame-vars :current-revision) ":" (plist-get mo-git-blame-vars :file-name)))
  (normal-mode)
  (use-local-map mo-git-blame-content-mode-map)
  (font-lock-fontify-buffer)
  (toggle-read-only t)
  (set-buffer-modified-p nil)
  (scroll-all-mode 1)
  (setq truncate-lines t))

(defun mo-git-blame-read-file-name ()
  "Calls `read-file-name' or `ido-read-file-name' depending on
the value of `mo-git-blame-use-ido'."
  (let ((the-func (cond ((eq mo-git-blame-use-ido 'always)
                         (require 'ido)
                         'ido-read-file-name)
                        ((and (eq mo-git-blame-use-ido 'if-available)
                              (functionp 'ido-read-file-name))
                         'ido-read-file-name)
                        (t 'read-file-name))))
    (funcall the-func "File for 'git blame': " nil nil t)))

;;;###autoload
(defun mo-git-blame-file (&optional file-name revision original-file-name)
  "Calls 'git blame' for REVISION of FILE-NAME or `HEAD' if
REVISION is not given. Initializes the two windows that will show
the output of 'git blame' and the content.

If FILE-NAME is missing it will be read with `find-file' in
interactive mode.

ORIGINAL-FILE-NAME defaults to FILE-NAME if not given. This is
used for tracking renaming and moving of files during iterative
re-blaming."
  (interactive)
  (let* ((file-name (or file-name (mo-git-blame-read-file-name)))
         (the-raw-revision (or revision "HEAD"))
         (the-revision (if (string= the-raw-revision "HEAD")
                           (mo-git-blame-git-string "rev-parse" "--short" "HEAD")
                         the-raw-revision))
         (base-name (concat (file-name-nondirectory file-name) "@" the-revision))
         (blame-buffer (get-buffer-create "*mo-git-blame*"))
         (content-buffer-name (concat "*mo-git-blame:" (file-name-nondirectory file-name) ":" the-revision "*"))
         (content-buffer (if (local-variable-p 'mo-git-blame-vars)
                             (plist-get mo-git-blame-vars :content-buffer)
                           (get-buffer-create content-buffer-name)))
         (top-dir (mo-git-blame-get-top-dir (file-name-directory file-name)))
         (relative-file-name (file-relative-name file-name top-dir))
         (blame-window (selected-window))
         content-window the-buffer)
    (switch-to-buffer blame-buffer)
    (if (window-full-width-p)
        (split-window-horizontally mo-git-blame-blame-window-width))
    (select-window (setq content-window (next-window)))
    (switch-to-buffer content-buffer)
    (select-window blame-window)
    (dolist (the-buffer (list blame-buffer content-buffer))
      (with-current-buffer the-buffer
        (toggle-read-only 0)
        (kill-all-local-variables)
        (buffer-disable-undo)
        (erase-buffer)
        (setq default-directory top-dir)
        (set (make-local-variable 'mo-git-blame-vars)
             (list :top-dir top-dir
                   :file-name relative-file-name
                   :full-file-name file-name
                   :original-file-name (or original-file-name file-name)
                   :current-revision the-revision
                   :blame-buffer blame-buffer
                   :blame-window blame-window
                   :content-buffer content-buffer
                   :content-window content-window))
        (set (make-local-variable 'line-move-visual) nil)))
    (with-current-buffer blame-buffer
      (mo-git-blame-mode)
      (mo-git-blame-init-blame-buffer))
    (with-current-buffer content-buffer
      (mo-git-blame-init-content-buffer))))

(defun mo-git-blame-quit ()
  "Kill the mo-git-blame buffers."
  (interactive)
  (delete-other-windows)
  (scroll-all-mode 0)
  (let ((buffer))
    (dolist (buffer (buffer-list))
      (if (string-match-p "^\\*mo-git-blame" (buffer-name buffer))
          (kill-buffer buffer)))))

(defun mo-git-blame-display-content-buffer ()
  "Show the content buffer in the content window."
  (interactive)
  ; Declare buffer here because mo-git-blame-vars might not be available in the other buffer.
  (let ((buffer (plist-get mo-git-blame-vars :content-buffer))
        (line-num (line-number-at-pos)))
    (goto-line line-num)
    (recenter)
    (with-selected-window (plist-get mo-git-blame-vars :content-window)
      (switch-to-buffer buffer)
      (goto-line line-num)
      (recenter))))

(defun mo-git-blame-other-buffer ()
  (plist-get mo-git-blame-vars
             (if (eq (current-buffer) (plist-get mo-git-blame-vars :blame-buffer))
                 :content-buffer
               :blame-buffer)))

(defun mo-git-blame-goto-line (line)
  "Goto a line in both the blame and the content buffer."
  (interactive "nGoto line: ")
  (with-selected-window (plist-get mo-git-blame-vars :blame-window)
    (goto-line line))
  (with-selected-window (plist-get mo-git-blame-vars :content-window)
    (goto-line line)))

;;;###autoload
(defun mo-git-blame-current ()
  "Calls `mo-git-blame-file' for HEAD for the current buffer."
  (interactive)
  (if (null (buffer-file-name))
      (error "The current buffer is not associated with a file."))
  (mo-git-blame-file (buffer-file-name)))

(provide 'mo-git-blame)
