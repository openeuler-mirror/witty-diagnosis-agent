from abc import ABC, abstractmethod
from typing import Any, Callable, Dict, List, Optional
import pandas as pd
import re
import schema

class MetricSemanticAdapter(ABC):
    @abstractmethod
    def get_candidate_entities(self, df: pd.DataFrame, time_range: Optional[Dict[str, str]] = None, label_selector: Optional[Dict[str, Any]] = None) -> List[str]:
        ...

    @abstractmethod
    def build_derived_metrics(self, df: pd.DataFrame) -> Optional[pd.DataFrame]:
        ...

    @abstractmethod
    def classify_metric(self, metric_name: str) -> Optional[Dict[str, Any]]:
        ...

    @abstractmethod
    def get_absolute_threshold(self, metric_class: Optional[Dict[str, Any]]) -> Optional[float]:
        ...

    @abstractmethod
    def get_baseline_params(self, metric_class: Optional[Dict[str, Any]]) -> Optional[Dict[str, float]]:
        ...

    @abstractmethod
    def format_severity(self, deviation_pct: float, max_value: float) -> Optional[str]:
        ...

class NullMetricAdapter(MetricSemanticAdapter):
    def get_candidate_entities(self, df: pd.DataFrame, time_range: Optional[Dict[str, str]] = None, label_selector: Optional[Dict[str, Any]] = None) -> List[str]:
        if df is None or df.empty:
            return []
        return sorted(df[schema.COL_ENTITY_ID].unique()) if schema.COL_ENTITY_ID in df.columns else []

    def build_derived_metrics(self, df: pd.DataFrame) -> Optional[pd.DataFrame]:
        return None

    def classify_metric(self, metric_name: str) -> Optional[Dict[str, Any]]:
        return None

    def get_absolute_threshold(self, metric_class: Optional[Dict[str, Any]]) -> Optional[float]:
        return None

    def get_baseline_params(self, metric_class: Optional[Dict[str, Any]]) -> Optional[Dict[str, float]]:
        return None

    def format_severity(self, deviation_pct: float, max_value: float) -> Optional[str]:
        return None


class OpenRCAMetricAdapter(MetricSemanticAdapter):
    def get_candidate_entities(self, df: pd.DataFrame, time_range: Optional[Dict[str, str]] = None, label_selector: Optional[Dict[str, Any]] = None) -> List[str]:
        candidates = [
            "apache01", "apache02",
            "Tomcat01", "Tomcat02", "Tomcat03", "Tomcat04",
            "Mysql01", "Mysql02",
            "Redis01", "Redis02",
            "MG01", "MG02",
            "IG01", "IG02",
        ]
        if df is None or df.empty:
            return candidates
        present = set(df[schema.COL_ENTITY_ID].unique())
        return [c for c in candidates if c in present]

    def build_derived_metrics(self, df: pd.DataFrame) -> Optional[pd.DataFrame]:
        if df is None or df.empty:
            return None
        heap_max_df = df[df[schema.COL_METRIC_NAME].str.contains('HeapMemoryMax', na=False)].copy()
        heap_used_df = df[df[schema.COL_METRIC_NAME].str.contains('HeapMemoryUsed', na=False)].copy()
        if heap_max_df.empty or heap_used_df.empty:
            return None
        jvm_oom_data: List[Dict[str, Any]] = []
        comps = set(heap_max_df[schema.COL_ENTITY_ID].unique()).intersection(set(heap_used_df[schema.COL_ENTITY_ID].unique()))
        for comp in comps:
            max_data = heap_max_df[heap_max_df[schema.COL_ENTITY_ID] == comp].sort_values(schema.COL_TIMESTAMP)
            used_data = heap_used_df[heap_used_df[schema.COL_ENTITY_ID] == comp].sort_values(schema.COL_TIMESTAMP)
            max_data['time_key'] = (max_data[schema.COL_TIMESTAMP].astype('int64') // 60000) * 60000
            used_data['time_key'] = (used_data[schema.COL_TIMESTAMP].astype('int64') // 60000) * 60000
            merged = pd.merge(
                max_data[['time_key', schema.COL_VALUE]].rename(columns={schema.COL_VALUE: 'HeapMemoryMax'}),
                used_data[['time_key', schema.COL_VALUE]].rename(columns={schema.COL_VALUE: 'HeapMemoryUsed'}),
                on='time_key',
                how='inner'
            )
            if merged.empty:
                continue
            merged['HeapUsage'] = merged['HeapMemoryUsed'] / merged['HeapMemoryMax']
            merged = merged[merged['HeapMemoryMax'] > 0]
            if merged.empty:
                continue
            for _, row in merged.iterrows():
                jvm_oom_data.append({
                    schema.COL_TIMESTAMP: int(row['time_key']),
                    schema.COL_ENTITY_ID: comp,
                    schema.COL_METRIC_NAME: 'JVM_Heap_Usage',
                    schema.COL_VALUE: row['HeapUsage']
                })
        return pd.DataFrame(jvm_oom_data) if jvm_oom_data else None

    def classify_metric(self, metric_name: str) -> Optional[Dict[str, Any]]:
        name = str(metric_name)
        lower = name.lower()
        if name == 'OSLinux-CPU_CPU_CPUCpuUtil':
            return {"kind": "cpu.util", "unit": "percent"}
        if name == 'OSLinux-OSLinux_MEMORY_MEMORY_MEMUsedMemPerc':
            return {"kind": "mem.util", "unit": "percent"}
        if re.match(r'.*DSKRead$', name) or re.match(r'.*DSKWrite$', name) or re.match(r'.*DSKReadWrite$', name):
            return {"kind": "disk.io", "unit": "rate"}
        if 'disk' in lower and ('space' in lower or 'usage' in lower):
            return {"kind": "disk.space", "unit": "percent"}
        if 'NETBandwidthUtil' in name:
            return {"kind": "net.util", "unit": "percent"}
        if re.match(r'.*NETInErr.*$', name) or re.match(r'.*NETOutErr.*$', name):
            return {"kind": "net.error", "unit": "count"}
        if 'TotalTcpConnNum' in name or 'TCP-CLOSE-WAIT' in name or 'TCP-FIN-WAIT' in name:
            return {"kind": "net.tcp", "unit": "count"}
        if re.match(r'.*NetworkRxBytes$', name) or re.match(r'.*NetworkTxBytes$', name):
            return {"kind": "net.bytes", "unit": "bytes"}
        if 'JVM' in name and '_CPULoad' in name:
            return {"kind": "jvm.cpu.load", "unit": "ratio"}
        if 'JVM_Heap_Usage' in name:
            return {"kind": "jvm.heap.usage", "unit": "ratio"}
        if 'HeapMemoryMax' in name or 'HeapMemoryUsed' in name:
            return None
        return None

    def get_absolute_threshold(self, metric_class: Optional[Dict[str, Any]]) -> Optional[float]:
        if not metric_class:
            return None
        kind = metric_class.get("kind")
        if kind == "mem.util":
            return 85.0
        if kind == "jvm.cpu.load":
            return 20.0
        if kind == "cpu.util":
            return 80.0
        if kind == "jvm.heap.usage":
            return 0.9
        if kind == "net.util":
            return 85.0
        return None

    def get_baseline_params(self, metric_class: Optional[Dict[str, Any]]) -> Optional[Dict[str, float]]:
        if not metric_class:
            return {"min_baseline_threshold": 0.1, "reference_value": 100.0}
        kind = metric_class.get("kind", "")
        if kind == "jvm.cpu.load":
            return {"min_baseline_threshold": 0.1, "reference_value": 1.0}
        if kind == "cpu.util":
            return {"min_baseline_threshold": 10.0, "reference_value": 100.0}
        if kind == "mem.util":
            return {"min_baseline_threshold": 10.0, "reference_value": 100.0}
        if kind == "jvm.heap.usage":
            return {"min_baseline_threshold": 0.1, "reference_value": 1.0}
        if kind in ("net.util", "disk.space"):
            return {"min_baseline_threshold": 10.0, "reference_value": 100.0}
        return {"min_baseline_threshold": 0.1, "reference_value": 100.0}

    def format_severity(self, deviation_pct: float, max_value: float) -> Optional[str]:
        sev = "严重" if deviation_pct > 100 else "显著" if deviation_pct > 50 else "中等"
        return f"{sev}（最大值：{max_value:.1f}，偏离：{deviation_pct:.1f}%）"


_ADAPTER_REGISTRY: Dict[str, Callable[..., MetricSemanticAdapter]] = {}

def register_metric_adapter(name: str, constructor: Callable[[], MetricSemanticAdapter]) -> None:
    _ADAPTER_REGISTRY[name.lower()] = constructor

def create_metric_adapter(config: Optional[Dict[str, Any]] = None) -> MetricSemanticAdapter:
    cfg = config or {}
    name = str(cfg.get("metric_adapter", "openrca")).lower()
    if name not in _ADAPTER_REGISTRY:
        return NullMetricAdapter()
    ctor = _ADAPTER_REGISTRY[name]
    return ctor()

register_metric_adapter("openrca", lambda: OpenRCAMetricAdapter())
