# 智能诊断前端 Web 服务（前端 SPA + 后端可运行骨架）

为 `witty-diagnosis-agent`（轩辕智能诊断系统）新增的 Web 交互界面与后端服务层。
实现「新建诊断任务 → 后台异步执行 → 实时进度/日志 → 任务列表管理 → 报告查看/下载/评分」闭环。

> 设计依据：`docs/design/intelligent-diagnosis-frontend-web-service/`（01 需求分析 / 02 需求设计 / 03 开发计划）。
> 高保真视觉参考：`openEuler-ops-prototype.html`（本实现已忠实移植其设计令牌与组件样式）。

## 当前实现范围

本次交付为 **前端 SPA + 后端可运行骨架**：端到端跑通诊断主链路（新建→执行→实时进度/日志→看报告→评分）。

| 已落地 | 说明 |
|-|-|
| 前端 SPA | React 18 + Vite 5 + TS + Zustand（03 §3.1）。登录、任务列表/筛选/搜索、新建任务（在线/离线）、任务详情（stepper + SSE 实时日志）、RCA 报告查看/下载、评分。 |
| 后端 API | Fastify + Knex（SQLite 默认 / MySQL 可切）+ SSE。任务 CRUD、测连通性、上传、取消/重试/删除、报告、评分、健康检查。 |
| 调度/队列 | 全局 FIFO + 并发上限（BC-005）。 |
| 凭据治理 | 内存加密保险箱 + 终态擦除（BC-004），事件流脱敏（FR-014）。 |
| 存储可插拔 | Knex 双方言 + 统一 migrations（NFR-010 / D-004）。 |
| 部署交付 | `start.sh` 本地一键安装 + 前/后端 Dockerfile + `docker-compose.yml`（NFR-011 / D-005/006）。 |

### 与真实 agent 的接缝（骨架用 stub 占位）

- **Agent Runner** (`server/src/runner.ts`)：当前用确定性阶段时序**模拟**整条诊断流水线，并生成高保真示例报告。
  真实实现按 02 §2.2.1：为每任务 spawn 隔离 OpenCode 进程（重定向 HOME/XDG）、`session.promptAsync(agent="xuanyuan", tools:{question:false})`、订阅 `event.subscribe` 合成进度/日志、双信号判定完成、采集 `baize/reports/*.html`、`finally` 擦除 taskHome。接缝（执行记录 / 凭据保险箱 / 脱敏 / SSE 推送）已就位，替换 `runner.run()` 内部即可接真。
- **认证** (`server/src/auth.ts`)：dev 占位单用户（表单登录 + 签名 Cookie）。生产把 `/api/auth/login` 换成外部 IdP（OIDC/LDAP）重定向 + 回调，"按 owner 鉴权" 逻辑不变。

## 目录约定

> 注意：03 §4.1 G1 原建议落位仓库根 `web/`；本次按用户指定放在 `src/opencode/web/`。
> 仅**新增**文件，未修改 `src/opencode` 下任何既有 agent 内核（保持「内核冻结」约束）。

```
src/opencode/web/
├─ frontend/           # React + Vite SPA
│  ├─ src/{pages,components,report}/ ...
│  ├─ nginx.conf       # 容器内反代后端（同源免 CORS）
│  └─ Dockerfile
├─ server/             # Fastify + Knex 后端
│  ├─ src/{routes,db}/ ...
│  ├─ knexfile.cjs     # 双方言配置（CLI + 运行时共用）
│  └─ Dockerfile
├─ start.sh            # 本地一键安装/启动
└─ docker-compose.yml  # 前后端分离 + 可选 MySQL
```

## 本地运行

需要 Node.js >= 20。

### 方式一：一键脚本（Linux/macOS/WSL）

```bash
cd src/opencode/web
./start.sh
# 后端 http://127.0.0.1:8787  前端 http://127.0.0.1:5173
```

### 方式二：分别启动

```bash
# 后端
cd src/opencode/web/server
cp .env.example .env
npm install
npm run migrate      # 建库 + 建表（幂等）
npm run start        # http://127.0.0.1:8787

# 前端（另开终端）
cd src/opencode/web/frontend
npm install
npm run dev          # http://127.0.0.1:5173 （/api 代理到后端）
```

打开 http://127.0.0.1:5173 ，演示账号已预填，点「登录」即可体验。

### 方式三：容器化（前后端分离）

```bash
cd src/opencode/web
docker compose up --build
# 浏览器访问 http://127.0.0.1:8080 （前端 nginx 反代后端）
```

## 切换存储后端（SQLite ↔ MySQL）

仅改环境变量，业务代码无改动（NFR-010 / AC-014）：

```bash
# server/.env
DB_CLIENT=mysql
DB_MYSQL_HOST=...
DB_MYSQL_PORT=3306
DB_MYSQL_USER=witty
DB_MYSQL_PASSWORD=...
DB_MYSQL_DATABASE=witty
```

随后 `npm run migrate` 在 MySQL 上建同一套表。

## 主要 API（对应 02 §6.1）

| 方法 | 路径 | 说明 |
|-|-|-|
| POST | `/api/auth/login` / `/api/auth/logout`，GET `/api/auth/me` | 会话 |
| POST | `/api/tasks` | 创建任务（在线需连通性已通过，BC-003） |
| POST | `/api/tasks/connectivity-test` | 测连通性 |
| POST | `/api/uploads` | 离线日志上传（.log/.tar.gz/.zip） |
| GET | `/api/tasks?type=all\|online\|offline` | 本人任务列表 |
| GET | `/api/tasks/:id` | 任务详情（含日志） |
| GET | `/api/tasks/:id/stream` | SSE 实时进度/日志 |
| POST | `/api/tasks/:id/cancel` \| `/retry` | 取消 / 重试 |
| DELETE | `/api/tasks/:id` | 删除（运行中需先取消） |
| GET | `/api/tasks/:id/report` | 报告 |
| PUT | `/api/tasks/:id/rating` | 评分 1–5 |

> 越权一致性：非 owner 的任务 ID 一律返回 404，不泄露存在性（NFR-003）。
