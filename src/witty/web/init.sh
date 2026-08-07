#!/usr/bin/env bash
# 环境初始化：装依赖 + 建库建表（幂等）
# 独立于启动脚本，只需执行一次，或依赖更新时重跑。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$HERE/server"
FRONTEND_DIR="$HERE/frontend"

# ---------- 系统依赖检查 ----------

if command -v ansible &>/dev/null; then
  echo "    ✅ Ansible 已安装"
else
  echo "    ⚠ 未检测到 Ansible，在线诊断需要此工具"
  echo "    安装命令：sudo apt-get install ansible"
  echo "    或参考：https://docs.ansible.com/ansible/latest/installation_guide/"
  echo "    （如果仅使用离线诊断模式，可忽略此提示）"
fi

if command -v sshpass &>/dev/null; then
  echo "    ✅ sshpass 已安装"
else
  echo "    ⚠ 未检测到 sshpass，在线诊断连通性测试需要此工具"
  echo "    安装命令：sudo apt-get install sshpass"
  echo "    （如果仅使用离线诊断模式，可忽略此提示）"
fi

# ---------- QA 模块（已知问题对话查询）可选安装 ----------
echo ""
echo "=> [可选] 已知问题对话查询（QA）模块"
echo "  该模块提供基于知识库的检索增强问答（RAG）能力，需连接 LightRAG 服务。"
echo "  如不确定，选 n 可后续手动配置（修改 .env 中 CONVERSATION_ENABLED=true）。"
read -r -p "  是否安装 QA 模块？(y/N): " qa_choice

if [[ "$qa_choice" =~ ^[Yy]$ ]]; then
  echo "  => 启用 QA 模块..."
  cd "$SERVER_DIR"
  # 确保 .env 存在
  [ -f .env ] || cp .env.example .env

  if grep -q '^CONVERSATION_ENABLED=' .env; then
    sed -i 's/^CONVERSATION_ENABLED=.*/CONVERSATION_ENABLED=true/' .env
  else
    echo 'CONVERSATION_ENABLED=true' >> .env
  fi

  read -r -p "  请输入 LightRAG 服务地址（默认 http://127.0.0.1:9621）: " lr_endpoint
  lr_endpoint="${lr_endpoint:-http://127.0.0.1:9621}"
  if grep -q '^LIGHTRAG_ENDPOINT=' .env; then
    sed -i "s|^LIGHTRAG_ENDPOINT=.*|LIGHTRAG_ENDPOINT=$lr_endpoint|" .env
  else
    echo "LIGHTRAG_ENDPOINT=$lr_endpoint" >> .env
  fi
  # 兼容旧版无 LIGHTRAG_MOCK 的 .env
  if ! grep -q '^LIGHTRAG_MOCK=' .env; then
    echo 'LIGHTRAG_MOCK=' >> .env
  fi
  echo "  ✅ QA 模块已启用 (CONVERSATION_ENABLED=true, LIGHTRAG_ENDPOINT=$lr_endpoint)"
else
  echo "  => 跳过 QA 模块（可后续手动启用，添加 CONVERSATION_ENABLED=true 到 .env）"
fi

echo "==> [1/3] 安装后端依赖"
cd "$SERVER_DIR"
[ -f .env ] || cp .env.example .env
npm install

echo "==> [2/3] 安装前端依赖"
cd "$FRONTEND_DIR"
npm install

echo "==> [3/3] 初始化数据库（migrate，幂等）"
cd "$SERVER_DIR"
npx knex migrate:latest --knexfile knexfile.cjs

echo "✅ 环境初始化完成"
