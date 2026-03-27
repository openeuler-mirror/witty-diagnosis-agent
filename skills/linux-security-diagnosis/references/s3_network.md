# S3 — 防火墙与网络访问：诊断参考

## 1. firewalld vs iptables 共存问题

CentOS 7+默认使用firewalld作为前端，底层仍是iptables。两者并存时需注意：
- **RHEL7/CentOS7**: firewalld + iptables 可并存，firewalld优先
- **RHEL8/CentOS8**: 默认nftables后端，firewalld使用nftables
- **冲突场景**: 直接操作iptables + firewalld同时运行 → 规则可能被覆盖

```bash
# 确认当前防火墙管理方式
systemctl is-active firewalld iptables nftables 2>/dev/null

# 查看实际生效的底层规则（nftables）
nft list ruleset 2>/dev/null

# 确认firewalld是否使用nftables后端
firewall-cmd --info-zone=public 2>/dev/null | grep backend
```

## 2. 常见防火墙故障模式

| 故障 | 症状 | 排查 |
|------|------|------|
| 规则未持久化 | 重启后规则消失 | `firewall-cmd --runtime-to-permanent` |
| zone分配错误 | 接口在wrong zone | `firewall-cmd --get-active-zones` |
| rich rule优先级 | 明确allow被隐式deny覆盖 | `firewall-cmd --list-rich-rules` |
| iptables与firewalld冲突 | 规则冲突/覆盖 | 确保只用一种管理工具 |

## 3. 端口暴露风险判断

```bash
# 对比：预期开放端口 vs 实际监听端口
EXPECTED_PORTS="22 80 443 3306"  # 根据业务填写
ss -tuln | grep "LISTEN" | grep -oP ':\K\d+' | sort -n | while read port; do
    echo "$EXPECTED_PORTS" | grep -wq "$port" \
        && echo "  ✓ $port: 预期端口" \
        || echo "  ⚠️ $port: 非预期端口（需审查）"
done
```

## 4. 连接被拒绝根因判断

```
连接被拒绝 (Connection refused)  → 服务未监听该端口（进程问题）
连接超时 (Connection timed out)   → 防火墙DROP规则（无响应）
连接被重置 (Connection reset)     → 防火墙REJECT规则（发RST）
权限拒绝 (Permission denied)      → SELinux或TCP Wrapper
```

## 5. TCP Wrapper 排查
```bash
# /etc/hosts.allow 和 /etc/hosts.deny 也可以限制访问
cat /etc/hosts.allow 2>/dev/null
cat /etc/hosts.deny 2>/dev/null
```
