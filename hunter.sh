#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v10.0 (凤凰涅槃版)
# 融合了高级失败备用策略和精确的测速需求
# ====================================================================================

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; }

# --- 函数定义区 ---

# (cf_api_request 函数保持不变)
function cf_api_request() {
    local method="$1"; local endpoint="$2"; local data="$3"; local response
    # ... (此处省略函数内部代码，与上一版完全相同)
}

# (gather_intelligence 函数保持不变)
function gather_intelligence() {
    info "阶段一：启动天网侦察兵模块..."
    # ... (此处省略函数内部代码，与上一版完全相同)
}

# 【全新】需求 4.2: 冷启动备用 IP 获取函数
function get_fallback_ip_from_hostmonit() {
    info "冷启动：正在从 Hostmonit 获取备用 IP..."
    # 从指定 URL 下载数据，提取联通 (CU) 的 IP 列表，并选择第一个 (通常是最好的)
    local fallback_ip=$(curl -s https://stock.hostmonit.com/CloudFlareYes | awk -F, '/CU/ {print $1}' | head -n 1)
    if [ -n "$fallback_ip" ]; then
        warn "获取到 Hostmonit 备用 IP: ${fallback_ip}"
        echo "$fallback_ip"
    else
        warn "无法从 Hostmonit 获取备用 IP，将使用最终备用 1.1.1.1"
        echo "1.1.1.1"
    fi
}

# --- 主工作流 ---

# (认证与初始化部分保持不变)
# ...

# --- 阶段一 & 二：智能情报驱动的 IP 池构建 (保持不变) ---
# ...

# --- 阶段三：准备测试工具 (保持不变) ---
# ...

# --- 阶段四：执行速度测试 (根据新需求调整) ---
info "阶段四：执行速度测试..."
# 需求 1: 延迟必须保持在 200ms 之内
# 需求 2: 只选出 1 个最好的 IP (通过 -dn 1 实现)
./cfst -f ip.txt -o result.csv -tp 443 -sl 2 -tl 200 -dn 1

# --- 阶段五：分析结果与失败备用策略 ---
BEST_IP=""
if [ -s "result.csv" ]; then
    info "阶段五：分析结果..."
    # 从结果中提取第一个 IP (因为我们只测了最好的一个)
    BEST_IP=$(tail -n +2 result.csv | awk -F, '{print $1}')
    info "本次优选成功！最佳 IP 为: ${BEST_IP}"
else
    warn "本次优选未能找到任何满足条件的 IP。"
    # 需求 4.1: 如果优选失败，则获取当前 DNS 记录中的 IP 作为备用
    info "启动失败备用策略：尝试获取当前云端 IP..."
    
    RECORD_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records?name=${CF_RECORD_NAME_CLEAN}&type=A"
    record_response=$(cf_api_request "GET" "$RECORD_ENDPOINT")
    
    if [ $? -eq 0 ]; then
        CURRENT_IP=$(echo "$record_response" | jq -r '.result[0].content')
        if [ -n "$CURRENT_IP" ] && [ "$CURRENT_IP" != "null" ]; then
            warn "获取到当前云端 IP: ${CURRENT_IP}，将保持不变。"
            BEST_IP="$CURRENT_IP"
        fi
    fi

    # 需求 4.2: 如果连当前 IP 都获取失败 (比如首次运行)，则启用冷启动备用策略
    if [ -z "$BEST_IP" ]; then
        warn "无法获取当前云端 IP，启动冷启动备用策略..."
        BEST_IP=$(get_fallback_ip_from_hostmonit)
    fi
fi

if [ -z "$BEST_IP" ]; then
    error "所有优选和备用策略均失败，无法确定最终 IP。脚本中止。"
    exit 1
fi
info "最终决策的 IP 是: ${BEST_IP}"

# --- 阶段六：更新 Cloudflare DNS 记录 ---
info "阶段六：开始更新 Cloudflare DNS 记录..."
# (此部分逻辑与上一版完全相同，只是现在处理的 BEST_IP 来源更丰富)
# ...

# --- 阶段七：清理 ---
# ...
