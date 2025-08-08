#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v12.0 (架构自适应版)
# 自动检测运行环境架构 (amd64/arm64) 并下载对应工具
# ====================================================================================

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; }

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

info "启动 Aura IP Hunter v12.0 (架构自适应版)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ]; then
  error "一个或多个必需的 Secrets 未设置。"
  exit 1
fi
CF_RECORD_NAME_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

info "阶段一/二：融合中国大陆视角的实时情报..."
FALLBACK_IP_SOURCE="https://stock.hostmonit.com/CloudFlareYes"
info "正在从情报源下载数据: ${FALLBACK_IP_SOURCE}"
curl -s "${FALLBACK_IP_SOURCE}" | awk -F, '{print $1}' | sort -u > ip.txt
if [ ! -s "ip.txt" ]; then
    error "无法从情报源获取任何 IP 数据，脚本中止。"
    exit 1
fi
info "情报融合完成！成功获取 $(wc -l < ip.txt) 个经过预筛选的高质量 IP。"

info "阶段三：准备测试工具 (架构自适应)..."
MACHINE_ARCH=$(uname -m)
case "$MACHINE_ARCH" in
    "x86_64") ARCH="amd64" ;;
    "aarch64") ARCH="arm64" ;;
    *)
        error "不支持的系统架构: ${MACHINE_ARCH}。本项目目前只支持 x86_64 (amd64) 和 aarch64 (arm64)。"
        exit 1
        ;;
esac
info "检测到系统架构: ${MACHINE_ARCH}, 对应工具架构: ${ARCH}"
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
info "准备从镜像仓库下载资产: ${ASSET_NAME}"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法从镜像仓库找到名为 '${ASSET_NAME}' 的下载资产。请检查军火库是否已同步该版本。"; exit 1; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"
tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

info "阶段四：在高质量 IP 池中执行最终验证..."
./cfst -f ip.txt -o result.csv -tp 443 -sl 5 -tl 400 -dn 10

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
    BEST_IP=$(curl -s "${FALLBACK_IP_SOURCE}" | awk -F, '{print $1}' | head -n 1)
    warn "已选择情报源中延迟最低的 IP 作为备用: ${BEST_IP}"
fi

if [ -z "$BEST_IP" ]; then
    error "所有策略均失败，脚本中止。"
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
