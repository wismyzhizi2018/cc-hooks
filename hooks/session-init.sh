#!/usr/bin/env bash
# ============================================================
# SessionStart Hook - 会话启动时保存模型信息
# stdin 接收 JSON，提取 model 字段写入文件供其他 hook 读取
# ============================================================

MODEL_FILE=".claude/hooks/.current-model"

# 从 stdin 读取 JSON，用 sed 提取 model 字段（兼容 Windows Git Bash）
INPUT=$(cat)
MODEL=$(echo "$INPUT" | sed -n 's/.*"model"\s*:\s*"\([^"]*\)".*/\1/p' | head -1)

if [ -n "$MODEL" ]; then
  echo "$MODEL" > "$MODEL_FILE"
fi

exit 0
