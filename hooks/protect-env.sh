#!/usr/bin/env bash
# ============================================================
# .env 文件保护 - PreToolUse Hook for Edit/Write
# 拦截对 .env 文件的修改和写入操作
# exit 0 = 放行, exit 2 = 拦截
# ============================================================

INPUT=$(cat)

# 从 JSON 输入中提取 file_path
FILE_PATH=$(echo "$INPUT" | grep -oP '(?<="file_path"\s*:\s*")[^"]*')

# 检查是否是 .env 文件（精确匹配 .env 或 .env.xxx）
BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
if [[ "$BASENAME" == ".env" || "$BASENAME" == .env.* ]]; then
  echo "[BLOCKED] .env 文件修改被拦截" >&2
  echo "原因：禁止 Claude 对 .env 文件进行修改或写入，保护敏感配置。" >&2
  echo "处理：请用户手动编辑 .env 文件。" >&2
  exit 2
fi

exit 0
