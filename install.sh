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

# --- 1. Environment Check ---
print_header
print_step 1 4 "Checking Environment"

# Node.js Check
if ! command -v node &> /dev/null; then
  print_error "Node.js not found. Please install Node.js (>=18.0.0)."
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

# Ansible Check (Required for diagnostic logic)
if ! command -v ansible &> /dev/null; then
  print_error "Ansible not found. Witty Agent requires Ansible for remote diagnostics."
  echo -e "   ${ARROW} Install guide: https://docs.ansible.com/ansible/latest/installation_guide/"
  exit 1
fi
ANSIBLE_VERSION=$(ansible --version | head -n 1 | awk '{print $2}')
print_success "Ansible $ANSIBLE_VERSION detected"

# OpenCode Check (Optional but recommended)
if ! command -v opencode &> /dev/null; then
  print_warning "OpenCode not found in PATH. You'll need it to run the plugin."
else
  print_success "OpenCode detected"
fi

echo ""

# --- 2. Dependency Installation ---
print_step 2 4 "Installing Dependencies"
if npm install; then
  print_success "Dependencies installed successfully"
else
  print_error "npm install failed. Please check your network or proxy settings."
  exit 1
fi
echo ""

# --- 3. Project Build ---
print_step 3 4 "Building Project"
if npm run build; then
  print_success "Project built successfully (dist/ created)"
else
  print_error "Build failed. Check the logs above for errors."
  exit 1
fi
echo ""

# --- 4. Plugin Registration ---
print_step 4 4 "Initializing Configuration"
echo -e "${CYAN}Launching Witty Installer...${NC}"
echo ""

# Execute the built CLI installer
# We use 'node dist/cli.js install' directly
if [ -f "dist/cli.js" ]; then
  node dist/cli.js install
else
  print_error "CLI entry point (dist/cli.js) not found after build."
  exit 1
fi

echo ""
echo -e "${LAUNCH} ${GREEN}${BOLD}All steps completed!${NC}"
echo -e "You can now start using Witty Diagnosis Agent via ${CYAN}opencode${NC}."
echo ""
echo -e "${BLUE}====================================================${NC}"
