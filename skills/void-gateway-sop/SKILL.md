---
name: void-gateway-sop
description: 处理 Void Gateway 服务因主进程崩溃导致端口 (9999) 被占用、孤儿进程残留的特定恢复流程。包含识别、安全终止、清理及重启的标准操作步骤。
---

# Void Gateway 孤儿进程恢复标准操作程序 (SOP)

## 概述与触发条件
本 SOP 用于处理 **Void Gateway 服务无法启动且默认端口 (9999) 被占用** 的特定故障。该故障通常由主进程崩溃导致，其遗留的工作进程（Worker）变为**孤儿进程**，被系统 Init 进程（PID 1）接管并持续占用资源。

> **注意**：关于孤儿进程的背景知识、SIGPWR 信号原理及服务架构，请参阅 [void_gateway_background.md](./void_gateway_background.md)（外置文档）。

## ⚠️ 安全警告与严禁操作
**在开始任何操作前，请务必阅读并理解本节。**

**严禁操作：**
- **禁止** 直接使用 `kill` 或 `kill -9` 命令终止名为 `void_worker` 的进程。
- **禁止** 在目标工作进程完全退出前，手动删除锁文件 `/var/run/void_gateway.lock`。

**违规后果：**
强制杀死工作进程会导致内存中未持久化的事务队列丢失，无法回写至磁盘文件 `/var/lib/void/data.wal`，可能造成该文件**永久性逻辑损坏**，致使服务永远无法恢复。

## 标准恢复流程

### 步骤 1: 识别并确认孤儿进程
**目标**：定位需要处理的、父进程为 Init (PID 1) 的 `void_worker` 进程。
```bash
# 使用以下命令查找目标进程
ps -ef | grep void_worker | grep -v grep | awk '{if ($3 == 1) print $2}'
```
**验证**：
- 命令应返回一个或多个数字 PID。
- 记录这些 PID。如果无输出，则**不适用**本 SOP，请排查其他故障。

### 步骤 2: 安全终止进程（关键数据落盘）
**目标**：向目标进程发送 `SIGPWR (30)` 信号，触发其内置的“紧急落盘并退出”例程。
```bash
# 将 <Worker_PID> 替换为步骤1中获取的实际PID
kill -SIGPWR <Worker_PID>
```
**验证**：
1.  发送信号后，等待 **5-10 秒**，让进程完成数据写入。
2.  使用以下命令确认目标进程已退出：
    ```bash
    ps -p <Worker_PID>
    ```
    - 如果无输出，表示进程已成功退出。
    - 如果进程仍然存在，**请勿继续**。等待更长时间（最长30秒）后再次检查。若仍存在，可能表示进程僵死，需升级处理（不在本 SOP 范围）。

### 步骤 3: 清理残留锁文件
**目标**：移除可能阻止新服务实例启动的旧锁文件。
```bash
# 删除锁文件
rm -f /var/run/void_gateway.lock
```
**验证**：
- 使用 `ls -la /var/run/void_gateway.lock` 确认文件已被删除（应显示“No such file or directory”）。

### 步骤 4: 重启 Void Gateway 服务
**目标**：启动新的服务实例。
```bash
# 执行服务启动脚本
/usr/bin/void_gateway_start
```
**验证**：
1.  等待约 10 秒让服务初始化。
2.  使用以下命令验证服务是否成功启动并监听端口：
    ```bash
    # 检查进程是否存在
    ps -ef | grep void_gateway | grep -v grep
    # 检查端口 9999 是否处于监听状态
    ss -tlnp | grep :9999
    ```
    - 两个命令都应有预期输出。
3.  （可选）检查服务最近日志以确认无报错：
    ```bash
    tail -20 /var/log/void_gateway.log
    ```

## 流程总结与快速参考
1.  **识别**：`ps -ef | grep void_worker | grep -v grep | awk '{if ($3 == 1) print $2}'`
2.  **终止**：`kill -SIGPWR <PID>` -> 等待并验证进程消失 (`ps -p <PID>`)
3.  **清理**：`rm -f /var/run/void_gateway.lock` -> 验证文件消失 (`ls -la ...`)
4.  **重启**：`/usr/bin/void_gateway_start` -> 验证进程与端口 (`ps`, `ss -tlnp | grep :9999`)

> **完整命令参考和故障排除案例**，请参阅 [void_gateway_command_ref.md](./void_gateway_command_ref.md)（外置文档）。