#!/bin/bash
# Multi-Report-OMV v2.0
# Core utilities module
# Based on SnapRAID Manager utils architecture

# Detect script location if not provided
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# -------------------------------------------------------
# VERSION MANAGEMENT
# -------------------------------------------------------

# Get the current version from VERSION file
get_version() {
    if [ -f "$BASE_DIR/VERSION" ]; then
        cat "$BASE_DIR/VERSION" 2>/dev/null | tr -d '\n\r' | head -1
    else
        echo "Unknown Version"
    fi
}

# Get the version with application name
get_full_version() {
    echo "Multi-Report-OMV $(get_version)"
}

# -------------------------------------------------------
# ENVIRONMENT MANAGEMENT
# -------------------------------------------------------

# Export environment variables to be used across all modules and plugins
export_environment() {
    # Core system paths
    export BASE_DIR
    export PLUGIN_DIR="${BASE_DIR}/plugins"
    export CONFIG_BASE
    export LOG_BASE
    export TMP_BASE
    
    # Core utilities
    export -f get_version
    export -f get_full_version
    export -f log_debug
    export -f log_info
    export -f log_warning
    export -f log_error
    export -f is_root
    export -f elevate_privileges
    
    log_debug "Environment variables exported"
}

# -------------------------------------------------------
# SYSTEM VALIDATION
# -------------------------------------------------------

# Check if running on OpenMediaVault
check_omv_version() {
    if [ -f "/etc/default/openmediavault" ]; then
        local omv_version=$(grep -oP 'OMV_VERSION="\K[^"]+' /etc/default/openmediavault 2>/dev/null)
        
        # If pattern didn't work, try simpler approach
        if [ -z "$omv_version" ]; then
            omv_version=$(grep 'OMV_VERSION=' /etc/default/openmediavault 2>/dev/null | cut -d'"' -f2)
        fi
        
        # Fallback to checking installed package
        if [ -z "$omv_version" ] && command -v dpkg-query >/dev/null 2>&1; then
            omv_version=$(dpkg-query -W -f='${Version}' openmediavault 2>/dev/null | cut -d'-' -f1)
        fi
        
        omv_version="${omv_version:-Unknown}"
        log_info "OpenMediaVault detected: Version $omv_version"
        export OMV_VERSION="$omv_version"
        return 0
    else
        log_warning "OpenMediaVault not detected"
        return 1
    fi
}

# Check if running as root
check_root_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    fi
    return 0
}

# Helper function - check if running as root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Elevate privileges if needed (wrapper for sudo management)
# This function should be called by plugins/commands that need root access
elevate_privileges() {
    # Skip if already root
    if is_root; then
        return 0
    fi
    
    # Initialize sudo keepalive if not already done
    if [ "${SUDO_PRIVILEGES_INITIALIZED:-false}" != "true" ]; then
        # This will be called from main script which has init_sudo_privileges
        log_error "Sudo privileges not initialized. This is a programming error."
        return 1
    fi
    
    return 0
}

# Validate system requirements
validate_system() {
    log_info "Validating system requirements"
    
    local has_warnings=false
    
    # Check root privileges (but only warn if sudo is also not available)
    if ! check_root_privileges; then
        # Check if sudo privileges have been initialized successfully
        if [ "${SUDO_PRIVILEGES_INITIALIZED:-false}" != "true" ]; then
            log_warning "Not running as root. SMART access requires root privileges."
            log_warning "Run with: sudo ./bin/multi-report-omv"
            has_warnings=true
        fi
    fi
    
    # Add sbin directories to PATH for smartctl
    export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"
    
    # Check for smartctl
    if ! command -v smartctl >/dev/null 2>&1; then
        log_warning "smartctl not found. SMART monitoring will not work. Install smartmontools package."
        has_warnings=true
    else
        log_debug "smartctl found: $(command -v smartctl)"
    fi
    
    # Check for mail command (optional)
    if ! command -v mail >/dev/null 2>&1; then
        log_warning "mail command not found. Email notifications will not work"
    fi
    
    # Check OMV
    check_omv_version || log_warning "Not running on OpenMediaVault"
    
    if [ "$has_warnings" = true ]; then
        log_info "System validation completed with warnings"
    else
        log_info "System validation completed"
    fi
    return 0
}

# -------------------------------------------------------
# FILE VALIDATION
# -------------------------------------------------------

# Validate required file exists
validate_required_file() {
    local file_path="$1"
    local file_description="$2"
    local component="${3:-system}"
    
    if [ ! -f "$file_path" ]; then
        log_error "$component: $file_description not found: $file_path"
        return 1
    fi
    
    if [ ! -r "$file_path" ]; then
        log_error "$component: $file_description not readable: $file_path"
        return 1
    fi
    
    log_debug "$component: $file_description validated: $file_path"
    return 0
}

# -------------------------------------------------------
# TEMPORARY DIRECTORY MANAGEMENT
# -------------------------------------------------------

# Initialize temporary directory
init_temp_dir() {
    # Use configuration or default
    TMP_DIR="${TMP_BASE:-$BASE_DIR/tmp}/run-$(date +%Y%m%d-%H%M%S)"
    
    if [ ! -d "$TMP_DIR" ]; then
        if ! mkdir -p "$TMP_DIR" 2>/dev/null; then
            log_error "Failed to create temp directory: $TMP_DIR"
            return 1
        fi
    fi
    
    chmod 700 "$TMP_DIR" 2>/dev/null
    
    # Create subdirectories
    mkdir -p "$TMP_DIR/plugins" "$TMP_DIR/reports" "$TMP_DIR/data" 2>/dev/null
    
    # Register cleanup
    register_cleanup "temp_dir_cleanup" "rm -rf \"$TMP_DIR\" 2>/dev/null"
    
    log_debug "Temporary directory created: $TMP_DIR"
    export TMP_DIR
    return 0
}

# Create plugin-specific temp directory
create_plugin_temp_dir() {
    local plugin_name="$1"
    local plugin_temp_dir="$TMP_DIR/plugins/$plugin_name"
    
    mkdir -p "$plugin_temp_dir" 2>/dev/null
    echo "$plugin_temp_dir"
    return 0
}

# -------------------------------------------------------
# CLEANUP MANAGEMENT
# -------------------------------------------------------

# Cleanup handlers registry
declare -A CLEANUP_HANDLERS
declare -a CLEANUP_ORDER

# Register cleanup handler
register_cleanup() {
    local name="$1"
    local command="$2"
    
    CLEANUP_HANDLERS["$name"]="$command"
    CLEANUP_ORDER+=("$name")
    
    log_debug "Registered cleanup handler: $name"
}

# Run all cleanup handlers
run_cleanup_handlers() {
    log_debug "Running cleanup handlers"
    
    # Run in reverse order
    for ((i=${#CLEANUP_ORDER[@]}-1; i>=0; i--)); do
        local name="${CLEANUP_ORDER[$i]}"
        local command="${CLEANUP_HANDLERS[$name]}"
        
        log_debug "Running cleanup: $name"
        eval "$command" 2>/dev/null || true
    done
    
    log_debug "Cleanup completed"
}

# -------------------------------------------------------
# DRIVE DETECTION
# -------------------------------------------------------

# Get list of all drives
get_all_drives() {
    lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print $1}' | sort
}

# Check if drive supports SMART
is_smart_capable() {
    local drive="$1"
    
    # Use sudo if not root
    if is_root; then
        smartctl -i "/dev/$drive" >/dev/null 2>&1
    else
        sudo smartctl -i "/dev/$drive" >/dev/null 2>&1
    fi
    
    return $?
}

# Get SMART-capable drives
get_smart_drives() {
    local all_drives=$(get_all_drives)
    local smart_drives=""
    
    for drive in $all_drives; do
        if is_smart_capable "$drive"; then
            smart_drives="$smart_drives $drive"
        fi
    done
    
    echo "$smart_drives" | xargs
}

# -------------------------------------------------------
# TIME CALCULATIONS
# -------------------------------------------------------

# Start timing for operation
start_timing() {
    export OPERATION_START_TIME=$(date +%s)
}

# Calculate elapsed time
calculate_elapsed_time() {
    local start_time="${1:-$OPERATION_START_TIME}"
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    if [ $elapsed -lt 60 ]; then
        echo "${elapsed}s"
    elif [ $elapsed -lt 3600 ]; then
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        echo "${minutes}m ${seconds}s"
    else
        local hours=$((elapsed / 3600))
        local minutes=$(((elapsed % 3600) / 60))
        echo "${hours}h ${minutes}m"
    fi
}

# -------------------------------------------------------
# MODULE INITIALIZATION
# -------------------------------------------------------

# Initialize when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Utils module loaded"
fi
