#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { data += chunk; });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(data));
  });
}

function parseJson(raw) {
  if (!raw || !raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

function getToolInput(payload) {
  const input = payload ? payload.tool_input || payload.toolInput : null;
  if (input && typeof input === "object") return input;
  if (typeof input === "string") return { input };
  return {};
}

function getToolName(payload) {
  return payload ? payload.tool_name || payload.toolName || "" : "";
}

function getEventName(payload) {
  return payload ? payload.hook_event_name || payload.hookEventName || "" : "";
}

function getCommand(payload) {
  const rawInput = payload ? payload.tool_input || payload.toolInput : null;
  if (typeof rawInput === "string") return rawInput;

  const input = getToolInput(payload);
  for (const key of ["command", "cmd", "script"]) {
    if (typeof input[key] === "string") return input[key];
  }
  if (Array.isArray(input.args)) return input.args.join(" ");
  return "";
}

function hasUserApproved(command) {
  return /#\s*USER_APPROVED\b/.test(command || "");
}

function jsonOut(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function denyPreToolUse(reason) {
  jsonOut({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  });
}

function denyPermissionRequest(reason) {
  jsonOut({
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior: "deny",
        message: reason,
      },
    },
  });
}

function block(reason, payload) {
  if (getEventName(payload) === "PermissionRequest") denyPermissionRequest(reason);
  else denyPreToolUse(reason);
  return true;
}

function runGit(args, cwd) {
  const result = spawnSync("git", args, {
    cwd: cwd || process.cwd(),
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  return {
    status: result.status,
    stdout: (result.stdout || "").trim(),
    stderr: (result.stderr || "").trim(),
  };
}

function currentBranch(cwd) {
  const result = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd);
  return result.status === 0 ? result.stdout : "";
}

function findEnvPathValues(value, out = []) {
  if (!value) return out;
  if (typeof value === "string") {
    if (isEnvPath(value)) out.push(value);
    return out;
  }
  if (Array.isArray(value)) {
    for (const item of value) findEnvPathValues(item, out);
    return out;
  }
  if (typeof value === "object") {
    for (const item of Object.values(value)) findEnvPathValues(item, out);
  }
  return out;
}

function isEnvPath(value) {
  const normalized = String(value || "").replace(/\\/g, "/");
  return /(^|\/)\.env(\.|$|\/)/.test(normalized);
}

function isFileMutationTool(toolName) {
  return /^(apply_patch|Edit|Write|MultiEdit)$/i.test(toolName || "");
}

function commandMutatesEnvFile(command) {
  if (!command) return false;
  const envPathPattern = "(?:^|[\\s\"'])(?:\\.?/?[^\\s\"']*/)?\\.env(?:\\.[^\\s\"']*)?(?=$|[\\s\"'])";
  const envPath = new RegExp(envPathPattern);
  const redirectsToEnv = new RegExp(`(?:>|>>|\\btee\\b[^\\n|;&]*|\\bcp\\b[^\\n|;&]*|\\bmv\\b[^\\n|;&]*|\\brm\\b[^\\n|;&]*|\\bsed\\b[^\\n|;&]*\\s-i\\b[^\\n|;&]*)${envPathPattern}`);
  return envPath.test(command) && redirectsToEnv.test(command);
}

function checkEnvProtection(payload) {
  const input = getToolInput(payload);
  if (isFileMutationTool(getToolName(payload)) && findEnvPathValues(input).length > 0) {
    return "禁止 Codex 修改 .env 文件，请用户手动编辑敏感配置。";
  }
  const command = getCommand(payload);
  if (command && /(^|\n)(\+\+\+|---|\*\*\* Update File:|\*\*\* Add File:)\s+[^\n]*\.env(\.|$|\s|\/|\\)/.test(command)) {
    return "禁止 Codex 修改 .env 文件，请用户手动编辑敏感配置。";
  }
  if (commandMutatesEnvFile(command)) {
    return "禁止 Codex 修改 .env 文件，请用户手动编辑敏感配置。";
  }
  return null;
}

function checkCommandPolicy(command, payload) {
  if (!command) return null;

  if (/\bgit\s+push\b/.test(command)) {
    return "git push 被拦截：未经用户明确要求不要自动推送。请让用户在终端手动执行，或在确认后由人工触发。";
  }

  if (/\bgit\s+commit\b/.test(command)) {
    const branch = currentBranch(payload.cwd);
    if (/^(main|master|test)$/.test(branch) && !hasUserApproved(command)) {
      return `git commit 被拦截：禁止在 ${branch} 分支直接提交。如确需提交，请先得到用户确认并在命令末尾添加 # USER_APPROVED。`;
    }
    if (/\bgit\s+commit\b[\s\S]*-F\s*-/.test(command)) {
      return "git commit -F - 被拦截：Windows 下管道传中文容易导致提交信息乱码，请改用多个 -m 参数或 UTF-8 文件。";
    }
  }

  if (/\bgit\s+stash\b/.test(command)) {
    if (/\bgit\s+stash\s+(list|show)\b/.test(command)) return null;
    if (!hasUserApproved(command)) {
      return "git stash 被拦截：未经用户同意禁止擅自 stash。确认后可在命令末尾添加 # USER_APPROVED。";
    }
  }

  if (/\bgit\s+reset\s+--hard\b/.test(command) && !hasUserApproved(command)) {
    return "git reset --hard 被拦截：该操作不可恢复。确认后可在命令末尾添加 # USER_APPROVED。";
  }

  if (/\bgit\s+(checkout|restore)\s+\./.test(command) && !hasUserApproved(command)) {
    return "git checkout/restore . 被拦截：该操作会覆盖本地改动。确认后可在命令末尾添加 # USER_APPROVED。";
  }

  if (/\bgit\s+clean\s+-[a-zA-Z]*f/.test(command) && !hasUserApproved(command)) {
    return "git clean -f 被拦截：该操作会删除未跟踪文件。确认后可在命令末尾添加 # USER_APPROVED。";
  }

  if (/\bgit\s+pull\b/.test(command) && !/\bgit\s+pull\s+--rebase\b/.test(command)) {
    return "git pull 被拦截：请改用 git pull --rebase，避免产生多余 merge commit。";
  }

  return null;
}

function checkDingTalkPolicy(command) {
  if (!/notify\.js/.test(command || "")) return null;

  const paramsMatch = command.match(/--params-file\s+("[^"]+"|'[^']+'|\S+)/);
  if (!paramsMatch) return null;

  const paramsFile = paramsMatch[1].replace(/^["']|["']$/g, "");
  if (!fs.existsSync(paramsFile)) return null;

  const body = fs.readFileSync(paramsFile, "utf8");
  if (/"dryRun"\s*:\s*false/.test(body) && !hasUserApproved(command)) {
    return "IM 真实发送被拦截：必须先 dryRun 预览，用户确认后在命令末尾添加 # USER_APPROVED。";
  }
  if (!/"dryRun"\s*:/.test(body)) {
    return "notify.js 被拦截：params-file 缺少 dryRun 字段，请显式设置 dryRun: true 先预览。";
  }
  return null;
}

function commandSucceeded(payload) {
  const response = payload ? payload.tool_response || payload.toolResponse : null;
  if (!response || typeof response !== "object") return true;

  for (const key of ["exit_code", "exitCode", "exit_status", "status", "code"]) {
    if (!Object.prototype.hasOwnProperty.call(response, key)) continue;
    const value = response[key];
    if (typeof value === "number") return value === 0;
    if (typeof value === "string") {
      const normalized = value.toLowerCase();
      if (normalized === "0" || normalized === "success" || normalized === "ok") return true;
      if (/^\d+$/.test(normalized)) return normalized === "0";
      if (normalized === "failed" || normalized === "error") return false;
    }
  }

  return true;
}

function latestCommitMessage(cwd) {
  const result = runGit(["log", "-1", "--format=%B"], cwd);
  return result.status === 0 ? result.stdout : "";
}

function latestCommitIsRecent(cwd) {
  const result = runGit(["log", "-1", "--format=%ct"], cwd);
  if (result.status !== 0) return false;
  const timestamp = Number(result.stdout);
  if (!Number.isFinite(timestamp)) return false;
  return Math.abs(Date.now() / 1000 - timestamp) <= 300;
}

function latestReflogIsCommit(cwd) {
  const result = runGit(["reflog", "-1", "--format=%gs"], cwd);
  if (result.status !== 0) return true;
  return /^commit(?: \([^)]*\))?:/.test(result.stdout);
}

function amendCommitMessage(message, cwd) {
  const tmp = path.join(os.tmpdir(), `codex-commit-${Date.now()}-${process.pid}.txt`);
  fs.writeFileSync(tmp, `${message.replace(/\s+$/, "")}\n`, "utf8");
  try {
    runGit(["commit", "--amend", "-F", tmp, "--no-verify"], cwd);
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
}

function postCommitCheck(command, payload) {
  if (!/\bgit\s+commit\b/.test(command || "")) return;
  if (/\b--amend\b/.test(command || "")) return;
  if (!commandSucceeded(payload)) return;
  if (!latestCommitIsRecent(payload.cwd)) return;
  if (!latestReflogIsCommit(payload.cwd)) return;

  const message = latestCommitMessage(payload.cwd);
  if (!message) return;

  if (message.includes("\uFFFD")) {
    process.stderr.write("[WARNING] commit message 疑似乱码，请检查并重新提交。\n");
    return;
  }

  if (!/Co-Authored-By:/i.test(message)) {
    amendCommitMessage(`${message}\n\nCo-Authored-By: Codex <noreply@openai.com>`, payload.cwd);
  }
}

function handlePreLike(payload) {
  const envReason = checkEnvProtection(payload);
  if (envReason) return block(envReason, payload);

  const command = getCommand(payload);
  const commandReason = checkCommandPolicy(command, payload);
  if (commandReason) return block(commandReason, payload);

  const dingTalkReason = checkDingTalkPolicy(command);
  if (dingTalkReason) return block(dingTalkReason, payload);

  return false;
}

async function main() {
  const payload = parseJson(await readStdin());
  const event = getEventName(payload);

  if (event === "PreToolUse" || event === "PermissionRequest") {
    handlePreLike(payload);
    return;
  }

  if (event === "PostToolUse") {
    postCommitCheck(getCommand(payload), payload);
  }
}

if (require.main === module) {
  main().catch((err) => {
    process.stderr.write(`[codex-hook] ${err && err.message ? err.message : String(err)}\n`);
    process.exit(1);
  });
}

module.exports = {
  checkCommandPolicy,
  checkDingTalkPolicy,
  checkEnvProtection,
  getCommand,
};
