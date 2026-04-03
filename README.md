# lark-wiki-import

上传本地 PPTX/PDF 文件到飞书知识库，支持分片上传和 Markdown 索引生成。

## 功能

- 支持 PPTX 文件分片（>20MB 自动分片，保留图片）
- 支持 PDF 直接上传
- 自动生成每页索引目录
- 先上传到云空间，再移动到知识库

## 安装

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/garygebt-rgb/lark-wiki-import/main/distribute.sh)"
```

或 clone 后本地运行：

```bash
git clone https://github.com/garygebt-rgb/lark-wiki-import.git
cd lark-wiki-import
bash distribute.sh
```

## 初始化

```bash
bash ~/.claude/skills/lark-wiki-import/install.sh
```

按向导完成：
1. 安装并初始化 lark-cli
2. 开通飞书应用权限
3. 进行用户授权
4. 绑定目标知识库

## 使用

上传文件时只需说「上传 xxx.pptx 到知识库」即可。

## 文件结构

```
lark-wiki-import/
├── SKILL.md           # Skill 说明文档
├── install.sh         # 初始化向导
├── distribute.sh      # 远程安装脚本
├── config.example.json # 配置模板
└── .gitignore
```
