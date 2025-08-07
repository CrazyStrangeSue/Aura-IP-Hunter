#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - v9.0 (天网侦察兵)
# 引入智能情报搜集模块，主动追踪高价值目标 IP 段
# ====================================================================================

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; }

# =================================================
# 全新的【阶段一：情报搜集】核心函数
# =================================================
function gather_intelligence() {
    info "阶段一：启动天网侦察兵模块..."

    # 步骤 1: 定义高价值目标域名清单
    # 我们直接在脚本里硬编码这个列表，未来也可以改成从外部文件读取
    local targets=(
        "www.huaweicloud.com"
        "www.alibabacloud.com"
        "www.tencentcloud.com"
        "www.bytedance.com"
        "www.dji.com"
        "gitee.com"
        "www.mi.com/global/"
    )
    info "已锁定 ${#targets[@]} 个高价值目标。"

    # 步骤 2: 定义全球多点侦察节点 (我们使用公共 DNS 服务)
    # 这里的 IP 代表了我们想模拟的地理位置，用于 edns_client_subnet
    declare -A dns_locations=(
        ["香港"]="1.2.15.255"
        ["东京"]="1.1.1.1"
        ["新加坡"]="1.0.0.1"
        ["法兰克福"]="8.8.4.4"
        ["美西"]="8.8.8.8"
    )

    info "部署了 ${#dns_locations[@]} 个全球侦察节点。"
    touch resolved_ips.txt

    # 步骤 3: 执行全球多点 DNS 解析
    for domain in "${targets[@]}"; do
        for location_name in "${!dns_locations[@]}"; do
            location_ip=${dns_locations[$location_name]}
            info "正在从 [${location_name}] 侦察目标: ${domain}..."
            # 使用 dns.google 的 API 进行解析
            curl -s "https://dns.google/resolve?name=${domain}&type=A&edns_client_subnet=${location_ip}" | \
            jq -r '.Answer[]? | select(.type == 1) | .data' >> resolved_ips.txt
        done
    done
    
    # 对所有解析到的 IP 进行去重
    sort -u resolved_ips.txt -o unique_ips.txt
    info "全球侦察完成，初步捕获 $(wc -l < unique_ips.txt) 个独立 IP 地址。"

    # 步骤 4: 自动化分析 IP，提取 CIDR 网段
    info "正在对捕获的 IP 进行分析，提取 BGP 网段..."
    touch bgp_prefixes.txt
    for ip in $(cat unique_ips.txt); do
        # 使用 whois 查询，并用 awk 精确提取 BGP Prefix
        whois -h whois.cymru.com " -v $ip" | \
        awk -F'|' 'NR>1 {gsub(/ /, "", $3); print $3}' >> bgp_prefixes.txt
    done

    # 对所有提取到的 CIDR 网段进行去重，生成我们的“黄金IP段”列表
    sort -u bgp_prefixes.txt -o golden_cidrs.txt
    
    if [ ! -s "golden_cidrs.txt" ]; then
        warn "天网侦察兵未能捕获任何有效的 BGP 网段，将回退到基础 IP 池。"
        return 1 # 返回失败状态
    else
        info "情报分析完成！成功生成黄金 IP 段数据库 (golden_cidrs.txt)，包含 $(wc -l < golden_cidrs.txt) 个网段。"
        return 0 # 返回成功状态
    fi
}

# =================================================
# 主工作流
# =================================================

# --- 认证与初始化 (保持不变) ---
info "启动 Aura IP Hunter v9.0 (天网侦察兵)..."
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ]; then
  error "一个或多个必需的 Secrets 未设置。"
  exit 1
fi
CF_RECORD_NAME_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
WORK_DIR=$(mktemp -d); cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

# --- 阶段一与阶段二合并：【全新】智能情报驱动的 IP 池构建 ---

# 首先执行情报搜集
if gather_intelligence; then
    # 如果情报搜集成功，则使用“黄金IP段”作为主要来源
    info "使用天网侦察兵生成的黄金 IP 段作为主要狩猎场。"
    mv golden_cidrs.txt ip.txt
else
    # 如果情报搜集失败，则回退到原来的基础方案
    info "回退到基础方案：下载社区维护的 IP 列表。"
    curl -sL https://raw.githubusercontent.com/ip-scanner/cloudflare/main/ips.txt -o ip.txt
fi

info "最终狩猎场准备就绪，总计 $(wc -l < ip.txt) 个 IP 段。"

# --- 后续阶段 (三、四、五、六、七) 完全保持不变 ---
# 它们现在将会在一个质量更高的 IP 池上进行操作

info "阶段三：准备测试工具..."
ARCH="amd64"; REPO="CrazyStrangeSue/CloudflareSpeedTest-Mirror"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")
if [ -z "$DOWNLOAD_URL" ]; then error "无法从镜像仓库找到名为 '${ASSET_NAME}' 的下载资产。"; exit 1; fi
wget -qO cfst.tar.gz "$DOWNLOAD_URL"
tar -zxf cfst.tar.gz; chmod +x cfst; info "工具准备就绪: ./cfst"

info "阶段四：执行速度测试..."
./cfst -f ip.txt -o result.csv -tp 443 -sl 2 -tl 400 -dn 10
if [ ! -s "result.csv" ]; then warn "测速未找到任何符合条件的 IP。"; BEST_IP="1.1.1.1"; else
    info "阶段五：分析结果"
    BEST_LINE=$(tail -n +2 result.csv | sort -t',' -k6nr | head -n 1)
    BEST_IP=$(echo "$BEST_LINE" | awk -F, '{print $1}')
fi
info "最终选择的优选 IP 是: ${BEST_IP}"
info "阶段六：开始更新 Cloudflare DNS 记录"
info "正在获取域名 ${CF_RECORD_NAME_CLEAN} 的记录 ID"
RECORD_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records?name=${CF_RECORD_NAME_CLEAN}&type=A"
record_response=$(cf_api_request "GET" "$RECORD_ENDPOINT")
if [ $? -ne 0 ]; then exit 1; fi
RECORD_ID=$(echo "$record_response" | jq -r '.result[0].id')
CURRENT_IP=$(echo "$record_response" | jq -r '.result[0].content')
if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    error "未找到域名为 ${CF_RECORD_NAME_CLEAN} 的 A 记录。请先在 Cloudflare 上手动创建一个。"
    exit 1
fi
info "获取到记录 ID: ${RECORD_ID}, 当前 IP: ${CURRENT_IP}"
if [ "$BEST_IP" == "$CURRENT_IP" ]; then
    info "优选 IP 与当前 IP 相同，无需更新。"
else
    info "IP 地址已变化，准备更新！"
    UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records/${RECORD_ID}"
    UPDATE_DATA=$(jq -n --arg name "$CF_RECORD_NAME_CLEAN" --arg content "$BEST_IP" \
      '{type: "A", name: $name, content: $content, ttl: 120, proxied: false}')
    update_response=$(cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
    if [ $? -ne 0 ]; then exit 1; fi
    info "DNS 记录更新成功！新 IP 地址为: ${BEST_IP}"
fi
info "阶段七：清理"
cd /; rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
