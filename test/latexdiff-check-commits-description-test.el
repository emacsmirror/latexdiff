(ert-deftest check-commits-description ()
  (let ((file (latexdiff-testcase-file1)))
    (find-file file)
    (let ((desc (latexdiff--get-commits-description))
          (descs (latexdiff-testcase-commits-description)))
      (should (= (length desc) (length descs)))
      (should (= (length (cdr desc)) (length (cdr descs))))
      )))
