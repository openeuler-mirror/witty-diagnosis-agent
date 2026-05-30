# OverlayFS 故障注入测试套件

## 目录结构

```
test/overlayfs/
├── 00_common.sh                 # 公共框架：容器管理、依赖检查、报告函数
├── run.sh                       # 主入口：交互菜单 + 命令行模式
├── cleanup_all.sh               # 全局清理：容器 + 临时文件 + loop 设备 + 镜像
├── README.md                    # 本文件
├── fault_injection/
│   ├── branch_A_config_error_inject.sh          # 配置错误（upperdir 不存在/权限不足/跨设备）
│   ├── branch_B_fs_incompatible_inject.sh       # 文件系统不兼容（vfat/tmpfs/FUSE）
│   ├── branch_C_cross_device_inject.sh          # 跨设备 overlay（upper/work 不同设备）
│   ├── branch_D_opaque_whiteout_inject.sh       # Opaque Whiteout（char 0,0 + xattr 注入）
│   ├── branch_E_copyup_perf_inject.sh           # Copy-up 性能退化
│   ├── branch_F_inotify_inject.sh               # inotify 失效
│   ├── branch_G_inode_exhaust_inject.sh         # inode 耗尽
│   ├── branch_H_diff_bloat_inject.sh            # diff 目录膨胀
│   ├── branch_I_redirect_metacopy_inject.sh     # redirect_dir / metacopy 冲突
│   ├── branch_J_permission_inject.sh            # 权限/元数据异常
│   ├── branch_K_readdir_perf_inject.sh          # readdir 性能
│   └── branch_Z_general_inject.sh               # 通用/最小化复现
└── reports/
    ├── OverlayFS挂载故障分析_*.md/html         # 分支 A
    ├── OverlayFS_upperdir_vfat不兼容_*          # 分支 B
    ├── OverlayFS跨设备挂载故障_*                # 分支 C
    ├── OverlayFS-Whiteout故障诊断_*             # 分支 D
    ├── OverlayFS_copy-up性能退化_*              # 分支 E
    ├── OverlayFS_inotify验证_*                  # 分支 F
    ├── Docker容器overlayfs-inode压力测试_*      # 分支 G
    ├── Docker容器OverlayFS上层膨胀_*            # 分支 H
    ├── OverlayFS重命名redirect_dir测试_*        # 分支 I
    ├── OverlayFS_merged写入Read-only_*          # 分支 J
    ├── OverlayFS大目录readdir性能瓶颈_*         # 分支 K
    └── Docker容器overlayfs-fault-Z最小化_*      # 分支 Z
```

## 前置条件

- Docker 已安装且守护进程运行中
- 当前用户有 Docker socket 权限
- 内核支持 overlay 文件系统（`lsmod | grep overlay`）

## 快速使用

```bash
# 单分支注入 + 自验证
bash fault_injection/branch_A_inject.sh
bash fault_injection/branch_D_inject.sh

# 交互菜单
bash run.sh

# 一键执行全部
bash run.sh all

# 全局清理
bash run.sh clean
# 或
bash cleanup_all.sh
```

## 技术说明

- 所有故障注入在 Docker `--privileged` 容器中执行，对宿主机零影响
- 容器根文件系统是 overlay2 时无法在其内部嵌套 `mount -t overlay`（内核限制），注入脚本使用 ext4 loop 设备或 tmpfs 绕开
- 内核 whiteout 识别：仅 `mknod ... c 0 0` 字符设备被内核认可，`.wh.` 前缀常规文件无效
- `metacopy`/`redirect_dir` 功能依赖内核配置（WSL2 默认关闭）

## 排除的文件

本目录仅包含故障测试所需的脚本和报告。以下 skill 文件未包含：
- `scripts/` — 诊断执行脚本（属于 overlayfs-diagnosis skill）
- `references/` — 参考文档
- `SKILL.md` — skill 主文档
