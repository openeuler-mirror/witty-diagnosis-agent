#!/bin/bash

# Witty Diagnosis Agent - One-Click Installer
# High-performance, automated setup for openEuler diagnostic agent.

set -e

# --- Colors & Symbols ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

CHECK="✅"
ERROR="❌"
STEP="📦"
LAUNCH="🚀"
ARROW="➜"

# --- Functions ---
print_header() {
  echo -e "${BLUE}${BOLD}====================================================${NC}"
  echo -e "${CYAN}${BOLD}       Witty Diagnosis Agent - Installer           ${NC}"
  echo -e "${BLUE}${BOLD}====================================================${NC}"
  echo ""
}

print_step() {
  echo -e "${STEP} ${BOLD}[$1/$2] $3...${NC}"
}

print_success() {
  echo -e "${GREEN}${CHECK} $1${NC}"
}

print_error() {
  echo -e "${RED}${ERROR} $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

ensure_writable_path() {
  local file_path="$1"
  if [ -e "$file_path" ] && [ ! -w "$file_path" ]; then
    chmod u+w "$file_path" 2>/dev/null || {
      print_error "Cannot write to ${file_path}. Please update its permissions and rerun install.sh."
      exit 1
    }
  fi
}

replace_xiaoo_witty_config() {
  local config_file="$1"
  local source_config="$2"
  local tmp_file="${config_file}.tmp"
  local fragment_file="${config_file}.witty.tmp"

  awk '
    function is_table_header(line) {
      return line ~ /^\[[A-Za-z0-9_.-]+\]/
    }

    function is_witty_section(name) {
      return name == "agent.fuxi" ||
        name == "agent.fuxi.tools" ||
        name == "agent.kuafu" ||
        name == "agent.kuafu.tools" ||
        name == "agent.dayu" ||
        name == "agent.dayu.tools" ||
        name == "agent.xuanyuan" ||
        name == "agent.xuanyuan.tools" ||
        name == "agent.baize" ||
        name == "agent.baize.tools" ||
        name == "subagent.fuxi" ||
        name == "subagent.fuxi.tools" ||
        name == "subagent.dayu" ||
        name == "subagent.dayu.tools" ||
        name == "subagent.kuafu" ||
        name == "subagent.kuafu.tools" ||
        name == "subagent.baize" ||
        name == "subagent.baize.tools"
    }

    function toggles_multiline(line) {
      return line ~ /'\'''\'''\''/ || line ~ /"""/
    }

    /^# >>> witty-diagnosis-agent xiaoO config >>>$/ { marker_skip = 1; next }
    /^# <<< witty-diagnosis-agent xiaoO config <<<$/{ marker_skip = 0; next }
    marker_skip { next }

    in_multiline {
      if (!section_skip) print
      if (toggles_multiline($0)) in_multiline = 0
      next
    }

    is_table_header($0) {
      section = $0
      sub(/^\[/, "", section)
      sub(/\].*$/, "", section)
      section_skip = is_witty_section(section)
    }

    /^\[/ && !is_table_header($0) { next }
    /WittyDiagnosisAgent/ && section_skip == 0 { next }
    /Predefined subagent roles for Xuanyuan delegation/ && section_skip == 0 { next }

    !section_skip { print }
    toggles_multiline($0) { in_multiline = 1 }
  ' "$config_file" > "$tmp_file"

  awk '
    function is_table_header(line) {
      return line ~ /^\[[A-Za-z0-9_.-]+\]/
    }

    function is_witty_section(name) {
      return name == "agent.fuxi" ||
        name == "agent.fuxi.tools" ||
        name == "agent.kuafu" ||
        name == "agent.kuafu.tools" ||
        name == "agent.dayu" ||
        name == "agent.dayu.tools" ||
        name == "agent.xuanyuan" ||
        name == "agent.xuanyuan.tools" ||
        name == "agent.baize" ||
        name == "agent.baize.tools" ||
        name == "subagent.fuxi" ||
        name == "subagent.fuxi.tools" ||
        name == "subagent.dayu" ||
        name == "subagent.dayu.tools" ||
        name == "subagent.kuafu" ||
        name == "subagent.kuafu.tools" ||
        name == "subagent.baize" ||
        name == "subagent.baize.tools"
    }

    function toggles_multiline(line) {
      return line ~ /'\'''\'''\''/ || line ~ /"""/
    }

    in_multiline {
      if (section_keep) print
      if (toggles_multiline($0)) in_multiline = 0
      next
    }

    is_table_header($0) {
      section = $0
      sub(/^\[/, "", section)
      sub(/\].*$/, "", section)
      section_keep = is_witty_section(section)
    }

    section_keep || /WittyDiagnosisAgent/ || /Predefined subagent roles for Xuanyuan delegation/ { print }
    toggles_multiline($0) { in_multiline = 1 }
  ' "$source_config" > "$fragment_file"

  {
    echo ""
    echo "# >>> witty-diagnosis-agent xiaoO config >>>"
    cat "$fragment_file"
    echo "# <<< witty-diagnosis-agent xiaoO config <<<"
  } >> "$tmp_file"

  mv "$tmp_file" "$config_file"
  rm -f "$fragment_file"
}

select_install_target() {
  local selected=0
  local key=""
  local options=("OpenCode" "xiaoO")
  local values=("opencode" "xiaoo")
  local option_count=2
  local dim='\033[2m'

  if [ ! -t 0 ]; then
    print_error "Interactive target selection requires a TTY."
    exit 1
  fi

  draw_target_menu() {
    local i marker color
    echo -e "${CYAN}◆${NC}  Select installation target for Witty Diagnosis Agent / 选择 Witty Diagnosis Agent 的安装目标"
    for i in 0 1; do
      if [ "$i" -eq "$selected" ]; then
        marker="●"
        color="${GREEN}"
      else
        marker="○"
        color="${dim}"
      fi
      printf "  %b%s %s%b\n" "$color" "$marker" "${options[$i]}" "$NC"
    done
  }

  echo ""
  printf '\0337'
  tput civis 2>/dev/null || true
  while true; do
    printf '\0338\033[J'
    draw_target_menu
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 key || true
        case "$key" in
          "[A") selected=$(( (selected + option_count - 1) % option_count )) ;;
          "[B") selected=$(( (selected + 1) % option_count )) ;;
        esac
        ;;
      " ")
        break
        ;;
      $'\n'|$'\r')
        break
        ;;
      "")
        break
        ;;
    esac
  done
  printf '\0338\033[J'
  draw_target_menu
  tput cnorm 2>/dev/null || true
  INSTALL_TARGET="${values[$selected]}"
  echo ""
}

usage() {
  cat <<'USAGE'
Usage: bash install.sh [--language zh|en]

Options:
  --language zh|en   Output language. If omitted, you are prompted interactively.
                     输出语言；省略时在安装过程中交互选择。
  -h, --help         Show this help.

Notes:
  插件实现位于 src/witty，构建产物为 dist/index.js + dist/cli.js。
USAGE
}

# --- Args ---
LANGUAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --language)
      shift
      LANGUAGE="$1"
      if [ "$LANGUAGE" != "zh" ] && [ "$LANGUAGE" != "en" ]; then
        echo "Invalid --language: $LANGUAGE (must be zh or en)"
        usage
        exit 1
      fi
      ;;
    --language=*) LANGUAGE="${1#--language=}"
      if [ "$LANGUAGE" != "zh" ] && [ "$LANGUAGE" != "en" ]; then
        echo "Invalid --language: $LANGUAGE (must be zh or en)"
        usage
        exit 1
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XIAOO_HOME="${XIAOO_HOME:-${HOME}/.xiaoo}"
XIAOO_CONFIG_DIR="${XIAOO_CONFIG_DIR:-${HOME}/.config/xiaoo}"
XIAOO_CONFIG_FILE="${XIAOO_CONFIG_DIR}/config.toml"
XIAOO_ASSETS_DIR="${SCRIPT_DIR}/src/xiaoO"
XIAOO_CONFIG_TEMPLATE="${XIAOO_ASSETS_DIR}/config/config.toml"

# --- Target Detection ---
print_header
print_step 1 5 "Detecting installation target"

HAS_OPENCODE=0
HAS_XIAOO=0
INSTALL_TARGET=""

if command -v opencode &> /dev/null; then
  HAS_OPENCODE=1
  print_success "OpenCode detected"
fi

if command -v xiaoo &> /dev/null; then
  HAS_XIAOO=1
  print_success "xiaoO detected"
fi

if [ "$HAS_OPENCODE" -eq 0 ] && [ "$HAS_XIAOO" -eq 0 ]; then
  print_error "Neither OpenCode nor xiaoO was found in PATH. Please install one of them first."
  exit 1
fi

if [ "$HAS_OPENCODE" -eq 1 ] && [ "$HAS_XIAOO" -eq 1 ]; then
  select_install_target
elif [ "$HAS_OPENCODE" -eq 1 ]; then
  INSTALL_TARGET="opencode"
  print_success "Only OpenCode was detected; installing to OpenCode"
else
  INSTALL_TARGET="xiaoo"
  print_success "Only xiaoO was detected; installing to xiaoO"
fi

install_xiaoo() {
  print_step 3 5 "Installing xiaoO assets"

  if [ ! -d "${SCRIPT_DIR}/skills" ]; then
    print_error "Skills directory not found: ${SCRIPT_DIR}/skills"
    exit 1
  fi

  if [ ! -d "${XIAOO_ASSETS_DIR}/command" ] || [ ! -d "${XIAOO_ASSETS_DIR}/tools" ]; then
    print_error "xiaoO assets not found under ${XIAOO_ASSETS_DIR}"
    exit 1
  fi

  mkdir -p "${XIAOO_HOME}/command" "${XIAOO_HOME}/skills" "${XIAOO_HOME}/tools" "${XIAOO_CONFIG_DIR}"
  cp -R "${SCRIPT_DIR}/skills/." "${XIAOO_HOME}/skills/"
  print_success "xiaoO skills installed ${ARROW} ${XIAOO_HOME}/skills"
  cp -R "${XIAOO_ASSETS_DIR}/command/." "${XIAOO_HOME}/command/"
  print_success "xiaoO command installed ${ARROW} ${XIAOO_HOME}/command"
  cp -R "${XIAOO_ASSETS_DIR}/tools/." "${XIAOO_HOME}/tools/"
  print_success "xiaoO tools installed ${ARROW} ${XIAOO_HOME}/tools"

  if [ ! -f "${XIAOO_CONFIG_TEMPLATE}" ]; then
    print_error "xiaoO config template not found: ${XIAOO_CONFIG_TEMPLATE}"
    exit 1
  fi

  if [ ! -f "${XIAOO_CONFIG_FILE}" ]; then
    cp "${XIAOO_CONFIG_TEMPLATE}" "${XIAOO_CONFIG_FILE}"
    print_success "xiaoO config installed ${ARROW} ${XIAOO_CONFIG_FILE}"
  else
    ensure_writable_path "${XIAOO_CONFIG_FILE}"
    replace_xiaoo_witty_config "${XIAOO_CONFIG_FILE}" "${XIAOO_CONFIG_TEMPLATE}"
    print_success "xiaoO config updated"
  fi

  if [ -e "${XIAOO_CONFIG_FILE}" ] && [ ! -w "${XIAOO_CONFIG_FILE}" ]; then
    chmod u+w "${XIAOO_CONFIG_FILE}" 2>/dev/null || true
  fi
}

echo ""

# --- 2. Common Environment Check ---
print_step 2 5 "Checking Common Environment"

# Ansible Check (Required for diagnostic logic)
if ! command -v ansible &> /dev/null; then
  print_error "Ansible not found. Witty Agent requires Ansible for remote diagnostics."
  echo -e "   ${ARROW} Install guide: https://docs.ansible.com/ansible/latest/installation_guide/"
  exit 1
fi
# Extract just the version number. Handles both new format
# "ansible [core 2.20.3]" and legacy "ansible 2.9.27".
ANSIBLE_VERSION=$(ansible --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
print_success "Ansible ${ANSIBLE_VERSION:-detected}"

ANSIBLE_USER_CFG="${HOME}/.ansible.cfg"
if [ ! -f "$ANSIBLE_USER_CFG" ]; then
  cat <<'EOF' > "$ANSIBLE_USER_CFG"
[defaults]
forks = 50
gathering = explicit

[ssh_connection]
pipelining = true
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
EOF
fi

if [ "$INSTALL_TARGET" = "opencode" ]; then
  # Node.js Check
  if ! command -v node &> /dev/null; then
    print_error "Node.js not found. Please install Node.js (>=20.0.0)."
    exit 1
  fi

  NODE_VERSION=$(node -v | cut -d 'v' -f 2)
  print_success "Node.js v$NODE_VERSION detected"

  # NPM Check
  if ! command -v npm &> /dev/null; then
    print_error "npm not found. Please install npm."
    exit 1
  fi
  print_success "npm detected"
fi

echo ""

if [ "$INSTALL_TARGET" = "xiaoo" ]; then
  install_xiaoo
  echo ""
  echo -e "${LAUNCH} ${GREEN}${BOLD}All steps completed!${NC}"
  echo -e "Witty Diagnosis Agent has been installed to ${CYAN}xiaoO${NC}."
  echo ""
  echo -e "${BLUE}====================================================${NC}"
  exit 0
fi

# --- 3. Dependency Installation ---
print_step 3 5 "Installing Dependencies"
(cd "$SCRIPT_DIR" && npm install)
print_success "Dependencies installed successfully"
echo ""

# --- 4. Project Build ---
print_step 4 5 "Building Project"
(cd "$SCRIPT_DIR" && npm run build)
print_success "Project built successfully (dist/ created)"
echo ""

# --- 5. Plugin Registration ---
print_step 5 5 "Initializing Configuration"

echo -e "${CYAN}Launching Witty Installer...${NC}"
echo ""
# 组装 install 参数：命令行显式给了 --language 则透传（跳过交互），否则交互选择
LANG_ARG=""
if [ -n "$LANGUAGE" ]; then
  LANG_ARG="--language $LANGUAGE"
fi
if [ -f "${SCRIPT_DIR}/dist/cli.js" ]; then
  (cd "$SCRIPT_DIR" && node dist/cli.js install $LANG_ARG)
  echo ""
  (cd "$SCRIPT_DIR" && node dist/cli.js doctor) || print_warning "doctor reported issues (see above)"
else
  print_error "CLI entry point (dist/cli.js) not found after build."
  exit 1
fi

echo ""
echo -e "${LAUNCH} ${GREEN}${BOLD}All steps completed!${NC}"
echo -e "Witty Diagnosis Agent has been installed to ${CYAN}OpenCode${NC}."
echo -e "You can now start using it via ${CYAN}opencode${NC}."
echo ""
echo -e "${BLUE}====================================================${NC}"
