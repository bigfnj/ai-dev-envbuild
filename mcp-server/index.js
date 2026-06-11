#!/usr/bin/env node
/**
 * devenv-mcp — MCP server that exposes every globally-installed tool from
 * ~/tools/manifest/tools.json as a discrete Claude Code tool.
 *
 * One tool per manifest entry (scope=global only). Tool names follow the
 * manifest name, sanitized to [a-zA-Z0-9_-]. Binary overrides and arg-prefix
 * overrides handle the handful of entries that need special invocation.
 */
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "child_process";
import { existsSync, readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Manifest ─────────────────────────────────────────────────────────────────

const localManifest =
  process.env.DEVENV_MANIFEST ??
  join(process.env.HOME ?? "", "tools/manifest/tools.json");
const catalog = join(__dirname, "../manifest/catalog.json");
const manifestPath = existsSync(localManifest) ? localManifest : catalog;
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

// ── Special-case overrides ────────────────────────────────────────────────────

// Use a different binary than what the manifest records.
const BINARY_OVERRIDES = {
  "gnu-time": "/usr/bin/time",   // manifest says 'time' — that's the shell builtin
};

// Prepend these args before the user's args when invoking the binary.
const ARG_PREFIX = {
  "docker-compose": ["compose"],  // invoked as: docker compose <args>
};

// Skip these manifest names entirely (not standalone CLI tools).
const SKIP = new Set([
  "pillow",   // Python library injected into ipython; same binary, not a CLI
]);

// ── Denylist ──────────────────────────────────────────────────────────────────
// Tools that must never be exposed as MCP tools regardless of the manifest.
// Keeps dynamic instrumentation / credential tools out of reach of AI agents.
let DENYLIST;
try {
  DENYLIST = new Set(
    JSON.parse(readFileSync(join(__dirname, "denylist.json"), "utf8"))
  );
} catch {
  DENYLIST = new Set();
}

// ── Tool definitions ──────────────────────────────────────────────────────────

function sanitizeName(name) {
  // MCP tool names: [a-zA-Z0-9_-]+
  return name
    .replace(/\+\+/g, "_plusplus")
    .replace(/\+/g, "_plus")
    .replace(/[^a-zA-Z0-9_-]/g, "_");
}

function buildDescription(tool) {
  const base = tool.notes
    ? tool.notes
    : `${tool.name} — ${tool.group} tool`;
  const method =
    tool.install_method !== "apt" ? ` (${tool.install_method})` : "";
  return `${base}${method}`;
}

const toolDefs = manifest
  .filter((t) => t.scope === "global" && !SKIP.has(t.name) && !DENYLIST.has(t.name))
  .map((t) => ({
    mcpName: sanitizeName(t.name),
    binary: BINARY_OVERRIDES[t.name] ?? t.binary,
    argPrefix: ARG_PREFIX[t.name] ?? [],
    description: buildDescription(t),
  }));

const byName = new Map(toolDefs.map((t) => [t.mcpName, t]));

// ── Server ────────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "devenv", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: toolDefs.map(({ mcpName, description }) => ({
    name: mcpName,
    description,
    inputSchema: {
      type: "object",
      properties: {
        args: {
          type: "array",
          items: { type: "string" },
          description: "Arguments to pass to the binary, one element per argument",
          default: [],
        },
        cwd: {
          type: "string",
          description: "Working directory (defaults to $HOME)",
        },
        stdin: {
          type: "string",
          description: "Data to pipe to stdin",
        },
      },
      required: [],
    },
  })),
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;
  const def = byName.get(name);

  if (!def) {
    return {
      content: [{ type: "text", text: `Unknown tool: ${name}` }],
      isError: true,
    };
  }

  const argv = [...def.argPrefix, ...(args.args ?? [])];
  const cwd = args.cwd ?? process.env.HOME ?? "/";
  const stdinData = args.stdin ?? null;

  const output = await run(def.binary, argv, { cwd, stdinData });
  return { content: [{ type: "text", text: output }] };
});

// ── Execution ─────────────────────────────────────────────────────────────────

function run(binary, argv, { cwd, stdinData, timeoutMs = 30_000 }) {
  return new Promise((resolve) => {
    const proc = spawn(binary, argv, {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
    });

    const out = [];
    const err = [];
    proc.stdout.on("data", (d) => out.push(d));
    proc.stderr.on("data", (d) => err.push(d));

    if (stdinData != null) {
      proc.stdin.write(stdinData);
    }
    proc.stdin.end();

    const timer = setTimeout(() => proc.kill("SIGTERM"), timeoutMs);

    proc.on("close", (code) => {
      clearTimeout(timer);
      const stdout = Buffer.concat(out).toString("utf8").trimEnd();
      const stderr = Buffer.concat(err).toString("utf8").trimEnd();
      let text = stdout;
      if (stderr) text += (stdout ? "\n[stderr]\n" : "[stderr]\n") + stderr;
      if (!text) text = code === 0 ? "(no output)" : `(exit ${code ?? "?"})`;
      resolve(text);
    });

    proc.on("error", (e) => {
      clearTimeout(timer);
      resolve(`[spawn error] ${e.message}`);
    });
  });
}

// ── Start ─────────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
