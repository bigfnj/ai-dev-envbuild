# Dev Environment — Tools Reference

Agent-facing usage guide. Read this for invocation patterns on specialized or
less-obvious tools. Mainstream tools (rg, fd, jq, fzf, bat, gh, git-delta,
just, hyperfine, tokei, rclone, docker) are well-covered by training data —
check `devtools report` to confirm they're present, then use them normally.

---

## Document / PDF tools (new in office + docs groups)

### tesseract — OCR engine

```bash
# Basic OCR to stdout
tesseract image.png stdout

# Specify language(s)
tesseract image.png stdout -l eng+spa

# Output to file (omit extension — tesseract adds it)
tesseract image.png output_base -l eng        # writes output_base.txt

# List available language packs
tesseract --list-langs

# Page segmentation modes (--psm)
tesseract image.png stdout --psm 6   # uniform block of text
tesseract image.png stdout --psm 7   # single line
tesseract image.png stdout --psm 3   # auto (default)
```

Add language packs: `apt install tesseract-ocr-spa` (Spanish), `tesseract-ocr-deu`, etc.

### ghostscript (gs) — PostScript/PDF interpreter

```bash
# PDF → PNG images (one per page)
gs -dNOPAUSE -dBATCH -sDEVICE=png16m -r300 \
   -sOutputFile=page_%03d.png input.pdf

# Merge PDFs
gs -dNOPAUSE -dBATCH -sDEVICE=pdfwrite \
   -sOutputFile=merged.pdf a.pdf b.pdf c.pdf

# Compress/optimise a PDF
gs -dNOPAUSE -dBATCH -sDEVICE=pdfwrite \
   -dCompatibilityLevel=1.5 -dPDFSETTINGS=/ebook \
   -sOutputFile=compressed.pdf input.pdf
# /screen=lowest, /ebook=medium, /printer=high, /prepress=highest

# Extract text
gs -dNOPAUSE -dBATCH -sDEVICE=txtwrite \
   -sOutputFile=output.txt input.pdf
```

### poppler-utils — PDF CLI utilities

```bash
pdfinfo document.pdf            # page count, dimensions, metadata
pdftoppm -r 150 -png document.pdf page  # → page-000001.png etc.
pdftotext document.pdf -         # text to stdout
pdfseparate document.pdf page_%d.pdf    # split to individual pages
pdfimages -png document.pdf img         # extract embedded images
```

### qpdf — PDF manipulation

```bash
# Merge / concatenate
qpdf --empty --pages a.pdf b.pdf -- merged.pdf

# Extract page range (pages 2-5)
qpdf input.pdf --pages input.pdf 2-5 -- output.pdf

# Linearize (web-optimize)
qpdf --linearize input.pdf output.pdf

# Remove password / decrypt
qpdf --decrypt --password=secret input.pdf output.pdf

# Inspect structure
qpdf --json input.pdf | jq '.objects | keys'
```

### LibreOffice headless (soffice) — Office document conversion

```bash
# Convert DOCX/PPTX/XLSX → PDF
soffice --headless --convert-to pdf document.docx
soffice --headless --convert-to pdf --outdir /tmp/ slides.pptx

# Convert to other formats
soffice --headless --convert-to html document.docx
soffice --headless --convert-to xlsx data.ods

# Batch convert a directory
soffice --headless --convert-to pdf *.docx

# Convert PPTX slides → images
soffice --headless --convert-to png presentation.pptx
```

`soffice` is single-threaded; run one instance at a time per machine.

---

## Python REPL — injected libraries (ipython)

The following libraries are injected into the global `ipython` venv and are
available in any `ipython` or `jupyter-lab` session without a project venv:

```python
# Office documents
import docx           # python-docx
doc = docx.Document("file.docx")
for para in doc.paragraphs:
    print(para.text)

doc2 = docx.Document()
doc2.add_heading("Title", 0)
doc2.add_paragraph("Body text.")
doc2.save("output.docx")

# PowerPoint
import pptx
from pptx import Presentation
prs = Presentation("slides.pptx")
for slide in prs.slides:
    for shape in slide.shapes:
        if shape.has_text_frame:
            print(shape.text_frame.text)

# Excel / XLSX
import openpyxl
wb = openpyxl.load_workbook("data.xlsx")
ws = wb.active
for row in ws.iter_rows(values_only=True):
    print(row)

# Data
import pandas as pd
df = pd.read_csv("data.csv")
df.describe()

import numpy as np
arr = np.array([1, 2, 3])

# Imaging (Pillow — also injected)
from PIL import Image
img = Image.open("photo.jpg")
img.thumbnail((800, 600))
img.save("thumb.jpg")
```

For project code, use `uv add python-docx` etc. — the ipython injections are
scratch-pad convenience only and not available in project venvs.

---

## Image / media tools

### realesrgan-ncnn-vulkan — AI upscaling

```bash
# Upscale a photo 4× (best for real-world photos)
realesrgan-ncnn-vulkan -i input.png -o output.png -n realesrgan-x4plus

# Anime / illustration upscaling
realesrgan-ncnn-vulkan -i input.png -o output.png -n realesrgan-x4plus-anime

# Fast variant (lower quality, much faster)
realesrgan-ncnn-vulkan -i input.png -o output.png -n realesr-animevideov3

# Upscale all PNGs in a directory
realesrgan-ncnn-vulkan -i input_dir/ -o output_dir/ -n realesrgan-x4plus

# GPU tile size (lower if VRAM issues)
realesrgan-ncnn-vulkan -i input.png -o output.png -n realesrgan-x4plus -t 200
```

Models live in `~/tools/realesrgan/realesrgan-ncnn-vulkan-v0.2.0-ubuntu/models/`.
If the binary exists but models are missing, obtain `.param` + `.bin` files and
place them there, or use `-m /path/to/models`.

### rembg — AI background removal

```bash
# Remove background from a single image
rembg i input.png output.png

# Process a whole directory
rembg p input_dir/ output_dir/

# From stdin/stdout
cat input.png | rembg i > output.png

# Keep original size, write alpha channel
rembg i --alpha-matting input.png output.png
```

Model (~170 MB) downloads to `~/.u2net/` on first use.

### iopaint — AI inpainting

```bash
# Start the web UI (open http://localhost:8080)
iopaint start --model=lama --device=cpu --port=8080

# GPU-accelerated
iopaint start --model=lama --device=cuda --port=8080

# Available models: lama (fast), mat (detail), sd1.5 (Stable Diffusion)
iopaint start --model=mat --device=cuda

# Run without web UI (batch mode)
iopaint run --model=lama --device=cuda \
    --image=photo.png --mask=mask.png --output=result.png
```

### yt-dlp — media downloader

```bash
# Download best quality video+audio
yt-dlp <url>

# Audio only (mp3)
yt-dlp -x --audio-format mp3 <url>

# Specific format
yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]" <url>

# Download playlist (skip existing)
yt-dlp --no-overwrites -o "%(playlist_index)s-%(title)s.%(ext)s" <playlist-url>

# List available formats
yt-dlp -F <url>
```

### ffmpeg — key invocations

```bash
# Transcode video
ffmpeg -i input.mp4 -c:v libx264 -crf 23 output.mp4

# Extract audio
ffmpeg -i input.mp4 -vn -acodec mp3 output.mp3

# Generate silence (for TTS pipelines)
ffmpeg -f lavfi -i anullsrc=r=24000:cl=mono -t 1.5 silence.wav

# Concatenate audio files (list.txt: one "file 'x.wav'" per line)
ffmpeg -f concat -safe 0 -i list.txt -c copy output.wav

# Convert sample rate
ffmpeg -i input.wav -ar 22050 output.wav

# Trim (start time, duration)
ffmpeg -ss 00:01:00 -t 30 -i input.mp4 -c copy clip.mp4
```

---

## Reverse engineering tools

### radare2 (r2) — disassembler / debugger / emulator

```bash
# Open a binary
r2 binary

# Inside r2:
# aaa          — analyze all (functions, calls, xrefs)
# pdf @ main   — disassemble main function
# px 64 @ 0x0  — hexdump 64 bytes at address
# s sym.main   — seek to main
# V            — visual mode (q to quit)
# q            — quit

# Headless (scriptable)
r2 -q -c "aaa; pdf @ main" binary        # run commands, exit
r2 -q -c "aaa; afl" binary               # list all functions

# With r2pipe (Python)
python3 -c "
import r2pipe
r2 = r2pipe.open('binary')
r2.cmd('aaa')
print(r2.cmd('afl'))   # list functions
r2.quit()
"
```

### Ghidra headless — scripted RE (no GUI)

```bash
# analyzeHeadless is at ~/tools/ghidra/ghidra_*/support/
GHIDRA="$(find ~/tools/ghidra -name analyzeHeadless | head -1)"

# Import and analyze a binary
"$GHIDRA" /tmp/ghidra-projects MyProject \
    -import /path/to/binary \
    -deleteProject   # clean up after

# Run a post-analysis script
"$GHIDRA" /tmp/ghidra-projects MyProject \
    -import binary \
    -postScript PrintFunctionNames.java \
    -scriptPath ~/ghidra_scripts \
    -deleteProject

# Analyze without importing (existing project)
"$GHIDRA" /path/to/project ProjectName \
    -process binary_name \
    -postScript MyScript.java
```

Scripts are Java (`.java`) or Python 2.7/Jython (`.py`). Place them in
`~/ghidra_scripts/` or pass `-scriptPath`. The GUI launcher is
`~/tools/ghidra/ghidra_*/ghidraRun`.

### frida — dynamic instrumentation

```bash
# List running processes
frida-ps

# Attach to a process by name
frida -n bash

# Attach and load a JS hook script
frida -n target_process -l hook.js

# Spawn a new process
frida -f /path/to/binary --no-pause -l hook.js

# Trace all calls to libc functions
frida-trace -n target -i "open" -i "read" -i "write"

# Python API
python3 -c "
import frida
session = frida.attach('target_process')
script = session.create_script('''
    Interceptor.attach(Module.getExportByName(null, 'open'), {
        onEnter: function(args) {
            console.log('open:', args[0].readUtf8String());
        }
    });
''')
script.load()
import sys; sys.stdin.read()
"
```

### dosbox-x-headless — DOS emulation (no display)

```bash
# Run a DOS executable headlessly (SDL_VIDEODRIVER=dummy set by wrapper)
dosbox-x-headless -c "mount c /dos_files" -c "c:" -c "program.exe" -c "exit"

# With a config file
dosbox-x-headless -conf dosbox.conf -c "program.exe" -c "exit"

# Useful for automated testing of DOS binaries
dosbox-x-headless -c "mount c ." -c "c:" -c "TEST.EXE" -c "exit" 2>&1 | tee output.log
```

---

## Secrets management

### age + sops (same pattern as Windows)

```bash
# Generate a key pair
age-keygen -o ~/.config/age/key.txt
# Public key is printed to stderr and stored in the file

# Encrypt
age -r <pubkey> -o secret.age plaintext.txt
echo "secret" | age -r <pubkey> > secret.age

# Decrypt
age -d -i ~/.config/age/key.txt secret.age

# sops with age backend
export SOPS_AGE_KEY_FILE=~/.config/age/key.txt
sops --encrypt --age <pubkey> secrets.yaml > secrets.enc.yaml
sops --decrypt secrets.enc.yaml
sops secrets.enc.yaml   # edit in place (opens $EDITOR)
```

---

## Data tools

### duckdb — in-process analytical SQL

```bash
# Interactive CLI
duckdb

# Query a CSV file directly
duckdb -c "SELECT * FROM 'data.csv' LIMIT 10"

# Query a Parquet file
duckdb -c "SELECT count(*) FROM 'data.parquet'"

# Multiple files as a table
duckdb -c "SELECT * FROM read_csv_auto('data/*.csv') LIMIT 5"

# Export results
duckdb -c "COPY (SELECT * FROM 'data.csv') TO 'out.parquet' (FORMAT PARQUET)"
```

### sqlite-utils

```bash
sqlite-utils insert db.sqlite mytable data.csv --csv
sqlite-utils query db.sqlite "SELECT * FROM mytable" --csv
sqlite-utils tables db.sqlite
sqlite-utils schema db.sqlite
sqlite-utils transform db.sqlite mytable --rename old_col new_col
sqlite-utils convert db.sqlite mytable col "lambda v: v.strip()"
```

### csvkit

```bash
csvlook data.csv                    # pretty-print table
csvcut -c name,age data.csv         # select columns
csvstat data.csv                    # summary statistics
csvjoin -c id left.csv right.csv    # join on a column
in2csv data.xlsx > data.csv         # Excel → CSV
sql2csv --db sqlite:///db.sqlite "SELECT * FROM t"
```

---

## HuggingFace CLI (hf)

```bash
hf whoami                           # verify login
hf login                            # authenticate (token from hf.co/settings)

# Download a model
hf download mistralai/Mistral-7B-v0.1

# Download specific files only
hf download mistralai/Mistral-7B-v0.1 config.json tokenizer.json

# Download to a specific directory
hf download mistralai/Mistral-7B-v0.1 --local-dir ~/models/mistral

# List cached models
hf scan-cache

# Upload a file to a repo
hf upload my-org/my-repo ./local_file.bin remote_file.bin
```
