#!/bin/bash
# crash_config.sh - Manage crash tool configuration

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CONFIG_FILE="${HOME}/.crash_analyzer.conf"

usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    set     - Set configuration parameters
    show    - Display current configuration
    test    - Test configuration validity
    run     - Launch crash with saved configuration

Options for 'set':
    --vmlinux <path>    Path to vmlinux kernel image
    --vmcore <path>     Path to vmcore dump file
    --crash <path>      Path to crash command (default: crash)

Examples:
    $0 set --vmlinux /usr/lib/debug/vmlinux --vmcore /var/crash/vmcore
    $0 show
    $0 test
    $0 run
EOF
    exit 1
}

set_config() {
    local vmlinux="" vmcore="" crash_cmd="crash"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vmlinux)
                vmlinux="$2"
                shift 2
                ;;
            --vmcore)
                vmcore="$2"
                shift 2
                ;;
            --crash)
                crash_cmd="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done
    
    # Update config file
    : > "$CONFIG_FILE"
    [[ -n "$vmlinux" ]] && echo "VMLINUX_PATH=$vmlinux" >> "$CONFIG_FILE"
    [[ -n "$vmcore" ]] && echo "VMCORE_PATH=$vmcore" >> "$CONFIG_FILE"
    echo "CRASH_CMD=$crash_cmd" >> "$CONFIG_FILE"
    
    echo -e "${GREEN}Configuration saved to $CONFIG_FILE${NC}"
}

show_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}No configuration file found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Current Configuration:${NC}"
    cat "$CONFIG_FILE"
}

test_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}No configuration file found${NC}"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    local errors=0
    
    # Check crash command
    if ! command -v "$CRASH_CMD" &> /dev/null; then
        echo -e "${RED}✗ crash command not found: $CRASH_CMD${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✓ crash command found: $CRASH_CMD${NC}"
    fi
    
    # Check vmlinux
    if [[ ! -f "$VMLINUX_PATH" ]]; then
        echo -e "${RED}✗ vmlinux not found: $VMLINUX_PATH${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✓ vmlinux found: $VMLINUX_PATH${NC}"
    fi
    
    # Check vmcore
    if [[ ! -f "$VMCORE_PATH" ]]; then
        echo -e "${RED}✗ vmcore not found: $VMCORE_PATH${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✓ vmcore found: $VMCORE_PATH${NC}"
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo -e "\n${GREEN}Configuration is valid!${NC}"
    else
        echo -e "\n${RED}Found $errors error(s)${NC}"
        exit 1
    fi
}

run_crash() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}No configuration file found. Run '$0 set' first${NC}"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    echo -e "${GREEN}Launching crash...${NC}"
    echo "Command: $CRASH_CMD $VMLINUX_PATH $VMCORE_PATH"
    echo ""
    
    exec "$CRASH_CMD" "$VMLINUX_PATH" "$VMCORE_PATH"
}

# Main
case "${1:-}" in
    set)
        shift
        set_config "$@"
        ;;
    show)
        show_config
        ;;
    test)
        test_config
        ;;
    run)
        run_crash
        ;;
    *)
        usage
        ;;
esac