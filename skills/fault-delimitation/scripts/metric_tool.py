"""
Metric Analysis Tool

高代码版本中的 MetricAnalysisTool 主要是为 LangChain Agent 提供工具包装。
在 Skill 场景下，我们只需要纯 Python 的分析能力，直接通过函数调用拿到
可疑组件列表等结果，因此这里保留分析逻辑，去掉所有 LangChain 相关封装，
并提供一个直接可调用的入口函数。
"""

from typing import Any, Dict, List, Optional, Tuple

from base import BaseRCATool
import pandas as pd
import numpy as np
import json
import ruptures as rpt

from time_utils import to_iso_with_tz
from data_loader import BaseDataLoader, create_data_loader
from metric_adapter import MetricSemanticAdapter, create_metric_adapter
import schema


class MetricAnalysisTool(BaseRCATool):
    """
    Tool for analyzing time-series metrics with high-level semantic operations.
    
    This tool analyzes both application-level metrics (service performance) and
    infrastructure-level metrics (CPU, memory, disk, network) to support root cause analysis.
    """
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """
        Initialize the metric analysis tool.
        
        Args:
            config: Configuration dictionary that may include:
                   - dataset_path: Path to the dataset
                   - metric_source: Source type (local, remote, etc.)
        """
        super().__init__(config)
        self.data_loader: Optional[BaseDataLoader] = None
        self.adapter: Optional[MetricSemanticAdapter] = None
        
    def initialize(self) -> None:
        """Initialize metric data source connections."""
        super().initialize()
        self.data_loader = create_data_loader(self.config)
        self.adapter = create_metric_adapter(self.config)
    
    def _check_loader(self) -> None:
        if not self.data_loader:
            raise RuntimeError("Tool not initialized. Call initialize() first.")
    
    def _get_metric_df(self, start_time: str, end_time: str) -> pd.DataFrame:
        if not self.data_loader:
            return pd.DataFrame(
                columns=[
                    schema.COL_TIMESTAMP,
                    schema.COL_ENTITY_ID,
                    schema.COL_METRIC_NAME,
                    schema.COL_VALUE,
                ]
            )
        return self.data_loader.get_metrics(start_time, end_time)
    
    def _calculate_robust_stats(self, df: pd.DataFrame, columns: List[str] = None) -> Dict[str, Dict[str, float]]:
        if columns is None:
            columns = df.select_dtypes(include=[np.number]).columns.tolist()
            default_cols = ["value", "mrt", "sr", "rr", "cnt"]
            known_cols = [c for c in default_cols if c in df.columns]
            if known_cols and len(columns) > len(known_cols):
                pass
        columns = [col for col in columns if col in df.columns]
        descriptions: Dict[str, Dict[str, float]] = {}
        for column in columns:
            col_data = df[column].dropna().sort_values()
            if len(col_data) > 4:
                trimmed_data = col_data.iloc[2:-2]
            else:
                trimmed_data = col_data
            if trimmed_data.empty:
                continue
            desc = trimmed_data.describe(percentiles=[0.25, 0.5, 0.75, 0.95, 0.99]).to_dict()
            non_zero_ratio = (trimmed_data != 0).sum() / len(trimmed_data)
            desc["non_zero_ratio"] = round(non_zero_ratio, 3)
            descriptions[column] = desc
        return descriptions
    
    def _infer_baseline_period(self, start_time: str, end_time: str) -> Tuple[str, str]:
        try:
            tz = self.data_loader.get_timezone() if self.data_loader else "UTC"
            target_start = pd.to_datetime(start_time)
            target_end = pd.to_datetime(end_time)
            if getattr(target_start, "tzinfo", None) is None:
                target_start = target_start.tz_localize(tz)
            else:
                target_start = target_start.tz_convert(tz)
            if getattr(target_end, "tzinfo", None) is None:
                target_end = target_end.tz_localize(tz)
            else:
                target_end = target_end.tz_convert(tz)
            duration = target_end - target_start
            baseline_end = target_start
            baseline_start = baseline_end - duration
            return to_iso_with_tz(baseline_start, tz), to_iso_with_tz(baseline_end, tz)
        except Exception:
            return "", ""
 
    # def compare_service_metrics(
    #     self,
    #     start_time: str,
    #     end_time: str,
    #     baseline_start: Optional[str] = None,
    #     baseline_end: Optional[str] = None,
    #     service_name: Optional[str] = None
    # ) -> str:
    #     """Compare service metrics between a target period and a baseline period.
        
    #     Analyzes performance metrics (response time, success rate, etc.) for a specific time range
    #     and compares them against a baseline period to identify deviations and anomalies.
    #     If baseline period is not provided, it attempts to infer one.
        
    #     Args:
    #         start_time: Target period start time (ISO format)
    #         end_time: Target period end time (ISO format)
    #         baseline_start: Optional baseline period start time (ISO format)
    #         baseline_end: Optional baseline period end time (ISO format)
    #         service_name: Optional specific service to analyze
            
    #     Returns:
    #         Detailed comparison report highlighting changes in metrics, including
    #         percentage changes and robust statistical analysis (outliers removed).
    #     """
    #     self._check_loader()
    #     target_all = self._get_metric_df(start_time, end_time)
    #     if target_all.empty:
    #         return f"No application metrics found between {start_time} and {end_time}"
    #     target_df = target_all[target_all[schema.COL_METRIC_NAME] == "App_mrt"].copy()
    #     if target_df.empty:
    #         return f"No application latency metrics found between {start_time} and {end_time}"
    #     if not baseline_start or not baseline_end:
    #         baseline_start, baseline_end = self._infer_baseline_period(start_time, end_time)
    #     baseline_all = self._get_metric_df(baseline_start, baseline_end)
    #     baseline_df = baseline_all[baseline_all[schema.COL_METRIC_NAME] == "App_mrt"].copy() if not baseline_all.empty else pd.DataFrame()
    #     if service_name:
    #         target_df = target_df[target_df[schema.COL_ENTITY_ID] == service_name]
    #         if not baseline_df.empty:
    #             baseline_df = baseline_df[baseline_df[schema.COL_ENTITY_ID] == service_name]
    #         if target_df.empty:
    #             return f"No metrics found for service '{service_name}' in target range"
    #     services = sorted(target_df[schema.COL_ENTITY_ID].unique())
    #     output = [f"Service Metric Comparison:"]
    #     output.append(f"Target Period:   {start_time} to {end_time}")
    #     output.append(f"Baseline Period: {baseline_start} to {baseline_end}")
    #     if baseline_df.empty:
    #         output.append("⚠️ No baseline data found. Showing target stats only.")
    #     for svc in services:
    #         svc_target = target_all[(target_all[schema.COL_ENTITY_ID] == svc) & (target_all[schema.COL_METRIC_NAME].isin(["App_mrt", "App_sr", "App_rr", "App_cnt"]))]
    #         svc_baseline = baseline_all[(baseline_all[schema.COL_ENTITY_ID] == svc) & (baseline_all[schema.COL_METRIC_NAME].isin(["App_mrt", "App_sr", "App_rr", "App_cnt"]))] if not baseline_all.empty else pd.DataFrame()
    #         output.append(f"\nService: {svc}")
    #         t_stats = {}
    #         b_stats = {}
    #         for kpi in ["App_mrt", "App_sr", "App_rr", "App_cnt"]:
    #             t_vals = svc_target[svc_target[schema.COL_METRIC_NAME] == kpi][schema.COL_VALUE]
    #             b_vals = svc_baseline[svc_baseline[schema.COL_METRIC_NAME] == kpi][schema.COL_VALUE] if not svc_baseline.empty else pd.Series(dtype=float)
    #             t_desc = self._calculate_robust_stats(pd.DataFrame({"value": t_vals}), columns=["value"])
    #             b_desc = self._calculate_robust_stats(pd.DataFrame({"value": b_vals}), columns=["value"]) if not b_vals.empty else {}
    #             t_stats[kpi] = t_desc.get("value", {})
    #             b_stats[kpi] = b_desc.get("value", {})
    #         metrics_map = {
    #             "App_mrt": "Response Time (ms)",
    #             "App_sr": "Success Rate (%)",
    #             "App_rr": "Request Rate (req/s)",
    #             "App_cnt": "Total Requests",
    #         }
    #         for kpi, name in metrics_map.items():
    #             if t_stats.get(kpi):
    #                 t_mean = t_stats[kpi].get("mean")
    #                 if b_stats.get(kpi):
    #                     b_mean = b_stats[kpi].get("mean")
    #                     diff = (t_mean - b_mean) if b_mean is not None and t_mean is not None else 0.0
    #                     pct_change = (diff / b_mean * 100) if b_mean not in (None, 0) else 0.0
    #                     change_icon = ""
    #                     if kpi == "App_mrt":
    #                         if pct_change > 20:
    #                             change_icon = "⚠️ (SLOWER)"
    #                         elif pct_change < -20:
    #                             change_icon = "✅ (FASTER)"
    #                     elif kpi == "App_sr":
    #                         if diff is not None and diff < -0.1:
    #                             change_icon = "⚠️ (ERRORS UP)"
    #                     output.append(f"  - {name}: {b_mean:.2f} -> {t_mean:.2f} ({pct_change:+.1f}%) {change_icon}")
    #                     if kpi == "App_mrt":
    #                         t_p99 = t_stats[kpi].get("99%")
    #                         b_p99 = b_stats[kpi].get("99%")
    #                         if t_p99 is not None and b_p99 is not None:
    #                             output.append(f"    p99: {b_p99:.2f} -> {t_p99:.2f}")
    #                 else:
    #                     output.append(f"  - {name}: {t_mean:.2f} (No baseline)")
    #     return "\n".join(output)

    # def compare_container_metrics(
    #     self,
    #     start_time: str,
    #     end_time: str,
    #     component_name: str,
    #     metric_pattern: Optional[str] = None,
    #     baseline_start: Optional[str] = None,
    #     baseline_end: Optional[str] = None
    # ) -> str:
    #     """Compare container/infrastructure metrics between a target period and a baseline period.
        
    #     Analyzes infrastructure metrics (CPU, Memory, Disk, etc.) for a specific component
    #     and compares them against a baseline period.
        
    #     Args:
    #         start_time: Target period start time (ISO format)
    #         end_time: Target period end time (ISO format)
    #         component_name: Name of the component to analyze (e.g., 'Tomcat01')
    #         metric_pattern: Optional pattern to filter metrics (e.g., 'CPU', 'Memory')
    #         baseline_start: Optional baseline period start time
    #         baseline_end: Optional baseline period end time
            
    #     Returns:
    #         Comparison report for matching metrics.
    #     """
    #     self._check_loader()
    #     target_df = self._get_metric_df(start_time, end_time)
    #     if target_df.empty:
    #         return f"No container metrics found between {start_time} and {end_time}"
    #     target_df = target_df[(target_df[schema.COL_ENTITY_ID] == component_name)]
    #     if metric_pattern:
    #         target_df = target_df[target_df[schema.COL_METRIC_NAME].str.contains(metric_pattern, case=False, na=False)]
    #     if target_df.empty:
    #         return f"No metrics found for component '{component_name}' in target range"
    #     if not baseline_start or not baseline_end:
    #         baseline_start, baseline_end = self._infer_baseline_period(start_time, end_time)
    #     baseline_df = self._get_metric_df(baseline_start, baseline_end)
    #     if not baseline_df.empty:
    #         baseline_df = baseline_df[baseline_df[schema.COL_ENTITY_ID] == component_name]
    #         if metric_pattern:
    #             baseline_df = baseline_df[baseline_df[schema.COL_METRIC_NAME].str.contains(metric_pattern, case=False, na=False)]
    #     metrics = sorted(target_df[schema.COL_METRIC_NAME].unique())
    #     output = [f"Container Metric Comparison for {component_name}:"]
    #     output.append(f"Target Period:   {start_time} to {end_time}")
    #     output.append(f"Baseline Period: {baseline_start} to {baseline_end}")
    #     if baseline_df.empty:
    #         output.append("⚠️ No baseline data found. Showing target stats only.")
    #     for metric in metrics:
    #         metric_target = target_df[target_df[schema.COL_METRIC_NAME] == metric]
    #         metric_baseline = baseline_df[baseline_df[schema.COL_METRIC_NAME] == metric] if not baseline_df.empty else pd.DataFrame()
    #         target_stats = self._calculate_robust_stats(metric_target, columns=[schema.COL_VALUE])
    #         baseline_stats = self._calculate_robust_stats(metric_baseline, columns=[schema.COL_VALUE]) if not metric_baseline.empty else {}
    #         if schema.COL_VALUE in target_stats:
    #             t_mean = target_stats[schema.COL_VALUE]["mean"]
    #             t_p99 = target_stats[schema.COL_VALUE]["99%"]
    #             if schema.COL_VALUE in baseline_stats:
    #                 b_mean = baseline_stats[schema.COL_VALUE]["mean"]
    #                 b_p99 = baseline_stats[schema.COL_VALUE]["99%"]
    #             diff = t_mean - b_mean
    #             pct_change = (diff / b_mean * 100) if b_mean != 0 else 0.0
    #             change_icon = ""
    #             if pct_change > 20:
    #                 change_icon = "⚠️ (+)"
    #             elif pct_change < -20:
    #                 change_icon = "📉 (-)"
    #             output.append(f"\nMetric: {metric}")
    #             output.append(f"  - Mean: {b_mean:.2f} -> {t_mean:.2f} ({pct_change:+.1f}%) {change_icon}")
    #             output.append(f"  - P99:  {b_p99:.2f} -> {t_p99:.2f}")
    #         else:
    #             output.append(f"\nMetric: {metric}")
    #             output.append(f"  - Mean: {t_mean:.2f} (No baseline)")
    #             output.append(f"  - P99:  {t_p99:.2f}")
    #     return "\n".join(output)

    def get_metric_statistics(
        self,
        start_time: str,
        end_time: str,
        component_name: str,
        metric_name: str
    ) -> str:
        """Get detailed statistical breakdown for a specific metric.
        
        Provides comprehensive statistics including mean, std, min, max,
        percentiles (p25, p50, p75, p95, p99), and non-zero ratios.
        Useful for deep-dive analysis of a specific anomalous metric.
        
        Args:
            start_time: Start time (ISO format)
            end_time: End time (ISO format)
            component_name: Name of the component (e.g., 'Tomcat01')
            metric_name: Exact name of the metric (e.g., 'OSLinux-CPU_CPU_CPUCpuUtil')
            
        Returns:
            JSON-formatted string with detailed statistics.
        """
        self._check_loader()
        df = self._get_metric_df(start_time, end_time)
        if df.empty:
            return json.dumps({"error": "No metrics found in time range"})
        df = df[(df[schema.COL_ENTITY_ID] == component_name) & (df[schema.COL_METRIC_NAME] == metric_name)]
        if df.empty:
            return json.dumps({"error": f"No data found for {component_name} - {metric_name}"})
        stats = self._calculate_robust_stats(df, columns=[schema.COL_VALUE])
        result = {
            "component": component_name,
            "metric": metric_name,
            "period": {"start": start_time, "end": end_time},
            "statistics": stats.get(schema.COL_VALUE, {}),
        }
        return json.dumps(result, indent=2)

    # def find_slow_services(
    #     self,
    #     start_time: str,
    #     end_time: str,
    #     threshold_ms: float = 500.0
    # ) -> str:
    #     """Find services with high response times.
        
    #     Identifies services experiencing slow response times that may indicate
    #     performance issues or bottlenecks.
        
    #     Args:
    #         start_time: Start time in ISO format
    #         end_time: End time in ISO format
    #         threshold_ms: Response time threshold in milliseconds (default: 500ms)
            
    #     Returns:
    #         List of slow services with their average response times, p95/p99 latencies,
    #         and comparison to normal baseline
    #     """
    #     self._check_loader()
    #     df = self._get_metric_df(start_time, end_time)
    #     if df.empty:
    #         return "No data found for analysis"
    #     df = df[df[schema.COL_METRIC_NAME] == "App_mrt"]
    #     if df.empty:
    #         return "No application latency data found"
    #     avg_rt = df.groupby(schema.COL_ENTITY_ID)[schema.COL_VALUE].mean()
    #     slow_services = avg_rt[avg_rt > threshold_ms].sort_values(ascending=False)
    #     if slow_services.empty:
    #         return f"No services exceeded the latency threshold of {threshold_ms}ms"
    #     output = [f"Slow Services Report (Threshold: {threshold_ms}ms):"]
    #     for service, rt in slow_services.items():
    #         peak = df[df[schema.COL_ENTITY_ID] == service][schema.COL_VALUE].max()
    #         output.append(f"\n🔴 {service}")
    #         output.append(f"  - Average Latency: {rt:.2f}ms")
    #         output.append(f"  - Peak Latency: {peak:.2f}ms")
    #     return "\n".join(output)
    
    # def find_low_success_rate_services(
    #     self,
    #     start_time: str,
    #     end_time: str,
    #     threshold_percent: float = 95.0
    # ) -> str:
    #     """Find services with low success rates.
        
    #     Identifies services experiencing elevated error rates that may indicate
    #     failures or degraded functionality.
        
    #     Args:
    #         start_time: Start time in ISO format
    #         end_time: End time in ISO format
    #         threshold_percent: Success rate threshold percentage (default: 95%)
            
    #     Returns:
    #         List of services with low success rates, their actual success percentages,
    #         and request volumes affected
    #     """
    #     self._check_loader()
    #     df = self._get_metric_df(start_time, end_time)
    #     if df.empty:
    #         return "No data found for analysis"
    #     df = df[df[schema.COL_METRIC_NAME] == "App_sr"]
    #     if df.empty:
    #         return "No application success rate data found"
    #     avg_sr = df.groupby(schema.COL_ENTITY_ID)[schema.COL_VALUE].mean()
    #     problem_services = avg_sr[avg_sr < threshold_percent].sort_values()
    #     if problem_services.empty:
    #         return f"All services operating above {threshold_percent}% success rate"
    #     output = [f"Low Success Rate Report (Threshold: {threshold_percent}%):"]
    #     for service, sr in problem_services.items():
    #         min_sr = df[df[schema.COL_ENTITY_ID] == service][schema.COL_VALUE].min()
    #         output.append(f"\n🔴 {service}")
    #         output.append(f"  - Average Success Rate: {sr:.2f}%")
    #         output.append(f"  - Minimum Success Rate: {min_sr:.2f}%")
    #     return "\n".join(output)
    
    def _build_core_df(self, df: pd.DataFrame, metric_selector: Optional[Any]) -> pd.DataFrame:
        if df.empty:
            return pd.DataFrame()
        if isinstance(metric_selector, list) and metric_selector:
            df = df[df[schema.COL_METRIC_NAME].isin(metric_selector)]
        elif isinstance(metric_selector, str) and metric_selector:
            df = df[df[schema.COL_METRIC_NAME].str.contains(metric_selector, regex=True, case=False, na=False)]
        derived = self.adapter.build_derived_metrics(df)
        if derived is not None and not derived.empty:
            df = pd.concat([df, derived], ignore_index=True)
        keep = []
        for kpi in df[schema.COL_METRIC_NAME].unique():
            mclass = self.adapter.classify_metric(kpi)
            if mclass:
                keep.append(df[df[schema.COL_METRIC_NAME] == kpi])
        return pd.concat(keep, ignore_index=True) if keep else pd.DataFrame()

    def handle_data_filtering(self, df: pd.DataFrame, entities: Optional[List[str]], metric_selector: Optional[Any]) -> pd.DataFrame:
        if entities:
            df = df[df[schema.COL_ENTITY_ID].isin(entities)].copy()
        if isinstance(metric_selector, list) and metric_selector:
            df = df[df[schema.COL_METRIC_NAME].isin(metric_selector)]
        elif isinstance(metric_selector, str) and metric_selector:
            df = df[df[schema.COL_METRIC_NAME].str.contains(metric_selector, regex=True, case=False, na=False)]
        return df

    def process_derived_metrics(self, df: pd.DataFrame) -> pd.DataFrame:
        derived = self.adapter.build_derived_metrics(df)
        if derived is not None and not derived.empty:
            df = pd.concat([df, derived], ignore_index=True)
        keep = []
        for kpi in df[schema.COL_METRIC_NAME].unique():
            mclass = self.adapter.classify_metric(kpi)
            if mclass:
                keep.append(df[df[schema.COL_METRIC_NAME] == kpi])
        return pd.concat(keep, ignore_index=True) if keep else pd.DataFrame()

    def run_anomaly_detectors(
        self,
        df_core: pd.DataFrame,
        method: str,
        sensitivity: float,
        ruptures_algorithm: str,
        ruptures_model: str,
        pen: float,
        z_threshold: Optional[float],
        min_data_points_ruptures: int,
        min_data_points_zscore: int,
        min_consecutive: int,
        tz: str
    ) -> List[Dict[str, Any]]:
        ruptures_algorithm = ruptures_algorithm.lower()
        ruptures_model = ruptures_model.lower()
        if z_threshold is None:
            z_threshold = sensitivity
        valid_algorithms = ['pelt', 'binseg', 'dynp', 'window']
        valid_models = ['rbf', 'l1', 'l2', 'linear', 'normal', 'ar', 'rank', 'mahalanobis']
        if ruptures_algorithm not in valid_algorithms:
            ruptures_algorithm = 'pelt'
        if ruptures_model not in valid_models:
            ruptures_model = 'rbf'
        all_anomalies: List[Dict[str, Any]] = []
        grouped = df_core.groupby([schema.COL_ENTITY_ID, schema.COL_METRIC_NAME])
        for (component, metric_name), group in grouped:
            if len(group) < min(min_data_points_ruptures, min_data_points_zscore):
                continue
            anomalies: List[Dict[str, Any]] = []
            anomalies.extend(self._detect_with_absolute_threshold(component, metric_name, group, tz, min_consecutive, min_data_points_zscore))
            if method in ['ruptures', 'both']:
                anomalies.extend(self._detect_with_ruptures(component, metric_name, group, tz, ruptures_algorithm, ruptures_model, pen, min_data_points_ruptures))
            if method in ['zscore', 'both']:
                anomalies.extend(self._detect_with_zscore(component, metric_name, group, tz, z_threshold, min_consecutive, min_data_points_zscore))
            if method == 'both' and len(anomalies) > 1:
                anomalies = sorted(anomalies, key=lambda x: x.get('change_idx', 0))
                ruptures_results = [a for a in anomalies if a['method'] == 'ruptures']
                anomalies = [ruptures_results[0]] if ruptures_results else [anomalies[0]]
            all_anomalies.extend(anomalies)
        return all_anomalies

    def post_process_anomalies(self, anomalies: List[Dict[str, Any]], method: str, top: int) -> List[Dict[str, Any]]:
        seen: Dict[Tuple[str, str], Dict[str, Any]] = {}
        for anomaly in anomalies:
            key = (anomaly['component_name'], anomaly['faulty_kpi'])
            if key not in seen:
                seen[key] = anomaly
            else:
                existing_time = pd.to_datetime(seen[key]['fault_start_time'])
                current_time = pd.to_datetime(anomaly['fault_start_time'])
                if current_time < existing_time:
                    seen[key] = anomaly
        final_anomalies = list(seen.values())
        final_anomalies = sorted(final_anomalies, key=lambda x: x.get('deviation_pct', 0), reverse=True)
        if method != 'both' and top > 0:
            final_anomalies = final_anomalies[:top]
        def convert_to_native_types(obj):
            if isinstance(obj, (np.integer, np.int64, np.int32, np.int16, np.int8)):
                return int(obj)
            elif isinstance(obj, (np.floating, np.float64, np.float32, np.float16)):
                return float(obj)
            elif isinstance(obj, np.ndarray):
                return obj.tolist()
            elif pd.isna(obj):
                return None
            elif isinstance(obj, dict):
                return {key: convert_to_native_types(value) for key, value in obj.items()}
            elif isinstance(obj, (list, tuple)):
                return [convert_to_native_types(item) for item in obj]
            else:
                return obj
        return [convert_to_native_types(anomaly) for anomaly in final_anomalies]

    def _detect_with_ruptures(self, component: str, metric_name: str, data: pd.DataFrame, tz: str, ruptures_algorithm: str, ruptures_model: str, pen: float, min_data_points_ruptures: int) -> List[Dict[str, Any]]:
        if len(data) < min_data_points_ruptures:
            return []
        data = data.sort_values(schema.COL_TIMESTAMP).reset_index(drop=True)
        values = data[schema.COL_VALUE].values.astype(float)
        ts_series = data[schema.COL_TIMESTAMP].astype('int64')
        anomalies: List[Dict[str, Any]] = []
        try:
            signal = values.reshape(-1, 1)
            algo = None
            if ruptures_algorithm == 'pelt':
                algo = rpt.Pelt(model=ruptures_model).fit(signal)
                change_points = algo.predict(pen=pen)
            elif ruptures_algorithm == 'binseg':
                algo = rpt.Binseg(model=ruptures_model).fit(signal)
                max_n_bkps = max(2, min(10, len(values) // 10))
                try:
                    change_points = algo.predict(pen=pen)
                except (TypeError, ValueError):
                    change_points = algo.predict(n_bkps=max_n_bkps)
            elif ruptures_algorithm == 'dynp':
                algo = rpt.Dynp(model=ruptures_model).fit(signal)
                max_n_bkps = max(2, min(10, len(values) // 10))
                change_points = algo.predict(n_bkps=max_n_bkps)
            elif ruptures_algorithm == 'window':
                algo = rpt.Window(width=min(40, len(values) // 2), model=ruptures_model).fit(signal)
                change_points = algo.predict(pen=pen)
            else:
                algo = rpt.Pelt(model=ruptures_model).fit(signal)
                change_points = algo.predict(pen=pen)
            if len(change_points) > 1 and change_points[-1] == len(values):
                change_points = change_points[:-1]
            if len(change_points) == 0:
                return []
            segments = []
            prev_cp = 0
            for cp in change_points:
                if cp > prev_cp and cp <= len(values):
                    segment_values = values[prev_cp:cp]
                    if len(segment_values) > 0:
                        segments.append({
                            'start_idx': prev_cp,
                            'end_idx': cp - 1,
                            'mean': np.mean(segment_values),
                            'max': np.max(segment_values),
                            'length': len(segment_values)
                        })
                    prev_cp = cp
            if prev_cp < len(values):
                segment_values = values[prev_cp:]
                if len(segment_values) > 0:
                    segments.append({
                        'start_idx': prev_cp,
                        'end_idx': len(values) - 1,
                        'mean': np.mean(segment_values),
                        'max': np.max(segment_values),
                        'length': len(segment_values)
                    })
            if len(segments) >= 2:
                overall_mean = np.mean(values)
                overall_std = np.std(values)
                baseline_value = overall_mean if overall_std < max(1e-9, overall_mean * 0.1) else np.mean([seg['mean'] for seg in segments[:min(3, len(segments))]])
                params = self.adapter.get_baseline_params(self.adapter.classify_metric(metric_name)) or {"min_baseline_threshold": 0.1, "reference_value": 100.0}
                mbt = params["min_baseline_threshold"]
                ref = params["reference_value"]
                for i in range(1, len(segments)):
                    prev_seg = segments[i-1]
                    curr_seg = segments[i]
                    if prev_seg['mean'] >= mbt:
                        relative_change_pct = abs((curr_seg['mean'] - prev_seg['mean']) / prev_seg['mean'] * 100)
                    else:
                        absolute_change = abs(curr_seg['mean'] - prev_seg['mean'])
                        relative_change_pct = (absolute_change / ref) * 100 if ref > 0 else 0
                    if baseline_value >= mbt:
                        baseline_deviation_pct = abs((curr_seg['mean'] - baseline_value) / baseline_value * 100)
                    else:
                        absolute_change = abs(curr_seg['mean'] - baseline_value)
                        baseline_deviation_pct = (absolute_change / ref) * 100 if ref > 0 else 0
                    if overall_std > 0:
                        change_in_std = abs(curr_seg['mean'] - prev_seg['mean']) / overall_std
                    else:
                        change_in_std = 0
                    is_anomaly = False
                    if relative_change_pct > 100 or relative_change_pct > 50 or (relative_change_pct > 30 and baseline_deviation_pct > 50) or change_in_std > 2.0:
                        is_anomaly = True
                    if is_anomaly:
                        deviation_pct = max(relative_change_pct, baseline_deviation_pct)
                        change_idx = curr_seg['start_idx']
                        if change_idx < len(ts_series):
                            change_time_ms = int(ts_series.iloc[change_idx])
                        anomalies.append({
                            'component_name': component,
                            'faulty_kpi': metric_name,
                            'fault_start_time': to_iso_with_tz(change_time_ms, tz),
                            'severity_score': self.adapter.format_severity(deviation_pct, curr_seg['max']) or f"{deviation_pct:.1f}%",
                            'deviation_pct': float(deviation_pct),
                            'method': 'ruptures',
                            'change_idx': int(change_idx)
                        })
        except Exception:
            pass
        return anomalies

    def _detect_with_zscore(self, component: str, metric_name: str, data: pd.DataFrame, tz: str, z_threshold: float, min_consecutive: int, min_data_points_zscore: int) -> List[Dict[str, Any]]:
        if len(data) < min_data_points_zscore:
            return []
        data = data.sort_values(schema.COL_TIMESTAMP).reset_index(drop=True)
        values = data[schema.COL_VALUE].values.astype(float)
        ts_series = data[schema.COL_TIMESTAMP].astype('int64')
        anomalies: List[Dict[str, Any]] = []
        try:
            mean_val = np.mean(values)
            std_val = np.std(values)
            if std_val == 0:
                return []
            z_scores = np.abs((values - mean_val) / std_val)
            anomaly_indices_global = np.where(z_scores > z_threshold)[0]
            baseline_window_size = max(5, min(int(len(values) * 0.15), int(len(values) * 0.1)))
            baseline_values_raw = values[:baseline_window_size]
            if len(baseline_values_raw) >= 4:
                q1 = np.percentile(baseline_values_raw, 25)
                q3 = np.percentile(baseline_values_raw, 75)
                iqr = q3 - q1
                if iqr > 0:
                    lower_bound = q1 - 1.5 * iqr
                    upper_bound = q3 + 1.5 * iqr
                    baseline_values = baseline_values_raw[(baseline_values_raw >= lower_bound) & (baseline_values_raw <= upper_bound)]
                else:
                    baseline_values = baseline_values_raw
            else:
                baseline_values = baseline_values_raw
            if len(baseline_values) < 3:
                baseline_values = baseline_values_raw
            baseline_mean = np.mean(baseline_values)
            baseline_std = np.std(baseline_values)
            if baseline_std == 0 or baseline_std < baseline_mean * 0.01:
                baseline_median = np.median(baseline_values)
                mad = np.median(np.abs(baseline_values - baseline_median))
                baseline_std = mad / 0.6745 if mad > 0 else std_val
            if baseline_std == 0:
                baseline_std = std_val
            baseline_z_scores = np.abs((values - baseline_mean) / baseline_std) if baseline_std > 0 else np.zeros_like(values)
            anomaly_indices_baseline = np.where(baseline_z_scores > z_threshold)[0]
            anomaly_indices = np.unique(np.concatenate([anomaly_indices_global, anomaly_indices_baseline]))
            if len(anomaly_indices) == 0:
                return []
            continuous_segments = []
            current_segment = []
            for idx in sorted(anomaly_indices):
                if not current_segment:
                    current_segment.append(idx)
                elif idx == current_segment[-1] + 1:
                    current_segment.append(idx)
                else:
                    if len(current_segment) >= min_consecutive:
                        continuous_segments.append(current_segment.copy())
                    current_segment = [idx]
            if len(current_segment) >= min_consecutive:
                continuous_segments.append(current_segment)
            params = self.adapter.get_baseline_params(self.adapter.classify_metric(metric_name)) or {"min_baseline_threshold": 0.1, "reference_value": 100.0}
            mbt = params["min_baseline_threshold"]
            ref = params["reference_value"]
            for segment in continuous_segments:
                if len(segment) == 0:
                    continue
                segment_values = values[segment]
                segment_mean = np.mean(segment_values)
                if baseline_mean >= mbt:
                    deviation_pct = abs((segment_mean - baseline_mean) / baseline_mean * 100)
                elif mean_val >= mbt:
                    deviation_pct = abs((segment_mean - mean_val) / mean_val * 100)
                else:
                    absolute_change = abs(segment_mean - baseline_mean)
                    deviation_pct = (absolute_change / ref) * 100 if ref > 0 else 0
                segment_z_score = np.mean(baseline_z_scores[segment]) if len(segment) > 0 else 0
                is_anomaly = deviation_pct > 100 or deviation_pct > 50 or (deviation_pct > 30 and segment_z_score > z_threshold)
                if is_anomaly:
                    max_value = np.max(segment_values)
                    segment_start_idx = segment[0]
                    if segment_start_idx < len(ts_series):
                        segment_time_ms = int(ts_series.iloc[segment_start_idx])
                    else:
                        segment_time_ms = int(ts_series.iloc[0])
                    anomalies.append({
                        'component_name': component,
                        'faulty_kpi': metric_name,
                        'fault_start_time': to_iso_with_tz(segment_time_ms, tz),
                        'severity_score': self.adapter.format_severity(deviation_pct, max_value) or f"{deviation_pct:.1f}%",
                        'deviation_pct': float(deviation_pct),
                        'method': 'zscore',
                        'change_idx': int(segment[0])
                    })
        except Exception:
            pass
        return anomalies

    def _detect_with_absolute_threshold(self, component: str, metric_name: str, data: pd.DataFrame, tz: str, min_consecutive: int, min_data_points_zscore: int) -> List[Dict[str, Any]]:
        mclass = self.adapter.classify_metric(metric_name)
        abs_threshold = self.adapter.get_absolute_threshold(mclass)
        if abs_threshold is None:
            return []
        if len(data) < min_data_points_zscore:
            return []
        data = data.sort_values(schema.COL_TIMESTAMP).reset_index(drop=True)
        values = data[schema.COL_VALUE].values.astype(float)
        ts_series = data[schema.COL_TIMESTAMP].astype('int64')
        baseline_window_size = max(5, min(int(len(values) * 0.15), int(len(values) * 0.1)))
        baseline_values_raw = values[:baseline_window_size]
        if len(baseline_values_raw) >= 4:
            q1 = np.percentile(baseline_values_raw, 25)
            q3 = np.percentile(baseline_values_raw, 75)
            iqr = q3 - q1
            if iqr > 0:
                lower_bound = q1 - 1.5 * iqr
                upper_bound = q3 + 1.5 * iqr
                baseline_values = baseline_values_raw[(baseline_values_raw >= lower_bound) & (baseline_values_raw <= upper_bound)]
            else:
                baseline_values = baseline_values_raw
        else:
            baseline_values = baseline_values_raw
        if len(baseline_values) < 3:
            baseline_values = baseline_values_raw
        baseline_mean = np.mean(baseline_values)
        overall_mean = np.mean(values)
        overall_std = np.std(values)
        stability_threshold = min(overall_mean * 0.05, abs_threshold * 0.05)
        is_stable = overall_std < stability_threshold
        if baseline_mean > abs_threshold and is_stable:
            if np.all(values > abs_threshold):
                return []
        is_cpu_metric = bool(mclass and mclass.get("kind") in ("cpu.util", "jvm.cpu.load"))
        soft_threshold = abs_threshold * 0.875 if is_cpu_metric else abs_threshold
        high_value_indices = np.where(values > abs_threshold)[0]
        near_threshold_indices = np.where((values > soft_threshold) & (values <= abs_threshold))[0] if is_cpu_metric else np.array([])
        all_high_indices = np.unique(np.concatenate([high_value_indices, near_threshold_indices])) if len(near_threshold_indices) > 0 else high_value_indices
        if len(all_high_indices) == 0:
            return []
        effective_min_consecutive = 1 if is_cpu_metric else min_consecutive
        continuous_segments = []
        current_segment = []
        for idx in sorted(all_high_indices):
            if not current_segment:
                current_segment.append(idx)
            elif idx == current_segment[-1] + 1:
                current_segment.append(idx)
            else:
                if len(current_segment) >= effective_min_consecutive:
                    continuous_segments.append(current_segment.copy())
                current_segment = [idx]
        if len(current_segment) >= effective_min_consecutive:
            continuous_segments.append(current_segment)
        anomalies: List[Dict[str, Any]] = []
        params = self.adapter.get_baseline_params(mclass) or {"min_baseline_threshold": 0.1, "reference_value": 100.0}
        mbt = params["min_baseline_threshold"]
        ref = params["reference_value"]
        for segment in continuous_segments:
            if len(segment) == 0:
                continue
            segment_values = values[segment]
            segment_mean = np.mean(segment_values)
            max_value = np.max(segment_values)
            segment_start_idx = segment[0]
            if segment_start_idx > 0:
                prev_value = values[segment_start_idx - 1]
                is_change_from_low = prev_value <= abs_threshold
            else:
                is_change_from_low = baseline_mean <= abs_threshold
            if baseline_mean > abs_threshold:
                relative_increase = (segment_mean - baseline_mean) / baseline_mean * 100
                is_significant_increase = relative_increase > 10.0
            else:
                is_significant_increase = False
            if not (is_change_from_low or is_significant_increase):
                continue
            normal_baseline = None
            if segment_start_idx > 0:
                prev_normal_values = []
                for i in range(segment_start_idx - 1, -1, -1):
                    if values[i] <= abs_threshold:
                        prev_normal_values.append(values[i])
                    if len(prev_normal_values) >= 3:
                        break
                if len(prev_normal_values) > 0:
                    normal_baseline = np.mean(prev_normal_values)
            if normal_baseline is None:
                baseline_normal_values = baseline_values[baseline_values <= abs_threshold]
                if len(baseline_normal_values) > 0:
                    normal_baseline = np.mean(baseline_normal_values)
            if normal_baseline is None:
                all_normal_indices = []
                for i in range(len(values)):
                    if values[i] <= abs_threshold:
                        is_in_segment = False
                        for seg in continuous_segments:
                            if i in seg:
                                is_in_segment = True
                                break
                        if not is_in_segment:
                            all_normal_indices.append(i)
                if len(all_normal_indices) > 0:
                    normal_baseline = np.mean(values[all_normal_indices])
            if normal_baseline is None or normal_baseline <= 0:
                normal_baseline = abs_threshold
            use_relative = (normal_baseline >= mbt and normal_baseline >= ref * 0.1)
            if use_relative:
                deviation_pct = abs((segment_mean - normal_baseline) / normal_baseline * 100)
            else:
                absolute_change = abs(segment_mean - normal_baseline)
                deviation_pct = (absolute_change / ref) * 100 if ref > 0 else 0
            if segment_mean > abs_threshold:
                if segment_start_idx < len(ts_series):
                    segment_time_ms = int(ts_series.iloc[segment_start_idx])
                else:
                    segment_time_ms = int(ts_series.iloc[0])
                anomalies.append({
                    'component_name': component,
                    'faulty_kpi': metric_name,
                    'fault_start_time': to_iso_with_tz(segment_time_ms, tz),
                    'severity_score': self.adapter.format_severity(deviation_pct, max_value) or f"{deviation_pct:.1f}%",
                    'deviation_pct': float(deviation_pct),
                    'method': 'absolute_threshold',
                    'change_idx': int(segment_start_idx)
                })
        return anomalies

    def detect_metric_anomalies(
        self,
        start_time: str,
        end_time: str,
        method: str = "both",
        entities: Optional[List[str]] = None,
        metric_selector: Optional[Any] = None,
        sensitivity: float = 3.0,
        top: int = 10,
        ruptures_algorithm: str = "pelt",
        ruptures_model: str = "rbf",
        pen: float = 5.0,
        z_threshold: Optional[float] = None,
        min_data_points_ruptures: int = 10,
        min_data_points_zscore: int = 5,
        min_consecutive: int = 3
    ) -> str:
        """
        Detect anomalies in time-series metrics for selected entities and metrics.
        
        This method runs a modular pipeline to surface significant changes or sustained
        high values across metrics. It is dataset-agnostic: domain-specific semantics,
        such as absolute thresholds and derived metrics, are provided by the configured
        MetricSemanticAdapter.
        
        Pipeline:
        1) Resolve timezone from the dataloader and load validated metric data.
        2) Optionally filter by entity IDs and by metric_selector (list of names or regex).
        3) Build derived metrics via the adapter (e.g., JVM heap usage) and keep only
           metrics that the adapter classifies as relevant.
        4) Run anomaly detectors:
           - absolute-threshold: flags sustained high values using adapter thresholds
             and baseline/reference parameters with CPU-friendly soft thresholds.
           - ruptures: applies change point detection (PELT/Binseg/Dynp/Window) with
             configurable model (rbf, l1, l2, linear, normal, ar, rank), then evaluates
             segment shifts using adapter baseline semantics.
           - zscore: computes both global and baseline Z-scores; requires consecutive
             points; deviation is relative to baseline or a reference value when baseline
             is too small.
        5) Deduplicate per (entity_id, metric_name) by keeping the earliest anomaly.
        6) Sort by deviation percentage (descending) and, if method != 'both', limit to top.
        
        Args:
            start_time: Target window start time (ISO string; naive or tz-aware).
            end_time: Target window end time (ISO string; naive or tz-aware).
            method: Detection method: 'ruptures', 'zscore', or 'both' (default).
            entities: Optional list of entity IDs to include.
            metric_selector: Optional selector to narrow metrics:
                - list: explicit metric names
                - str: case-insensitive regex pattern
                - None: all adapter-classified metrics
            sensitivity: Default Z-score threshold used when z_threshold is None.
            top: Max number of results when method != 'both' (default: 10).
            ruptures_algorithm: 'pelt' | 'binseg' | 'dynp' | 'window' (default: 'pelt').
            ruptures_model: 'rbf' | 'l1' | 'l2' | 'linear' | 'normal' | 'ar' | 'rank' (default: 'rbf').
            pen: Penalty parameter for ruptures algorithms.
            z_threshold: Z-score threshold; falls back to sensitivity if None.
            min_data_points_ruptures: Minimum points required to run ruptures (default: 10).
            min_data_points_zscore: Minimum points required to run Z-score (default: 5).
            min_consecutive: Minimum consecutive anomaly points for Z-score (default: 3).
        
        Returns:
            A JSON string encoding a list of anomalies with fields:
            - component_name: Entity ID
            - faulty_kpi: Metric name
            - fault_start_time: ISO timestamp formatted using dataloader timezone
            - severity_score: Adapter-formatted severity text
            - deviation_pct: Percentage deviation used for ranking
            - method: 'absolute_threshold' | 'ruptures' | 'zscore'
            - change_idx: Index of the first anomalous point within the series
        
        Notes:
            - All domain-specific decisions (thresholds, baseline semantics, derived
              metrics, severity formatting) are delegated to MetricSemanticAdapter.
            - Timezone normalization relies on the dataloader; naive times are localized,
              tz-aware times are converted.
            - If no data after filtering or no adapter-classified metrics are present,
              the method returns an empty JSON array.
        """
        self._check_loader()
        tz = self.data_loader.get_timezone()
        df = self._get_metric_df(start_time, end_time)
        if df.empty:
            return json.dumps([], ensure_ascii=False, indent=2)
        if not entities:
            try:
                candidates = self.adapter.get_candidate_entities(df, {"start_time": start_time, "end_time": end_time}, None)
                if candidates:
                    entities = candidates
            except Exception:
                pass
        df = self.handle_data_filtering(df, entities, metric_selector)
        if df.empty:
            return json.dumps([], ensure_ascii=False, indent=2)
        df_core = self.process_derived_metrics(df)
        if df_core.empty:
            return json.dumps([], ensure_ascii=False, indent=2)
        anomalies = self.run_anomaly_detectors(
            df_core,
            method,
            sensitivity,
            ruptures_algorithm,
            ruptures_model,
            pen,
            z_threshold,
            min_data_points_ruptures,
            min_data_points_zscore,
            min_consecutive,
            tz
        )
        final_anomalies = self.post_process_anomalies(anomalies, method, top)
        return json.dumps(final_anomalies, ensure_ascii=False, indent=2)

    
    def get_available_entities(
        self,
        start_time: str,
        end_time: str
    ) -> str:
        """Get list of available entity IDs in the specified time range.
        
        Provides a concise overview of which entities have any metric data
        within the given time window, along with the count of distinct metrics
        observed for each entity. This is useful for discovery and scoping
        before running deeper analyses.
        
        Args:
            start_time: Start time in ISO format (e.g., "2021-03-04T01:00:00" or with timezone)
            end_time: End time in ISO format (e.g., "2021-03-04T01:30:00" or with timezone)
            
        Returns:
            A formatted string listing:
            - total number of entities found
            - each entity_id and the number of unique metric names associated
              with it during the specified period
            If no metrics are found in the time range, returns a short message.
        """
        self._check_loader()
        df = self._get_metric_df(start_time, end_time)
        if df.empty:
            return "No metrics found in the specified time range"
        entities = sorted(df[schema.COL_ENTITY_ID].unique())
        output = [f"Available Entities ({len(entities)} total):"]
        for eid in entities:
            metric_count = df[df[schema.COL_ENTITY_ID] == eid][schema.COL_METRIC_NAME].nunique()
            output.append(f"  - {eid} ({metric_count} metrics)")
        return "\n".join(output)
    
    def get_available_metrics(
        self,
        start_time: str,
        end_time: str,
        entity_id: Optional[str] = None,
        metric_pattern: Optional[str] = None,
        top: int = 10
    ) -> str:
        """Get list of available metric names in the specified time range.
        
        Useful for discovering what metrics are available for analysis.
        
        Args:
            start_time: Start time in ISO format
            end_time: End time in ISO format
            component_id: Optional filter by specific component (if None, returns all metrics)
            metric_pattern: Optional pattern to filter metric names (case-insensitive)
            top: Maximum metrics to show per group (default: 10)
            
        Returns:
            List of unique metric names (kpi_name) available in the time range
        """
        self._check_loader()
        df = self._get_metric_df(start_time, end_time)
        
        if df.empty:
            return "No metrics found in the specified time range"
        
        if entity_id:
            df = df[df[schema.COL_ENTITY_ID] == entity_id]
            if df.empty:
                return f"No metrics found for entity '{entity_id}'"
        
        # Apply metric pattern filter if provided
        if metric_pattern:
            df = df[df[schema.COL_METRIC_NAME].str.contains(metric_pattern, case=False, na=False)]
            if df.empty:
                return f"No metrics matching pattern '{metric_pattern}' found"
        
        metrics = sorted(df[schema.COL_METRIC_NAME].unique())
        
        # Build header
        if entity_id and metric_pattern:
            output = [f"Available Metrics for {entity_id} matching '{metric_pattern}' ({len(metrics)} total):"]
        elif entity_id:
            output = [f"Available Metrics for {entity_id} ({len(metrics)} total):"]
        elif metric_pattern:
            output = [f"Available Metrics matching '{metric_pattern}' ({len(metrics)} total):"]
        else:
            output = [f"Available Metrics ({len(metrics)} total):"]
        
        # Group metrics by prefix for better readability
        metric_groups = {}
        for metric in metrics:
            # Extract prefix (e.g., "OSLinux-CPU" from "OSLinux-CPU_CPU_CPUUtil")
            parts = metric.split('_')
            if len(parts) > 1:
                prefix = parts[0]
            else:
                prefix = "Other"
            
            if prefix not in metric_groups:
                metric_groups[prefix] = []
            metric_groups[prefix].append(metric)
        
        # Display grouped metrics
        for prefix in sorted(metric_groups.keys()):
            output.append(f"\n{prefix} ({len(metric_groups[prefix])} metrics):")
            for metric in sorted(metric_groups[prefix])[:top]:  # Use top parameter
                output.append(f"  - {metric}")
            if len(metric_groups[prefix]) > top:
                output.append(f"  ... and {len(metric_groups[prefix]) - top} more")
        
        return "\n".join(output)
    
    def compare_entity_metrics(
        self,
        start_time: str,
        end_time: str,
        entity_id: str,
        metric_names: Optional[List[str]] = None,
        metric_pattern: Optional[str] = None,
        baseline_start: Optional[str] = None,
        baseline_end: Optional[str] = None
    ) -> str:
        """Compare metrics of a single entity between target and baseline periods.
        
        Provides a side-by-side comparison of selected metrics for the target
        time window versus a baseline window. Calculates robust statistics
        (mean and p99) per metric and reports percentage changes to help
        identify deviations.
        
        Args:
            start_time: Target period start time (ISO format, timezone optional)
            end_time: Target period end time (ISO format, timezone optional)
            entity_id: The entity identifier to analyze
            metric_names: Optional explicit list of metric names to include
            metric_pattern: Optional case-insensitive pattern to filter metrics
                           (ignored if metric_names is provided)
            baseline_start: Optional baseline period start time (ISO). If not
                            provided, a baseline period is inferred from the
                            target period duration.
            baseline_end: Optional baseline period end time (ISO). If not
                          provided, it is inferred together with baseline_start.
        
        Returns:
            A formatted comparison report including:
            - Target and baseline period ranges
            - Each matched metric's mean change and p99 comparison
            - Percentage change for mean values
            If baseline data is missing, the report falls back to target stats.
            If the entity or metrics are not found, returns a brief message.
        """
        self._check_loader()
        target_df = self._get_metric_df(start_time, end_time)
        if target_df.empty:
            return f"No metrics found between {start_time} and {end_time}"
        target_df = target_df[target_df[schema.COL_ENTITY_ID] == entity_id]
        if metric_names:
            target_df = target_df[target_df[schema.COL_METRIC_NAME].isin(metric_names)]
        elif metric_pattern:
            target_df = target_df[target_df[schema.COL_METRIC_NAME].str.contains(metric_pattern, case=False, na=False)]
        if target_df.empty:
            return f"No metrics found for entity '{entity_id}' in target range"
        if not baseline_start or not baseline_end:
            baseline_start, baseline_end = self._infer_baseline_period(start_time, end_time)
        baseline_df = self._get_metric_df(baseline_start, baseline_end)
        baseline_df = baseline_df[baseline_df[schema.COL_ENTITY_ID] == entity_id]
        if metric_names:
            baseline_df = baseline_df[baseline_df[schema.COL_METRIC_NAME].isin(metric_names)]
        elif metric_pattern:
            baseline_df = baseline_df[baseline_df[schema.COL_METRIC_NAME].str.contains(metric_pattern, case=False, na=False)]
        metrics = sorted(target_df[schema.COL_METRIC_NAME].unique())
        output = [f"Entity Metric Comparison for {entity_id}:"]
        output.append(f"Target Period:   {start_time} to {end_time}")
        output.append(f"Baseline Period: {baseline_start} to {baseline_end}")
        if baseline_df.empty:
            output.append("⚠️ No baseline data found. Showing target stats only.")
        for metric in metrics:
            t_vals = target_df[target_df[schema.COL_METRIC_NAME] == metric][schema.COL_VALUE]
            b_vals = baseline_df[baseline_df[schema.COL_METRIC_NAME] == metric][schema.COL_VALUE] if not baseline_df.empty else pd.Series(dtype=float)
            t_stats = self._calculate_robust_stats(pd.DataFrame({schema.COL_VALUE: t_vals}), columns=[schema.COL_VALUE])
            b_stats = self._calculate_robust_stats(pd.DataFrame({schema.COL_VALUE: b_vals}), columns=[schema.COL_VALUE]) if not b_vals.empty else {}
            if schema.COL_VALUE in t_stats:
                t_mean = t_stats[schema.COL_VALUE].get("mean")
                t_p99 = t_stats[schema.COL_VALUE].get("99%")
                if schema.COL_VALUE in b_stats:
                    b_mean = b_stats[schema.COL_VALUE].get("mean")
                    b_p99 = b_stats[schema.COL_VALUE].get("99%")
                    diff = (t_mean - b_mean) if (t_mean is not None and b_mean is not None) else 0.0
                    pct_change = (diff / b_mean * 100) if (b_mean not in (None, 0)) else 0.0
                    output.append(f"\nMetric: {metric}")
                    output.append(f"  - Mean: {b_mean:.2f} -> {t_mean:.2f} ({pct_change:+.1f}%)")
                    if t_p99 is not None and b_p99 is not None:
                        output.append(f"  - P99:  {b_p99:.2f} -> {t_p99:.2f}")
                else:
                    output.append(f"\nMetric: {metric}")
                    output.append(f"  - Mean: {t_mean:.2f} (No baseline)")
                    if t_p99 is not None:
                        output.append(f"  - P99:  {t_p99:.2f}")
        return "\n".join(output)
    
    def find_metric_outliers(
        self,
        start_time: str,
        end_time: str,
        metric_selector: Optional[Any] = None,
        z_threshold: float = 3.0,
        min_points: int = 5,
        limit: int = 10
    ) -> str:
        """Find metric outliers using Z-score across entities for selected metrics.
        
        Scans the specified time range and identifies significant spikes or dips
        in metric values by computing Z-scores per (entity_id, metric_name)
        series. This generic detector is dataset-agnostic and works purely on
        statistical deviation without domain-specific thresholds.
        
        Args:
            start_time: Start time in ISO format (timezone optional)
            end_time: End time in ISO format (timezone optional)
            metric_selector: Optional selector to narrow metrics:
                - list: explicit metric names to include
                - str: case-insensitive regex pattern to match metric names
                - None: analyze all metrics present
            z_threshold: Absolute Z-score threshold to flag outliers (default: 3.0)
            min_points: Minimum number of data points required per series (default: 5)
            limit: Maximum number of findings to include in the output (default: 10)
        
        Returns:
            A formatted list of outliers sorted by descending Z-score, each entry
            including time (formatted by dataloader timezone), entity_id, metric_name,
            the flagged value, series mean and std, and the Z-score.
            If no metrics or no outliers are found, returns a short message.
        """
        self._check_loader()
        tz = self.data_loader.get_timezone()
        df = self._get_metric_df(start_time, end_time)
        if df.empty:
            return "No metrics found in the specified time range"
        if isinstance(metric_selector, list) and metric_selector:
            df = df[df[schema.COL_METRIC_NAME].isin(metric_selector)]
        elif isinstance(metric_selector, str) and metric_selector:
            df = df[df[schema.COL_METRIC_NAME].str.contains(metric_selector, regex=True, case=False, na=False)]
        grouped = df.groupby([schema.COL_ENTITY_ID, schema.COL_METRIC_NAME])
        findings: List[Dict[str, Any]] = []
        for (eid, mname), g in grouped:
            g = g.sort_values(schema.COL_TIMESTAMP)
            vals = g[schema.COL_VALUE].astype(float).values
            if len(vals) < min_points:
                continue
            mean_val = np.mean(vals)
            std_val = np.std(vals)
            if std_val == 0:
                continue
            z_scores = np.abs((vals - mean_val) / std_val)
            idxs = np.where(z_scores > z_threshold)[0]
            if len(idxs) == 0:
                continue
            first_idx = int(idxs[0])
            ts_ms = int(g.iloc[first_idx][schema.COL_TIMESTAMP])
            findings.append({
                "entity_id": eid,
                "metric_name": mname,
                "time": to_iso_with_tz(ts_ms, tz),
                "zscore": float(z_scores[first_idx]),
                "mean": float(mean_val),
                "std": float(std_val),
                "value": float(vals[first_idx]),
            })
        findings.sort(key=lambda x: x["zscore"], reverse=True)
        if not findings:
            return "No significant outliers found."
        findings = findings[:limit]
        lines = ["Metric Outliers:"]
        for f in findings:
            lines.append(
                f"- {f['entity_id']}::{f['metric_name']} at {f['time']} "
                f"value={f['value']:.3f} z={f['zscore']:.2f} mean={f['mean']:.2f} std={f['std']:.2f}"
            )
        return "\n".join(lines)
    
    def cleanup(self) -> None:
        """Clean up metric data source connections."""
        super().cleanup()


def run_suspicious_identification(
    start_time: str,
    end_time: str,
    config: Optional[Dict[str, Any]] = None,
    method: str = "both",
    entities: Optional[List[str]] = None,
    metric_selector: Optional[Any] = None,
    sensitivity: float = 3.0,
    top: int = 10,
) -> List[Dict[str, Any]]:
    """
    直接入口：运行可疑组件识别流程，返回 Python 对象形式的结果列表。

    这是对 MetricAnalysisTool.detect_metric_anomalies 的薄包装：
    - 负责构造并初始化 MetricAnalysisTool
    - 调用 detect_metric_anomalies 获取 JSON 字符串
    - 将 JSON 解析成 List[Dict] 后返回，便于在 Python 中直接使用
    """
    tool = MetricAnalysisTool(config=config)
    tool.initialize()
    raw = tool.detect_metric_anomalies(
        start_time=start_time,
        end_time=end_time,
        method=method,
        entities=entities,
        metric_selector=metric_selector,
        sensitivity=sensitivity,
        top=top,
    )
    try:
        return json.loads(raw)
    except Exception:
        return []


def _build_default_config() -> Dict[str, Any]:
    from pathlib import Path
    root = Path(__file__).resolve().parents[4]
    return {
        "dataloader": "openrca",
        "dataset_path": str(root / "datasets" / "OpenRCA" / "Bank"),
        "default_timezone": "Asia/Shanghai",
        "metric_adapter": "openrca",
    }


def _cli() -> None:
    import argparse
    parser = argparse.ArgumentParser(prog="metric_tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    common = {
        "start_time": ("--start", "Start time in ISO format"),
        "end_time": ("--end", "End time in ISO format"),
    }

    p_entities = subparsers.add_parser("entities")
    p_entities.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_entities.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])

    p_metrics = subparsers.add_parser("metrics")
    p_metrics.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_metrics.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])
    p_metrics.add_argument("--entity", dest="entity_id")
    p_metrics.add_argument("--pattern", dest="metric_pattern")
    p_metrics.add_argument("--top", type=int, default=10)

    p_detect = subparsers.add_parser("detect")
    p_detect.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_detect.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])
    p_detect.add_argument("--method", default="both", choices=["ruptures", "zscore", "both"])
    p_detect.add_argument("--top", type=int, default=10)

    p_suspicious = subparsers.add_parser("suspicious")
    p_suspicious.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_suspicious.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])
    p_suspicious.add_argument("--method", default="both", choices=["ruptures", "zscore", "both"])
    p_suspicious.add_argument("--top", type=int, default=10)

    p_stats = subparsers.add_parser("get_metric_statistics")
    p_stats.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_stats.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])
    p_stats.add_argument("--component", required=True, dest="component_name")
    p_stats.add_argument("--metric", required=True, dest="metric_name")

    p_compare = subparsers.add_parser("compare_entity_metrics")
    p_compare.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_compare.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])
    p_compare.add_argument("--entity", required=True, dest="entity_id")
    p_compare.add_argument("--metric-names", dest="metric_names")
    p_compare.add_argument("--pattern", dest="metric_pattern")
    p_compare.add_argument("--baseline-start", dest="baseline_start")
    p_compare.add_argument("--baseline-end", dest="baseline_end")

    p_outliers = subparsers.add_parser("find_metric_outliers")
    p_outliers.add_argument(common["start_time"][0], required=True, dest="start_time", help=common["start_time"][1])
    p_outliers.add_argument(common["end_time"][0], required=True, dest="end_time", help=common["end_time"][1])
    p_outliers.add_argument("--metric-selector", dest="metric_selector")
    p_outliers.add_argument("--z-threshold", type=float, default=3.0, dest="z_threshold")
    p_outliers.add_argument("--min-points", type=int, default=5, dest="min_points")
    p_outliers.add_argument("--limit", type=int, default=10, dest="limit")

    args = parser.parse_args()
    config = _build_default_config()
    tool = MetricAnalysisTool(config=config)
    tool.initialize()

    if args.command == "entities":
        out = tool.get_available_entities(args.start_time, args.end_time)
        print(out)
    elif args.command == "metrics":
        out = tool.get_available_metrics(
            args.start_time,
            args.end_time,
            entity_id=args.entity_id,
            metric_pattern=args.metric_pattern,
            top=args.top,
        )
        print(out)
    elif args.command == "detect":
        out = tool.detect_metric_anomalies(
            start_time=args.start_time,
            end_time=args.end_time,
            method=args.method,
            top=args.top,
        )
        print(out)
    elif args.command == "suspicious":
        res = run_suspicious_identification(
            start_time=args.start_time,
            end_time=args.end_time,
            config=config,
            method=args.method,
            top=args.top,
        )
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif args.command == "get_metric_statistics":
        out = tool.get_metric_statistics(
            start_time=args.start_time,
            end_time=args.end_time,
            component_name=args.component_name,
            metric_name=args.metric_name,
        )
        print(out)
    elif args.command == "compare_entity_metrics":
        metric_names = None
        if args.metric_names:
            metric_names = [name for name in args.metric_names.split(",") if name]
        out = tool.compare_entity_metrics(
            start_time=args.start_time,
            end_time=args.end_time,
            entity_id=args.entity_id,
            metric_names=metric_names,
            metric_pattern=args.metric_pattern,
            baseline_start=args.baseline_start,
            baseline_end=args.baseline_end,
        )
        print(out)
    elif args.command == "find_metric_outliers":
        metric_selector = None
        if args.metric_selector:
            if "," in args.metric_selector:
                metric_selector = [s for s in args.metric_selector.split(",") if s]
            else:
                metric_selector = args.metric_selector
        out = tool.find_metric_outliers(
            start_time=args.start_time,
            end_time=args.end_time,
            metric_selector=metric_selector,
            z_threshold=args.z_threshold,
            min_points=args.min_points,
            limit=args.limit,
        )
        print(out)


if __name__ == "__main__":
    _cli()
