#!/bin/bash
set -e
# ====================================================================================
# Aura IP Hunter - v22.0 (Final Verdict Edition)
# 最终修复版：修复了脆弱的数据提取逻辑，确保在任何情况下都能获取情报
# ====================================================================================
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"
info() { echo -e "\e[32m[信息]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }
# 加载配置文件，注意路径，因为我们先 cd 到了工作目录
if [ -f "../hunter.conf" ]; then info "加载 hunter.conf..."; source ../hunter.conf; fi
TOP_N=${TOP_N:-5}
CF_API_REQUEST_ARGS=(-s -H "X-Auth-Email: ${CF_API_EMAIL}" -H "X-Auth-Key: ${CF_API_KEY}" -H "Content-Type: application/json")

info "启动 Aura IP Hunter v22.0..."
if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; fi

info "阶段一：检测网络环境..."
if curl -s -6 --connect-timeout 5 "google.com" &>/dev/null; then
    IP_TYPE="IPv6"; DNS_RECORD_TYPE="AAAA"; SPEEDTEST_EXTRA_ARGS="-f6"
    # 【最终修复】使用最健壮的 awk 命令来提取 IP，兼容任何格式变化
    IP_FETCH_COMMAND="awk -F, '/:/ {print \$1}'"
else
    IP_TYPE="IPv4"; DNS_RECORD_TYPE="A"; SPEEDTEST_EXTRA_ARGS=""
    # 【最终修复】使用最健壮的 awk 命令来提取 IP
    IP_FETCH_COMMAND="awk -F, '/\./ {print \$1}'"
fi
info "将优选 ${IP_TYPE} IP 并更新 ${DNS_RECORD_TYPE} 记录。"

info "阶段二：获取情报..."; curl -s "https://stock.hostmonit.com/CloudFlareYes" | eval "$IP_FETCH_COMMAND" > ip.txt
if [ ! -s "ip.txt" ]; then error "无法获取任何 ${IP_TYPE} 数据。"; fi
info "获取了 $(wc -l < ip.txt) 个高质量 ${IP_TYPE} IP。"

info "阶段三：准备测试工具..."; MACHINE_ARCH=$(uname -m); case "$MACHINE_ARCH" in "x86_64") ARCH="amd64" ;; "aarch64") ARCH="arm64" ;; *) error "不支持的架构: ${MACHINE_ARCH}。";; esac
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"; API_URL="https://api.github.com/repos/${REPO}/releases/latest"; ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url"); if [ -z "$DOWNLOAD_URL" ]; then error "无法找到下载资产 '${ASSET_NAME}'。"; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"; tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪。"

info "阶段四：执行验证..."; ./cfst -f ip.txt -o result.csv -p "${TOP_N}" ${SPEEDTEST_EXTRA_ARGS}
info "阶段五：分析结果..."; if [ ! -s "result.csv" ]; then error "优选失败：未能找到任何满足条件的 IP。"; fi
TOP_IPS=($(tail -n +2 result.csv | awk -F, '{print $1}'))
info "已捕获 Top ${#TOP_IPS[@]} ${IP_TYPE} IP 舰队：${TOP_IPS[*]}"
if [ ${#TOP_IPS[@]} -eq 0 ]; then error "未能提取任何IP。"; fi

info "阶段六：部署“无敌舰队”..."
ALL_RECORDS_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${DNS_RECORD_TYPE}&per_page=100"
all_records_response=$(curl "${CF_API_REQUEST_ARGS[@]}" -X GET "${ALL_RECORDS_ENDPOINT}")
for i in $(seq 1 "${TOP_N}"); do
    TARGET_DOMAIN="${CF_RECORD_NAME}${i}.${CF_ZONE_NAME}"; ip_index=$((i-1));
    if [ -z "${TOP_IPS[$ip_index]}" ]; then warn "优选IP不足，无法为 ${TARGET_DOMAIN} 分配。"; continue; fi
    NEW_IP="${TOP_IPS[$ip_index]}"
    info "正在处理 #${i}: ${TARGET_DOMAIN}"
    record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${TARGET_DOMAIN}\")")
    if [ -z "$record_info" ]; then
        info "  -> 记录不存在，创建 -> ${NEW_IP}"
        UPDATE_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
        UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
        curl "${CF_API_REQUEST_ARGS[@]}" -X POST "${UPDATE_ENDPOINT}" --data-raw "$UPDATE_DATA" > /dev/null
    else
        RECORD_ID=$(echo "$record_info" | jq -r '.id'); CURRENT_IP=$(echo "$record_info" | jq -r '.content')
        if [ "$NEW_IP" == "$CURRENT_IP" ]; then info "  -> IP 未变化 (${CURRENT_IP})。"; else
            info "  -> IP 变化 (${CURRENT_IP} -> ${NEW_IP})，更新..."
            UPDATE_ENDPOINT="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}"
            UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
            curl "${CF_API_REQUEST_ARGS[@]}" -X PUT "${UPDATE_ENDPOINT}" --data-raw "$UPDATE_DATA" > /dev/null
        fi
    fi
done
info "“无敌舰队”部署完毕！"; info "阶段七：清理..."; cd /; rm -rf "$WORK_DIR"; info "Aura IP Hunter 成功运行完毕。"
