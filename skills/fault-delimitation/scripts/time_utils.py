from typing import Any
import pandas as pd
import numpy as np


def to_iso_shanghai(ts: Any) -> str:
    if isinstance(ts, (int, np.integer, float)):
        dt = pd.to_datetime(ts, unit="ms", utc=True).tz_convert("Asia/Shanghai")
        return dt.isoformat()
    if isinstance(ts, pd.Timestamp):
        timestamp = ts
    else:
        timestamp = pd.Timestamp(ts)
    if timestamp.tzinfo is None:
        timestamp = timestamp.tz_localize("Asia/Shanghai")
    else:
        timestamp = timestamp.tz_convert("Asia/Shanghai")
    return timestamp.isoformat()

def to_iso_with_tz(ts: Any, tz: str) -> str:
    if isinstance(ts, (int, np.integer, float)):
        dt = pd.to_datetime(ts, unit="ms", utc=True).tz_convert(tz)
        return dt.isoformat()
    if isinstance(ts, pd.Timestamp):
        timestamp = ts
    else:
        timestamp = pd.Timestamp(ts)
    if timestamp.tzinfo is None:
        timestamp = timestamp.tz_localize(tz)
    else:
        timestamp = timestamp.tz_convert(tz)
    return timestamp.isoformat()
