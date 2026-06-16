#!/usr/bin/env bash
# docs — document conversion + markdown quality. pandoc (apt) for broad
# cross-project document conversion; markdownlint-cli (npm, user prefix) so
# agents and humans can lint docs before committing.

docs_desc() { echo "pandoc, markdownlint-cli, ghostscript, poppler-utils, qpdf, tesseract-ocr"; }

docs_install() {
    apt_install pandoc ghostscript poppler-utils qpdf tesseract-ocr
    npm_global markdownlint-cli markdownlint
    docs_record_manifest
}

docs_record_manifest() {
    if has pandoc;       then manifest_add pandoc           pandoc       docs global apt      "pandoc --version"            core "universal document converter"; fi
    if has markdownlint; then manifest_add markdownlint-cli markdownlint docs global npm-user "markdownlint --version"      core "markdown linter for docs"; fi
    if has gs;           then manifest_add ghostscript      gs           docs global apt      "gs --version"                core "PostScript/PDF interpreter; backend for pandoc PDF output and many image pipelines"; fi
    if has pdfinfo;      then manifest_add poppler-utils    pdfinfo      docs global apt      "pdfinfo -v 2>&1"             core "PDF utilities: pdfinfo, pdftoppm, pdftotext, pdfseparate, pdfimages"; fi
    if has qpdf;         then manifest_add qpdf             qpdf         docs global apt      "qpdf --version"              core "PDF manipulation: merge, split, decrypt, linearize, watermark"; fi
    if has tesseract;    then manifest_add tesseract-ocr    tesseract    docs global apt      "tesseract --version"         core "OCR engine; add language packs via 'apt install tesseract-ocr-<lang>'"; fi
    log_ok "manifest updated — docs group"
}
