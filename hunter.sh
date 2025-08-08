#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v13.0 (无敌舰队版)
# 优选 Top 5 IP 并分别更新到 5 个独立的 DNS 记录
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

info "启动 Aura IP Hunter v13.0 (无敌舰队版)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ] || [ -z "$CF_ZONE_NAME" ]; then
  error "一个或多个必需的 Secrets (CF_API_KEY, CF_API_EMAIL, CF_ZONE_ID, CF_RECORD_NAME, CF_ZONE_NAME) 未设置。"
  exit 1
fi
CF_RECORD_PREFIX_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_NAME_CLEAN=$(echo "$CF_ZONE_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
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
    *) error "不支持的系统架构: ${MACHINE_ARCH}。"; exit 1 ;;
esac
info "检测到系统架构: ${MACHINE_ARCH}, 对应工具架构: ${ARCH}"
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
info "准备从镜像仓库下载资产: ${ASSET_NAME}"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法从镜像仓库找到名为 '${ASSET_NAME}' 的下载资产。"; exit 1; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"
tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

info "阶段四：在高质量 IP 池中执行最终验证..."
./cfst -f ip.txt -o result.csv -tp 443 -sl 5 -tl 400 -dn 20

info "阶段五：分析结果并提取 Top 5 IP..."
if [ ! -s "result.csv" ]; then
    error "优选失败：在高质量 IP 池中未能找到任何满足条件的 IP。脚本中止，以保持现有 DNS 记录稳定。"
    exit 1
fi
TOP_5_IPS=($(tail -n +2 result.csv | sort -t',' -k6nr | head -n 5 | awk -F, '{print $1}'))
info "本次优选成功！已捕获 Top ${#TOP_5_IPS[@]} IP 舰队："
for ip in "${TOP_5_IPS[@]}"; do
    echo "  -> ${ip}"
done
if [ ${#TOP_5_IPS[@]} -eq 0 ]; then
    error "优选成功但未能提取任何IP，脚本中止。"
    exit 1
fi

info "阶段六：开始部署“无敌舰队”至 Cloudflare DNS..."
ALL_RECORDS_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records?per_page=100"
all_records_response=$(cf_api_request "GET" "$ALL_RECORDS_ENDPOINT")
if [ $? -ne 0 ]; then exit 1; fi

for i in "${!TOP_5_IPS[@]}"; do
    FLEET_MEMBER_INDEX=$((i + 1))
    TARGET_DOMAIN="${CF_RECORD_PREFIX_CLEAN}${FLEET_MEMBER_INDEX}.${CF_ZONE_NAME_CLEAN}"
    NEW_IP="${TOP_5_IPS[i]}"
    
    info "正在处理舰队成员 #${FLEET_MEMBER_INDEX}: ${TARGET_DOMAIN}"
    record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${TARGET_DOMAIN}\")")
    
    if [ -z "$record_info" ]; then
        warn "未能在 Cloudflare 上找到预创建的 DNS 记录: ${TARGET_DOMAIN}。跳过此成员。"
        continue
    fi

    RECORD_ID=$(echo "$record_info" | jq -r '.id')
    CURRENT_IP=$(echo "$record_info" | jq -r '.content')
    info "  -> 记录 ID: ${RECORD_ID}, 当前 IP: ${CURRENT_IP}"

    if [ "$NEW_IP" == "$CURRENT_IP" ]; then
        info "  -> IP 未变化，无需更新。"
    else
        info "  -> IP 地址已变化，准备更新为 ${NEW_IP}..."
        UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records/${RECORD_ID}"
        UPDATE_DATA=$(jq -n --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: "A", name: $name, content: $content, ttl: 120, proxied: false}')
        update_response=$(cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
        if [ $? -ne 0 ]; then
            warn "  -> 更新 ${TARGET_DOMAIN} 失败！将继续处理下一个。"
        else
            info "  -> DNS 记录更新成功！"
        fi
    fi
done
info "“无敌舰队”部署完毕！"

info "阶段七：清理..."
cd /; rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
