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

# (cf_api_request 函数保持不变)
function cf_api_request() {
    local method="$1"; local endpoint="$2"; local data="$3"; local response
    # ... (此处省略函数内部代码，与上一版完全相同) ...
}

info "启动 Aura IP Hunter v13.0 (无敌舰队版)..."
# 【核心升级】检查新的 CF_ZONE_NAME Secret
if [ -z "$CF_API_KEY" ] || [ -z "$CF_API_EMAIL" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ] || [ -z "$CF_ZONE_NAME" ]; then
  error "一个或多个必需的 Secrets (CF_API_KEY, CF_API_EMAIL, CF_ZONE_ID, CF_RECORD_NAME, CF_ZONE_NAME) 未设置。"
  exit 1
fi
# (变量清理保持不变)
CF_RECORD_PREFIX_CLEAN=$(echo "$CF_RECORD_NAME" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_ID_CLEAN=$(echo "$CF_ZONE_ID" | tr -d '[:cntrl:]' | tr -d '\\')
CF_ZONE_NAME_CLEAN=$(echo "$CF_ZONE_NAME" | tr -d '[:cntrl:]' | tr -d '\\')

WORK_DIR=$(mktemp -d); cd "$WORK_DIR"; info "工作目录: $WORK_DIR"

# (阶段一/二 情报融合保持不变)
# ...

# (阶段三 准备工具，架构自适应保持不变)
# ...

# --- 阶段四：【核心升级】执行更广泛的测速 ---
info "阶段四：在高质量 IP 池中执行最终验证..."
# 我们需要获取至少 5 个结果，所以把 -dn (测速数量) 调高
./cfst -f ip.txt -o result.csv -tp 443 -sl 5 -tl 400 -dn 20

# --- 阶段五：【核心升级】分析并提取 Top 5 IP ---
info "阶段五：分析结果..."
if [ ! -s "result.csv" ]; then
    error "优选失败：在高质量 IP 池中未能找到任何满足条件的 IP。脚本中止，以保持现有 DNS 记录稳定。"
    exit 1
fi

# 从 result.csv 中提取速度最快的前 5 个 IP
TOP_5_IPS=($(tail -n +2 result.csv | sort -t',' -k6nr | head -n 5 | awk -F, '{print $1}'))

info "本次优选成功！已捕获 Top ${#TOP_5_IPS[@]} IP 舰队："
for ip in "${TOP_5_IPS[@]}"; do
    echo "  -> ${ip}"
done

# --- 阶段六：【核心升级】循环更新“舰队”的 DNS 记录 ---
info "阶段六：开始部署“无敌舰队”至 Cloudflare DNS..."

# 首先，获取当前 Zone 下的所有 DNS 记录，我们只请求一次，提高效率
ALL_RECORDS_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records?per_page=100"
all_records_response=$(cf_api_request "GET" "$ALL_RECORDS_ENDPOINT")
if [ $? -ne 0 ]; then exit 1; fi

# 循环处理 Top 5 的每一个 IP
for i in "${!TOP_5_IPS[@]}"; do
    # 计算当前的域名，例如 fast1.chathub.qzz.io, fast2...
    FLEET_MEMBER_INDEX=$((i + 1))
    TARGET_DOMAIN="${CF_RECORD_PREFIX_CLEAN}${FLEET_MEMBER_INDEX}.${CF_ZONE_NAME_CLEAN}"
    NEW_IP="${TOP_5_IPS[i]}"
    
    info "正在处理舰队成员 #${FLEET_MEMBER_INDEX}: ${TARGET_DOMAIN}"

    # 从之前获取的全部记录中，用 jq 查找当前域名的信息
    record_info=$(echo "$all_records_response" | jq -r ".result[] | select(.name == \"${TARGET_DOMAIN}\")")
    
    if [ -z "$record_info" ]; then
        warn "未能在 Cloudflare 上找到预创建的 DNS 记录: ${TARGET_DOMAIN}。跳过此成员。"
        continue # 跳过当前循环，继续处理下一个
    fi

    RECORD_ID=$(echo "$record_info" | jq -r '.id')
    CURRENT_IP=$(echo "$record_info" | jq -r '.content')
    
    info "  -> 记录 ID: ${RECORD_ID}, 当前 IP: ${CURRENT_IP}"

    if [ "$NEW_IP" == "$CURRENT_IP" ]; then
        info "  -> IP 未变化，无需更新。"
    else
        info "  -> IP 地址已变化，准备更新为 ${NEW_IP}..."
        UPDATE_ENDPOINT="zones/${CF_ZONE_ID_CLEAN}/dns_records/${RECORD_ID}"
        UPDATE_DATA=$(jq -n --arg name "$TARGET_DOMAIN" --arg content "$NEW_IP" \
          '{type: "A", name: $name, content: $content, ttl: 120, proxied: false}')
        
        update_response=$(cf_api_request "PUT" "$UPDATE_ENDPOINT" "$UPDATE_DATA")
        if [ $? -ne 0 ]; then
            warn "  -> 更新 ${TARGET_DOMAIN} 失败！将继续处理下一个。"
        else
            info "  -> DNS 记录更新成功！"
        fi
    fi
done

info "“无敌舰队”部署完毕！"

# --- 阶段七：清理 ---
info "阶段七：清理..."
cd /; rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
