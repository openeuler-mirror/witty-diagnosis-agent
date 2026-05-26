import pandas as pd
from typing import Optional, List, Dict, Any, Callable, Tuple
from pathlib import Path
from abc import ABC, abstractmethod
import os
from datetime import datetime
import pytz
from schema import (
    COL_TIMESTAMP,
    COL_ENTITY_ID,
    COL_MESSAGE,
    COL_SEVERITY,
    COL_METRIC_NAME,
    COL_VALUE,
    COL_TRACE_ID,
    COL_SPAN_ID,
    COL_PARENT_SPAN_ID,
    COL_DURATION_MS,
    COL_STATUS_CODE,
    COL_HOST_IP,
)


class DataValidationError(Exception):
    pass


class BaseDataLoader(ABC):
    def __init__(self, default_timezone: str = "Asia/Shanghai"):
        self._tz = default_timezone
    
    def get_timezone(self) -> str:
        return self._tz
    
    @abstractmethod
    def load_metrics(self, start_time: str, end_time: str) -> pd.DataFrame:
        raise NotImplementedError()
    
    @abstractmethod
    def load_logs(self, start_time: str, end_time: str) -> pd.DataFrame:
        raise NotImplementedError()
    
    @abstractmethod
    def load_traces(self, start_time: str, end_time: str) -> pd.DataFrame:
        raise NotImplementedError()

    def validate_metrics_df(self, df: pd.DataFrame) -> pd.DataFrame:
        if df is None or df.empty:
            return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE])
        required = [COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE]
        for col in required:
            if col not in df.columns:
                raise DataValidationError(f"metrics missing required column: {col}")
        df = df.copy()
        df[COL_TIMESTAMP] = pd.to_numeric(df[COL_TIMESTAMP], errors="coerce").astype("Int64")
        df[COL_ENTITY_ID] = df[COL_ENTITY_ID].astype(str)
        df[COL_METRIC_NAME] = df[COL_METRIC_NAME].astype(str)
        df[COL_VALUE] = pd.to_numeric(df[COL_VALUE], errors="coerce").astype(float)
        df = df.dropna(subset=[COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE])
        return df[[COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE]]

    def validate_logs_df(self, df: pd.DataFrame) -> pd.DataFrame:
        if df is None or df.empty:
            return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_MESSAGE, COL_SEVERITY, COL_HOST_IP])
        required = [COL_TIMESTAMP, COL_ENTITY_ID, COL_MESSAGE]
        for col in required:
            if col not in df.columns:
                raise DataValidationError(f"logs missing required column: {col}")
        df = df.copy()
        df[COL_TIMESTAMP] = pd.to_numeric(df[COL_TIMESTAMP], errors="coerce").astype("Int64")
        df[COL_ENTITY_ID] = df[COL_ENTITY_ID].astype(str)
        df[COL_MESSAGE] = df[COL_MESSAGE].astype(str)
        if COL_SEVERITY not in df.columns:
            df[COL_SEVERITY] = None
        if COL_HOST_IP not in df.columns:
            df[COL_HOST_IP] = None
        df = df.dropna(subset=[COL_TIMESTAMP, COL_ENTITY_ID, COL_MESSAGE])
        return df[[COL_TIMESTAMP, COL_ENTITY_ID, COL_MESSAGE, COL_SEVERITY, COL_HOST_IP]]

    def validate_traces_df(self, df: pd.DataFrame) -> pd.DataFrame:
        if df is None or df.empty:
            return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_PARENT_SPAN_ID, COL_DURATION_MS, COL_STATUS_CODE])
        required = [COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_DURATION_MS]
        for col in required:
            if col not in df.columns:
                raise DataValidationError(f"traces missing required column: {col}")
        df = df.copy()
        df[COL_TIMESTAMP] = pd.to_numeric(df[COL_TIMESTAMP], errors="coerce").astype("Int64")
        df[COL_ENTITY_ID] = df[COL_ENTITY_ID].astype(str)
        df[COL_TRACE_ID] = df[COL_TRACE_ID].astype(str)
        df[COL_SPAN_ID] = df[COL_SPAN_ID].astype(str)
        df[COL_PARENT_SPAN_ID] = df.get(COL_PARENT_SPAN_ID)
        df[COL_DURATION_MS] = pd.to_numeric(df[COL_DURATION_MS], errors="coerce").astype(float)
        if COL_STATUS_CODE not in df.columns:
            df[COL_STATUS_CODE] = None
        df = df.dropna(subset=[COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_DURATION_MS])
        df = df[df[COL_DURATION_MS] >= 0]
        return df[[COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_PARENT_SPAN_ID, COL_DURATION_MS, COL_STATUS_CODE]]


    def get_metrics(self, start_time: str, end_time: str) -> pd.DataFrame:
        df = self.load_metrics(start_time, end_time)
        return self.validate_metrics_df(df)

    def get_logs(self, start_time: str, end_time: str) -> pd.DataFrame:
        df = self.load_logs(start_time, end_time)
        return self.validate_logs_df(df)

    def get_traces(self, start_time: str, end_time: str) -> pd.DataFrame:
        df = self.load_traces(start_time, end_time)
        return self.validate_traces_df(df)


class OpenRCADataLoader(BaseDataLoader):
    def __init__(self, dataset_path: str, default_timezone: str = "Asia/Shanghai"):
        super().__init__(default_timezone=default_timezone)
        self.dataset_path = Path(dataset_path)
        self.telemetry_path = self.dataset_path / "telemetry"
        self._cache: Dict[str, pd.DataFrame] = {}

    def get_available_dates(self) -> List[str]:
        if not self.telemetry_path.exists():
            return []
        dates = []
        for item in self.telemetry_path.iterdir():
            if item.is_dir() and item.name.count("_") == 2:
                dates.append(item.name)
        return sorted(dates)

    def _date_to_path_format(self, date_str: str) -> str:
        if "_" in date_str:
            return date_str
        return date_str.replace("-", "_")

    def _get_file_path(self, date: str, data_type: str, filename: str) -> Optional[Path]:
        date_formatted = self._date_to_path_format(date)
        file_path = self.telemetry_path / date_formatted / data_type / filename
        if file_path.exists():
            return file_path
        return None

    def load_metrics(self, start_time: str, end_time: str) -> pd.DataFrame:
        start_dt = pd.to_datetime(start_time)
        end_dt = pd.to_datetime(end_time)
        if start_dt.tzinfo is None:
            start_dt = start_dt.tz_localize(self._tz)
        else:
            start_dt = start_dt.tz_convert(self._tz)
        if end_dt.tzinfo is None:
            end_dt = end_dt.tz_localize(self._tz)
        else:
            end_dt = end_dt.tz_convert(self._tz)
        dates_to_load = []
        current_date = start_dt.date()
        while current_date <= end_dt.date():
            date_str = current_date.strftime("%Y_%m_%d")
            dates_to_load.append(date_str)
            current_date = pd.Timestamp(current_date) + pd.Timedelta(days=1)
            current_date = current_date.date()
        app_dfs = []
        cont_dfs = []
        for date in dates_to_load:
            app_key = f"metric_app_{date}"
            if app_key in self._cache:
                app_df = self._cache[app_key]
            else:
                app_path = self._get_file_path(date, "metric", "metric_app.csv")
                app_df = pd.read_csv(app_path) if app_path else None
                if app_df is not None:
                    app_df[COL_TIMESTAMP] = (pd.to_numeric(app_df["timestamp"], errors="coerce") * 1000).astype("Int64")
                    self._cache[app_key] = app_df
            if app_df is not None:
                app_dfs.append(app_df)
            cont_key = f"metric_container_{date}"
            if cont_key in self._cache:
                cont_df = self._cache[cont_key]
            else:
                cont_path = self._get_file_path(date, "metric", "metric_container.csv")
                cont_df = pd.read_csv(cont_path) if cont_path else None
                if cont_df is not None:
                    cont_df[COL_TIMESTAMP] = (pd.to_numeric(cont_df["timestamp"], errors="coerce") * 1000).astype("Int64")
                    self._cache[cont_key] = cont_df
            if cont_df is not None:
                cont_dfs.append(cont_df)
        app_df = pd.concat(app_dfs, ignore_index=True) if app_dfs else pd.DataFrame()
        cont_df = pd.concat(cont_dfs, ignore_index=True) if cont_dfs else pd.DataFrame()
        records = []
        if not app_df.empty:
            for _, row in app_df.iterrows():
                svc = row.get("tc")
                ts = row.get(COL_TIMESTAMP)
                for col, kpi in [("mrt", "App_mrt"), ("sr", "App_sr"), ("rr", "App_rr"), ("cnt", "App_cnt")]:
                    if col in app_df.columns:
                        val = row.get(col)
                        records.append(
                            {
                                COL_TIMESTAMP: ts,
                                COL_ENTITY_ID: svc,
                                COL_METRIC_NAME: kpi,
                                COL_VALUE: val,
                            }
                        )
        cont_norm = pd.DataFrame()
        if not cont_df.empty:
            if all(c in cont_df.columns for c in [COL_TIMESTAMP, "cmdb_id", "kpi_name", "value"]):
                cont_norm = cont_df.rename(columns={"cmdb_id": COL_ENTITY_ID, "kpi_name": COL_METRIC_NAME})[
                    [COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE]
                ]
            else:
                cont_norm = pd.DataFrame()
        app_norm = pd.DataFrame.from_records(records) if records else pd.DataFrame()
        if not app_norm.empty:
            start_ms = int(start_dt.timestamp() * 1000)
            end_ms = int(end_dt.timestamp() * 1000)
            app_norm = app_norm[(app_norm[COL_TIMESTAMP] >= start_ms) & (app_norm[COL_TIMESTAMP] <= end_ms)]
        if not cont_norm.empty:
            start_ms = int(start_dt.timestamp() * 1000)
            end_ms = int(end_dt.timestamp() * 1000)
            cont_norm = cont_norm[(cont_norm[COL_TIMESTAMP] >= start_ms) & (cont_norm[COL_TIMESTAMP] <= end_ms)]
        if app_norm.empty and cont_norm.empty:
            return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE])

        if app_norm.empty:
            merged = cont_norm
        elif cont_norm.empty:
            merged = app_norm
        else:
            merged = pd.concat([cont_norm, app_norm], ignore_index=True)
        return merged

    def clear_cache(self):
        self._cache.clear()

    def get_cache_info(self) -> Dict[str, Any]:
        return {
            "cached_files": len(self._cache),
            "cache_keys": list(self._cache.keys()),
            "total_rows": sum(len(df) for df in self._cache.values()),
        }

    def load_logs(self, start_time: str, end_time: str) -> pd.DataFrame:
        start_dt = pd.to_datetime(start_time)
        end_dt = pd.to_datetime(end_time)
        if start_dt.tzinfo is None:
            start_dt = start_dt.tz_localize(self._tz)
        else:
            start_dt = start_dt.tz_convert(self._tz)
        if end_dt.tzinfo is None:
            end_dt = end_dt.tz_localize(self._tz)
        else:
            end_dt = end_dt.tz_convert(self._tz)
            
        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)
            
        dates_to_load = []
        current_date = start_dt.date()
        while current_date <= end_dt.date():
            date_str = current_date.strftime("%Y_%m_%d")
            dates_to_load.append(date_str)
            current_date = pd.Timestamp(current_date) + pd.Timedelta(days=1)
            current_date = current_date.date()
        dfs = []
        for date in dates_to_load:
            key = f"log_{date}"
            if key in self._cache:
                df = self._cache[key]
                # Filter cached data
                if df is not None and COL_TIMESTAMP in df.columns:
                     df = df[(df[COL_TIMESTAMP] >= start_ms) & (df[COL_TIMESTAMP] <= end_ms)]
            else:
                path = self._get_file_path(date, "log", "log_service.csv")
                df = None
                if path:
                    try:
                        # Use chunked reading to avoid loading full file
                        chunks = []
                        for chunk in pd.read_csv(path, chunksize=10000):
                            # Normalize timestamp
                            chunk[COL_TIMESTAMP] = (pd.to_numeric(chunk["timestamp"], errors="coerce") * 1000).astype("Int64")
                            # Filter
                            chunk = chunk[(chunk[COL_TIMESTAMP] >= start_ms) & (chunk[COL_TIMESTAMP] <= end_ms)]
                            if not chunk.empty:
                                chunks.append(chunk)
                        
                        if chunks:
                            df = pd.concat(chunks, ignore_index=True)
                            # Do not cache filtered results under the full-file key
                        else:
                            df = None
                    except Exception:
                        df = None
            if df is not None:
                dfs.append(df)
        if not dfs:
            return pd.DataFrame()
        combined = pd.concat(dfs, ignore_index=True)
        # Filter again to be safe (e.g. if combined from multiple chunks/cached items)
        if COL_TIMESTAMP in combined.columns:
            combined = combined[(combined[COL_TIMESTAMP] >= start_ms) & (combined[COL_TIMESTAMP] <= end_ms)]
        if not combined.empty and all(c in combined.columns for c in [COL_TIMESTAMP, "cmdb_id", "value"]):
            combined = combined.rename(columns={"cmdb_id": COL_ENTITY_ID, "value": COL_MESSAGE})
        if COL_SEVERITY not in combined.columns:
            combined[COL_SEVERITY] = None
        if COL_HOST_IP not in combined.columns:
            combined[COL_HOST_IP] = None
        keep = [COL_TIMESTAMP, COL_ENTITY_ID, COL_MESSAGE, COL_SEVERITY, COL_HOST_IP]
        return combined[keep] if all(c in combined.columns for c in keep) else pd.DataFrame()


    def load_traces(self, start_time: str, end_time: str) -> pd.DataFrame:
        start_dt = pd.to_datetime(start_time)
        end_dt = pd.to_datetime(end_time)
        if start_dt.tzinfo is None:
            start_dt = start_dt.tz_localize(self._tz)
        else:
            start_dt = start_dt.tz_convert(self._tz)
        if end_dt.tzinfo is None:
            end_dt = end_dt.tz_localize(self._tz)
        else:
            end_dt = end_dt.tz_convert(self._tz)
        dates_to_load = []
        current_date = start_dt.date()
        while current_date <= end_dt.date():
            date_str = current_date.strftime("%Y_%m_%d")
            dates_to_load.append(date_str)
            current_date = pd.Timestamp(current_date) + pd.Timedelta(days=1)
            current_date = current_date.date()
        dfs = []
        for date in dates_to_load:
            key = f"trace_{date}"
            if key in self._cache:
                df = self._cache[key]
            else:
                path = self._get_file_path(date, "trace", "trace_span.csv")
                df = pd.read_csv(path) if path else None
                if df is not None:
                    df[COL_TIMESTAMP] = pd.to_numeric(df["timestamp"], errors="coerce").astype("Int64")
                    self._cache[key] = df
            if df is not None:
                dfs.append(df)
        if not dfs:
            return pd.DataFrame()
        combined = pd.concat(dfs, ignore_index=True)
        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)
        if COL_TIMESTAMP in combined.columns:
            combined = combined[(combined[COL_TIMESTAMP] >= start_ms) & (combined[COL_TIMESTAMP] <= end_ms)]
        if not combined.empty:
            rename_map = {"cmdb_id": "entity_id", "parent_id": "parent_span_id", "duration": "duration_ms"}
            for k, v in rename_map.items():
                if k in combined.columns:
                    combined[v] = combined[k]
        
        if COL_STATUS_CODE not in combined.columns:
            combined[COL_STATUS_CODE] = None
            
        keep = [COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_PARENT_SPAN_ID, COL_DURATION_MS, COL_STATUS_CODE]
        return combined[keep] if all(c in combined.columns for c in keep) else pd.DataFrame()


class GenericLogDataLoader(BaseDataLoader):
    """
    Unified loader for both Disk Fault and Super Node scenarios.
    Automatically detects directory structure:
    - If subdirectories exist (e.g., <date>/<ip>/<log>), treats as Super Node structure with host_ip.
    - If files exist directly (e.g., <date>/<log>), treats as Disk Fault structure (host_ip=None).
    """
    def __init__(self, dataset_path: str, default_timezone: str = "UTC"):
        super().__init__(default_timezone=default_timezone)
        self.dataset_path = Path(dataset_path)
        self._cache: Dict[str, pd.DataFrame] = {}
        try:
            self._tz_obj = pytz.timezone(default_timezone)
        except:
            self._tz_obj = pytz.UTC

    def load_metrics(self, start_time: str, end_time: str) -> pd.DataFrame:
        # Generic loader focuses on logs for now
        return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_METRIC_NAME, COL_VALUE])

    def load_traces(self, start_time: str, end_time: str) -> pd.DataFrame:
        start_dt = pd.to_datetime(start_time)
        end_dt = pd.to_datetime(end_time)
        if start_dt.tzinfo is None:
            start_dt = start_dt.tz_localize(self._tz)
        if end_dt.tzinfo is None:
            end_dt = end_dt.tz_localize(self._tz)

        dfs = []
        current_date = start_dt.date()
        end_date_val = end_dt.date()
        
        while current_date <= end_date_val:
            date_str = current_date.strftime("%Y-%m-%d")
            day_dir = self.dataset_path / date_str
            
            if day_dir.exists() and day_dir.is_dir():
                items = list(day_dir.iterdir())
                subdirs = [i for i in items if i.is_dir() and not i.name.startswith(".")]
                
                candidates = []
                # Check for trace files in current dir
                candidates.extend(list(day_dir.glob("*trace*.csv")))
                candidates.extend(list(day_dir.glob("*span*.csv")))
                
                # Check inside subdirs (SuperNode style)
                for ip_dir in subdirs:
                    candidates.extend(list(ip_dir.glob("*trace*.csv")))
                    candidates.extend(list(ip_dir.glob("*span*.csv")))
                
                for f in candidates:
                    try:
                        df = pd.read_csv(f)
                        # Basic validation of columns
                        # We expect at least trace_id, span_id
                        if not all(c in df.columns for c in ["trace_id", "span_id"]):
                            continue
                            
                        # Normalize timestamp
                        if COL_TIMESTAMP not in df.columns and "timestamp" in df.columns:
                             df[COL_TIMESTAMP] = pd.to_numeric(df["timestamp"], errors="coerce").astype("Int64")
                        
                        # Normalize other columns
                        rename_map = {
                            "cmdb_id": COL_ENTITY_ID, 
                            "parent_id": COL_PARENT_SPAN_ID, 
                            "duration": COL_DURATION_MS
                        }
                        df = df.rename(columns=rename_map)
                        
                        dfs.append(df)
                    except:
                        continue
                        
            current_date += pd.Timedelta(days=1)

        if not dfs:
            return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_PARENT_SPAN_ID, COL_DURATION_MS, COL_STATUS_CODE])

        combined = pd.concat(dfs, ignore_index=True)
        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)
        
        if COL_TIMESTAMP in combined.columns:
            combined = combined[(combined[COL_TIMESTAMP] >= start_ms) & (combined[COL_TIMESTAMP] <= end_ms)]
            
        if COL_STATUS_CODE not in combined.columns:
            combined[COL_STATUS_CODE] = None
            
        keep = [COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_PARENT_SPAN_ID, COL_DURATION_MS, COL_STATUS_CODE]
        # Only return if we have the essential columns
        if all(c in combined.columns for c in [COL_TIMESTAMP, COL_ENTITY_ID, COL_TRACE_ID, COL_SPAN_ID, COL_DURATION_MS]):
             return combined[keep]
        return pd.DataFrame(columns=keep)

    def load_logs(self, start_time: str, end_time: str) -> pd.DataFrame:
        start_dt = pd.to_datetime(start_time)
        end_dt = pd.to_datetime(end_time)
        if start_dt.tzinfo is None:
            start_dt = start_dt.tz_localize(self._tz)
        if end_dt.tzinfo is None:
            end_dt = end_dt.tz_localize(self._tz)

        # Pre-calculate milliseconds for filtering
        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)

        dfs = []
        current_date = start_dt.date()
        end_date_val = end_dt.date()
        
        # Iterate days
        while current_date <= end_date_val:
            date_str = current_date.strftime("%Y-%m-%d") # Log fetcher uses YYYY-MM-DD
            day_dir = self.dataset_path / date_str
            
            if day_dir.exists() and day_dir.is_dir():
                # Check for subdirectories (IPs) vs Files
                items = list(day_dir.iterdir())
                subdirs = [i for i in items if i.is_dir() and not i.name.startswith(".")]
                files = [i for i in items if i.is_file() and not i.name.startswith(".")]
                
                if subdirs:
                    # Super Node Structure: <date>/<ip>/<file>
                    for ip_dir in subdirs:
                        host_ip = ip_dir.name
                        for file_path in ip_dir.iterdir():
                            if file_path.is_file() and not file_path.name.startswith("."):
                                df = self._load_single_log_file(file_path, host_ip=host_ip, current_date=current_date, start_ms=start_ms, end_ms=end_ms)
                                if not df.empty:
                                    dfs.append(df)
                elif files:
                    # Disk Fault Structure: <date>/<file>
                    for file_path in files:
                        df = self._load_single_log_file(file_path, host_ip=None, current_date=current_date, start_ms=start_ms, end_ms=end_ms)
                        if not df.empty:
                            dfs.append(df)
                            
            current_date += pd.Timedelta(days=1)

        if not dfs:
            return pd.DataFrame(columns=[COL_TIMESTAMP, COL_ENTITY_ID, COL_MESSAGE, COL_SEVERITY, COL_HOST_IP])

        combined = pd.concat(dfs, ignore_index=True)
        
        # Filtering is already done during loading, but we keep this for safety
        if COL_TIMESTAMP in combined.columns:
            combined = combined[(combined[COL_TIMESTAMP] >= start_ms) & (combined[COL_TIMESTAMP] <= end_ms)]
        
        if COL_HOST_IP not in combined.columns:
            combined[COL_HOST_IP] = None
            
        return combined

    def _load_single_log_file(self, file_path: Path, host_ip: Optional[str], current_date, start_ms: int = None, end_ms: int = None) -> pd.DataFrame:
        key = f"{file_path.parent.name}_{file_path.name}"
        # Only use cache if we are loading the full file (no filtering)
        if start_ms is None and end_ms is None and key in self._cache:
            return self._cache[key]
        
        try:
            data = []
            entity_id = file_path.stem # Default entity_id is filename without extension
            
            # Cache the timestamp format for this file to speed up parsing
            cached_fmt = None
            
            # Read file content line by line to save memory
            with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                        
                    ts_ms, fmt = self._parse_timestamp_fast(line, current_date, cached_fmt)
                    if fmt:
                        cached_fmt = fmt
                    
                    if ts_ms is not None:
                        # Filter by time range if provided
                        if start_ms is not None and ts_ms < start_ms:
                            continue
                        if end_ms is not None and ts_ms > end_ms:
                            continue

                        # Try to extract message part
                        # If line starts with timestamp, message is the rest.
                        parts = line.split(" ", 3)
                        if len(parts) > 1:
                            msg_val = line
                        else:
                            msg_val = line
                            
                        data.append({
                            COL_TIMESTAMP: ts_ms,
                            COL_ENTITY_ID: entity_id,
                            COL_MESSAGE: msg_val,
                            COL_SEVERITY: "INFO", # Default, TODO: parse severity (INFO, WARN, ERROR)
                            COL_HOST_IP: host_ip
                        })
            
            if data:
                df = pd.DataFrame(data)
                # Only cache if we loaded the full file
                if start_ms is None and end_ms is None:
                    self._cache[key] = df
                return df
            return pd.DataFrame()
            
        except Exception as e:
            # print(f"Error reading {file_path}: {e}")
            return pd.DataFrame()

    _MONTH_MAP = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
    }

    def _parse_syslog_fast(self, line: str, year: int) -> Optional[datetime]:
        """
        Fast parsing for Syslog timestamp: Jan 23 10:32:01
        """
        try:
            # Check length: at least 15 chars for timestamp
            if len(line) < 15:
                return None
            
            month_str = line[:3]
            month = self._MONTH_MAP.get(month_str)
            if not month: return None
            
            day = int(line[4:6])
            hour = int(line[7:9])
            minute = int(line[10:12])
            second = int(line[13:15])
            
            return datetime(year, month, day, hour, minute, second)
        except:
            return None

    def _parse_iso_fast(self, ts_str: str) -> Optional[datetime]:
        """
        Fast parsing for ISO 8601-like strings: YYYY-MM-DDTHH:MM:SS or YYYY-MM-DDTHH:MM:SS.f
        Avoids strptime for common case.
        """
        try:
            # Check length: 19 for seconds, >20 for fractional
            if len(ts_str) < 19:
                return None
            
            # Simple manual parsing:
            # 0123456789012345678
            # YYYY-MM-DDTHH:MM:SS
            year = int(ts_str[0:4])
            month = int(ts_str[5:7])
            day = int(ts_str[8:10])
            hour = int(ts_str[11:13])
            minute = int(ts_str[14:16])
            second = int(ts_str[17:19])
            
            microsecond = 0
            if len(ts_str) > 19 and ts_str[19] == '.':
                 # Parse microseconds
                 # fractional part can be variable length
                 frac = ts_str[20:]
                 if frac:
                     # pad to 6 digits
                     if len(frac) > 6:
                         frac = frac[:6]
                     elif len(frac) < 6:
                         frac = frac.ljust(6, '0')
                     microsecond = int(frac)

            return datetime(year, month, day, hour, minute, second, microsecond)
        except:
            return None

    def _parse_timestamp_fast(self, line: str, current_date, cached_fmt: str = None) -> Tuple[Optional[int], Optional[str]]:
        """
        Optimized timestamp parser using strptime and format caching.
        Returns (timestamp_ms, format_used)
        """
        try:
            # Fast path: try cached format first
            if cached_fmt:
                try:
                    ts = None
                    # Special handling for Chinese Syslog which needs pre-processing
                    if cached_fmt == "chinese_syslog":
                        parts = line.split(" ", 2)
                        if len(parts) >= 3 and parts[0].endswith("月"):
                            month_str = parts[0].replace("月", "")
                            if month_str.isdigit():
                                time_token = parts[2].split()[0]
                                ts_str = f"{current_date.year}-{month_str}-{parts[1]} {time_token}"
                                dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
                                ts = dt
                    # Special handling for Syslog which needs year injection
                    elif cached_fmt == "syslog":
                         parts = line.split(" ", 3)
                         if len(parts) >= 3:
                             # e.g. Jan 23 10:32:01
                             time_token = parts[2]
                             ts_str = f"{current_date.year} {parts[0]} {parts[1]} {time_token}"
                             dt = datetime.strptime(ts_str, "%Y %b %d %H:%M:%S")
                             ts = dt
                    # Special handling for Syslog Fast
                    elif cached_fmt == "syslog_fast":
                         # Assume line starts with timestamp
                         dt = self._parse_syslog_fast(line, current_date.year)
                         ts = dt
                    # Special handling for ISO Fast
                    elif cached_fmt == "iso_fast":
                         # Assume start of line is ISO timestamp
                         # We can slice safely because we checked length in _parse_iso_fast or detection
                         if len(line) >= 19:
                             ts_token = line.split()[0]
                             dt = self._parse_iso_fast(ts_token)
                             ts = dt
                    # Standard formats
                    else:
                        # Optimization: slice the string to likely length to avoid parsing full log message
                        # ISO is usually ~19-25 chars
                        if len(line) > 30:
                            ts_part = line[:30]
                        else:
                            ts_part = line
                            
                        # If format contains T, it might be iso
                        if "T" in cached_fmt:
                             # Simple extraction for ISO
                             dt = datetime.strptime(ts_part.split()[0], cached_fmt)
                             ts = dt
                        else:
                             # Fallback to slow but correct if cached_fmt is complex
                             # But here we only cache standard strptime formats
                             pass

                    if ts:
                        if ts.tzinfo is None:
                            # We need to localize
                            # Use pytz or pandas localization
                            # Since we are inside a class with self._tz (str), use pd.Timestamp for convenience or pytz
                            # pd.Timestamp is slower than pytz for scalar, but let's stick to consistent logic
                            # For speed:
                            ts = self._tz_obj.localize(ts)
                        return int(ts.timestamp() * 1000), cached_fmt
                except:
                    # Cached format failed, fall back to detection
                    pass

            # Detection Logic
            parts = line.split(" ", 2)
            if not parts:
                return None, None
            
            first_token = parts[0]
            
            # 1. ISO 8601-like (YYYY-MM-DD...)
            if "-" in first_token and len(first_token) >= 10:
                # 2026-01-29T17:45:00
                if "T" in first_token:
                    # Try fast parser first
                    dt = self._parse_iso_fast(first_token)
                    if dt:
                        ts = self._tz_obj.localize(dt)
                        return int(ts.timestamp() * 1000), "iso_fast"
                    
                    try:
                        dt = datetime.strptime(first_token, "%Y-%m-%dT%H:%M:%S")
                        fmt = "%Y-%m-%dT%H:%M:%S"
                        ts = self._tz_obj.localize(dt)
                        return int(ts.timestamp() * 1000), fmt
                    except:
                        pass
                    # Try with fractional seconds?
                    try:
                        dt = datetime.strptime(first_token, "%Y-%m-%dT%H:%M:%S.%f")
                        fmt = "%Y-%m-%dT%H:%M:%S.%f"
                        ts = self._tz_obj.localize(dt)
                        return int(ts.timestamp() * 1000), fmt
                    except:
                        pass
                else:
                    # 2026-01-29 17:45:00
                    if len(parts) >= 2:
                        try:
                            ts_str = f"{parts[0]} {parts[1]}"
                            dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
                            
                            ts = self._tz_obj.localize(dt)
                            return int(ts.timestamp() * 1000), None # Don't cache for now
                        except:
                            pass

            # 2. Syslog (Jan 01 ...)
            if len(parts) >= 3 and first_token.isalpha() and len(first_token) == 3:
                # Try fast parser first
                dt = self._parse_syslog_fast(line, current_date.year)
                if dt:
                    ts = self._tz_obj.localize(dt)
                    return int(ts.timestamp() * 1000), "syslog_fast"

                try:
                    time_token = parts[2].split()[0] # Handle cases where time is followed by hostname immediately? No, usually space.
                    # parts[2] is the rest of the line? No, split(" ", 2) means [Jan, 01, "12:00:00 hostname..."]
                    
                    # parts[2] starts with time
                    rest = parts[2]
                    time_part = rest.split(" ")[0]
                    
                    ts_str = f"{current_date.year} {parts[0]} {parts[1]} {time_part}"
                    dt = datetime.strptime(ts_str, "%Y %b %d %H:%M:%S")
                    
                    ts = self._tz_obj.localize(dt)
                    return int(ts.timestamp() * 1000), "syslog"
                except:
                    pass

            # 3. Chinese Syslog (1月 29 ...)
            if len(parts) >= 3 and first_token.endswith("月"):
                try:
                    month_str = first_token.replace("月", "")
                    if month_str.isdigit():
                        # parts[2] starts with time
                        rest = parts[2]
                        time_part = rest.split(" ")[0]
                        
                        ts_str = f"{current_date.year}-{month_str}-{parts[1]} {time_part}"
                        dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
                        
                        ts = self._tz_obj.localize(dt)
                        return int(ts.timestamp() * 1000), "chinese_syslog"
                except:
                    pass
            
            # Fallback to pandas for difficult cases (but don't cache)
            try:
                # pd.to_datetime is robust but slow
                # Only use as last resort
                # ts = pd.to_datetime(first_token)
                # ...
                pass
            except:
                pass
                
            return None, None
            
        except Exception:
            return None, None

    def _parse_timestamp(self, line: str, current_date) -> Optional[int]:
        # Backward compatibility wrapper
        ts, _ = self._parse_timestamp_fast(line, current_date)
        return ts


class UniversalDataLoader(BaseDataLoader):
    def __init__(self, dataset_path: str, default_timezone: str = "Asia/Shanghai"):
        super().__init__(default_timezone=default_timezone)
        self.dataset_path = Path(dataset_path)
        self._delegate = None
        
        # Detect scenario
        # OpenRCA usually has a 'telemetry' folder
        if (self.dataset_path / "telemetry").exists():
             self._delegate = OpenRCADataLoader(dataset_path, default_timezone=default_timezone)
        else:
             # Default to GenericLogDataLoader which handles DiskFault and SuperNode
             self._delegate = GenericLogDataLoader(dataset_path, default_timezone=default_timezone)

    def load_metrics(self, start_time: str, end_time: str) -> pd.DataFrame:
        return self._delegate.load_metrics(start_time, end_time)

    def load_logs(self, start_time: str, end_time: str) -> pd.DataFrame:
        return self._delegate.load_logs(start_time, end_time)
    
    def load_traces(self, start_time: str, end_time: str) -> pd.DataFrame:
        return self._delegate.load_traces(start_time, end_time)


_LOADER_REGISTRY: Dict[str, Callable[..., BaseDataLoader]] = {}

def register_data_loader(name: str, constructor: Callable[..., BaseDataLoader]) -> None:
    _LOADER_REGISTRY[name.lower()] = constructor

def create_data_loader(config: Optional[Dict[str, Any]] = None) -> BaseDataLoader:
    cfg = config or {}
    # Ignore 'dataloader' parameter, use UniversalDataLoader
    dataset_path = cfg.get("dataset_path", "datasets/OpenRCA/Bank")
    timezone = cfg.get("default_timezone", "Asia/Shanghai")
    
    # Auto-correct dataset_path if it points to a specific date directory
    path_obj = Path(dataset_path)
    if path_obj.exists() and path_obj.is_dir():
        import re
        # Check if directory name matches YYYY-MM-DD
        if re.match(r'^\d{4}-\d{2}-\d{2}$', path_obj.name):
            # If so, use parent directory as root
            dataset_path = str(path_obj.parent)

    return UniversalDataLoader(dataset_path, default_timezone=timezone)

# Kept for backward compatibility or internal usage if needed
register_data_loader("openrca", lambda dataset_path, default_timezone="Asia/Shanghai": OpenRCADataLoader(dataset_path, default_timezone=default_timezone))
