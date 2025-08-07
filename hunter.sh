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

function cf_api_request() {
    local method="$1"; local endpoint="$2"; local data="$3"; local response
    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" -H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json" --data-raw "$data")
    else
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" -H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json")
    fi
    if ! echo "$response" | jq -e .success >/dev/null; then error "Cloudflare API 请求失败！\n响应: $(echo "$response" | jq .)"; return 1; fi
    echo "$response"
}

function gather_intelligence() {
    info "阶段一：启动天网侦察兵模块..."
    local targets=("www.huaweicloud.com" "www.alibabacloud.com" "www.tencentcloud.com" "www.bytedance.com" "www.dji.com" "gitee.com" "www.mi.com/global/")
    info "已锁定 ${#targets[@]} 个高价值目标。"
    declare -A dns_locations=(["香港"]="1.2.15.255" ["东京"]="1.1.1.1" ["新加坡"]="1.0.0.1" ["法兰克福"]="8.8.4.4" ["美西"]="8.8.8.8")
    info "部署了 ${#dns_locations[@]} 个全球侦察节点。"
    touch resolved_ips.txt
    for domain in "${targets[@]}"; do
        for location_name in "${!dns_locations[@]}"; do
            location_ip=${dns_locations[$location_name]}
            info "正在从 [${location_name}] 侦察目标: ${domain}..."
            curl -s "https://dns.google/resolve?name=${domain}&type=A&edns_client_subnet=${location_ip}" | jq -r '.Answer[]? | select(.type == 1) | .data' >> resolved_ips.txt
        done
    done
    sort -u resolved_ips.txt -o unique_ips.txt
    info "全球侦察完成，初步捕获 $(wc -l < unique_ips.txt) 个独立 IP 地址。"
    info "正在对捕获的 IP 进行分析，提取 BGP 网段..."
    touch bgp_prefixes.txt
    for ip in $(cat unique_ips.txt); do
        whois -h whois.cymru.com " -v $ip" | awk -F'|' 'NR>1 {gsub(/ /, "", $3); print $3}' >> bgp_prefixes.txt
    done
    sort -u bgp_prefixes.txt -o golden_cidrs.txt
    if [ ! -s "golden_cidrs.txt" ]; then
        warn "天网侦察兵未能捕获任何有效的 BGP 网段，将回退到基础 IP 池。"
        return 1
    else
        info "情报分析完成！成功生成黄金 IP 段数据库 (golden_cidrs.txt)，包含 $(wc -l < golden_cidrs.txt) 个网段。"
        return 0
    fi
}

function get_fallback_ip_from_hostmonit() {
    info "冷启动：正在从 Hostmonit 获取备用 IP..."
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

info "启动 Aura IP Hunter v10.0 (凤凰涅槃版)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ]; then
  error "一个或多个必需的 Secrets 未设置。"
  exit 1
fi
CF_RECORD_NAME_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

if gather_intelligence; then
    info "使用天网侦察兵生成的黄金 IP 段作为主要狩猎场。"
    mv golden_cidrs.txt ip.txt
else
    info "回退到基础方案：下载社区维护的 IP 列表。"
    curl -sL https://raw.githubusercontent.com/ip-scanner/cloudflare/main/ips.txt -o ip.txt
fi
info "最终狩猎场准备就绪，总计 $(wc -l < ip.txt) 个 IP 段。"

info "阶段三：准备测试工具..."
ARCH="amd64"; REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法从镜像仓库找到名为 '${ASSET_NAME}' 的下载资产。"; exit 1; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"
tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

info "阶段四：执行速度测试..."
./cfst -f ip.txt -o result.csv -tp 443 -sl 2 -tl 200 -dn 1

BEST_IP=""
if [ -s "result.csv" ]; then
    info "阶段五：分析结果..."
    BEST_IP=$(tail -n +2 result.csv | awk -F, '{print $1}')
    info "本次优选成功！最佳 IP 为: ${BEST_IP}"
else
    warn "本次优选未能找到任何满足条件的 IP。"
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

info "阶段六：开始更新 Cloudflare DNS 记录..."
RECORD_ENDPOINT_FOR_CHECK="zones/${CF_ZONE_ID_CLEAN}/dns_records?name=${CF_RECORD_NAME_CLEAN}&type=A"
record_response_for_check=$(cf_api_request "GET" "$RECORD_ENDPOINT_FOR_CHECK")
if [ $? -ne 0 ]; then exit 1; fi
RECORD_ID=$(echo "$record_response_for_check" | jq -r '.result[0].id')
CURRENT_IP_IN_CLOUD=$(echo "$record_response_for_check" | jq -r '.result[0].content')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    error "未找到域名为 ${CF_RECORD_NAME_CLEAN} 的 A 记录。请先在 Cloudflare 上手动创建一个。"
    exit 1
fi
info "获取到记录 ID: ${RECORD_ID}, 当前云端 IP: ${CURRENT_IP_IN_CLOUD}"

if [ "$BEST_IP" == "$CURRENT_IP_IN_CLOUD" ]; then
    info "最终决策 IP 与当前云端 IP 相同，无需更新。"
else
    info "IP 地址已变化，准备更新！"
    UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records/${RECORD_ID}"
    UPDATE_DATA=$(jq -n --arg name "$CF_RECORD_NAME_CLEAN" --arg content "$BEST_IP" \
      '{type: "A", name: $name, content: $content, ttl: 120, proxied: false}')
    update_response=$(cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
    if [ $? -ne 0 ]; then exit 1; fi
    info "DNS 记录更新成功！新 IP 地址为: ${BEST_IP}"
fi

info "阶段七：清理..."
cd /; rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
