<div align="center">

**中文** | [English](README_EN.md)

# CC-Hooks

**AI 编程助手安全护栏 — 让 AI 自主干活，危险操作你说了算**

为 Claude Code 和 OpenAI Codex 提供安全拦截规则，防止 AI 自动执行不可逆操作。

[![GitHub stars](https://img.shields.io/github/stars/wismyzhizi2018/cc-hooks?style=social)](https://github.com/wismyzhizi2018/cc-hooks/stargazers)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

[为什么需要](#为什么需要-cc-hooks) · [安全规则](#安全规则) · [拦截效果](#拦截效果) · [Agent 安装指引](#-如果你是-ai-agent请阅读这里)

</div>

---

## 为什么需要 CC-Hooks？

| 场景 | 没有 CC-Hooks | 有 CC-Hooks |
|------|---------------|-------------|
| AI 想 `git push` | 直接推了，你都不知道 | 拦截，必须你手动执行 |
| AI 在 `main` 分支提交 | 静默提交，污染保护分支 | 拦截，要求确认或切分支 |
| AI 执行 `git reset --hard` | 工作区没了，不可恢复 | 拦截，必须你明确同意 |
| AI `git stash` 隐藏改动 | 改动消失，你找不到 | 拦截，确认后才执行 |
| AI `git pull` 不带 `--rebase` | 多一个无意义的 merge commit | 自动拦截，提示用 `--rebase` |
| AI 修改 `.env` 文件 | API Key 可能泄露 | 拦截，要求手动编辑 |
| AI 发 IM 通知没预览 | 消息直接发出去了 | 拦截，必须先 dry-run |

---

## 安全规则

| 被拦截操作 | 原因 | 放行方式 |
| --- | --- | --- |
| `git push` | 禁止 AI 自动推送远端 | 无自动放行；由用户手动执行 |
| 在 `main` / `master` / `test` 上 `git commit` | 防止污染保护分支 | 用户确认后追加 `# USER_APPROVED` |
| `git commit -F -` | Windows 管道传中文会乱码 | 改用多个 `-m` 或 UTF-8 文件 |
| `git stash` 写操作 | 防止未经确认隐藏改动 | 用户确认后追加 `# USER_APPROVED` |
| `git reset --hard` | 不可恢复操作 | 用户确认后追加 `# USER_APPROVED` |
| `git checkout .` / `git restore .` | 会覆盖本地改动 | 用户确认后追加 `# USER_APPROVED` |
| `git clean -f` | 会删除未跟踪文件 | 用户确认后追加 `# USER_APPROVED` |
| 不带 `--rebase` 的 `git pull` | 避免多余 merge commit | 改用 `git pull --rebase` |
| IM 通知未 dry-run | 防止未经预览真实发送 | 先设置 `dryRun: true`；确认后追加 `# USER_APPROVED` |
| 修改 `.env` 文件 | 保护敏感配置 | 用户手动编辑 |

### 放行机制

在命令末尾追加 `# USER_APPROVED` 表示用户已确认：

```bash
git stash  # USER_APPROVED
git reset --hard HEAD~1  # USER_APPROVED
```

---

## 拦截效果

### 场景 1：AI 想 git push

```
$ git push origin main

[BLOCKED] git push 被拦截
原因：CLAUDE.md 规定禁止任何情况下自动 git push。
处理：请用户在终端手动执行以下命令。
  git push origin main
```

### 场景 2：AI 在 main 分支提交

```
$ git commit -m "feat: add new feature"

[BLOCKED] git commit 被拦截
原因：CLAUDE.md 规定禁止在 main 分支上直接提交代码。
处理：请先创建 feature# 或 hotfix# 分支。如确需在当前分支提交，请确认后加上 # USER_APPROVED 重新执行。
```

### 场景 3：AI 想 reset --hard

```
$ git reset --hard HEAD~3

[BLOCKED] git reset --hard 被拦截
原因：CLAUDE.md 规定未经用户同意禁止重置工作区，该操作不可恢复。
处理：请确认后在命令末尾加上 # USER_APPROVED 重新执行。
  git reset --hard HEAD~3  # USER_APPROVED
```

### 场景 4：commit 后自动补全 Co-Authored-By

```
$ git commit -m "feat: add login"

[AUTO-FIX] 已自动追加: Co-Authored-By: Claude claude-sonnet-4.6 <noreply@anthropic.com>
```

---

## Codex Hook 行为

`hooks/codex-hook.js` 使用 Codex hook schema，具体规则由脚本内部判断：

| 事件 | 行为 |
|------|------|
| `PreToolUse` | 阻止危险 Bash、`apply_patch` 文件改动和 MCP 参数中的敏感路径 |
| `PermissionRequest` | 在 Codex 请求权限前复用同一套安全策略 |
| `PostToolUse` | `git commit` 成功后检查提交信息，并补齐 `Co-Authored-By` |

---

## 仓库结构

```text
cc-hooks/
├── AGENTS.md                  # OpenAI Codex 全局协作规范
├── CLAUDE.md                  # Claude Code 全局协作规范
├── settings.json              # Claude Code hooks 注册配置
├── install-codex.ps1          # Codex Windows 安装器
├── install-codex.sh           # Codex macOS/Linux 安装器
├── hooks/
│   ├── codex-hook.js          # Codex hook 入口
│   ├── codex-hooks.json       # Codex hooks 示例配置
│   ├── session-init.sh        # Claude SessionStart（保存模型信息）
│   ├── guard.sh               # Claude PreToolUse(Bash)（核心拦截逻辑）
│   ├── post-commit-check.sh   # Claude PostToolUse(Bash)（提交后校验）
│   └── protect-env.sh         # Claude PreToolUse(Edit|Write)（.env 保护）
├── LICENSE                    # MIT License
└── README.md
```

---

## 🤖 如果你是 AI Agent，请阅读这里

这是 CC-Hooks，一套 AI 编程助手安全护栏，拦截危险 Git 操作（push、reset --hard、在 main 提交等）和敏感文件修改（.env）。

---

### 第零步：先判断用户意图

| 用户说的 | 你要做的 |
|---------|---------|
| 「帮我装一下」「怎么安装」「配置 hooks」 | 走安装流程（见下方） |
| 「帮我装一下安全规则」 | 走安装流程（见下方） |
| 已安装，用户在做正常开发 | 不需要干预，正常工作 |
| 用户执行了危险操作被拦截 | 解释拦截原因，帮用户决定是否放行 |

**判断是否已安装：**
- 检查当前项目 `.claude/hooks/` 目录是否存在 `guard.sh`
- 或检查 `~/.codex/hooks.json` 是否包含 `cc-codex-hook.js`
- 如果不确定，重新运行安装脚本也可以；已有配置会尽量保留

---

### 第一步：安装

**判断当前 Agent 类型：**

| 你是谁 | 安装方式 |
|--------|----------|
| Claude Code | 运行下方 Claude Code 安装命令 |
| OpenAI Codex | 运行下方 Codex 安装命令 |
| 不确定 | 两个都装 |

#### Claude Code 安装（macOS / Linux）

```bash
git clone https://github.com/wismyzhizi2018/cc-hooks.git /tmp/cc-hooks
mkdir -p .claude
cp /tmp/cc-hooks/settings.json .claude/
cp -r /tmp/cc-hooks/hooks .claude/
cp /tmp/cc-hooks/CLAUDE.md ~/.claude/CLAUDE.md
chmod +x .claude/hooks/*.sh
rm -rf /tmp/cc-hooks
```

#### Claude Code 安装（Windows PowerShell）

```powershell
git clone https://github.com/wismyzhizi2018/cc-hooks.git $env:TEMP\cc-hooks
New-Item -ItemType Directory -Force -Path .claude | Out-Null
Copy-Item $env:TEMP\cc-hooks\settings.json .claude\
Copy-Item -Recurse $env:TEMP\cc-hooks\hooks .claude\
Copy-Item $env:TEMP\cc-hooks\CLAUDE.md $env:USERPROFILE\.claude\CLAUDE.md
Remove-Item -Recurse -Force $env:TEMP\cc-hooks
```

#### OpenAI Codex 安装（macOS / Linux）

```bash
git clone https://github.com/wismyzhizi2018/cc-hooks.git /tmp/agent-hooks
cd /tmp/agent-hooks
./install-codex.sh
```

#### OpenAI Codex 安装（Windows PowerShell）

```powershell
git clone https://github.com/wismyzhizi2018/cc-hooks.git $env:TEMP\agent-hooks
Set-Location $env:TEMP\agent-hooks
.\install-codex.ps1
```

**安装后重启你的 Agent 会话，hooks 才会生效。**

---

### 第二步：安装完成后

安装完成后，告诉用户：

> CC-Hooks 已安装！现在我会在执行危险操作前拦截并询问你确认。
>
> 被拦截的操作包括：
> - `git push`（禁止自动推送）
> - 在 `main`/`master`/`test` 分支提交
> - `git reset --hard`、`git stash`、`git clean -f` 等不可逆操作
> - 修改 `.env` 文件
>
> 如果你确认要执行，我会在命令末尾加上 `# USER_APPROVED`。

---

### 第三步：日常行为规范

安装 hooks 后，你的行为会自动受到约束。以下是关键规则：

#### 你不能做的事（会被拦截）

| 操作 | 为什么不行 |
|------|-----------|
| `git push` | 禁止自动推送，用户必须手动执行 |
| 在 `main`/`master`/`test` 上 `git commit` | 防止污染保护分支 |
| `git reset --hard` | 不可恢复，必须用户确认 |
| `git stash`（写操作） | 防止隐藏改动，必须用户确认 |
| `git checkout .` / `git restore .` | 会覆盖本地改动 |
| `git clean -f` | 会删除未跟踪文件 |
| `git pull`（不带 `--rebase`） | 避免多余 merge commit |
| 修改 `.env` 文件 | 保护敏感配置 |

#### 你要做的事

| 场景 | 正确做法 |
|------|----------|
| 需要推送代码 | 告诉用户手动执行 `git push` |
| 需要在保护分支提交 | 先创建 feature#/hotfix# 分支 |
| 需要 stash/reset | 先问用户是否同意 |
| commit 完成后 | 检查 Co-Authored-By 是否正确 |

#### 放行机制

如果用户明确同意执行被拦截的操作，在命令末尾追加 `# USER_APPROVED`：

```bash
git stash  # USER_APPROVED
git reset --hard HEAD~1  # USER_APPROVED
```

---

## 更新

重新运行对应安装器即可覆盖更新 hooks。安装器会去重旧的 `cc-codex-hook.js` 配置，不会删除用户已有的其他 hooks。

---

## 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建你的分支：`git checkout -b feat/my-feature`
3. 提交改动：`git commit -m 'feat: add my feature'`
4. 推送分支：`git push origin feat/my-feature`
5. 发起 Pull Request

---

## Star 趋势

[![Star History Chart](https://api.star-history.com/svg?repos=wismyzhizi2018/cc-hooks&type=Date)](https://star-history.com/#wismyzhizi2018/cc-hooks&Date)

---

## 许可证

[MIT License](LICENSE) — 可自由使用、修改、分发，包括商业用途。
