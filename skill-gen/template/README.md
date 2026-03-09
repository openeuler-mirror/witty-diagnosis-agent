## skill 模板
本目录提供了用于用户自定义skill的参考模板，用户需要根据如下目录结构进行组织skill目录
```bash
|--- skill_name/ # skill的名称
    |--- SKILL.md # skill主要描述文件，按照SKILL.md.example进行撰写
    |--- reference/ # 可选，SKILL.md中需要参考的资源
    |--- scripts/ # 可选，可用的工具脚本等
```

在完成上述skill目录的文件内容之后，用户需要将skill文件夹拷贝到指定的自定义skill目录下，由OpsAgent自动进行加载