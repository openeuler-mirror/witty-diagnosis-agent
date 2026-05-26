# Collect Data Command

## Overview

The `collect-data` command collects system data and metrics without performing analysis. It's useful for gathering baseline data, creating system snapshots, or preparing data for offline analysis.

## Usage

```bash
# Collect all system data
collect-data

# Collect specific data types
collect-data --type system
collect-data --type network
collect-data --type storage
collect-data --type processes

# With output options
collect-data --output /path/to/data.json
collect-data --format json
collect-data --compress

# For specific time period
collect-data --duration 300  # 5 minutes
collect-data --interval 10   # 10-second intervals
```

## Command Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--type` | `-t` | Data type to collect | `all` |
| `--output` | `-o` | Output file or directory | None (stdout) |
| `--format` | `-f` | Output format (json, yaml, csv) | `json` |
| `--compress` | `-c` | Compress output data | `false` |
| `--duration` | `-d` | Collection duration in seconds | `60` |
| `--interval` | `-i` | Collection interval in seconds | `1` |
| `--verbose` | `-v` | Enable verbose output | `false` |
| `--quiet` | `-q` | Suppress non-essential output | `false` |
| `--help` | `-h` | Show help message | N/A |

## Data Types

### System Data
- CPU information and usage
- Memory information and usage
- Disk information and usage
- System load averages
- Uptime and boot time
- Kernel version and parameters
- Hardware information

### Network Data
- Network interfaces and configurations
- Connection statistics
- Routing tables
- DNS configuration
- Network services status
- Firewall rules

### Storage Data
- Disk partitions and filesystems
- Mount points and options
- Storage device information
- RAID configurations
- LVM configurations
- Filesystem usage and inodes

### Process Data
- Running processes
- Process resource usage
- Service status
- Cron jobs
- Systemd units
- User sessions

### Log Data
- System log excerpts
- Application log excerpts
- Security log excerpts
- Kernel log messages
- Audit log entries

## Examples

### Collect Comprehensive System Snapshot
```bash
collect-data --output system_snapshot.json --format json --compress
```

### Collect Network Data for 5 Minutes
```bash
collect-data --type network --duration 300 --interval 5 --output network_data.json
```

### Collect Real-time System Metrics
```bash
collect-data --type system --duration 60 --interval 1 --format csv --output metrics.csv
```

## Output Formats

### JSON Format (Default)
```json
{
  "timestamp": "2026-02-03T17:30:00Z",
  "collection_duration": 60,
  "collection_interval": 1,
  "data_types": ["system", "network", "storage"],
  "system": {
    "cpu": {
      "cores": 8,
      "usage_percent": 45.2,
      "load_average": [1.2, 1.5, 1.8]
    },
    "memory": {
      "total_gb": 16,
      "used_gb": 8.2,
      "available_gb": 7.8
    }
  },
  "network": {
    "interfaces": [
      {
        "name": "eth0",
        "ip_address": "192.168.1.100",
        "rx_bytes": 10245789,
        "tx_bytes": 8945621
      }
    ]
  }
}
```

### CSV Format
```csv
timestamp,cpu_usage,memory_used,disk_used,network_rx
2026-02-03T17:30:00Z,45.2,8.2,65.3,10245789
2026-02-03T17:30:01Z,46.1,8.3,65.3,10245890
```

### YAML Format
```yaml
timestamp: 2026-02-03T17:30:00Z
collection_duration: 60
collection_interval: 1
data_types:
  - system
  - network
system:
  cpu:
    cores: 8
    usage_percent: 45.2
    load_average: [1.2, 1.5, 1.8]
```

## Data Collection Methods

### Direct System Calls
- `/proc` filesystem access
- `sysctl` commands
- `ps`, `top`, `vmstat` utilities
- `df`, `du`, `lsblk` commands
- `ip`, `ss`, `netstat` commands

### API Calls
- SystemD DBus API
- NetworkManager API
- Hardware detection libraries
- Performance monitoring APIs

### File Reading
- Configuration files (`/etc/*`)
- Log files (`/var/log/*`)
- Status files (`/sys/*`, `/proc/*`)

## Performance Considerations

- Collection interval affects system load
- Large datasets may require compression
- Disk I/O can impact performance during collection
- Network collection may affect network performance
- Consider using `--quiet` for minimal impact

## Security Considerations

- Some data collection requires root privileges
- Sensitive data may be included in output
- Use appropriate file permissions for output files
- Consider data anonymization for sharing
- Be mindful of privacy regulations

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Data collection completed successfully |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Insufficient permissions |
| 4 | Output file error |
| 5 | Data collection timeout |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATA_COLLECTION_DIR` | Directory for collected data | `/tmp/witty-data` |
| `DATA_COLLECTION_FORMAT` | Default output format | `json` |
| `DATA_COLLECTION_COMPRESS` | Enable compression by default | `false` |
| `DATA_COLLECTION_TIMEOUT` | Collection timeout in seconds | `3600` |

## Related Commands

- `diagnose` - Collect data and perform analysis
- `analyze-logs` - Specifically collect and analyze logs
- `health-check` - Quick data collection for health assessment

## Notes

- Data collection may temporarily increase system load
- Consider scheduling collection during off-peak hours
- Output files can grow large for long collection periods
- Use compression for long-term storage
- Data format compatibility may vary between versions