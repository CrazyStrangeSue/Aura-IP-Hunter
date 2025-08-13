#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v15.0 (毕业作品版)
# 最终形态：网络自适应、配置文件驱动、域名拼接修复
# ====================================================================================

WORK_DIR=$(mktemp -d)

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }

# --- 默认配置 ---
DEFAULT_TOP_N=5
DEFAULT_SPEEDTEST_THREADS=200
DEFAULT_SPEEDTEST_TIMEOUT=4
DEFAULT_DOWNLOAD_THRESHOLD=10

# --- 加载配置文件 ---
if [ -f "hunter.conf" ]; then
    info "加载 hunter.conf 配置文件..."
    source ./hunter.conf
fi

TOP_N=${TOP_N:-$DEFAULT_TOP_N}
SPEEDTEST_THREADS=${SPEEDTEST_THREADS:-$DEFAULT_SPEEDTEST_THREADS}
SPEEDTEST_TIMEOUT=${SPEEDTEST_TIMEOUT:-$DEFAULT_SPEEDTEST_TIMEOUT}
DOWNLOAD_THRESHOLD=${DOWNLOAD_THRESHOLD:-$DEFAULT_DOWNLOAD_THRESHOLD}

function cf_api_request() {
    # ... (此函数与 v14.1 保持一致)
}

info "启动 Aura IP Hunter v15.0 (毕业作品版)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ] || [ -z "$CF_ZONE_NAME" ]; then
  error "一个或多个必需的 Secrets 未设置。"
fi
# ... (其余代码与 v14.1 几乎完全一致，但修复了域名拼接和健壮性)

# --- 完整的、未省略的 hunter.sh v15.0 代码 ---
#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v15.0 (毕业作品版)
# 最终形态：网络自适应、配置文件驱动、域名拼接修复
# ====================================================================================

WORK_DIR=$(mktemp -d)

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }

# --- 默认配置 ---
DEFAULT_TOP_N=5
DEFAULT_SPEEDTEST_THREADS=200
DEFAULT_SPEEDTEST_TIMEOUT=4
DEFAULT_DOWNLOAD_THRESHOLD=10

# --- 加载配置文件 ---
if [ -f "hunter.conf" ]; then
    info "加载 hunter.conf 配置文件..."
    source ./hunter.conf
fi

TOP_N=${TOP_N:-$DEFAULT_TOP_N}
SPEEDTEST_THREADS=${SPEEDTEST_THREADS:-$DEFAULT_SPEEDTEST_THREADS}
SPEEDTEST_TIMEOUT=${SPEEDTEST_TIMEOUT:-$DEFAULT_SPEEDTEST_TIMEOUT}
DOWNLOAD_THRESHOLD=${DOWNLOAD_THRESHOLD:-$DEFAULT_DOWNLOAD_THRESHOLD}

function cf_api_request() {
    local method="$1"; local endpoint="$2"; local data="$3"; local response
    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" -H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json" --data-raw "$data")
    else
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" -H "X-Auth-Email: $CF_API_EMAIL" -H "X-Auth-Key: $CF_API_KEY" -H "Content-Type: application/json")
    fi
    if ! echo "$response" | jq -e .success >/dev/null; then error "Cloudflare API 请求失败！\n响应: $(echo "$response" | jq .)"; fi
    echo "$response"
}

info "启动 Aura IP Hunter v15.0 (毕业作品版)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ] || [ -z "$CF_ZONE_NAME" ]; then
  error "一个或多个必需的 Secrets 未设置。"
fi
if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; fi

CF_RECORD_PREFIX_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_NAME_CLEAN=$(echo "$CF_ZONE_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

info "阶段一：自动检测运行环境网络类型..."
if curl -s -6 --connect-timeout 5 "ifconfig.co" &>/dev/null; then
    IP_TYPE="IPv6"; DNS_RECORD_TYPE="AAAA"; SPEEDTEST_EXTRA_ARGS="-f6"
    IP_FETCH_COMMAND="curl -s \"https://stock.hostmonit.com/CloudFlareYes\" | grep -oP '([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}' | sort -u"
else
    IP_TYPE="IPv4"; DNS_RECORD_TYPE="A"; SPEEDTEST_EXTRA_ARGS=""
    IP_FETCH_COMMAND="curl -s \"https://stock.hostmonit.com/CloudFlareYes\" | grep -oP '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u"
fi
info "检测到优先网络环境为: ${IP_TYPE}。将优选此类 IP 并更新 ${DNS_RECORD_TYPE} 记录。"

info "阶段二：融合 ${IP_TYPE} 实时情报..."
eval "$IP_FETCH_COMMAND" > ip.txt
if [ ! -s "ip.txt" ]; then error "无法从情报源获取任何 ${IP_TYPE} 数据。"; fi
info "情报融合完成！获取了 $(wc -l < ip.txt) 个高质量 ${IP_TYPE} IP。"

info "阶段三：准备测试工具 (架构自适应)..."
MACHINE_ARCH=$(uname -m); case "$MACHINE_ARCH" in "x86_64") ARCH="amd64" ;; "aarch64") ARCH="arm64" ;; *) error "不支持的架构: ${MACHINE_ARCH}。";; esac
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"; API_URL="https://api.github.com/repos/${REPO}/releases/latest"; ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法找到下载资产 '${ASSET_NAME}'。"; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"; tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

info "阶段四：在高质量 ${IP_TYPE} IP 池中执行验证..."
./cfst -f ip.txt -o result.csv -tp 443 -sl ${DOWNLOAD_THRESHOLD} -tl 400 -dn ${SPEEDTEST_THREADS} -t ${SPEEDTEST_TIMEOUT} ${SPEEDTEST_EXTRA_ARGS}

info "阶段五：分析结果并提取 Top ${TOP_N} IP..."
if [ ! -s "result.csv" ]; then error "优选失败：未能找到任何满足条件的 IP。"; fi
TOP_IPS=($(tail -n +2 result.csv | sort -t',' -k6nr | head -n ${TOP_N} | awk -F, '{print $1}'))
info "已捕获 Top ${#TOP_IPS[@]} ${IP_TYPE} IP 舰队：${TOP_IPS[*]}"
if [ ${#TOP_IPS[@]} -eq 0 ]; then error "优选成功但未能提取任何IP。"; fi

info "阶段六：部署“无敌舰队”至 Cloudflare DNS (${DNS_RECORD_TYPE} 记录)..."
ALL_RECORDS_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records?type=${DNS_RECORD_TYPE}&per_page=100"
all_records_response=$(cf_api_request "GET" "$ALL_RECORDS_ENDPOINT")

for i in $(seq 1 $TOP_N); do
    FLEET_MEMBER_INDEX=$i
    # 【最终修复】使用从 Secrets 传来的、绝对正确的 CF_ZONE_NAME_CLEAN 来拼接域名
    TARGET_DOMAIN="${CF_RECORD_PREFIX_CLEAN}${FLEET_MEMBER_INDEX}.${CF_ZONE_NAME_CLEAN}"
    ip_index=$((i-1))
    
    if [ -z "${TOP_IPS[$ip_index]}" ]; then
        warn "优选出的 IP 数量不足，无法为 ${TARGET_DOMAIN} 分配 IP。跳过。"
        continue
    fi
    
    NEW_IP="${TOP_IPS[$ip_index]}"
    info "正在处理舰队成员 #${FLEET_MEMBER_INDEX}: ${TARGET_DOMAIN}"
    record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${TARGET_DOMAIN}\")")
    
    if [ -z "$record_info" ]; then
        info "  -> 记录不存在，执行创建 -> ${NEW_IP}"
        UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records"
        UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
        cf_api_request "POST" "$UPDATE_ENDPOINT" "$UPDATE_DATA" > /dev/null
    else
        RECORD_ID=$(echo "$record_info" | jq -r '.id'); CURRENT_IP=$(echo "$record_info" | jq -r '.content')
        if [ "$NEW_IP" == "$CURRENT_IP" ]; then info "  -> IP 未变化 (${CURRENT_IP})，无需更新。"; else
            info "  -> IP 地址已变化 (${CURRENT_IP} -> ${NEW_IP})，执行更新..."
            UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records/${RECORD_ID}"
            UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
            cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA" > /dev/null
        fi
    fi
done
info "“无敌舰队”部署完毕！"

info "阶段七：清理..."; cd /; rm -rf "$WORK_DIR"; info "Aura IP Hunter 成功运行完毕。"
