#!/usr/bin/env bash
# ============================================================
# CLAUDE.md 铁律硬拦截 - PreToolUse Hook for Bash
# 接收 Bash 工具的 JSON 输入（stdin），检查违规操作并拦截
# exit 0 = 放行, exit 2 = 拦截
# 拦截消息输出到 stderr，Claude Code 会展示给用户
#
# 放行机制：在命令末尾附加 # USER_APPROVED 注释
# 例：git stash  # USER_APPROVED
# ============================================================

INPUT=$(cat)

# ------------------------------------------------------------
# 规则 1: 禁止 git push（绝对拦截，无放行机制）
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+push'; then
  echo "[BLOCKED] git push 被拦截" >&2
  echo "原因：CLAUDE.md 规定禁止任何情况下自动 git push。" >&2
  echo "处理：请用户在终端手动执行以下命令。" >&2
  PUSH_CMD=$(echo "$INPUT" | grep -oP 'git\s+push[^\n"]*' | head -1)
  echo "  ${PUSH_CMD:-git push}" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 2: 禁止在 main/master/test 分支上 git commit
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+commit'; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$BRANCH" =~ ^(main|master|test)$ ]]; then
    if echo "$INPUT" | grep -q '# USER_APPROVED'; then
      exit 0
    fi
    echo "[BLOCKED] git commit 被拦截" >&2
    echo "原因：CLAUDE.md 规定禁止在 $BRANCH 分支上直接提交代码。" >&2
    echo "处理：请先创建 feature# 或 hotfix# 分支。如确需在当前分支提交，请立即调用 AskUserQuestion 工具向用户确认，用户确认后加上 # USER_APPROVED 重新执行。" >&2
    exit 2
  fi
fi

# ------------------------------------------------------------
# 规则 3: 禁止 git commit -F - （管道传中文会乱码）
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+commit.*-F\s*-'; then
  echo "[BLOCKED] git commit -F - 被拦截" >&2
  echo "原因：CLAUDE.md 规定禁止此用法，Windows 下管道传中文会导致 commit message 乱码。" >&2
  echo "处理：请使用多个 -m 参数，或先写入 UTF-8 文件再 git commit -F <file>。" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 4: 禁止擅自 git stash（用户明确同意后可放行）
# 只读子命令（list/show）不修改工作区，直接放行
# stash drop 会删除记录，走 USER_APPROVED 流程
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+stash'; then
  # 放行只读子命令
  if echo "$INPUT" | grep -qE 'git\s+stash\s+(list|show)'; then
    exit 0
  fi
  if echo "$INPUT" | grep -q '# USER_APPROVED'; then
    exit 0
  fi
  echo "[BLOCKED] git stash 被拦截" >&2
  echo "原因：CLAUDE.md 规定未经用户同意禁止擅自 stash。" >&2
  echo "处理：请立即调用 AskUserQuestion 工具，向用户确认是否允许执行本次操作。用户确认后，在命令末尾加上 # USER_APPROVED 重新执行。" >&2
  STASH_CMD=$(echo "$INPUT" | grep -oP 'git\s+stash[^\n"]*' | head -1)
  echo "  ${STASH_CMD:-git stash}  # USER_APPROVED" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 5: 禁止 git reset --hard（用户明确同意后可放行）
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+reset\s+--hard'; then
  if echo "$INPUT" | grep -q '# USER_APPROVED'; then
    exit 0
  fi
  echo "[BLOCKED] git reset --hard 被拦截" >&2
  echo "原因：CLAUDE.md 规定未经用户同意禁止重置工作区，该操作不可恢复。" >&2
  echo "处理：请立即调用 AskUserQuestion 工具，向用户确认是否允许执行本次操作。用户确认后，在命令末尾加上 # USER_APPROVED 重新执行。" >&2
  RESET_CMD=$(echo "$INPUT" | grep -oP 'git\s+reset\s+--hard[^\n"]*' | head -1)
  echo "  ${RESET_CMD:-git reset --hard}  # USER_APPROVED" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 6: 禁止 git checkout . / git restore .（用户明确同意后可放行）
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+(checkout|restore)\s+\.'; then
  if echo "$INPUT" | grep -q '# USER_APPROVED'; then
    exit 0
  fi
  echo "[BLOCKED] git checkout/restore . 被拦截" >&2
  echo "原因：CLAUDE.md 规定未经用户同意禁止覆盖本地改动，该操作不可恢复。" >&2
  echo "处理：请立即调用 AskUserQuestion 工具，向用户确认是否允许执行本次操作。用户确认后，在命令末尾加上 # USER_APPROVED 重新执行。" >&2
  RESTORE_CMD=$(echo "$INPUT" | grep -oP 'git\s+(checkout|restore)[^\n"]*' | head -1)
  echo "  ${RESTORE_CMD:-git checkout .}  # USER_APPROVED" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 7: 禁止 git clean -f（用户明确同意后可放行）
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  if echo "$INPUT" | grep -q '# USER_APPROVED'; then
    exit 0
  fi
  echo "[BLOCKED] git clean -f 被拦截" >&2
  echo "原因：CLAUDE.md 规定未经用户同意禁止删除未跟踪文件，该操作不可恢复。" >&2
  echo "处理：请立即调用 AskUserQuestion 工具，向用户确认是否允许执行本次操作。用户确认后，在命令末尾加上 # USER_APPROVED 重新执行。" >&2
  CLEAN_CMD=$(echo "$INPUT" | grep -oP 'git\s+clean\s+-[^\n"]*' | head -1)
  echo "  ${CLEAN_CMD:-git clean -f}  # USER_APPROVED" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 8: 禁止 git pull 不带 --rebase
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'git\s+pull' && ! echo "$INPUT" | grep -qE 'git\s+pull\s+--rebase'; then
  echo "[BLOCKED] git pull 被拦截" >&2
  echo "原因：CLAUDE.md 规定优先使用 git pull --rebase 同步代码。" >&2
  echo "处理：请改用 git pull --rebase。" >&2
  exit 2
fi

# ------------------------------------------------------------
# 规则 9: IM 通知 - 检查是否跳过 dryRun
# ------------------------------------------------------------
if echo "$INPUT" | grep -qE 'notify\.js'; then
  PARAMS_FILE=$(echo "$INPUT" | grep -oP '(?<=--params-file\s)[^\s"]+' | head -1)
  if [ -n "$PARAMS_FILE" ] && [ -f "$PARAMS_FILE" ]; then
    if grep -qE '"dryRun"\s*:\s*false' "$PARAMS_FILE"; then
      if echo "$INPUT" | grep -q '# USER_APPROVED'; then
        exit 0
      fi
      echo "[BLOCKED] IM 真实发送被拦截" >&2
      echo "原因：CLAUDE.md 规定必须先 dryRun 预览，用户确认后才能真实发送。" >&2
      echo "处理：请立即调用 AskUserQuestion 工具，向用户确认是否允许真实发送。用户确认后，在命令末尾加上 # USER_APPROVED 重新执行。" >&2
      exit 2
    fi
    if ! grep -qE '"dryRun"' "$PARAMS_FILE"; then
      echo "[BLOCKED] notify.js 被拦截" >&2
      echo "原因：CLAUDE.md 规定 params-file 中未包含 dryRun 字段，无法判断是否为预览。" >&2
      echo "处理：请在参数中显式设置 dryRun: true 先预览。" >&2
      exit 2
    fi
  fi
fi

# 所有检查通过，放行
exit 0
