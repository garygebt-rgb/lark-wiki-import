#!/bin/bash
# lark-wiki-import 远程安装脚本
# 用法:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/你的用户名/lark-wiki-import/main/distribute.sh)"
#
# 或 clone 后本地运行:
#   bash install-from-repo.sh

set -e

SKILL_DIR="${HOME}/.claude/skills/lark-wiki-import"
REPO_URL="https://github.com/你的用户名/lark-wiki-import"
BRANCH="main"

echo "=========================================="
echo "lark-wiki-import 安装向导"
echo "=========================================="
echo ""

# Step 1: 检测目录是否已有配置（升级时保留）
if [[ -f "${SKILL_DIR}/config.json" ]]; then
    echo "检测到已有配置，升级时将保留..."
    echo ""
fi

# Step 2: 安装依赖检查
echo "检查依赖..."
echo ""

command -v lark-cli &> /dev/null || {
    echo "✗ lark-cli 未安装"
    echo ""
    echo "请先安装 lark-cli："
    echo "  npm install -g @larksuite/cli"
    echo ""
    echo "安装完成后重新运行此脚本"
    exit 1
}
echo "✓ lark-cli 已安装"

command -v python3 &> /dev/null || {
    echo "✗ python3 未安装"
    exit 1
}
echo "✓ python3 已安装"
echo ""

# Step 3: 下载或更新 skill 文件
echo "=========================================="
echo "下载 skill 文件..."
echo "=========================================="
echo ""

# 方法 A: 如果已 clone 仓库（本地开发模式）
if [[ -d ".git" ]] && [[ -f "SKILL.md" ]]; then
    echo "检测为本地仓库，直接链接..."
    ln -sfn "$(pwd)" "${SKILL_DIR}"
    echo "✓ skill 已链接到 ${SKILL_DIR}"
else
    # 方法 B: 从 GitHub 下载
    TEMP_DIR=$(mktemp -d)
    echo "从 GitHub 下载..."
    git clone --depth 1 -b "${BRANCH}" "${REPO_URL}" "${TEMP_DIR}/lark-wiki-import" 2>&1 || {
        echo "✗ 从 GitHub 下载失败"
        echo ""
        echo "请确认："
        echo "  1. 仓库 ${REPO_URL} 是否存在"
        echo "  2. 网络是否正常"
        echo "  3. 仓库是否设置为 public"
        exit 1
    }
    rm -rf "${SKILL_DIR}"
    mv "${TEMP_DIR}/lark-wiki-import" "${SKILL_DIR}"
    rm -rf "${TEMP_DIR}"
    echo "✓ skill 已安装到 ${SKILL_DIR}"
fi
echo ""

# Step 4: 保留原有配置（如有）
if [[ -f "${SKILL_DIR}/config.json" ]] && [[ ! -f "${HOME}/.claude/skills/lark-wiki-import/config.json" ]]; then
    echo "保留原有配置..."
else
    echo "新安装，将运行初始化向导..."
    bash "${SKILL_DIR}/install.sh"
fi

echo ""
echo "=========================================="
echo "安装完成！"
echo "=========================================="
echo ""
echo "配置文件: ${SKILL_DIR}/config.json"
echo ""
echo "常用命令："
echo "  bash ~/.claude/skills/lark-wiki-import/install.sh   # 重新初始化"
echo "  上传文件时只需说「上传 xxx 到知识库」即可"
