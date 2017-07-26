(ert-deftest check-if-pdf-produced ()
  (let ((pdf1 (latexdiff-testcase-pdf1))
        (dummypdf (latexdiff-testcase-dummy-pdf)))
    (should (latexdiff--check-if-pdf-produced pdf1))
    (should (not (latexdiff--check-if-pdf-produced dummypdf)))))
