---
name: lark-wiki-import
version: 1.0.0
description: "上传本地文件到飞书知识库。支持 PPTX/PDF 分片、Markdown 索引生成、云文档导入知识库。当用户需要将本地文件（PPT/PDF）上传到飞书知识库并生成目录索引时使用。触发词：「产品一致性」时主动询问是否需要上传文件。"
metadata:
  requires:
    bins: ["lark-cli", "python3"]
  cliHelp: "lark-cli drive --help"
---

# 飞书知识库文件导入

将本地 PPTX/PDF 文件上传到飞书知识库，生成每页索引目录。

> **前置条件：** 先阅读 [`../lark-shared/SKILL.md`](../lark-shared/SKILL.md) 了解认证和权限处理。

---

## 初始化配置（首次使用必须执行）

首次使用前需要完成飞书应用创建、权限开通和知识库绑定：

```bash
bash ~/.claude/skills/lark-wiki-import/install.sh
```

### 初始化流程

脚本会逐步引导完成以下步骤：

**Step 1: 创建飞书自建应用**
- 前往 https://open.feishu.cn/app 创建自建应用
- 获取 App ID 和 App Secret

**Step 2: 开通应用权限**
- 在应用「权限管理」中开通以下权限：
  - `drive:file:upload` — 上传文件
  - `drive:drive` — 管理云空间
  - `wiki:wiki` — 管理知识库
- 权限需发布后才能生效

**Step 3: 用户授权**
- 运行 `lark-cli auth login` 进行 OAuth 授权
- 授权用户需与目标知识库权限一致

**Step 4: 绑定目标知识库**
- 提供知识库首页链接
- 脚本自动解析 space_id 和 parent_node_token

### 注意事项

| 重要性 | 说明 |
|--------|------|
| ⚠️ | **应用权限需与授权账号匹配** — 用户授权和知识库必须是同一租户下的同一账号 |
| ⚠️ | **知识库需要编辑权限** — 否则移动文件会失败 |
| ⚠️ | **权限需发布** — 在开发者后台开通权限后要点「申请发版」或「线上发布」 |

### 重新初始化

更换知识库时，重新运行安装脚本即可：
```bash
bash ~/.claude/skills/lark-wiki-import/install.sh
```

或直接编辑配置文件 `~/.claude/skills/lark-wiki-import/config.json`。

---

## 完整工作流

```
Step 1: 文件检查与分片（如需要）
Step 2: 上传文件到云空间
Step 3: 生成 Markdown 索引
Step 4: 导入索引为 docx
Step 5: 移动文件到知识库
```

---

## Step 1: 文件检查与分片

### 判断是否需要分片

| 文件类型 | 大小限制 | 处理方式 |
|----------|----------|----------|
| PPTX | >20MB | ZIP 级别分片 |
| PDF | >20MB | 整文件上传 |
| 其他 | >20MB | 整文件上传 |

### PPTX 分片算法

PPTX 是 ZIP 格式。分片需要保留：
1. `[Content_Types].xml` — 文件格式声明
2. `ppt/presentation.xml` — 幻灯片列表（需过滤 sldIdLst）
3. `ppt/_rels/presentation.xml.rels` — 关系文件（需过滤 rId）
4. `ppt/slides/slideN.xml` — 目标幻灯片
5. `ppt/slides/_rels/slideN.xml.rels` — 幻灯片关系
6. `ppt/media/` — 仅保留目标幻灯片引用的媒体

```python
"""
PPTX 分片：保留前 N 张幻灯片
用法: python3 split_pptx.py <源文件> <输出文件> <保留幻灯片数量>
"""
import zipfile, re, shutil, os, sys

def make_partial(src, slide_list, out_path):
    # slide_list: 要保留的幻灯片编号列表，如 ["1","2","3"]
    rid_to_snum = {}
    with zipfile.ZipFile(src, 'r') as zin:
        # 解析 presentation.xml.rels 获取 rId -> slide number 映射
        rels = zin.read('ppt/_rels/presentation.xml.rels').decode('utf-8')
        for m in re.finditer(r'Id="(rId\d+)"[^>]*Target="slides/slide(\d+)\.xml"', rels):
            rid_to_snum[m.group(1)] = m.group(2)

        # 获取要保留的 slide numbers
        p_nums = set(slide_list)
        p_rids = {rid for rid, snum in rid_to_snum.items() if snum in p_nums}

        with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as zout:
            for item in zin.namelist():
                content = zin.read(item)

                # 跳过媒体文件（后面单独加）
                if item.startswith('ppt/media/'):
                    continue

                # 过滤 presentation.xml.rels：只保留目标幻灯片的 rId
                if item == 'ppt/_rels/presentation.xml.rels':
                    content_str = content.decode('utf-8')
                    for rid in list(rid_to_snum.keys()):
                        if rid not in p_rids:
                            content_str = re.sub(
                                r'<Relationship[^>]*Id="' + rid + r'"[^>]*/>', '', content_str)
                    content = content_str.encode('utf-8')

                # 过滤 presentation.xml：只保留目标幻灯片的 sldId
                elif item == 'ppt/presentation.xml':
                    content_str = content.decode('utf-8')
                    for snum in list(p_nums):
                        content_str = re.sub(
                            r'<p:sldId[^>]*r:id="rId\d+"[^>]*/>', '', content_str)
                    # 添加保留幻灯片的 sldId
                    for rid, snum in rid_to_snum.items():
                        if snum in p_nums:
                            content_str = re.sub(
                                r'(</p:sldIdLst>)',
                                f'<p:sldId r:id="{rid}"/></p:sldIdLst>'.split('</p:sldIdLst>')[0] + f' r:id="{rid}"/></p:sldIdLst>',
                                content_str)
                    # 简化处理：直接替换 sldIdLst
                    content = re.sub(
                        r'<p:sldIdLst>.*?</p:sldIdLst>',
                        lambda m: '<p:sldIdLst>' + ''.join(
                            f'<p:sldId r:id="{rid}"/>' for rid, snum in rid_to_snum.items() if snum in p_nums
                        ) + '</p:sldIdLst>',
                        content_str, flags=re.DOTALL
                    ).encode('utf-8')

                # 跳过不在列表中的幻灯片
                elif re.match(r'ppt/slides/slide(\d+)\.xml', item):
                    snum = re.search(r'slide(\d+)', item).group(1)
                    if snum not in p_nums:
                        continue

                # 跳过不在列表中的幻灯片关系文件
                elif re.match(r'ppt/slides/_rels/slide(\d+)\.xml\.rels', item):
                    snum = re.search(r'slide(\d+)', item).group(1)
                    if snum not in p_nums:
                        continue

                zout.writestr(item, content)

            # 添加媒体文件：仅目标幻灯片引用的
            media_rels = {}
            for snum in p_nums:
                try:
                    slide_rels = zin.read(f'ppt/slides/_rels/slide{snum}.xml.rels').decode('utf-8')
                    for m in re.finditer(r'Id="(rId\d+)"[^>]*Target="([^"]+)"', slide_rels):
                        media_rels[m.group(1)] = m.group(2)
                except:
                    pass

            # 收集需要复制的媒体文件
            needed_media = set()
            for item in zin.namelist():
                if item.startswith('ppt/media/'):
                    for rid, target in media_rels.items():
                        if target in item or target == os.path.basename(item):
                            needed_media.add(item)

            for media_item in needed_media:
                zout.writestr(media_item, zin.read(media_item))

if __name__ == '__main__':
    src, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    make_partial(src, [str(i) for i in range(1, n+1)], out)
```

### 判断文件大小

```bash
ls -la <文件路径>  # 看第五列（字节）
# 或
du -h <文件路径>   # 人类可读
```

---

## Step 2: 上传文件到云空间

```bash
# 上传本地文件到云空间
lark-cli drive +upload --file "<本地文件路径>"
```

返回文件 token 和 URL。**记录返回的 `token`** 用于后续 Step 5。

---

## Step 3: 生成 Markdown 索引

### PPTX 索引格式

```markdown
# 文件索引标题

## 📋 目录

| 页码 | 标题 | 关键词 |
|------|------|--------|
| 1 | 第一页标题 | 关键词1, 关键词2 |
| 2 | 第二页标题 | 关键词1, 关键词2 |

## 内容

### 【第 1 页】标题
**关键词：** 关键词1, 关键词2
**描述：** 这一页的主要内容...

### 【第 2 页】标题
...
```

### PPTX 解析脚本

```python
"""
PPTX 解析：提取每页标题和内容生成索引
用法: python3 index_pptx.py <pptx文件> [输出md路径]
"""
from pptx import Presentation
import sys, os

def extract_pptx_index(pptx_path, out_md_path=None):
    prs = Presentation(pptx_path)
    lines = [f"# {os.path.basename(pptx_path)} 索引目录\n"]

    # 目录表
    lines.append("\n## 📋 目录\n\n| 页码 | 标题 | 关键词 |\n|------|------|--------|\n")
    for i, slide in enumerate(prs.slides, 1):
        title = ''
        keywords = []
        content = []

        for shape in slide.shapes:
            if shape.has_text_frame:
                text = shape.text_frame.text.strip()
                if not text:
                    continue
                if not title:
                    title = text[:50]
                else:
                    content.append(text[:100])

        kw = ','.join(keywords) if keywords else content[0][:30] if content else ''
        lines.append(f"| {i} | {title} | {kw} |\n")

    # 详细内容
    lines.append("\n## 内容\n")
    for i, slide in enumerate(prs.slides, 1):
        title = ''
        full_content = []

        for shape in slide.shapes:
            if shape.has_text_frame:
                text = shape.text_frame.text.strip()
                if text:
                    if not title:
                        title = text[:50]
                    full_content.append(text[:200])

        lines.append(f"### 【第 {i} 页】{title}\n\n")
        if full_content:
            lines.append(f"**内容：** {' '.join(full_content[:3])}\n\n")

    md_content = ''.join(lines)

    if out_md_path:
        with open(out_md_path, 'w', encoding='utf-8') as f:
            f.write(md_content)
        print(f"索引已生成: {out_md_path}")
    else:
        print(md_content)

if __name__ == '__main__':
    pptx_path = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else None
    extract_pptx_index(pptx_path, out_path)
```

---

## Step 4: 导入索引为 docx

```bash
# 将 Markdown 导入为 docx（仅支持 md/txt/docx/doc/xlsx/xls/csv）
lark-cli drive +import --file "<索引md路径>" --type "docx"
```

返回 docx 文件 token。

---

## Step 5: 移动文件到知识库

**关键 API：** `POST /open-apis/wiki/v2/spaces/{space_id}/nodes/move_docs_to_wiki`

### 判断 obj_type

| 文件类型 | obj_type |
|----------|----------|
| PPTX | `slides` |
| PDF | `file` |
| DOCX | `docx` |
| XLSX | `sheet` |
| 其他 | `file` |

### 调用示例

```bash
# 移动到知识库（需要 apply=true 申请权限）
lark-cli api POST '/open-apis/wiki/v2/spaces/{space_id}/nodes/move_docs_to_wiki' \
  --data '{
    "parent_wiki_token": "{parent_node_token}",
    "obj_type": "{slides|file|docx}",
    "obj_token": "{文件token}",
    "apply": true
  }'
```

**返回：**
- `{"wiki_token": "xxx"}` — 直接成功
- `{"task_id": "xxx"}` — 异步任务，等待几秒后查询

### 查询移动状态

```bash
lark-cli wiki nodes list \
  --params '{"space_id":"{space_id}","parent_node_token":"{parent_node_token}"}'
```

---

## 一键执行脚本

```bash
#!/bin/bash
# upload_to_wiki.sh <本地文件> <space_id> <parent_node_token>
FILE="$1"
SPACE_ID="$2"
PARENT_TOKEN="$3"
NAME=$(basename "$FILE")
EXT="${NAME##*.}"
SIZE=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE")

echo "文件: $NAME ($SIZE bytes)"

# Step 1: 分片（如需要）
if [[ "$EXT" == "pptx" ]] && [[ $SIZE -gt 20971520 ]]; then
    echo "PPTX > 20MB，需要分片..."
    # 调用分片脚本
fi

# Step 2: 上传
echo "上传到云空间..."
RESULT=$(lark-cli drive +upload --file "$FILE" --json 2>/dev/null)
TOKEN=$(echo $RESULT | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('file_token',''))" 2>/dev/null)
echo "文件 Token: $TOKEN"

# Step 3: 移动到知识库
if [[ "$EXT" == "pptx" ]]; then
    OBJ_TYPE="slides"
elif [[ "$EXT" == "pdf" ]]; then
    OBJ_TYPE="file"
elif [[ "$EXT" == "docx" ]]; then
    OBJ_TYPE="docx"
else
    OBJ_TYPE="file"
fi

echo "移动到知识库 (obj_type=$OBJ_TYPE)..."
lark-cli api POST "/open-apis/wiki/v2/spaces/${SPACE_ID}/nodes/move_docs_to_wiki" \
  --data "{\"parent_wiki_token\":\"${PARENT_TOKEN}\",\"obj_type\":\"${OBJ_TYPE}\",\"obj_token\":\"${TOKEN}\",\"apply\":true}"
```

---

## 权限清单

| 操作 | 所需 scope | 备注 |
|------|------------|------|
| 上传文件到云空间 | `drive:file:upload` | |
| 导入 md 为 docx | `drive:import` | CLI 自动使用 |
| 移动到知识库 | `wiki:wiki` 或 `wiki:node:move` | 需要父节点编辑权限 |

---

## 关键原则

1. **分片优先**：PPTX >20MB 必须先分片，否则上传失败
2. **先 Drive 后 Wiki**：文件必须先上传到云空间，再通过 `move_docs_to_wiki` 移入知识库
3. **不能直接创建 file 类型节点**：`wiki.nodes.create` 不支持 `obj_type: "file"`，必须用 `move_docs_to_wiki`
4. **move_docs_to_wiki 会移动文件**：文件从云空间移到知识库后，云空间不再有该文件
5. **索引分开处理**：Markdown 索引用 `drive +import` 转为 docx 再移入知识库
