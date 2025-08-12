#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v14.0 (自适应混合动力版)
# 自动检测运行环境，智能优选 IPv4/IPv6 并更新对应类型的 DNS 记录
# ====================================================================================

# --- 全局变量 ---
WORK_DIR=$(mktemp -d)

# 颜色定义
info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }

# --- Cloudflare API 封装函数 ---
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

# --- 主逻辑 ---
info "启动 Aura IP Hunter v14.0 (自适应混合动力版)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ] || [ -z "$CF_ZONE_NAME" ]; then
  error "一个或多个必需的 Secrets (CF_API_KEY, CF_API_EMAIL, CF_ZONE_ID, CF_RECORD_NAME, CF_ZONE_NAME) 未设置。"
fi
CF_RECORD_PREFIX_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_NAME_CLEAN=$(echo "$CF_ZONE_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

# ==================== 【v14.0 核心升级】: 自动检测网络环境 ====================
info "阶段一：自动检测运行环境网络类型..."
if curl -s -6 --connect-timeout 5 "ifconfig.co" &>/dev/null; then
    IP_TYPE="IPv6"
    DNS_RECORD_TYPE="AAAA"
    SPEEDTEST_EXTRA_ARGS="-f6"
    # 使用 grep 的 Perl 兼容正则表达式 (PCRE) 来精确匹配 IPv6
    IP_FETCH_COMMAND="curl -s \"https://stock.hostmonit.com/CloudFlareYes\" | grep -oP '([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}' | sort -u"
else
    IP_TYPE="IPv4"
    DNS_RECORD_TYPE="A"
    SPEEDTEST_EXTRA_ARGS=""
    # 匹配 IPv4
    IP_FETCH_COMMAND="curl -s \"https://stock.hostmonit.com/CloudFlareYes\" | grep -oP '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u"
fi
info "检测到优先网络环境为: ${IP_TYPE}。将优选此类 IP 并更新 ${DNS_RECORD_TYPE} 记录。"
# ==============================================================================

info "阶段二：融合 ${IP_TYPE} 实时情报..."
eval "$IP_FETCH_COMMAND" > ip.txt
if [ ! -s "ip.txt" ]; then
    error "无法从情报源获取任何 ${IP_TYPE} 数据，脚本中止。"
fi
info "情报融合完成！成功获取 $(wc -l < ip.txt) 个经过预筛选的高质量 ${IP_TYPE} IP。"

info "阶段三：准备测试工具 (架构自适应)..."
MACHINE_ARCH=$(uname -m)
case "$MACHINE_ARCH" in
    "x86_64") ARCH="amd64" ;;
    "aarch64") ARCH="arm64" ;;
    *) error "不支持的系统架构: ${MACHINE_ARCH}。";;
esac
info "检测到系统架构: ${MACHINE_ARCH}, 对应工具架构: ${ARCH}"
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
info "准备从镜像仓库下载资产: ${ASSET_NAME}"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法从镜像仓库找到名为 '${ASSET_NAME}' 的下载资产。"; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"
tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

info "阶段四：在高质量 ${IP_TYPE} IP 池中执行最终验证..."
# ==================== 【v14.0 核心升级】: 动态传入测速参数 ====================
./cfst -f ip.txt -o result.csv -tp 443 -sl 5 -tl 400 -dn 20 ${SPEEDTEST_EXTRA_ARGS}
# ===========================================================================

info "阶段五：分析结果并提取 Top 5 IP..."
if [ ! -s "result.csv" ]; then
    error "优选失败：在高质量 IP 池中未能找到任何满足条件的 IP。脚本中止，以保持现有 DNS 记录稳定。"
fi
TOP_5_IPS=($(tail -n +2 result.csv | sort -t',' -k6nr | head -n 5 | awk -F, '{print $1}'))
info "本次优选成功！已捕获 Top ${#TOP_5_IPS[@]} ${IP_TYPE} IP 舰队："
for ip in "${TOP_5_IPS[@]}"; do
    echo "  -> ${ip}"
done
if [ ${#TOP_5_IPS[@]} -eq 0 ]; then
    error "优选成功但未能提取任何IP，脚本中止。"
fi

info "阶段六：开始部署“无敌舰队”至 Cloudflare DNS (${DNS_RECORD_TYPE} 记录)..."
# ==================== 【v14.0 核心升级】: 根据 IP 类型查询 DNS 记录 ====================
ALL_RECORDS_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records?type=${DNS_RECORD_TYPE}&per_page=100"
# ===================================================================================
all_records_response=$(cf_api_request "GET" "$ALL_RECORDS_ENDPOINT")
if [ $? -ne 0 ]; then exit 1; fi

for i in "${!TOP_5_IPS[@]}"; do
    FLEET_MEMBER_INDEX=$((i + 1))
    TARGET_DOMAIN="${CF_RECORD_PREFIX_CLEAN}${FLEET_MEMBER_INDEX}.${CF_ZONE_NAME_CLEAN}"
    NEW_IP="${TOP_5_IPS[i]}"
    
    info "正在处理舰队成员 #${FLEET_MEMBER_INDEX}: ${TARGET_DOMAIN}"
    record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${TARGET_DOMAIN}\")")
    
    if [ -z "$record_info" ]; then
        warn "未能在 Cloudflare 上找到预创建的 ${DNS_RECORD_TYPE} 记录: ${TARGET_DOMAIN}。将尝试创建新记录。"
        # ==================== 【v14.0 核心升级】: 动态创建记录 ====================
        UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records"
        UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
        update_response=$(cf_api_request "POST" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
        if [ $? -ne 0 ]; then
            warn "  -> 创建 ${TARGET_DOMAIN} 失败！将继续处理下一个。"
        else
            info "  -> DNS 记录创建成功！"
        fi
        # ===========================================================================
        continue
    fi

    RECORD_ID=$(echo "$record_info" | jq -r '.id')
    CURRENT_IP=$(echo "$record_info" | jq -r '.content')
    info "  -> 记录 ID: ${RECORD_ID}, 当前 IP: ${CURRENT_IP}"

    if [ "$NEW_IP" == "$CURRENT_IP" ]; then
        info "  -> IP 未变化，无需更新。"
    else
        info "  -> IP 地址已变化，准备更新为 ${NEW_IP}..."
        # ==================== 【v14.0 核心升级】: 动态更新记录 ====================
        UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records/${RECORD_ID}"
        UPDATE_DATA=$(jq -n --arg type "$DNS_RECORD_TYPE" --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
        update_response=$(cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
        if [ $? -ne 0 ]; then
            warn "  -> 更新 ${TARGET_DOMAIN} 失败！将继续处理下一个。"
        else
            info "  -> DNS 记录更新成功！"
        fi
        # ===========================================================================
    fi
done
info "“无敌舰队”部署完毕！"

info "阶段七：清理..."
cd /; rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
