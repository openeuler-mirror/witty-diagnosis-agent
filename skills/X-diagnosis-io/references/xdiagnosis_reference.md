# X-diagnosis IO/文件系统诊断工具参考手册

本手册涵盖了用于存储系统与文件系统在线故障诊断的核心工具及其详细使用说明。

---

## 1. xd_iolatency

**功能**
用于跟踪块设备（Block Device）的 IO 时延分布情况，帮助定位 IO 性能瓶颈。

**用法**
```bash
xd_iolatency [ OPTIONS ]
```

**参数**
- `-d, --device=DEVICE`: 指定需要监控的设备（如 sdb），该项必须指定，最多支持 4 个。
- `-i, --issue=ISSUE`: 指定监控的 IO 时延阶段（Q2G, Q2M, G2M, G2I, I2D, D2C）。
- `-m, --milliseconds`: 显示时延单位为毫秒（默认为微秒）。
- `-t, --time=TIME`: 监控时长，单位秒（默认 5s）。
- `-T, --times=TIMES`: 监控次数，达到后自动结束。
- `-c, --clean`: 每个周期清理历史数据。

**核心阶段定义**
- **Q2G**: 从 bio 提交到 generic_make_request 耗时。
- **G2I**: 从 block 层下发到 IO 调度器耗时。
- **I2D**: 从 IO 调度器下发到设备驱动耗时。
- **D2C**: 设备处理耗时。

---

## 2. xd_scsiiocount

**功能**
用于统计 SCSI 命令下发的各类命令数量，常用于定位写放大或异常 IO 高负载。

**用法**
```bash
xd_scsiiocount [ OPTIONS ]
```

**参数**
- `-d, --device=DEVICE`: 指定监控的设备，默认监控所有。
- `-i, --interval=INTERVAL`: 刷新时间间隔，单位秒（默认 5s）。
- `-t, --times=TIMES`: 监控次数。

---

## 3. xd_scsiiotrace

**功能**
监控 SCSI 命令的执行结果，捕获驱动返回、SCSI 转换结果及处理状态。

**用法**
```bash
xd_scsiiotrace [ OPTIONS ]
```

**参数**
- `-d, --device=h:c:t:l`: 指定监控的 SCSI 设备（格式：host:channel:target:lun）。
- `-e, --event=EVENT`: 监控指定事件（start, error, timeout, done）。
- `-o, --opcode=OPCODE`: 监控指定 SCSI 命令操作码。
- `-p, --parse=RESULT`: 用于解析 DRIVER_RESULT 或 SCSI_RESULT 的十六进制值含义。
- `-r, --result`: 仅监控结果大于 0 的异常命令。

**结果说明 (DISPOSITION)**
- **SUCCESS**: 成功。
- **NEEDS_RETRY / ADD_TO_MLQUEUE**: 重新入队列重试。
- **TIMEOUT_ERROR**: 命令超时。

---

## 4. xd_ext4fsstat

**功能**
用于监控 ext4 文件系统的读写数据量统计，可精确到进程或文件。

**用法**
```bash
xd_ext4fsstat [ OPTIONS ]
```

**参数**
- `-m, --mnt=MNTPOINT`: 指定监控的 ext4 挂载点（如 /mnt/data）。
- `-v, --view=VIEW`: 显示模式（p: 进程模式，f: 文件模式，默认文件模式）。
- `-o, --opcode=OPCODE`: 指定监控读(r)或写(w)，默认两者都监控。
- `-s, --sort=SORT`: 排序方式（r/w/wb），默认按读量排序。
- `-p, --pid=PID`: 仅监控特定进程。
- `-i, --interval=INTERVAL`: 刷新间隔，默认 5s。
- `-t, --times=TIMES`: 监控次数。
- `-T, --top=TOP`: 仅显示 Top N 数据。
- `-c, --clean`: 每个周期清理数据。

**注意事项**
- 进程模式下，若多进程写入同一文件，writeback 数据显示为文件写入总和。
