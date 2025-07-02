#!/bin/bash

# Common functions for Baltic DNS project scripts
# This file contains shared functions used across deployment, configuration, and diagnostic scripts

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}======================================${NC}\n"
}

print_step() {
    echo -e "${CYAN}► $1${NC}"
}

print_info() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check if docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        return 1
    fi
    
    return 0
}

# Check if docker-compose is available
check_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        return 0
    elif docker compose version &> /dev/null; then
        return 0
    else
        print_error "Neither docker-compose nor 'docker compose' is available"
        return 1
    fi
}

# Get docker compose command (prefer 'docker compose' over 'docker-compose')
get_docker_compose_cmd() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        print_error "No docker compose command found"
        return 1
    fi
}

# Wait for user confirmation
confirm() {
    local message="$1"
    echo -e "${YELLOW}$message (y/N): ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if port is available
check_port() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

# Check service status
check_service_status() {
    local service_name="$1"
    local compose_cmd="$2"
    
    if $compose_cmd ps "$service_name" 2>/dev/null | grep -q "Up"; then
        return 0  # Service is running
    else
        return 1  # Service is not running
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local compose_cmd="$2"
    local max_attempts="${3:-30}"
    local attempt=1
    
    print_step "Waiting for $service_name to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if check_service_status "$service_name" "$compose_cmd"; then
            print_info "$service_name is ready"
            return 0
        fi
        
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    print_error "$service_name failed to start within $((max_attempts * 2)) seconds"
    return 1
}

# Get system info
get_system_info() {
    echo "System Information:"
    echo "==================="
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -s)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Memory: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Disk Space: $(df -h / | awk 'NR==2 {print $4 " available"}')"
    echo "Docker Version: $(docker --version 2>/dev/null || echo "Not installed")"
    echo "Docker Compose: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "Not available")"
    echo ""
}

# Backup file if it exists
backup_file() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        local backup_path="${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file_path" "$backup_path"
        print_info "Backed up $file_path to $backup_path"
    fi
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir_path="$1"
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
        print_info "Created directory: $dir_path"
    fi
}

# Check if file exists and is readable
check_file() {
    local file_path="$1"
    if [[ -f "$file_path" && -r "$file_path" ]]; then
        return 0
    else
        return 1
    fi
}

# Get timestamp for logging
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Log message with timestamp
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(get_timestamp)] [$level] $message"
}

# Export functions so they can be used by scripts that source this file
export -f print_header print_step print_info print_warning print_error print_success
export -f check_root check_docker check_docker_compose get_docker_compose_cmd
export -f confirm check_port check_service_status wait_for_service
export -f get_system_info backup_file ensure_directory check_file
export -f get_timestamp log_message