#!/bin/bash
set -e
# ====================================================================================
# Aura IP Hunter - v23.0 (Dual Track Edition)
# 最终形态：双轨并行，同时优选 IPv4 和 IPv6 到不同指定域名
# ====================================================================================
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"
info() { echo -e "\e[32m[信息]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }
if [ -f "../hunter.conf" ]; then info "加载 hunter.conf..."; source ../hunter.conf; fi
TOP_N=${TOP_N:-5} # 每个协议优选的数量
CF_API_REQUEST_ARGS=(-s -H "X-Auth-Email: ${CF_API_EMAIL}" -H "X-Auth-Key: ${CF_API_KEY}" -H "Content-Type: application/json")

# --- 核心优选与更新函数 ---
function hunt_and_update() {
    local ip_type="$1"
    local dns_record_type="$2"
    local speedtest_args="$3"
    local record_prefix="$4"
    local ip_fetch_cmd="$5"

    info "====== 开始处理 ${ip_type} 优选 ======"
    info "阶段1：获取 ${ip_type} 情报..."; curl -s "https://stock.hostmonit.com/CloudFlareYes" | eval "$ip_fetch_cmd" > "ip_${ip_type}.txt"
    if [ ! -s "ip_${ip_type}.txt" ]; then error "无法获取任何 ${ip_type} 数据。"; fi
    info "获取了 $(wc -l < "ip_${ip_type}.txt") 个高质量 ${ip_type} IP。"
    
    info "阶段2：执行 ${ip_type} 测速..."; ./cfst -f "ip_${ip_type}.txt" -o "result_${ip_type}.csv" -p "${TOP_N}" ${speedtest_args}
    if [ ! -s "result_${ip_type}.csv" ]; then error "${ip_type} 优选失败：未能找到满足条件的 IP。"; fi
    
    local top_ips; top_ips=($(tail -n +2 "result_${ip_type}.csv" | awk -F, '{print $1}'))
    info "已捕获 Top ${#top_ips[@]} ${ip_type} IP 舰队：${top_ips[*]}"
    if [ ${#top_ips[@]} -eq 0 ]; then error "未能提取任何 ${ip_type} IP。"; fi
    
    info "阶段3：部署 ${ip_type} 舰队..."
    local all_records_endpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=${dns_record_type}&per_page=100"
    local all_records_response; all_records_response=$(curl "${CF_API_REQUEST_ARGS[@]}" -X GET "${all_records_endpoint}")
    
    for i in $(seq 0 $((TOP_N - 1))); do
        local target_domain="${record_prefix}${i}.${CF_ZONE_NAME}"
        if [ -z "${top_ips[$i]}" ]; then warn "优选IP不足，无法为 ${target_domain} 分配。"; continue; fi
        local new_ip="${top_ips[$i]}"
        info "正在处理 #${i}: ${target_domain}"
        local record_info; record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${target_domain}\")")
        if [ -z "$record_info" ]; then
            info "  -> 记录不存在，创建 -> ${new_ip}"
            local update_endpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records"
            local update_data; update_data=$(jq -n --arg type "$dns_record_type" --arg name "$target_domain" --arg content "$new_ip" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
            curl "${CF_API_REQUEST_ARGS[@]}" -X POST "${update_endpoint}" --data-raw "$update_data" > /dev/null
        else
            local record_id; record_id=$(echo "$record_info" | jq -r '.id'); local current_ip; current_ip=$(echo "$record_info" | jq -r '.content')
            if [ "$new_ip" == "$current_ip" ]; then info "  -> IP 未变化 (${current_ip})。"; else
                info "  -> IP 变化 (${current_ip} -> ${new_ip})，更新..."
                local update_endpoint="https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}"
                local update_data; update_data=$(jq -n --arg type "$dns_record_type" --arg name "$target_domain" --arg content "$new_ip" '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')
                curl "${CF_API_REQUEST_ARGS[@]}" -X PUT "${update_endpoint}" --data-raw "$update_data" > /dev/null
            fi
        fi
    done
    info "====== ${ip_type} 舰队部署完毕 ======"
}

# --- 主流程 ---
info "启动 Aura IP Hunter v23.0 (Dual Track Edition)..."
if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; fi

info "准备测试工具..."; MACHINE_ARCH=$(uname -m); case "$MACHINE_ARCH" in "x86_64") ARCH="amd64" ;; "aarch64") ARCH="arm64" ;; *) error "不支持的架构。";; esac
REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"; API_URL="https://api.github.com/repos/${REPO}/releases/latest"; ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url"); if [ -z "$DOWNLOAD_URL" ]; then error "无法找到下载资产 '${ASSET_NAME}'。"; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"; tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪。"

# --- 双轨并行执行 ---
# IPv4 轨道: fast0 -> fast4
hunt_and_update "IPv4" "A" "" "fast" "awk -F, '/\./ {print \$1}'"
# IPv6 轨道: fast5 -> fast9
hunt_and_update "IPv6" "AAAA" "-f6" "fast" "awk -F, '/:/ {print \$1}' | sed 's/\[//g; s/\]//g'" # 增加 sed 清理可能存在的 []

info "所有任务完成！"; info "阶段七：清理..."; cd /; rm -rf "$WORK_DIR"; info "Aura IP Hunter 成功运行完毕。"
