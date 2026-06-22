# 后端镜像（Node，单实例）。表初始化由 entrypoint 复用同一 Knex migrations 完成。
FROM node:20-bookworm-slim

WORKDIR /app

# 仅 Linux 成立的进程级隔离（D-001）：基础镜像须为 Linux
COPY package.json ./
RUN npm install --omit=dev && npm install tsx

COPY . .

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8787
EXPOSE 8787

# entrypoint：先 migrate（建库+建表，幂等）再启动
CMD ["sh", "-c", "npx knex migrate:latest --knexfile knexfile.cjs && npx tsx src/index.ts"]
