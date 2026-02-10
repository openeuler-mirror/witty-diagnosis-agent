"""
Base RCA Tool

Provides a lightweight base class for RCA analysis tools used in the
Suspicious Identification Skill. This version intentionally removes
any LangChain/tooling依赖，只保留纯 Python 逻辑，方便直接通过
import + 函数调用的方式使用。
"""

from typing import Any, Dict, Optional, Tuple
from datetime import datetime, timedelta


class BaseRCATool:
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        self.config: Dict[str, Any] = config or {}
        self._initialized: bool = False

    def initialize(self) -> None:
        self._initialized = True

    def is_initialized(self) -> bool:
        return self._initialized

    def validate_time_range(
        self,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
    ) -> Tuple[datetime, datetime]:
        if start_time and end_time and start_time > end_time:
            raise ValueError("start_time must be before end_time")

        if end_time is None:
            end_time = datetime.now()
        if start_time is None:
            start_time = end_time - timedelta(hours=1)

        return start_time, end_time

    def cleanup(self) -> None:
        self._initialized = False
