#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
HOOKS_DIR="$CODEX_DIR/hooks"
HOOK_SCRIPT="$HOOKS_DIR/cc-codex-hook.js"
HOOKS_JSON="$CODEX_DIR/hooks.json"
CONFIG_TOML="$CODEX_DIR/config.toml"
AGENTS_FILE="$CODEX_DIR/AGENTS.md"

mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/hooks/codex-hook.js" "$HOOK_SCRIPT"
chmod +x "$HOOK_SCRIPT"

node - "$HOOKS_JSON" "$HOOK_SCRIPT" "$CONFIG_TOML" "$AGENTS_FILE" "$REPO_DIR" "${1:-}" <<'NODE'
const fs = require("fs");
const path = require("path");

const [hooksPath, hookScript, configToml, agentsFile, repoDir, option] = process.argv.slice(2);
const blockStart = "<!-- cc-hooks-rules:start -->";
const blockEnd = "<!-- cc-hooks-rules:end -->";

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function ensureHooksFeature(text) {
  if (!text || !text.trim()) return "[features]\nhooks = true\n";

  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const start = lines.findIndex((line) => /^\s*\[features\]\s*$/.test(line));
  if (start === -1) return `${text.replace(/\s+$/, "")}\n\n[features]\nhooks = true\n`;

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^\s*\[.*\]\s*$/.test(lines[index])) {
      end = index;
      break;
    }
  }

  for (let index = start + 1; index < end; index += 1) {
    if (/^\s*hooks\s*=/.test(lines[index])) {
      lines[index] = "hooks = true";
      return `${lines.join("\n").replace(/\n+$/, "")}\n`;
    }
  }

  lines.splice(end, 0, "hooks = true");
  return `${lines.join("\n").replace(/\n+$/, "")}\n`;
}

const command = `node ${shellQuote(hookScript)}`;
let settings = {};
try { settings = JSON.parse(fs.readFileSync(hooksPath, "utf8")); } catch {}
if (!settings.hooks || typeof settings.hooks !== "object") settings.hooks = {};

const events = [
  ["PreToolUse", "Checking repository safety policy"],
  ["PermissionRequest", "Checking approval policy"],
  ["PostToolUse", "Checking git commit metadata"],
];

for (const [name, statusMessage] of events) {
  const entries = Array.isArray(settings.hooks[name]) ? settings.hooks[name] : [];
  settings.hooks[name] = entries.filter((entry) => !JSON.stringify(entry).includes("cc-codex-hook.js"));
  settings.hooks[name].push({
    hooks: [{ type: "command", command, timeout: 30, statusMessage }],
  });
}

fs.mkdirSync(path.dirname(hooksPath), { recursive: true });
fs.writeFileSync(hooksPath, `${JSON.stringify(settings, null, 2)}\n`, "utf8");

const configText = fs.existsSync(configToml) ? fs.readFileSync(configToml, "utf8") : "";
fs.mkdirSync(path.dirname(configToml), { recursive: true });
fs.writeFileSync(configToml, ensureHooksFeature(configText), "utf8");

if (option !== "--no-agent-rules") {
  const source = path.join(repoDir, "AGENTS.md");
  const rules = fs.readFileSync(source, "utf8").replace(/\s+$/, "");
  const block = `${blockStart}\n${rules}\n${blockEnd}`;
  const existing = fs.existsSync(agentsFile) ? fs.readFileSync(agentsFile, "utf8") : "";
  const next = existing.includes(blockStart)
    ? existing.replace(/<!-- cc-hooks-rules:start -->[\s\S]*?<!-- cc-hooks-rules:end -->/, block)
    : `${existing.replace(/\s+$/, "")}${existing.trim() ? "\n\n" : ""}${block}\n`;
  fs.mkdirSync(path.dirname(agentsFile), { recursive: true });
  fs.writeFileSync(agentsFile, `${next.replace(/\s+$/, "")}\n`, "utf8");
}
NODE

echo "Codex hooks installed to $HOOKS_JSON"
echo "Hook script: $HOOK_SCRIPT"
echo "Next step: restart Codex or run /hooks to review and trust the hook."
