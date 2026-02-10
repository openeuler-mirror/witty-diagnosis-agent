## `scripts/` — 可执行脚本库

**核心用途：** 封装原子化的工具，供 Agent 直接调用。在架构设计上需严格遵守 **幂等性**。

**⚙️ 规范要求**

* **幂等性：** 无论执行多少次，系统状态保持一致。
* **安全性：** 默认仅限只读操作，变更操作需显式声明。
* **标准化输出：** 统一返回 JSON 或结构化文本，便于 Agent 解析。

**📄 模板示例 (`validate.py`)**

```python
#!/usr/bin/env python3
"""
Description: 输入文件格式校验工具
Usage: python validate.py <file_path>
"""

import sys
import json

def validate_schema(filepath):
    try:
        with open(filepath) as f:
            data = json.load(f)
        
        errors = []
        if 'name' not in data:
            errors.append("Missing required field: 'name'")
        
        return len(errors) == 0, errors
    except Exception as e:
        return False, [str(e)]

if __name__ == "__main__":
    is_valid, errors = validate_schema(sys.argv[1])
    if is_valid:
        print(json.dumps({"status": "success", "message": "OK"}))
    else:
        print(json.dumps({"status": "error", "details": errors}))
        sys.exit(1)
```
