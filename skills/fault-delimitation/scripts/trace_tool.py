"""
Trace Analysis Tool

Provides high-level semantic operations for analyzing distributed tracing data
in the context of root cause analysis.
"""

from typing import Any, Dict, List, Optional, Tuple
import pandas as pd
import numpy as np
import networkx as nx
from sklearn.ensemble import IsolationForest
import pickle
import os
# Note: pydantic BaseModel is not used directly here; removing to keep imports clean.

from base import BaseRCATool
from data_loader import BaseDataLoader, create_data_loader
from time_utils import to_iso_with_tz
from schema import (
    COL_TIMESTAMP,
    COL_ENTITY_ID,
    COL_TRACE_ID,
    COL_SPAN_ID,
    COL_PARENT_SPAN_ID,
    COL_DURATION_MS,
    COL_STATUS_CODE,
)


class TraceAnalysisTool(BaseRCATool):
    """
    Tool for analyzing distributed tracing data with high-level semantic operations.
    
    This tool analyzes trace data to identify slow spans, problematic call chains,
    and service dependency issues without overwhelming the agent with raw trace data.
    """
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """
        Initialize the trace analysis tool.
        
        Args:
            config: Configuration dictionary that may include:
                   - trace_source_path: Path to trace data or database
                   - trace_format: Format of traces (jaeger, zipkin, etc.)
                   - sampling_rate: Sampling rate for trace analysis
        """
        super().__init__(config)
        self.trace_source = None
        self.data_loader: Optional[BaseDataLoader] = None
        self.trace_detectors: Dict[str, IsolationForest] = {}
        self.normal_stats: Dict[str, Dict[str, float]] = {}
        
    def initialize(self) -> None:
        """Initialize trace data source connections."""
        super().initialize()
        self.data_loader = create_data_loader(self.config)
    
    def _get_trace_df(self, start_time: str, end_time: str) -> pd.DataFrame:
        return self.data_loader.get_traces(start_time, end_time) if self.data_loader else pd.DataFrame(columns=[COL_TIMESTAMP,COL_ENTITY_ID,COL_TRACE_ID,COL_SPAN_ID,COL_PARENT_SPAN_ID,COL_DURATION_MS,COL_STATUS_CODE])
    
    def get_tools(self) -> List[Any]:
        """Get list of LangChain tools for trace analysis."""
        return [
            self.wrap(self.find_slow_spans),
            self.wrap(self.analyze_trace_call_tree),
            self.wrap(self.get_dependency_graph),
            self.wrap(self.detect_anomalies_zscore),
            self.wrap(self.identify_bottlenecks),
            # self.wrap(self.train_iforest_model),
            self.wrap(self.detect_anomalies_iforest),
        ]
    
    def find_slow_spans(
        self,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None,
        entity_id: Optional[str] = None,
        min_duration_ms: int = 1000,
        limit: int = 10
    ) -> str:
        """Find the slowest spans in the specified time range.
        
        Identifies performance bottlenecks by finding spans with the longest execution times.
        
        Args:
            start_time: Start of time range in ISO format
            end_time: End of time range in ISO format
            entity_id: Optional filter by entity identifier
            min_duration_ms: Minimum duration in milliseconds to consider (default: 1000)
            limit: Maximum number of slow spans to return (default: 10)
            
        Returns:
            A formatted list of slow spans with duration, entity, operation, and percentile stats
        """
        if not start_time or not end_time:
            return "Error: start_time and end_time are required"
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found for the specified time range."
        slow_spans = df[df[COL_DURATION_MS] >= min_duration_ms].copy()
        if entity_id:
            slow_spans = slow_spans[slow_spans[COL_ENTITY_ID] == entity_id]
        if slow_spans.empty:
            msg = f"No spans found with duration >= {min_duration_ms}ms"
            if entity_id:
                msg += f" for entity {entity_id}"
            return msg
        slow_spans = slow_spans.sort_values(COL_DURATION_MS, ascending=False).head(limit)
        result = [f"Top {len(slow_spans)} slow spans (>= {min_duration_ms}ms):"]
        for _, row in slow_spans.iterrows():
            tz = self.data_loader.get_timezone()
            result.append(
                f"- Entity: {row[COL_ENTITY_ID]}, Duration: {row[COL_DURATION_MS]}ms, "
                f"TraceID: {row[COL_TRACE_ID]}, SpanID: {row[COL_SPAN_ID]}, "
                f"Time: {to_iso_with_tz(row[COL_TIMESTAMP], tz)}"
            )
        return "\n".join(result)
    
    def analyze_trace_call_tree(
        self,
        trace_id: Optional[str] = None,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None
    ) -> str:
        """Analyze the call chain for specific traces.
        
        Provides a hierarchical view of how requests flow through services,
        helping identify where time is spent in distributed transactions.
        
        Args:
            trace_id: Specific trace ID to analyze (if None, analyzes representative traces)
            start_time: Start of time range in ISO format (used if trace_id is None)
            end_time: End of time range in ISO format (used if trace_id is None)
            
        Returns:
            A formatted representation of the call chain with durations and critical path
        """
        if not trace_id:
            return "Error: trace_id is required"
        if not start_time or not end_time:
            return "Error: start_time and end_time are required to locate the trace"
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found for the specified time range."
        trace_spans = df[df[COL_TRACE_ID] == trace_id].copy()
        if trace_spans.empty:
            return f"Trace ID {trace_id} not found in the specified time range."
        G = nx.DiGraph()
        span_map: Dict[str, Any] = {}
        for _, row in trace_spans.iterrows():
            sid = row[COL_SPAN_ID]
            span_map[sid] = row
            G.add_node(sid, service=row[COL_ENTITY_ID], duration=row[COL_DURATION_MS], timestamp=row[COL_TIMESTAMP])
        for _, row in trace_spans.iterrows():
            sid = row[COL_SPAN_ID]
            pid = row[COL_PARENT_SPAN_ID]
            if pid in span_map and pid != sid:
                G.add_edge(pid, sid)
        roots = [n for n, d in G.in_degree() if d == 0]
        result = []
        if not roots:
            try:
                cycles = list(nx.simple_cycles(G))
                if cycles:
                    all_nodes = set()
                    for c in cycles:
                        all_nodes.update(c)
                    root = min(all_nodes, key=lambda n: span_map[n][COL_TIMESTAMP])
                    roots = [root]
            except Exception:
                pass
        if not roots:
            root = min(span_map.keys(), key=lambda n: span_map[n][COL_TIMESTAMP])
            roots = [root]
            result.append("Warning: Cycle detected or root ambiguous. Using earliest span as root.")
        else:
            result.append(f"Call Chain for Trace {trace_id}:")
        for root in roots:
            root_data = span_map[root]
            result.append(f"[{root_data[COL_ENTITY_ID]}] {root_data[COL_DURATION_MS]}ms (Root)")
            self._print_tree(G, root, span_map, result, level=1)
        return "\n".join(result)

    def get_dependency_graph(
        self,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None,
        entity_id: Optional[str] = None
    ) -> str:
        """Get entity dependency graph from trace data.
        
        Maps out how entities call each other, which is essential for understanding
        system architecture and potential failure propagation paths.
        
        Args:
            start_time: Start of time range in ISO format
            end_time: End of time range in ISO format
            entity_id: Optional focus on specific entity's dependencies
            
        Returns:
            A formatted dependency graph showing entity relationships and call frequencies
        """
        if not start_time or not end_time:
            return "Error: start_time and end_time are required"
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found."
        spans = df[[COL_SPAN_ID, COL_ENTITY_ID, COL_PARENT_SPAN_ID]].copy()
        merged = pd.merge(
            spans,
            spans,
            left_on=COL_PARENT_SPAN_ID,
            right_on=COL_SPAN_ID,
            suffixes=("_child", "_parent"),
            how="inner",
        )
        deps = merged.groupby([f"{COL_ENTITY_ID}_parent", f"{COL_ENTITY_ID}_child"]).size().reset_index(name="count")
        if entity_id:
            deps = deps[(deps[f"{COL_ENTITY_ID}_parent"] == entity_id) | (deps[f"{COL_ENTITY_ID}_child"] == entity_id)]
        if deps.empty:
            return "No dependencies found."
        result = ["Entity Dependencies:"]
        for _, row in deps.iterrows():
            result.append(f"{row[f'{COL_ENTITY_ID}_parent']} -> {row[f'{COL_ENTITY_ID}_child']} (Calls: {row['count']})")
        return "\n".join(result)

    def detect_anomalies_zscore(
        self,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None,
        entity_id: Optional[str] = None,
        sensitivity: float = 0.8
    ) -> str:
        """Detect anomalous latency patterns in traces using Z-Score algorithm.
        
        Identifies unusual response times that deviate from normal behavior,
        which can indicate emerging performance issues.
        
        Args:
            start_time: Start of time range in ISO format
            end_time: End of time range in ISO format
            entity_id: Optional filter by entity identifier
            sensitivity: Anomaly detection sensitivity from 0.0 to 1.0 (default: 0.8)
            
        Returns:
            A formatted list of latency anomalies with affected operations and severity
        """
        if not start_time or not end_time:
            return "Error: start_time and end_time are required"
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found."
        if entity_id:
            df = df[df[COL_ENTITY_ID] == entity_id]
        if df.empty:
            return "No data for specified entity."
        stats = df.groupby(COL_ENTITY_ID)[COL_DURATION_MS].agg(["mean", "std", "count"]).reset_index()
        stats = stats[stats["count"] > 10]
        df_merged = pd.merge(df, stats, on=COL_ENTITY_ID)
        z_threshold = 5.0 - (sensitivity * 3.0)
        df_merged["z_score"] = (df_merged[COL_DURATION_MS] - df_merged["mean"]) / df_merged["std"]
        anomalous_spans = df_merged[df_merged["z_score"] > z_threshold].sort_values("z_score", ascending=False)
        if anomalous_spans.empty:
            return "No latency anomalies detected."
        result = [f"Detected {len(anomalous_spans)} latency anomalies (Threshold Z-Score > {z_threshold:.1f}):"]
        top_anomalies = anomalous_spans.head(10)
        for _, row in top_anomalies.iterrows():
            result.append(
                f"- Entity: {row[COL_ENTITY_ID]}, Duration: {row[COL_DURATION_MS]}ms "
                f"(Mean: {row['mean']:.1f}, Z: {row['z_score']:.1f}), "
                f"TraceID: {row[COL_TRACE_ID]}"
            )
        return "\n".join(result)
    
    def identify_bottlenecks(
        self,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None,
        min_impact_percentage: float = 10.0
    ) -> str:
        """Identify performance bottlenecks in the system.
        
        Finds operations or services that contribute most to overall latency,
        helping prioritize optimization efforts.
        
        Args:
            start_time: Start of time range in ISO format
            end_time: End of time range in ISO format
            min_impact_percentage: Minimum impact percentage to consider a bottleneck (default: 10.0)
            
        Returns:
            A formatted list of bottlenecks with impact analysis and recommendations
        """
        if not start_time or not end_time:
            return "Error: start_time and end_time are required"
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found."
        total_duration = df[COL_DURATION_MS].sum()
        if total_duration == 0:
            return "No duration recorded."
        service_duration = df.groupby(COL_ENTITY_ID)[COL_DURATION_MS].sum().reset_index()
        service_duration["impact"] = (service_duration[COL_DURATION_MS] / total_duration) * 100
        bottlenecks = service_duration[service_duration["impact"] >= min_impact_percentage].sort_values("impact", ascending=False)
        if bottlenecks.empty:
            return f"No single service contributes more than {min_impact_percentage}% to total system latency."
        result = ["Identified Bottlenecks (Services consuming significant time):"]
        for _, row in bottlenecks.iterrows():
            result.append(f"- {row[COL_ENTITY_ID]}: {row['impact']:.2f}% of total latency")
        return "\n".join(result)

    def train_iforest_model(
        self,
        start_time: str,
        end_time: str,
        save_path: Optional[str] = None
    ) -> str:
        """Train Isolation Forest anomaly detection model using trace data from the specified period.

        This method trains an unsupervised anomaly detection model (Isolation Forest) based on trace duration.
        It learns the normal behavior of service calls (Parent -> Child) during the specified time range.
        
        Args:
            start_time: Start time for training data in ISO format (e.g., "2021-03-04T00:00:00")
            end_time: End time for training data in ISO format (e.g., "2021-03-04T00:30:00")
            save_path: Optional path to save the trained model (e.g., "models/trace_model.pkl"). 
                       If not provided, the model is kept in memory.
            
        Returns:
            A status message indicating the number of trained service dependency models.
        """
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found for training period."
        spans = df[[COL_SPAN_ID, COL_ENTITY_ID, COL_PARENT_SPAN_ID, COL_TIMESTAMP, COL_DURATION_MS]].copy()
        merged = pd.merge(
            spans,
            spans[[COL_SPAN_ID, COL_ENTITY_ID]],
            left_on=COL_PARENT_SPAN_ID,
            right_on=COL_SPAN_ID,
            suffixes=("", "_parent"),
            how="left",
        )
        merged[f"{COL_ENTITY_ID}_parent"] = merged[f"{COL_ENTITY_ID}_parent"].fillna("unknown")
        grouped = merged.groupby([f"{COL_ENTITY_ID}_parent", COL_ENTITY_ID])
        self.trace_detectors = {}
        self.normal_stats = {}
        count = 0
        for (parent, child), group_df in grouped:
            _, durs = self._slide_window(group_df)
            if len(durs) < 10:
                continue
            clf = IsolationForest(random_state=42, n_estimators=100, contamination=0.01)
            clf.fit(durs.reshape(-1, 1))
            key = f"{parent}->{child}"
            self.trace_detectors[key] = clf
            self.normal_stats[key] = {
                "mean": float(np.mean(durs)),
                "std": float(np.std(durs)),
                "count": len(durs),
            }
            count += 1
        if save_path:
            dirname = os.path.dirname(save_path)
            if dirname:
                os.makedirs(dirname, exist_ok=True)
            with open(save_path, "wb") as f:
                pickle.dump({"detectors": self.trace_detectors, "stats": self.normal_stats}, f)
        return f"Trained anomaly detection models for {count} entity dependencies."

    def detect_anomalies_iforest(
        self,
        start_time: str,
        end_time: str,
        model_path: Optional[str] = None
    ) -> str:
        """Detect anomalies using the trained Isolation Forest model.

        This method uses the previously trained model (Isolation Forest) to detect anomalies in trace duration
        during the specified analysis period. It identifies service calls that significantly deviate from 
        the learned normal patterns.
        
        Args:
            start_time: Analysis start time in ISO format
            end_time: Analysis end time in ISO format
            model_path: Optional path to load the model from. If not provided, uses the in-memory model.
            
        Returns:
            A formatted string listing detected anomalies, including affected services, timestamps, 
            durations, and deviation scores.
        """
        df = self._get_trace_df(start_time, end_time)
        if df.empty:
            return "No trace data found for analysis period."
        if model_path and os.path.exists(model_path):
            try:
                with open(model_path, "rb") as f:
                    data = pickle.load(f)
                    self.trace_detectors = data.get("detectors", {})
                    self.normal_stats = data.get("stats", {})
            except Exception as e:
                return f"Error loading model: {e}"
        if not self.trace_detectors:
            return "No trained models available. Please train a model first."
        spans = df[[COL_SPAN_ID, COL_ENTITY_ID, COL_PARENT_SPAN_ID, COL_TIMESTAMP, COL_DURATION_MS, COL_TRACE_ID]].copy()
        merged = pd.merge(
            spans,
            spans[[COL_SPAN_ID, COL_ENTITY_ID]],
            left_on=COL_PARENT_SPAN_ID,
            right_on=COL_SPAN_ID,
            suffixes=("", "_parent"),
            how="left",
        )
        merged[f"{COL_ENTITY_ID}_parent"] = merged[f"{COL_ENTITY_ID}_parent"].fillna("unknown")
        grouped = merged.groupby([f"{COL_ENTITY_ID}_parent", COL_ENTITY_ID])
        anomalies: List[Dict[str, Any]] = []
        for (parent, child), group_df in grouped:
            key = f"{parent}->{child}"
            if key not in self.trace_detectors:
                continue
            clf = self.trace_detectors[key]
            window_starts, durs = self._slide_window(group_df)
            if len(durs) == 0:
                continue
            preds = clf.predict(durs.reshape(-1, 1))
            anomaly_indices = [i for i, x in enumerate(preds) if x == -1]
            if anomaly_indices:
                stats = self.normal_stats.get(key, {})
                normal_mean = stats.get("mean", 0.0)
                for idx in anomaly_indices:
                    timestamp = window_starts[idx]
                    duration = durs[idx]
                    tz = self.data_loader.get_timezone() 
                    dt_str = to_iso_with_tz(timestamp, tz)
                    anomalies.append(
                        {
                            "entity": child,
                            "parent_entity": parent,
                            "timestamp": dt_str,
                            "duration": float(duration),
                            "normal_mean": float(normal_mean),
                            "score": float(duration / normal_mean) if isinstance(normal_mean, (int, float)) and normal_mean > 0 else 0.0,
                        }
                    )
        if not anomalies:
            return "No anomalies detected using the trained model."
        anomalies.sort(key=lambda x: x["score"], reverse=True)
        result = [f"Detected {len(anomalies)} anomalies using Isolation Forest:"]
        for a in anomalies[:20]:
            result.append(
                f"- Entity: {a['entity']} (called by {a['parent_entity']}) "
                f"at {a['timestamp']}: Duration {a['duration']:.2f}ms "
                f"(Normal Mean: {a['normal_mean']:.2f}ms)"
            )
        return "\n".join(result)
    
    def cleanup(self) -> None:
        """Clean up trace data source connections."""
        if self.trace_source:
            self.trace_source = None
        if self.data_loader:
            self.data_loader = None
        super().cleanup()

    def _slide_window(self, df: pd.DataFrame, win_size_ms: int = 30000) -> Tuple[np.ndarray, np.ndarray]:
        window_start_times: List[int] = []
        durations: List[float] = []
        if df.empty:
            return np.array([]), np.array([])
        time_min = df[COL_TIMESTAMP].min()
        time_max = df[COL_TIMESTAMP].max()
        i = time_min
        while i < time_max:
            temp_df = df[(df[COL_TIMESTAMP] >= i) & (df[COL_TIMESTAMP] < i + win_size_ms)]
            if not temp_df.empty:
                window_start_times.append(int(i))
                durations.append(float(temp_df[COL_DURATION_MS].mean()))
            i += win_size_ms
        return np.array(window_start_times), np.array(durations)

    def _print_tree(self, G: nx.DiGraph, node: Any, span_map: Dict[str, Any], result: List[str], level: int) -> None:
        children = sorted(G.successors(node), key=lambda x: span_map[x][COL_TIMESTAMP])
        for child in children:
            data = span_map[child]
            indent = "  " * level
            result.append(f"{indent}└─ [{data[COL_ENTITY_ID]}] {data[COL_DURATION_MS]}ms")
            self._print_tree(G, child, span_map, result, level + 1)


def _build_default_config() -> Dict[str, Any]:
    from pathlib import Path
    root = Path(__file__).resolve().parents[4]
    return {
        "dataset_path": str(root / "datasets" / "DiskFault"),
        "default_timezone": "Asia/Shanghai",
    }


def _cli() -> None:
    import argparse

    parser = argparse.ArgumentParser(prog="trace_tool")
    parser.add_argument("--dataset-path", dest="dataset_path")
    parser.add_argument("--timezone", dest="default_timezone")
    subparsers = parser.add_subparsers(dest="command", required=True)

    common = {
        "start_time": ("--start", "Start time in ISO format"),
        "end_time": ("--end", "End time in ISO format"),
    }

    p_slow = subparsers.add_parser("find_slow_spans")
    p_slow.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_slow.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_slow.add_argument("--entity", dest="entity_id")
    p_slow.add_argument("--min-duration-ms", type=int, default=1000, dest="min_duration_ms")
    p_slow.add_argument("--limit", type=int, default=10)
    p_slow.add_argument("--dataset-path", dest="dataset_path")
    p_slow.add_argument("--timezone", dest="default_timezone")

    p_call = subparsers.add_parser("analyze_trace_call_tree")
    p_call.add_argument("--trace-id", required=True, dest="trace_id")
    p_call.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_call.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_call.add_argument("--dataset-path", dest="dataset_path")
    p_call.add_argument("--timezone", dest="default_timezone")

    p_deps = subparsers.add_parser("get_dependency_graph")
    p_deps.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_deps.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_deps.add_argument("--entity", dest="entity_id")
    p_deps.add_argument("--dataset-path", dest="dataset_path")
    p_deps.add_argument("--timezone", dest="default_timezone")

    p_z = subparsers.add_parser("detect_anomalies_zscore")
    p_z.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_z.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_z.add_argument("--entity", dest="entity_id")
    p_z.add_argument("--sensitivity", type=float, default=0.8)
    p_z.add_argument("--dataset-path", dest="dataset_path")
    p_z.add_argument("--timezone", dest="default_timezone")

    p_bottleneck = subparsers.add_parser("identify_bottlenecks")
    p_bottleneck.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_bottleneck.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_bottleneck.add_argument("--min-impact-percentage", type=float, default=10.0, dest="min_impact_percentage")
    p_bottleneck.add_argument("--dataset-path", dest="dataset_path")
    p_bottleneck.add_argument("--timezone", dest="default_timezone")

    p_train = subparsers.add_parser("train_iforest_model")
    p_train.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_train.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_train.add_argument("--save-path", dest="save_path")
    p_train.add_argument("--dataset-path", dest="dataset_path")
    p_train.add_argument("--timezone", dest="default_timezone")

    p_iforest = subparsers.add_parser("detect_anomalies_iforest")
    p_iforest.add_argument(
        common["start_time"][0],
        required=True,
        dest="start_time",
        help=common["start_time"][1],
    )
    p_iforest.add_argument(
        common["end_time"][0],
        required=True,
        dest="end_time",
        help=common["end_time"][1],
    )
    p_iforest.add_argument("--model-path", dest="model_path")
    p_iforest.add_argument("--dataset-path", dest="dataset_path")
    p_iforest.add_argument("--timezone", dest="default_timezone")

    args = parser.parse_args()
    config = _build_default_config()
    if getattr(args, "dataset_path", None):
        config["dataset_path"] = args.dataset_path
    if getattr(args, "default_timezone", None):
        config["default_timezone"] = args.default_timezone
    tool = TraceAnalysisTool(config=config)
    tool.initialize()

    if args.command == "find_slow_spans":
        out = tool.find_slow_spans(
            start_time=args.start_time,
            end_time=args.end_time,
            entity_id=args.entity_id,
            min_duration_ms=args.min_duration_ms,
            limit=args.limit,
        )
        print(out)
    elif args.command == "analyze_trace_call_tree":
        out = tool.analyze_trace_call_tree(
            trace_id=args.trace_id,
            start_time=args.start_time,
            end_time=args.end_time,
        )
        print(out)
    elif args.command == "get_dependency_graph":
        out = tool.get_dependency_graph(
            start_time=args.start_time,
            end_time=args.end_time,
            entity_id=args.entity_id,
        )
        print(out)
    elif args.command == "detect_anomalies_zscore":
        out = tool.detect_anomalies_zscore(
            start_time=args.start_time,
            end_time=args.end_time,
            entity_id=args.entity_id,
            sensitivity=args.sensitivity,
        )
        print(out)
    elif args.command == "identify_bottlenecks":
        out = tool.identify_bottlenecks(
            start_time=args.start_time,
            end_time=args.end_time,
            min_impact_percentage=args.min_impact_percentage,
        )
        print(out)
    elif args.command == "train_iforest_model":
        out = tool.train_iforest_model(
            start_time=args.start_time,
            end_time=args.end_time,
            save_path=args.save_path,
        )
        print(out)
    elif args.command == "detect_anomalies_iforest":
        out = tool.detect_anomalies_iforest(
            start_time=args.start_time,
            end_time=args.end_time,
            model_path=args.model_path,
        )
        print(out)


if __name__ == "__main__":
    _cli()
