#!/usr/bin/env python3
import os
import shutil
import argparse
import paramiko
import sys
import uuid
import tarfile
import logging
import tempfile
import re
from datetime import datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from rich.console import Console
from rich.logging import RichHandler
from tqdm import tqdm

try:
    import yaml
except ImportError:
    print("PyYAML not found. Please install it: pip install PyYAML")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level="INFO",
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger("log_fetcher")

# --- Configuration Management ---

class ConfigLoader:
    def __init__(self, config_path="config/rca_config.yaml"):
        self.config_path = Path(config_path)
        if not self.config_path.is_absolute():
            # Assume relative to project root (2 levels up from this script location: scripts -> fault-background-info -> skills -> .claude -> root)
            # Actually, let's find the config relative to this script or current working dir.
            # Best effort: look in CWD/config or script_dir/../../../../config
            
            # Strategy: If running from root, config/rca_config.yaml exists.
            if Path("config/rca_config.yaml").exists():
                self.config_path = Path("config/rca_config.yaml")
            else:
                # Fallback: relative to script
                script_dir = Path(__file__).resolve().parent
                # script is in .claude/skills/fault-background-info/scripts
                # root is 5 levels up? .claude/skills/fault-background-info/scripts -> fault-background-info -> skills -> .claude -> rca-agent-skill
                root_dir = script_dir.parents[4] 
                self.config_path = root_dir / "config" / "rca_config.yaml"

    def load(self):
        if not self.config_path.exists():
            logger.warning(f"Config file not found at {self.config_path}. Using empty config.")
            return {}
            
        with open(self.config_path, 'r') as f:
            content = f.read()
        
        # Simple env var substitution
        # Matches ${VAR_NAME}
        pattern = re.compile(r'\$\{([^}^{]+)\}')
        
        def replace(match):
            env_var = match.group(1)
            return os.environ.get(env_var, "") # Return empty string if not set, or maybe raise error?
            
        content = pattern.sub(replace, content)
        
        return yaml.safe_load(content)

# --- Log Fetcher Abstraction ---

class LogFetcher:
    def __init__(self, config):
        self.config = config
        self.dataset_root = Path(config.get("common", {}).get("dataset_root", "datasets"))
        
    def get_unique_filename(self, directory, filename):
        base, ext = os.path.splitext(filename)
        name = base + ext
        counter = 1
        while (directory / name).exists():
            name = f"{base}_{counter}{ext}"
            counter += 1
        return name

    def is_within_directory(self, directory, target):
        abs_directory = os.path.abspath(directory)
        abs_target = os.path.abspath(target)
        prefix = os.path.commonprefix([abs_directory, abs_target])
        return prefix == abs_directory

    def safe_extract(self, tar, path=".", members=None, *, numeric_owner=False):
        for member in tar.getmembers():
            member_path = os.path.join(path, member.name)
            if not self.is_within_directory(path, member_path):
                raise Exception(f"Attempted Path Traversal in Tar File: {member.name}")
        tar.extractall(path, members, numeric_owner=numeric_owner)

    def fetch_local(self, src_dir: str, target_dir: Path, files_map: dict):
        logger.info(f"Fetching logs locally from {src_dir}")
        base_path = Path(src_dir)
        success_count = 0
        
        for dest_name, src_pattern in files_map.items():
            if os.path.isabs(src_pattern):
                src_file = Path(src_pattern)
            else:
                src_file = base_path / src_pattern

            if src_file.exists():
                try:
                    shutil.copy2(src_file, target_dir / dest_name)
                    logger.info(f"Copied {src_file} -> {dest_name}")
                    success_count += 1
                except Exception as e:
                    logger.error(f"Error copying {src_file}: {e}")
            else:
                logger.warning(f"Log file not found: {src_file}")
                
        return success_count > 0

    def fetch_remote(self, host, port, user, password, files_map: dict, target_dir: Path, is_super_node=False, super_node_special_ip_dir=None, remote_base_dir=None):
        """
        Fetches logs from a single remote node.
        If is_super_node is True, handles the specific directory structure and special files.
        """
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(hostname=host, port=port, username=user, password=password, timeout=10)
            
            # 1. Create remote temp dir
            stdin, stdout, stderr = ssh.exec_command("mktemp -d")
            remote_tmp_dir = stdout.read().decode().strip()
            if not remote_tmp_dir:
                raise Exception("Failed to create remote temp directory")
                
            # 2. Gather files
            files_to_tar = []
            
            # In super_node mode, files_map keys are paths, values are paths (or list of paths)
            # In disk_fault mode, files_map is dest_name -> src_path
            
            if is_super_node:
                # Check existence
                sftp = ssh.open_sftp()
                for fpath in files_map.keys(): # In super_node, we passed a list converted to dict or just list
                    try:
                        sftp.stat(fpath)
                        files_to_tar.append(fpath)
                    except IOError:
                        pass
                sftp.close()
            else:
                # Disk fault mode: we know the files we want, we copy them to temp first
                 for dest_name, src_path in files_map.items():
                    # Handle relative paths if remote_base_dir is set
                    if remote_base_dir and not os.path.isabs(src_path):
                        full_src_path = str(Path(remote_base_dir) / src_path).replace("\\", "/")
                    else:
                        full_src_path = src_path

                    remote_dest = f"{remote_tmp_dir}/{dest_name}"
                    # Try copy (sudo fallback)
                    cmd = f"cp '{full_src_path}' '{remote_dest}' 2>/dev/null || sudo -n cp '{full_src_path}' '{remote_dest}'"
                    ssh.exec_command(cmd)
                    # chmod
                    ssh.exec_command(f"sudo -n chmod a+r '{remote_dest}' || chmod a+r '{remote_dest}'")
                    # We assume it worked for now, tar will verify
                    files_to_tar.append(dest_name) # These are relative to remote_tmp_dir

            if not files_to_tar:
                logger.warning(f"[{host}] No files found.")
                ssh.exec_command(f"rm -rf {remote_tmp_dir}")
                ssh.close()
                return False

            # 3. Compress
            remote_archive = f"{remote_tmp_dir}/logs_archive.tar.gz"
            if is_super_node:
                files_str = " ".join(files_to_tar)
                cmd = f"tar -czf {remote_archive} {files_str} 2>/dev/null"
            else:
                # cd to temp dir and tar everything
                cmd = f"cd '{remote_tmp_dir}' && tar -czf logs_archive.tar.gz *"
                
            stdin, stdout, stderr = ssh.exec_command(cmd)
            if stdout.channel.recv_exit_status() != 0:
                 # Check if archive exists (tar warnings)
                 pass 

            # 4. Download
            local_archive = target_dir / f"logs_{host}_{uuid.uuid4().hex}.tar.gz"
            sftp = ssh.open_sftp()
            try:
                sftp.get(remote_archive, str(local_archive))
            except Exception as e:
                logger.error(f"[{host}] Download failed: {e}")
                return False
            finally:
                sftp.close()
                
            # 5. Cleanup Remote
            ssh.exec_command(f"rm -rf {remote_tmp_dir}")
            ssh.close()
            
            # 6. Extract
            if is_super_node:
                # Super node extraction logic (flatten/rename/special handling)
                with tarfile.open(local_archive, "r:gz") as tar:
                    # Extract to temp
                    with tempfile.TemporaryDirectory() as temp_extract_dir:
                        self.safe_extract(tar, path=temp_extract_dir)
                        temp_extract_path = Path(temp_extract_dir)
                        
                        for member in tar.getmembers():
                            if member.isfile():
                                filename = os.path.basename(member.name)
                                src_file = temp_extract_path / member.name
                                
                                # Special handling for ub_link.log
                                if filename == "ub_link.log" and super_node_special_ip_dir:
                                    final_name = self.get_unique_filename(super_node_special_ip_dir, filename)
                                    shutil.move(str(src_file), super_node_special_ip_dir / final_name)
                                else:
                                    final_name = self.get_unique_filename(target_dir, filename)
                                    shutil.move(str(src_file), target_dir / final_name)
            else:
                # Disk fault extraction (keep structure or flat?)
                # The original script extracted to target_dir directly
                with tarfile.open(local_archive, "r:gz") as tar:
                    self.safe_extract(tar, path=target_dir)
                    
            # Remove archive
            if local_archive.exists():
                os.remove(local_archive)
                
            logger.info(f"[{host}] Logs fetched successfully.")
            return True

        except Exception as e:
            logger.error(f"[{host}] Error: {e}")
            return False

# --- Scenario Logic ---

def run_disk_fault_fetch(args, config, fetcher):
    sc_config = config.get("scenarios", {}).get("disk_fault", {})
    remote_config = sc_config.get("remote", {})
    
    target_dir = fetcher.dataset_root / "DiskFault" / args.date
    if target_dir.exists():
        shutil.rmtree(target_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    
    files_map = sc_config.get("files", {})
    if not files_map:
         # Fallback to defaults if config missing
         files_map = {
            "app.log": "app.log",
            "kernel.log": "kernel.log",
            "messages.log": "/var/log/messages"
        }
    
    mode = args.mode or sc_config.get("default_mode", "local")
    
    if mode == 'local':
        fetcher.fetch_local(args.local_dir, target_dir, files_map)
    else:
        # Prioritize args > config > defaults
        host = args.host or remote_config.get("host")
        port = args.port or remote_config.get("port", 22)
        user = args.user or remote_config.get("user")
        
        # Password handling
        password = args.password
        if not password:
            password = remote_config.get("password")
            if not password:
                # Check for password_env in config
                env_var = remote_config.get("password_env")
                if env_var:
                    password = os.environ.get(env_var)
        
        if not host or not user or not password:
            logger.error("Missing remote credentials (host, user, or password). Check args or config/env vars.")
            return

        remote_dir = args.remote_dir or remote_config.get("remote_dir")

        fetcher.fetch_remote(host, port, user, password, files_map, target_dir, is_super_node=False, remote_base_dir=remote_dir)

def run_super_node_fetch(args, config, fetcher):
    sc_config = config.get("scenarios", {}).get("super_node", {})
    cred_config = sc_config.get("credentials", {})
    
    date_str = args.date
    base_target = fetcher.dataset_root / "SuperNode" / date_str
    if base_target.exists():
        shutil.rmtree(base_target)
    base_target.mkdir(parents=True, exist_ok=True)
    
    if args.servers:
        servers = args.servers
    else:
        lenders = sc_config.get("lenders", [])
        borrowers = sc_config.get("borrowers", [])
        servers = lenders + borrowers
        # Remove duplicates while preserving order
        servers = list(dict.fromkeys(servers))

    if not servers:
        logger.error("No servers specified (args or config lenders/borrowers).")
        return

    special_ip = sc_config.get("special_ip", "special_node")
    
    # Pre-create special dir
    special_target_dir = base_target / special_ip
    special_target_dir.mkdir(parents=True, exist_ok=True)
    
    user = args.user or cred_config.get("user")
    password = args.password
    if not password:
        password = cred_config.get("password")
        if not password:
            env_var = cred_config.get("password_env")
            if env_var:
                password = os.environ.get(env_var)
            
    if not user or not password:
        logger.error("Missing credentials (user or password). Check args or config/env vars.")
        return

    file_list = sc_config.get("files", [])
    
    # Using tqdm for progress
    with tqdm(total=len(servers), desc="Fetching Logs", unit="server") as pbar:
        with ThreadPoolExecutor(max_workers=len(servers)) as executor:
            futures = []
            for ip in servers:
                # Target dir for this IP
                ip_dir = base_target / ip
                ip_dir.mkdir(parents=True, exist_ok=True)
                
                files_map = {f: f for f in file_list}
                
                futures.append(executor.submit(
                    fetcher.fetch_remote,
                    host=ip,
                    port=22,
                    user=user,
                    password=password,
                    files_map=files_map,
                    target_dir=ip_dir,
                    is_super_node=True,
                    super_node_special_ip_dir=special_target_dir
                ))
            
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    logger.error(f"Thread Error: {e}")
                finally:
                    pbar.update(1)

def main():
    # Load config
    config_loader = ConfigLoader()
    config = config_loader.load()
    
    fetcher = LogFetcher(config)

    parser = argparse.ArgumentParser(description="Unified Log Fetcher")
    subparsers = parser.add_subparsers(dest="scenario", required=True)
    
    # Disk Fault Parser
    df_parser = subparsers.add_parser("disk_fault", help="Fetch logs for disk fault scenario")
    df_parser.add_argument("--mode", choices=["local", "remote"])
    df_parser.add_argument("--date", default=datetime.now().strftime("%Y-%m-%d"))
    df_parser.add_argument("--local-dir", default=".")
    df_parser.add_argument("--host")
    df_parser.add_argument("--port", type=int)
    df_parser.add_argument("--user")
    df_parser.add_argument("--password")
    df_parser.add_argument("--remote-dir", help="Base directory for remote logs (for relative paths)")

    # Super Node Parser
    sn_parser = subparsers.add_parser("super_node", help="Fetch logs for super node scenario")
    sn_parser.add_argument("--date", default=datetime.now().strftime("%Y-%m-%d"))
    sn_parser.add_argument("--servers", nargs="+", help="List of server IPs")
    sn_parser.add_argument("--user")
    sn_parser.add_argument("--password")

    args = parser.parse_args()
    
    if args.scenario == "disk_fault":
        run_disk_fault_fetch(args, config, fetcher)
    elif args.scenario == "super_node":
        run_super_node_fetch(args, config, fetcher)

if __name__ == "__main__":
    main()
