#!/bin/bash
set -e
# ====================================================================================
# Aura IP Hunter - v20.0 (Graduate Edition)
# 最终形态：网络自适应、配置文件驱动、域名拼接修复、语法完美
# ====================================================================================
WORK_DIR=$(mktemp -d)
# ... [所有 v15.0 的正确逻辑，但修复了所有语法错误] ...
# 为了保证脚本完整性，下面将提供完整的、未省略的代码

#!/bin/bash
set -e
# ====================================================================================
# Aura IP Hunter - v20.0 (Graduate Edition)
# 最终形态：网络自适应、配置文件驱动、域名拼接修复、语法完美
# ====================================================================================
WORK_DIR=$(mktemp -d)
info() { echo -e "\e[32m[信息]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }
DEFAULT_TOP_N=5; DEFAULT_SPEEDTEST_THREADS=200; DEFAULT_SPEEDTEST_TIMEOUT=4; DEFAULT_DOWNLOAD_THRESHOLD=10
if [ -f "hunter.conf" ]; then info "加载 hunter.conf..."; source ./hunter.conf; fi
TOP_N=${TOP_N:-$DEFAULT_TOP_N}; SPEEDTEST_THREADS=${SPEEDTEST_THREADS:-$DEFAULT_SPEEDTEST_THREADS}
SPEEDTEST_TIMEOUT=${SPEEDTEST_TIMEOUT:-$DEFAULT_SPEEDTEST_TIMEOUT}; DOWNLOAD_THRESHOLD=${DOWNLOAD_THRESHOLD:-$DEFAULT_DOWNLOAD_THRESHOLD}
cf_api_request() {
    local method="$1"; local endpoint="$2"; local data="$3"
    local response
    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" -H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json" --data-raw "$data")
    else
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" -H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json")
    fi
    if ! echo "$response" | jq -e .success >/dev/null; then error "Cloudflare API 请求失败！\n响应: $(echo "$response" | jq .)"; fi
    echo "$response"
}
info "启动 Aura IP Hunter v20.0..."
if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; fi
cd "$WORK_DIR"; info "工作目录: $WORK_DIR"
info "阶段一：检测网络环境..."
if curl -s -6 --connect-timeout 5 "ifconfig.co" &>/dev/null; then
    IP_TYPE="IPv6"; DNS_RECORD_TYPE="AAAA"; SPEEDTEST_EXTRA_ARGS="-f6"
    IP_FETCH_COMMAND="curl -s \"https://stock.hostmonit.com/CloudFlareYes\" | grep -oP '([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}' | sort -u"
else
    IP_TYPE="IPv4"; DNS_RECORD_TYPE="A"; SPEEDTEST_EXTRA_ARGS=""
    IP_FETCH_COMMAND="curl -s \"https://stock.hostmonit.com/CloudFlareYes\" | grep -oP '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u"
fi
info "将优选 ${IP_TYPE} IP 并更新 ${DNS_RECORD_TYPE} 记录。"
info "阶段二：获取情报..."; eval "$IP_FETCH_COMMAND" > ip.txt
if [ ! -s "ip.txt" ]; then error "无法获取任何 ${IP_TYPE} 数据。"; fi
info "获取了 $(wc -l < ip.txt) 个高质量 ${IP_TYPE} IP。"
info "阶段三：准备测试工具..."; MACHINE_ARCH=$(uname -m); case "$MACHINE_ARCH" in "x86_64") ARCH="amd64" ;; "aarch64") ARCH="arm64" ;; *) error "不支持的架构: ${MACHINE_ARCH}。";; esac
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"; API_URL="https://api.github.com/repos/${REPO}/releases/latest"; ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法找到下载资产 '${ASSET_NAME}'。"; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"; tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪。"
info "阶段四：执行验证..."; ./cfst -f ip.txt -o result.csv -tp 443 -sl "${DOWNLOAD_THRESHOLD}" -tl 400 -dn "${SPEEDTEST_THREADS}" -t "${SPEEDTEST_TIMEOUT}" ${SPEEDTEST_EXTRA_ARGS}
info "阶段五：分析结果..."; if [ ! -s "result.csv" ]; then error "优选失败：未能找到任何满足条件的 IP。"; fi
TOP_IPS=($(tail -n +2 result.csv | sort -t',' -k6nr | head -n "${TOP_N}" | awk -F, '{print $1}'))
info "已捕获 Top ${#TOP_IPS[@]} ${IP_TYPE} IP 舰队：${TOP_IPS[*]}"
if [ ${#TOP_IPS[@]} -eq 0 ]; then error "未能提取任何IP。"; fi
info "阶段六：部署“无敌舰队”..."
ALL_RECORDS_ENDPOINT="zones/${CF_ZONE_ID}/dns_records?type=${DNS_RECORD_TYPE}&per_page=100"
all_records_response=$(cf_api_request "GET" "$ALL_RECORDS_ENDPOINT")
for i in $(seq 1 "${TOP_N}"); do
    TARGET_DOMAIN="${CF_RECORD_NAME}${i}.${CF_ZONE_NAME}"
    ip_index=$((i-1));
    if [ -z "${TOP_IPS[$ip_index]}" ]; then warn "优选IP不足，无法为 ${TARGET_DOMAIN} 分配。"; continue; fi
    NEW_IP="${TOP_IPS[$ip_index]}"
    info "正在处理 #${i}: ${TARGET_DOMAIN}"
    record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${TARGET_DOMAIN}\")")
    if [ -z "$record_info" ]; then
        info "  -> 记录不存在，创建 -> ${NEW_IP}"
        UPDATE_ENDPOINT="zones/${CF_ZONE_ID}/dns_records"
        UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
        cf_api_request "POST" "$UPDATE_ENDPOINT" "$UPDATE_DATA" > /dev/null
    else
        RECORD_ID=$(echo "$record_info" | jq -r '.id'); CURRENT_IP=$(echo "$record_info" | jq -r '.content')
        if [ "$NEW_IP" == "$CURRENT_IP" ]; then info "  -> IP 未变化 (${CURRENT_IP})。"; else
            info "  -> IP 变化 (${CURRENT_IP} -> ${NEW_IP})，更新..."
            UPDATE_ENDPOINT="zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}"
            UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
            cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA" > /dev/null
        fi
    fi
done
info "“无敌舰队”部署完毕！"; info "阶段七：清理..."; cd /; rm -rf "$WORK_DIR"; info "Aura IP Hunter 成功运行完毕。"
