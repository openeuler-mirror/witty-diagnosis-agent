# S2 — 权限控制：诊断参考

## 1. 权限检查优先级（三层叠加）

Linux权限控制有三个独立层次，**任意一层拒绝即拒绝访问**：

```
访问请求
  │
  ├─[1] DAC（传统Unix权限）: ls -l 查看，chmod/chown 控制
  │       user:rwx  group:rwx  other:rwx
  │
  ├─[2] ACL（访问控制列表）: getfacl 查看，setfacl 控制
  │       比DAC更细粒度，可针对特定用户/组设置权限
  │
  └─[3] MAC（强制访问控制）: SELinux/AppArmor
          即使DAC+ACL都允许，SELinux仍可拒绝
```

## 2. 常见权限问题快速判断

```bash
# 一键判断: 权限拒绝来自哪一层
check_access() {
    local file="$1" user="$2"
    echo "=== DAC权限 ==="
    ls -la "$file"
    echo "=== ACL权限 ==="
    getfacl "$file" 2>/dev/null
    echo "=== SELinux标签 ==="
    ls -laZ "$file" 2>/dev/null
    echo "=== 当前SELinux模式 ==="
    getenforce 2>/dev/null
}
```

## 3. Capabilities 与 SUID 的区别

| 机制 | 说明 | 查看 | 风险 |
|------|------|------|------|
| SUID位 | 以文件所有者身份运行 | `find -perm -4000` | 高风险，可完全提权 |
| Capabilities | 细粒度特权（如cap_net_raw） | `getcap -r /` | 低风险，但需审计 |

```bash
# 查看文件capabilities
getcap /usr/bin/ping 2>/dev/null
# 正常输出: /usr/bin/ping = cap_net_raw+ep

# 清除capabilities
setcap -r /path/to/binary

# 常见需要capabilities的程序
# ping: cap_net_raw
# tcpdump: cap_net_raw,cap_net_admin
# wireshark: cap_net_raw,cap_net_admin
```

## 4. SELinux 文件标签修复

```bash
# 最常用：恢复文件SELinux默认标签
restorecon -Rv /path/to/directory

# 手动修改标签
chcon -t httpd_sys_content_t /var/www/html/file.php

# 查看某类型的文件应该有什么标签
matchpathcon /var/www/html/

# 应用场景：文件从一个目录移动到另一个目录后标签不对
# mv会保留原标签，cp会继承目标目录标签
# 移动后必须 restorecon
```

## 5. sudo 配置安全审计

```bash
# 查看完整sudo配置（包含#include）
sudo -l -U username  # 查看特定用户的sudo权限

# 危险的sudo配置识别
grep -E "ALL.*NOPASSWD|!authenticate|\(ALL\)" /etc/sudoers /etc/sudoers.d/* 2>/dev/null

# 特别危险的配置示例（应告警）：
# user ALL=(ALL) NOPASSWD: ALL     → 无密码root权限
# user ALL=(ALL) /bin/bash         → 可以开root shell
# user ALL=(ALL) /bin/less         → less可以执行命令
```
