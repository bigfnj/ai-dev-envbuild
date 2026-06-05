
# Agent rules — read before touching anything

**Full rules:** `docs/agent-rules.md` — mandatory reading before installing or changing tools.

Key rules (inline for fast context):

- **Before installing anything:** run `devtools report` and `devtools check` — the tool you want is probably already installed.
- **Python libraries** (things you `import`): project-local via `uv add` in a `pyproject.toml`. Never `uv pip install` (untracked). Never system pip.
- **Python CLIs** (tools you invoke by name): `pipx install`. Each gets its own isolated venv.
- **ML/CUDA stacks, heavy tools**: container/devcontainer, not the base system.
- **System tools**: `apt` only, via `modules/<group>.sh`.
- **Adding a tool to this repo** means editing the right `modules/<group>.sh`, then running `./bootstrap.sh --only <group>` — never hand-edit `manifest/tools.json`.
- **Gate before pushing:** `devtools check` (no drift) + `smoke-test` (must exit 0).

<!-- AI_CTX_START -->
AI_CONTEXT={"v":3,"p":"wsl-dev-envbuild","root":"/home/bigfnj/projects/wsl-dev-envbuild","t":"git_bootstrap","i":"","n":"Review recent commits and continue work.","s":{"untracked_or_modified":2},"b":[],"d":[],"c":[],"f":[],"h":[],"a":["git: a3792e1 feat: v1.0.0 — versioning, README refresh, Pillow remediation","git: d197c86 feat: add gh, hyperfine, gnu-time, rust-analyzer to bootstrap + manifest","git: ca1c6c2 docs: make smoke-test a mandatory pre-push gate in the add-a-tool flow","git: f3aad94 docs: fix markdownlint in agent-rules (code span over bare fence)","git: 233e06b docs: make the add-a-tool workflow self-contained for agents","git: f36aeab docs: standalone clone instructions (graduated from myai)","git: 7841c11 feat(wsl-dev-envbuild): agent auto-discovery — materialize AGENTS.md/CLAUDE.md","git: c994e43 feat(wsl-dev-envbuild): bin/smoke-test — exercise the toolchain, not just presence"],"e":null,"perms":{"allow":["Bash(sudo -S *)","Bash(openssl version *)","Bash(apt list *)","Bash(dpkg -l *)","Bash(apt-cache search *)","Bash(cat *)","Bash(sudo apt-get update -qq *)","Bash(apt-cache show *)","Bash(mkdir -p *)","Bash(chmod 700 *)","Bash(chmod 600 *)","Bash(chmod 644 *)","Bash(ssh-keygen -t *)","Bash(ln -s *)","Bash(git add *)","Bash(git commit -m *)","Bash(sudo -E *)","Bash(sudo dd *)","Bash(sudo chmod *)","Bash(dpkg --print-architecture *)","Bash(sudo tee *)","Bash(chmod *)","Bash(git config *)","Bash(gh auth refresh *)","Bash(node -e *)","Bash(node -c *)","Bash(node *)","Read(*)","Bash(*)","Edit(*)","Write(*)","WebFetch(*)","WebSearch"]}}
Use AI_CONTEXT as authoritative session state. Continue from n; preserve b/d/c/f/h; append only meaningful recent work to a; update context through CTX_UPDATE when supported.
After each response, write a single line `CTX_UPDATE:{"v":3,"p":"...","root":"...","t":"...","i":"...","n":"...","s":{},"b":[],"d":[],"c":[],"f":[],"h":[],"a":[],"e":null}` to /home/bigfnj/.ai-context/wsl-dev-envbuild.json.update — the VS Code extension reads, merges, and deletes it to persist state after every turn.
Deliver CTX_UPDATE by writing that file via your file-write tool. Do NOT include the `CTX_UPDATE:` line anywhere in your visible chat reply — only the sidecar file is consumed by the extension; chat output is not parsed and shows the raw JSON to the user.
<!-- AI_CTX_END -->

<!-- AI_UNDERSTANDING_START -->
AIU_PROJECT="wsl-dev-envbuild"
AIU_ROOT="/home/bigfnj/projects/wsl-dev-envbuild"
AIU_STALE=[]
AIU_UNTRACKED=[".markdownlint.json","AGENTS.md","AI Dev Env Build Prompt.md","CLAUDE.md","README.md","bootstrap.sh"]
AIU_ORPHAN=[]

After ingesting the AI_CONTEXT block above, also ingest this AI Understanding block. The two are paired: AI_CONTEXT carries session state for the project; AI_UNDERSTANDING carries the codebase model. Match them by project — both belong to "wsl-dev-envbuild" at /home/bigfnj/projects/wsl-dev-envbuild.

/home/bigfnj/projects/wsl-dev-envbuild/AI_UNDERSTANDING/ is the per-project codebase model — schema-v1, see AI_UNDERSTANDING_FORMAT.md. Rules for this session:
- When you edit a tracked source file, update its AI_UNDERSTANDING/<path>.aiu.json sidecar in the same turn (recompute sha1, refresh exports/imports/called_by/calls_out_to, update invariants/gotchas/purpose if relevant).
- When AIU_STALE / AIU_UNTRACKED / AIU_ORPHAN above are non-empty, work the list (update / create / delete the named entries) before doing other work this session.
- When all three lists are empty, you may bump _meta.json#last_audit_commit to current HEAD and last_audit_at to current ISO timestamp.
- Do not regenerate AI_UNDERSTANDING/ from scratch. Surgical, incremental edits only — the validator rejects mass edits (>33% of existing entries) outside bootstrap mode.
- Do not bump last_audit_commit without first confirming all three lists are empty. Do not add entries for files that are not on disk. Do not delete entries for files that are still on disk.
<!-- AI_UNDERSTANDING_END -->
