# WSL Filesystem Guidance

Where files live matters a lot under WSL2. The short version: **keep active
project work on the Linux filesystem (`~/projects`), not `/mnt/c`.**

## Why `/mnt/c` is slow

WSL2 runs a real Linux kernel in a lightweight VM. The Linux filesystem
(`ext4`, under `~`) is local to that VM and fast. `/mnt/c` (and any
`/mnt/<drive>`) is the Windows filesystem exposed over the **9P protocol** —
every file operation crosses the VM boundary. For metadata-heavy workloads
(git status, `node_modules`, test runners, compilers) this is often **10×+
slower**.

Worse, **inotify file-watchers do not work reliably across the 9P boundary**.
Tools that watch for changes — Vite, webpack, nodemon, `pytest-watch`, `cargo
watch`, `entr` — silently miss edits or busy-poll when the tree is on `/mnt/c`.

## Rules

- **Active project trees → `~/projects/<name>`.** Clone and build there.
- **Sandboxes / throwaway / untrusted analysis → `~/sandboxes`.**
- **`/mnt/c` is fine for:** reading a one-off file from the Windows side,
  copying a final artifact out to Windows, or pointing a Windows app at output.
  Not for a working tree you build or test in.
- **Don't store `node_modules`, `.venv`, build output, or `.git` on `/mnt/c`.**

## VS Code

- Open project folders with **Remote - WSL** (`code .` from inside WSL, or
  "Reopen in WSL"). The VS Code server then runs inside Linux and reads the
  Linux filesystem directly — fast, and watchers work.
- The integrated terminal will already be inside WSL; keep project paths under
  `~`.

## Git, SSH, credentials

- Run git **inside WSL**; keep the repo on the Linux filesystem.
- SSH keys live in WSL at `~/.ssh` (mode 600). Don't reach across to Windows
  keys for WSL-side git.
- Line endings: set `git config --global core.autocrlf input` to avoid CRLF
  creeping in from Windows tooling.

## Sharing files between Windows and WSL

- From Windows, reach WSL files via the `\\wsl$\<distro>\home\<user>\…` UNC path
  (or `\\wsl.localhost\…`). Use this for occasional access, not as a build
  location.
- From WSL, Windows files are under `/mnt/c/…`. Copy in/out deliberately rather
  than working in place.

## Quick check

`devtools doctor` warns if your current working directory is under `/mnt` so you
don't accidentally build there.
