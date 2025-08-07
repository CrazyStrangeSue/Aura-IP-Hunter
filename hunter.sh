#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v11.0 (情报融合版)
# 核心升级：直接从中国大陆视角的监控站融合实时、低延迟的 IP 数据
# ====================================================================================

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; }

# (cf_api_request 函数保持不变)
function cf_api_request() {
    # ... (此处省略函数内部代码，与上一版完全相同) ...
}

# --- 主工作流 ---
info "启动 Aura IP Hunter v11.0 (情报融合版)..."
# (Secrets 检查保持不变)
# ...
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

# --- 阶段一/二：【核心升级】情报融合 ---
info "阶段一/二：融合中国大陆视角的实时情报..."

# 我们直接从 stock.hostmonit.com 获取已经被验证为低延迟的 IP
# 这是最精准、最高效的情报来源
FALLBACK_IP_SOURCE="https://stock.hostmonit.com/CloudFlareYes"
info "正在从情报源下载数据: ${FALLBACK_IP_SOURCE}"

# 使用 curl 下载数据，并通过 awk 提取所有 IP 地址 (第一列)，然后去重
curl -s "${FALLBACK_IP_SOURCE}" | awk -F, '{print $1}' | sort -u > ip.txt

if [ ! -s "ip.txt" ]; then
    error "无法从情报源获取任何 IP 数据，脚本中止。"
    exit 1
fi

info "情报融合完成！成功获取 $(wc -l < ip.txt) 个经过预筛选的高质量 IP。"

# --- 阶段三：准备测试工具 (保持不变) ---
info "阶段三：准备测试工具..."
# ... (此部分代码与上一版完全相同) ...

# --- 阶段四：执行最终验证性测速 ---
info "阶段四：在高质量 IP 池中执行最终验证..."
# 既然 IP 质量已经很高，我们可以稍微放宽延迟，重点关注下载速度
# -sl 5: 下载速度必须高于 5 MB/s
# -tl 400: 延迟在 400ms 内即可 (因为我们的测试点在美国)
# -dn 10: 从延迟最低的10个IP里选速度最快的
./cfst -f ip.txt -o result.csv -tp 443 -sl 5 -tl 400 -dn 10

# --- 阶段五：分析结果与最终决策 ---
BEST_IP=""
if [ -s "result.csv" ]; then
    info "阶段五：分析结果..."
    BEST_LINE=$(tail -n +2 result.csv | sort -t',' -k6nr | head -n 1)
    BEST_IP=$(echo "$BEST_LINE" | awk -F, '{print $1}')
    BEST_SPEED=$(echo "$BEST_LINE" | awk -F, '{print $6}')
    info "本次优选成功！最佳 IP 为: ${BEST_IP} (速度: ${BEST_SPEED} MB/s)"
else
    warn "警告：在高质量 IP 池中也未能找到满足速度条件的 IP。"
    info "启动备用策略：直接使用情报源中延迟最低的 IP。"
    # 如果速度测试失败，我们就退一步，直接用情报源里延迟最低的那个
    BEST_IP=$(curl -s "${FALLBACK_IP_SOURCE}" | awk -F, '{print $1}' | head -n 1)
    warn "已选择情报源中延迟最低的 IP 作为备用: ${BEST_IP}"
fi

if [ -z "$BEST_IP" ]; then
    error "所有策略均失败，脚本中止。"
    exit 1
fi
info "最终决策的 IP 是: ${BEST_IP}"

# --- 阶段六 & 七 (更新与清理) ---
# ... (此部分代码与上一版完全相同) ...
