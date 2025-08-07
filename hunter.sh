#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - 自主 Cloudflare IP 情报搜集与更新系统
#
# v1.0 - 功能完整版
# ====================================================================================

# --- 全局变量与函数定义 ---
info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; }

# Cloudflare API 请求函数
# 参数1: 请求方法 (GET, PUT, etc.)
# 参数2: API 端点 (例如: zones)
# 参数3: (可选) 请求体数据
function cf_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local response

    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$data")
    else
        response=$(curl -s -X "$method" "https://api.cloudflare.com/client/v4/${endpoint}" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json")
    fi
    
    # 检查 API 是否成功
    if ! echo "$response" | jq -e .success >/dev/null; then
        error "Cloudflare API 请求失败！"
        error "响应: $(echo "$response" | jq .errors)"
        return 1
    fi

    echo "$response"
}

# --- 主逻辑开始 ---

# --- 1. 初始化与环境检查 ---
info "启动 Aura IP Hunter v1.0 (功能完整版)..."
if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ]; then
  error "一个或多个必需的 Secrets (CF_API_TOKEN, CF_ZONE_ID, CF_RECORD_NAME) 未设置。"
  exit 1
fi
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

# --- 2. 情报搜集 ---
info "阶段二：情报搜集 (基础版)..."
info "正在下载 Cloudflare 官方 IPv4 列表..."
curl -sL https://www.cloudflare.com/ips-v4 -o ip.txt
info "IP 列表下载完成，总行数: $(wc -l < ip.txt)"

# --- 3. 准备测试工具 ---
info "阶段三：准备测试工具 (CloudflareSpeedTest)..."
ARCH="amd64"
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror" # 从我们自己的镜像仓库下载
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
info "正在从我们的镜像仓库获取最新版本信息: $API_URL"
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then error "无法从镜像仓库找到名为 '${ASSET_NAME}' 的下载资产。"; exit 1; fi
info "已获取到真实的下载链接: $DOWNLOAD_URL"
info "正在下载工具..."; wget -qO cfst.tar.gz "$DOWNLOAD_URL"
info "正在解压工具..."; tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

# --- 4. 执行速度测试 ---
info "阶段四：执行速度测试 (这可能需要几分钟)..."
./cfst -f ip.txt -o result.csv -tp 443 -sl 2 -tl 200
if [ ! -f "result.csv" ] || [ ! -s "result.csv" ]; then warn "测速未找到任何符合条件的 IP。"; BEST_IP="1.1.1.1"; else
    # --- 5. 分析与选择 ---
    info "阶段五：分析结果并选择最佳 IP..."
    BEST_LINE=$(tail -n +2 result.csv | sort -t',' -k6nr | head -n 1)
    BEST_IP=$(echo "$BEST_LINE" | awk -F, '{print $1}')
    BEST_SPEED=$(echo "$BEST_LINE" | awk -F, '{print $6}')
    BEST_LATENCY=$(echo "$BEST_LINE" | awk -F, '{print $5}')
    info "最佳 IP 已找到！速度: ${BEST_SPEED} MB/s, 延迟: ${BEST_LATENCY} ms"
fi
info "最终选择的优选 IP 是: ${BEST_IP}"

# --- 6. 更新 Cloudflare DNS 记录 (核心功能) ---
info "阶段六：开始更新 Cloudflare DNS 记录..."

# 步骤 6.1: 获取 DNS 记录的 ID
info "正在获取域名 ${CF_RECORD_NAME} 的记录 ID..."
RECORD_ENDPOINT="zones/${CF_ZONE_ID}/dns_records?name=${CF_RECORD_NAME}&type=A"
record_response=$(cf_api_request "GET" "$RECORD_ENDPOINT")
if [ $? -ne 0 ]; then exit 1; fi # 如果请求失败，则退出
RECORD_ID=$(echo "$record_response" | jq -r '.result[0].id')
CURRENT_IP=$(echo "$record_response" | jq -r '.result[0].content')

if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    error "未找到域名为 ${CF_RECORD_NAME} 的 A 记录。请先在 Cloudflare 上手动创建一个。"
    exit 1
fi
info "获取到记录 ID: ${RECORD_ID}, 当前 IP: ${CURRENT_IP}"

# 步骤 6.2: 比较 IP，如果不同则更新
if [ "$BEST_IP" == "$CURRENT_IP" ]; then
    info "优选 IP 与当前 IP 相同，无需更新。"
else
    info "IP 地址已变化，准备更新！"
    UPDATE_ENDPOINT="zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}"
    UPDATE_DATA="{\"type\":\"A\",\"name\":\"${CF_RECORD_NAME}\",\"content\":\"${BEST_IP}\",\"ttl\":120,\"proxied\":false}"
    
    update_response=$(cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
    if [ $? -ne 0 ]; then exit 1; fi
    
    info "DNS 记录更新成功！新 IP 地址为: ${BEST_IP}"
fi

# --- 7. 清理工作 ---
info "阶段七：清理..."
cd /; rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
