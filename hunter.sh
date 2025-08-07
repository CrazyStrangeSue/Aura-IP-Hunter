#!/bin/bash
set -e

# ====================================================================================
# Aura IP Hunter - 法医诊断脚本 v5.0
# 目的：隔离并展示隐藏在 Secret 变量中的“幽灵字符”
# ====================================================================================

echo "--- 开始法医分析 ---"

if [ -z "$CF_RECORD_NAME" ]; then
  echo "错误：未能从环境中读取到 CF_RECORD_NAME Secret。"
  exit 1
fi

echo ""
echo "--- 步骤 1: 打印原始 Secret 变量 (我们看到的样子) ---"
echo "CF_RECORD_NAME 的值是: [${CF_RECORD_NAME}]"

echo ""
echo "--- 步骤 2: 使用 'od -c' 命令，暴露所有隐藏字符 ---"
echo "这是计算机真正看到的样子："
echo -n "$CF_RECORD_NAME" | od -c

echo ""
echo "--- 步骤 3: 尝试用 'tr -d [:cntrl:]' 进行清理 ---"
CF_RECORD_NAME_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]')
echo "清理后的变量 (我们看到的样子): [${CF_RECORD_NAME_CLEAN}]"

echo ""
echo "--- 步骤 4: 再次使用 'od -c' 检查清理效果 ---"
echo "这是清理后，计算机真正看到的样子："
echo -n "$CF_RECORD_NAME_CLEAN" | od -c

echo ""
echo "--- 法医分析结束 ---"
