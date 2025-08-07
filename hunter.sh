#!/bin/bash
set -e
set -o pipefail

# ====================================================================================
# Aura IP Hunter - 自主 Cloudflare IP 情报搜集与更新系统
#
# 此脚本被设计在 GitHub Actions 环境中运行。
# 它负责搜集高价值的 Cloudflare IP，进行测试，并更新 DNS 记录。
# v0.1 - MVP 版本：实现核心的下载、测速和结果分析功能
# ====================================================================================

info() { echo -e "\e[32m[信息]\e[0m $1"; }
warn() { echo -e "\e[33m[警告]\e[0m $1"; }
error() { echo -e "\e[31m[错误]\e[0m $1"; }

# --- 1. 初始化与环境检查 ---
info "启动 Aura IP Hunter v0.1..."

# 检查 GitHub Actions 环境中必需的 Secrets (在此MVP版本中暂时不强制检查)
# if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_NAME" ]; then
#   error "一个或多个必需的 Secrets (CF_API_TOKEN, CF_ZONE_ID, CF_RECORD_NAME) 未设置。"
#   exit 1
# fi

# 创建一个临时工作目录
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"
info "工作目录: $WORK_DIR"


# --- 2. 情报搜集：寻找高价值 IP ---
info "阶段二：情报搜集 (MVP 版本)..."

info "正在下载 Cloudflare 官方 IPv4 列表作为基础..."
curl -sL https://www.cloudflare.com/ips-v4 -o ip.txt
# 在这个版本，我们只使用官方列表。
info "IP 列表下载完成，总行数: $(wc -l < ip.txt)"

# --- 3. 下载并准备测试工具 ---
info "阶段三：准备测试工具 (CloudflareSpeedTest)..."

# GitHub Actions 的运行环境是 amd64
ARCH="amd64"
REPO="XIU2/CloudflareSpeedTest"

# 通过 GitHub API 获取最新发布版的信息
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
info "正在从 API 获取最新版本信息: $API_URL"

# 使用 jq 解析 API 响应，找到我们需要的资产的真实下载地址 (browser_download_url)
# 这是一个更可靠的方法，因为它直接从 API 获取，而不是自己拼接 URL
ASSET_NAME="cfst_linux_${ARCH}.tar.gz"
DOWNLOAD_URL=$(curl -s "$API_URL" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .browser_download_url")

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    error "无法从 GitHub API 找到名为 '${ASSET_NAME}' 的下载资产。"
    # 打印 API 响应以供调试
    curl -s "$API_URL"
    exit 1
fi

info "已获取到真实的下载链接: $DOWNLOAD_URL"

info "正在下载工具..."
# 使用 wget 下载这个真实链接
wget --no-check-certificate -qO cfst.tar.gz "$DOWNLOAD_URL" -T 15 -t 3
if [ $? -ne 0 ]; then
    error "使用 wget 下载 CloudflareSpeedTest 失败。"
    exit 1
fi

# 在解压前，再次校验文件类型
FILE_TYPE=$(file -b cfst.tar.gz)
info "下载的文件类型为: $FILE_TYPE"
if ! [[ "$FILE_TYPE" == "gzip compressed data"* ]]; then
    error "下载的文件不是有效的 Gzip 压缩包。中止执行。"
    warn "文件内容可能如下："
    cat cfst.tar.gz
    exit 1
fi

# 解压并授权
info "正在解压工具..."
tar -zxf cfst.tar.gz
chmod +x cfst
info "工具准备就绪: ./cfst"

# --- 4. 执行：运行速度测试 ---
info "阶段四：执行速度测试 (这可能需要几分钟)..."

# 使用 CloudflareSpeedTest 进行测速
# -f ip.txt      : 指定 IP 来源文件
# -o result.csv  : 指定结果输出文件
# -tp 443        : 指定测试端口为 443
# -sl 2          : 下载速度下限，低于 2MB/s 的不显示
# -tl 200        : 平均延迟上限，高于 200ms 的不显示
./cfst -f ip.txt -o result.csv -tp 443 -sl 2 -tl 200

# 检查是否生成了结果文件
if [ ! -f "result.csv" ] || [ ! -s "result.csv" ]; then
    warn "测速完成，但没有找到任何符合条件的 IP。尝试放宽条件或检查网络。"
    # 在这种情况下，我们先选择一个默认的公共IP作为备用
    BEST_IP="1.1.1.1"
else
    # --- 5. 分析与选择 ---
    info "阶段五：分析结果并选择最佳 IP..."

    # 从 result.csv 中提取 IP、下载速度、延迟
    # tail -n +2: 跳过第一行表头
    # awk -F, '{print $1,$6,$5}': 提取第1, 6, 5列 (IP, 下载速度, 延迟)
    # sort -k2 -nr: 按第2列 (下载速度) 进行数字、反向排序 (速度最快的在前)
    # head -n 1: 取排序后的第一行
    BEST_LINE=$(tail -n +2 result.csv | awk -F, '{print $1,$6,$5}' | sort -k2 -nr | head -n 1)
    
    BEST_IP=$(echo "$BEST_LINE" | awk '{print $1}')
    BEST_SPEED=$(echo "$BEST_LINE" | awk '{print $2}')
    BEST_LATENCY=$(echo "$BEST_LINE" | awk '{print $3}')

    info "最佳 IP 已找到！"
    echo "----------------------------------------"
    echo -e "  IP 地址: \e[33m$BEST_IP\e[0m"
    echo -e "  下载速度: \e[33m$BEST_SPEED MB/s\e[0m"
    echo -e "  延迟: \e[33m$BEST_LATENCY ms\e[0m"
    echo "----------------------------------------"
fi


# --- 6. 更新 DNS 记录 ---
info "阶段六：更新 Cloudflare DNS 记录 (MVP 版本)..."

# 在这个 MVP 版本中，我们只打印出最终选择的 IP
# TODO: 实现真正的 DNS 更新逻辑
info "最终选择的优选 IP 是: ${BEST_IP}"
# echo "BEST_IP=${BEST_IP}" >> $GITHUB_ENV # 可以把IP传递给后续的step，暂时不用


# --- 7. 清理工作 ---
info "阶段七：清理..."
cd /
rm -rf "$WORK_DIR"
info "Aura IP Hunter 成功运行完毕。"
