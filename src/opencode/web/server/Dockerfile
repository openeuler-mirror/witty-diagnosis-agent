# 后端镜像（Node，单实例）。表初始化由 entrypoint 复用同一 Knex migrations 完成。
FROM node:20-bookworm-slim

WORKDIR /app

# 仅 Linux 成立的进程级隔离（D-001）：基础镜像须为 Linux。
# better-sqlite3 官方对 linux-x64/linux-arm64 提供预编译（Node 20/22/23），装包即用；
# 私仓/离线场景拿不到 prebuild 时会退化到本地编译——需要 python3 + make + g++ 兜底。
# 注意：若把基础镜像换成 node:*-alpine，需要额外安装 python3 make g++（apk add），
# 且拉取 linuxmusl 变体 prebuild；bookworm 一切默认走 linux-x64/arm64 分支。
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 make g++ ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm install --omit=dev && npm install tsx

COPY . .

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8787
EXPOSE 8787

# entrypoint：先 migrate（建库+建表，幂等）再启动
CMD ["sh", "-c", "npx knex migrate:latest --knexfile knexfile.cjs && npx tsx src/index.ts"]
