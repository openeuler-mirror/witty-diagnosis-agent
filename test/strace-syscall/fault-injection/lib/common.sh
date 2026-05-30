# ================================================================
# common.sh - Shared helper functions for fault injection scripts
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_IMAGE="strace-fault-injection:latest"
OUTPUT_DIR="${SCRIPT_DIR}/output"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Check prerequisites
check_prereqs() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}[ERROR] Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi

    if ! docker info &>/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Docker daemon is not running or user lacks permissions.${NC}"
        echo "  Try: sudo usermod -aG docker ${USER} && newgrp docker"
        exit 1
    fi
}

# Build Docker image if not already built
ensure_image() {
    if ! docker image inspect "${DOCKER_IMAGE}" &>/dev/null 2>&1; then
        echo -e "${YELLOW}[BUILD] Building Docker image '${DOCKER_IMAGE}'...${NC}"
        docker build -t "${DOCKER_IMAGE}" "${SCRIPT_DIR}"
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERROR] Docker build failed.${NC}"
            exit 1
        fi
        echo -e "${GREEN}[BUILD] Image built successfully.${NC}"
    fi
}

# Generate a timestamp-based container name
container_name() {
    local branch="$1"
    local mode="$2"
    echo "strace-fi-${branch}-${mode}-$(date +%s)"
}

# Generate output file path for strace log
output_path() {
    local branch="$1"
    local mode="$2"
    local ts=$(date +%Y%m%d%H%M%S)
    echo "${OUTPUT_DIR}/${branch}_${mode}_${ts}"
}

# Print section header
print_header() {
    echo ""
    echo "============================================================"
    echo -e "${BLUE}$1${NC}"
    echo "============================================================"
}

# Print info message
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Print warning
print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Print error
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
