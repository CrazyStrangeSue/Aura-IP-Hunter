#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v36.0 (Purge & Deploy Edition)
# 最终版: 采用“先净化，后部署”模式，从根本上杜绝 DNS 记录重复
# ====================================================================================

WORK_DIR=$(mktemp -d); cd "$WORK_DIR" || exit 1
info() { echo -e "\e[32m[信息]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }

# 加载配置文件 (如果存在)
if [ -f "../hunter.conf" ]; then info "加载 hunter.conf..."; source ../hunter.conf; fi
TOP_N=${TOP_N:-5}
CF_API_REQUEST_ARGS=(-s --connect-timeout 20 -H "X-Auth-Email: ${CF_API_EMAIL}" -H "X-Auth-Key: ${CF_API_KEY}" -H "Content-Type: application/json")
DATA_SOURCE="https://stock.hostmonit.com/CloudFlareYes"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

# --- 核心优选与更新函数 ---
hunt_and_update() {
    local ip_type="$1"
    local dns_record_type="$2"
    local speedtest_args="$3"
    local start_index="$4"
    local ip_fetch_cmd="$5"

    info "====== 开始处理 ${ip_type} 优选 ======"
    info "阶段1：从 [${DATA_SOURCE}] 获取 ${ip_type} 情报..."
    curl -s -A "${USER_AGENT}" "$DATA_SOURCE" | eval "$ip_fetch_cmd" > "ip_${ip_type}.txt"
    if [ ! -s "ip_${ip_type}.txt" ]; then error "无法从情报源获取任何 ${ip_type} 数据。"; fi
    info "情报获取成功！准备了 $(wc -l < "ip_${ip_type}.txt") 个 ${ip_type} IP。"

    info "阶段2：执行 ${ip_type} 测速...";
    ./cfst -f "ip_${ip_type}.txt" -o "result_${ip_type}.csv" -p "${TOP_N}" ${speedtest_args}
    if [ ! -s "result_${ip_type}.csv" ]; then error "${ip_type} 优选失败：未能找到满足条件的 IP。"; fi

    local top_ips; top_ips=($(tail -n +2 "result_${ip_type}.csv" | awk -F, '{print $1}'))
    info "已捕获 Top ${#top_ips[@]} ${ip_type} IP 舰队：${top_ips[*]}"
    if [ ${#top_ips[@]} -eq 0 ]; then error "未能从测速结果中提取任何 ${ip_type} IP。"; fi

    # ==================== 【最终修复】: 净化式更新 ====================
    info "阶段3.1：净化 Cloudflare 上的所有旧 ${ip_type} 舰队记录..."
    local all_records_endpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${dns_record_type}&per_page=100"
    local all_records_response; all_records_response=$(curl "${CF_API_REQUEST_ARGS[@]}" -X GET "${all_records_endpoint}")
    local old_record_ids; old_record_ids=$(echo "$all_records_response" | jq -r ".result[] | select(.name | startswith(\"${CF_RECORD_NAME}\")) | .id")
    
    if [ -n "$old_record_ids" ]; then
        for record_id in $old_record_ids; do
            info "  -> 删除旧记录 ID: ${record_id}"
            local delete_endpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}"
            curl "${CF_API_REQUEST_ARGS[@]}" -X DELETE "${delete_endpoint}" > /dev/null
        done
        info "净化完成。"
    else
        info "未发现需要净化的旧记录。"
    fi
    # =================================================================

    info "阶段3.2：部署全新的 ${ip_type} 舰队..."
    local current_index=0
    for i in $(seq "${start_index}" "$((start_index + TOP_N - 1))"); do
        local target_domain="${CF_RECORD_NAME}${i}.${CF_ZONE_NAME}"
        if [ -z "${top_ips[$current_index]}" ]; then warn "优选IP不足，无法为 ${target_domain} 分配。"; continue; fi
        local new_ip="${top_ips[$current_index]}"
        
        info "  -> 正在为 ${target_domain} 创建新记录 -> ${new_ip}"
        local create_endpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
        local create_data; create_data=$(jq -n --arg type "$dns_record_type" --arg name "$target_domain" --arg content "$new_ip" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
        curl "${CF_API_REQUEST_ARGS[@]}" -X POST "${create_endpoint}" --data-raw "$create_data" > /dev/null
        
        current_index=$((current_index+1))
    done
    info "====== ${ip_type} 舰队部署完毕 ======"
}

# --- 主流程 ---
info "启动 Aura IP Hunter v36.0 (Purge & Deploy Edition)..."
if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; fi

info "准备测试工具..."; MACHINE_ARCH=$(uname -m); case "$MACHINE_ARCH" in "x86_64") ARCH="amd64" ;; "aarch64") ARCH="arm64" ;; *) error "不支持的架构。";; esac
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"; API_URL="https://api.github.com/repos/${REPO}/releases/latest"; ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url"); if [ -z "$DOWNLOAD_URL" ]; then error "无法找到下载资产 '${ASSET_NAME}'。"; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"; tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪。"

# --- 【最终蓝图】双轨并行执行 ---
# IPv4 轨道: fast0 -> fast4
hunt_and_update "IPv4" "A" "" 0 "awk -F, '/\./ {print \$1}'"
# IPv6 轨道: fast5 -> fast9
hunt_and_update "IPv6" "AAAA" "-f6" 5 "awk -F, '/:/ {print \$1}' | sed 's/\[//g; s/\]//g'"

info "所有任务完成！"; info "清理..."; cd /; rm -rf "$WORK_DIR"; info "Aura IP Hunter 成功运行完毕。"
