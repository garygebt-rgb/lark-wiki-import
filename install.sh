#!/bin/bash
# lark-wiki-import 安装脚本
# 首次使用引导用户完成飞书 CLI 安装和知识库配置
#
# 用法:
#   bash ~/.claude/skills/lark-wiki-import/install.sh
#
# 本脚本会引导完成：
#   1. 安装并初始化 lark-cli（自动创建飞书应用）
#   2. 配置应用权限
#   3. 获取用户授权
#   4. 绑定目标知识库

set -e

echo "=========================================="
echo "飞书知识库导入 Skill 初始化"
echo "=========================================="
echo ""

# 检测是否有现有配置
CONFIG_DIR="${HOME}/.claude/skills/lark-wiki-import"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "$CONFIG_DIR"

# Step 0: 欢迎与说明
echo "欢迎使用 lark-wiki-import！"
echo ""
echo "本工具可以将本地 PPTX/PDF 文件上传到飞书知识库并生成索引目录。"
echo ""
echo "首次使用需要："
echo "  1. 安装并初始化 lark-cli（自动创建飞书应用）"
echo "  2. 为应用开通必要权限"
echo "  3. 进行用户授权"
echo "  4. 绑定目标知识库"
echo ""
read -p "按回车继续..." REPLY
echo ""

# Step 1: 安装并初始化 lark-cli
echo "=========================================="
echo "Step 1: 安装并初始化 lark-cli"
echo "=========================================="
echo ""
echo "lark-cli 是飞书官方 CLI 工具，安装时会自动创建自建应用。"
echo ""

# 检查是否已安装
if command -v lark-cli &> /dev/null; then
    echo "✓ lark-cli 已安装: $(lark-cli --version 2>/dev/null || echo 'unknown version')"
else
    echo "请安装 lark-cli："
    echo "  npm install -g @larksuite/cli"
    echo ""
    read -p "按回车在浏览器打开安装说明..."
    echo "  1. 打开 https://www.npmjs.com/package/@larksuite/cli"
    echo "  2. 按页面说明安装"
    echo "  3. 安装完成后运行: lark-cli config init --new"
    echo ""
    read -p "安装并初始化完成？按回车继续..." REPLY
fi

echo ""
echo "运行 lark-cli config init --new 进行初始化..."
echo "（会引导创建飞书应用并完成授权）"
echo ""
lark-cli config init --new 2>&1 || {
    echo "初始化遇到问题，请确保："
    echo "  1. lark-cli 已正确安装"
    echo "  2. 运行过 lark-cli config init --new"
    echo ""
    read -p "初始化完成后再按回车继续..." REPLY
}
echo ""

# Step 2: 配置应用权限
echo "=========================================="
echo "Step 2: 开通应用权限"
echo "=========================================="
echo ""
echo "请在飞书开放平台为应用开通以下权限："
echo ""
echo "  权限名称                    | 权限说明"
echo "  --------------------------|--------------------------"
echo "  drive:file:upload         | 上传文件到云空间"
echo "  drive:drive                | 管理云空间文件"
echo "  wiki:wiki                  | 管理知识库"
echo ""
echo "开通方式："
echo "  1. 在应用页面点击「权限管理」"
echo "  2. 搜索以上权限名称并开通"
echo "  3. 点击「申请发版」或「线上发布」使权限生效"
echo ""
read -p "权限已开通并发布？按回车继续..." REPLY
echo ""

# Step 3: 用户授权
echo "=========================================="
echo "Step 3: 用户授权"
echo "=========================================="
echo ""
echo "正在进行 OAuth 授权，请稍候..."
echo "（会输出授权链接，请在浏览器中打开并完成授权）"
echo ""

lark-cli auth login --scope "drive:file:upload drive:drive wiki:wiki" 2>&1
echo ""

# 验证授权
STATUS=$(lark-cli auth status 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tokenStatus','invalid'))" 2>/dev/null || echo "no_token")
if [[ "$STATUS" != "valid" ]]; then
    echo "✗ 授权失败，请重试"
    exit 1
fi

USER=$(lark-cli auth status 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('userName',''))" 2>/dev/null || echo "")
echo "✓ 授权成功 (用户: $USER)"
echo ""

# Step 4: 绑定目标知识库
echo "=========================================="
echo "Step 4: 绑定目标知识库"
echo "=========================================="
echo ""
echo "请提供目标知识库的首页链接："
echo ""
echo "  ⚠️ 重要提醒："
echo "    • 您必须对该知识库有编辑权限"
echo "    • 应用授权的用户账号需要与知识库权限一致"
echo "    • 如果上传到别人的知识库会失败"
echo ""
read -p "知识库首页链接: " WIKI_URL

if [[ -z "$WIKI_URL" ]]; then
    echo "✗ 链接不能为空"
    exit 1
fi

# 解析 node_token
NODE_TOKEN=$(echo "$WIKI_URL" | python3 -c "
import sys, re
url = sys.stdin.read().strip()
m = re.search(r'wiki/([A-Za-z0-9]+)', url)
print(m.group(1) if m else '')
")

if [[ -z "$NODE_TOKEN" ]]; then
    echo "✗ 无法从链接解析 node_token，请检查链接格式"
    exit 1
fi

echo "  node_token: $NODE_TOKEN"
echo "  正在查询知识空间信息..."

# 遍历 spaces 找到该 node 所在的 space
SPACE_ID=""
SPACE_NAME=""
PARENT_TOKEN=""

SPACES_RESULT=$(lark-cli api GET '/open-apis/wiki/v2/spaces' --params '{"page_size":"50"}' 2>/dev/null)

# 先作为一级节点查找
for try_space in $(echo "$SPACES_RESULT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d.get('data',{}).get('items',[]):
    print(s.get('space_id',''))
" 2>/dev/null); do
    NODES=$(lark-cli wiki nodes list --params "{\"space_id\":\"${try_space}\",\"page_size\":\"50\"}" 2>/dev/null)
    MATCH=$(echo "$NODES" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for n in d.get('data',{}).get('items',[]):
    if n.get('node_token','') == '$NODE_TOKEN':
        print(n.get('space_id',''))
        print(n.get('parent_node_token',''))
        print(n.get('title',''))
" 2>/dev/null)
    if [[ -n "$MATCH" ]]; then
        SPACE_ID=$(echo "$MATCH" | sed -n '1p')
        PARENT_TOKEN=$(echo "$MATCH" | sed -n '2p')
        SPACE_NAME=$(echo "$MATCH" | sed -n '3p')
        break
    fi
done

if [[ -z "$SPACE_ID" ]]; then
    echo "✗ 无法找到该节点所属的知识空间"
    echo "  请确认："
    echo "    1. 链接是否正确"
    echo "    2. 您是否有该知识库的访问权限"
    echo "    3. 应用授权账号与知识库权限是否一致"
    exit 1
fi

echo "✓ 知识空间: $SPACE_NAME"
echo "✓ space_id: $SPACE_ID"
if [[ -n "$PARENT_TOKEN" ]]; then
    echo "✓ parent_node_token: $PARENT_TOKEN"
else
    echo "  (将作为一级节点创建)"
    PARENT_TOKEN=""
fi
echo ""

# 保存配置
echo "=========================================="
echo "保存配置"
echo "=========================================="
echo ""

cat > "${CONFIG_FILE}" << EOF
{
  "space_id": "${SPACE_ID}",
  "parent_node_token": "${PARENT_TOKEN}",
  "space_name": "${SPACE_NAME}",
  "wiki_url": "${WIKI_URL}",
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "✓ 配置已保存到 ${CONFIG_FILE}"
echo ""

# 完成
echo "=========================================="
echo "初始化完成！"
echo "=========================================="
echo ""
echo "目标知识库: $SPACE_NAME"
echo "知识库链接: $WIKI_URL"
echo ""
echo "现在可以使用 lark-wiki-import skill 上传文件到知识库了。"
echo ""
echo "常见问题："
echo "  • 权限不足？→ 检查应用是否已开通 drive:drive, wiki:wiki 权限并发布"
echo "  • 授权过期？→ 运行 lark-cli auth login --scope \"drive:file:upload drive:drive wiki:wiki\""
echo "  • 更换知识库？→ 重新运行此脚本或编辑 ${CONFIG_FILE}"
echo ""
