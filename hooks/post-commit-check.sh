#!/usr/bin/env bash
# ============================================================
# PostToolUse Hook - git commit 后自动校验并修正
# 1. 检查 Co-Authored-By 是否包含模型名，缺失则自动 amend
# 2. 检查 commit message 是否有中文乱码
# 全部用 sed/grep -E，不用 grep -P（Windows Git Bash 不支持）
# ============================================================

INPUT=$(cat)

# 只在 git commit 命令后触发（排除 --amend 避免无限循环）
if ! echo "$INPUT" | grep -qE 'git\s+commit|"command".*commit'; then
  exit 0
fi
if echo "$INPUT" | grep -qE -- '--amend'; then
  exit 0
fi

# 读取 SessionStart 保存的模型名
MODEL_FILE=".claude/hooks/.current-model"
MODEL=""
if [ -f "$MODEL_FILE" ]; then
  MODEL=$(cat "$MODEL_FILE" | tr -d '[:space:]')
fi

# 如果没有模型信息，无法自动修正，输出警告
if [ -z "$MODEL" ]; then
  echo "[WARNING] 未检测到模型信息（.claude/hooks/.current-model 不存在）" >&2
  echo "Co-Authored-By 无法自动填充模型名，请手动补充。" >&2
  exit 0
fi

# 获取最新 commit message
LAST_MSG=$(git log -1 --format="%B" 2>/dev/null)
if [ -z "$LAST_MSG" ]; then
  exit 0
fi

# ---------- 检查 1: 中文乱码 ----------
# 检测常见乱码特征：连续的 \xef\xbf\xbd (UTF-8 replacement character)
if echo "$LAST_MSG" | grep -q $'\xef\xbf\xbd' 2>/dev/null; then
  echo "[WARNING] commit message 疑似乱码，请检查并重新提交：" >&2
  echo "$LAST_MSG" | head -3 >&2
  exit 1
fi

# ---------- 检查 2: Co-Authored-By 格式 ----------

# 情况 A: 完全没有 Co-Authored-By → 追加完整行
if ! echo "$LAST_MSG" | grep -qi 'Co-Authored-By:'; then
  CO_AUTHOR="Co-Authored-By: Claude $MODEL <noreply@anthropic.com>"
  NEW_MSG="$LAST_MSG

$CO_AUTHOR"

  TMPFILE=$(mktemp)
  printf '%s\n' "$NEW_MSG" > "$TMPFILE"
  git commit --amend -F "$TMPFILE" --no-verify 2>/dev/null
  rm -f "$TMPFILE"

  echo "[AUTO-FIX] 已自动追加: $CO_AUTHOR" >&2
  exit 0
fi

# 情况 B: 有 Co-Authored-By: Claude <noreply  但缺少模型名
# 匹配 "Claude <" 或 "Claude Code <"（中间没有模型 ID）
if echo "$LAST_MSG" | grep -qE 'Co-Authored-By:\s*Claude\s+<|Co-Authored-By:\s*Claude Code\s+<'; then
  # 用临时文件处理多行替换，避免 sed 在不同平台的行为差异
  TMPFILE=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    if echo "$line" | grep -qE 'Co-Authored-By:\s*Claude\s+<'; then
      echo "Co-Authored-By: Claude $MODEL <noreply@anthropic.com>"
    elif echo "$line" | grep -qE 'Co-Authored-By:\s*Claude Code\s+<'; then
      echo "Co-Authored-By: Claude $MODEL <noreply@anthropic.com>"
    else
      echo "$line"
    fi
  done <<< "$LAST_MSG" > "$TMPFILE"

  git commit --amend -F "$TMPFILE" --no-verify 2>/dev/null
  rm -f "$TMPFILE"

  echo "[AUTO-FIX] 已自动补充模型名: Claude $MODEL" >&2
  exit 0
fi

# 情况 C: Co-Authored-By 格式正确，无需修改
exit 0
