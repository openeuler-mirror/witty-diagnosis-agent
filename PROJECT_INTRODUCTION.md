这是一个由 openEuler sig-intelligence 社区维护的开源智能运维（AIOps）平台。

我们为该项目贡献了 mmap-vma-diagnosis 诊断技能，专门用于 Linux 环境下的内存映射与虚拟地址空间故障诊断。该技能覆盖了六类最常见的 mmap 相关故障场景：vm.max_map_count 耗尽（Elasticsearch 中尤为常见）、SIGBUS 文件截断、mlock 超限、共享内存权限拒绝、地址空间碎片化以及通用 mmap 失败。

整个交付共 26 个文件、约 2,600 行代码，包括核心诊断流程文档、专业参考文档、诊断脚本、C 语言故障注入程序、Docker 测试框架脚本以及验证报告，形成了从故障注入到数据采集、场景识别、根因推理再到报告输出的全链路闭环。