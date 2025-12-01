#!/bin/bash
################################################################################
# Multi-Report-OMV
# Core Utilities Module
# Based on SnapRAID Manager utils architecture
################################################################################
#
# Table of Contents:
# 1. Version Management
# 2. Environment Management
# 3. Plugin Utilities
# 4. CSV Utilities
# 5. Module Initialization
#
################################################################################

################################################################################
# 1. VERSION MANAGEMENT
################################################################################

# Detect script location if not provided
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

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

################################################################################
# 2. ENVIRONMENT MANAGEMENT
################################################################################

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
    
    # CSV utilities
    export -f csv_escape
    export -f csv_parse_line
    export -f csv_append_row
    export -f csv_read_column
    
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
    
    # Register cleanup (unless KEEP_TEMP_FILES is enabled)
    local keep_temp=$(get_config "KEEP_TEMP_FILES" "false")
    if [ "$keep_temp" = "true" ]; then
        log_debug "Temporary files will be preserved (KEEP_TEMP_FILES=true)"
        log_info "Temp directory: $TMP_DIR (will be preserved)"
    else
        register_cleanup "temp_dir_cleanup" "rm -rf \"$TMP_DIR\" 2>/dev/null"
        log_debug "Temporary directory created: $TMP_DIR (will be cleaned up)"
    fi
    
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

# Wrapper for smartctl that handles sudo
run_smartctl() {
    if is_root; then
        smartctl "$@"
    else
        sudo smartctl "$@"
    fi
}

# Get list of all drives
get_all_drives() {
    lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print $1}' | sort
}

# Get serial number from lsblk
get_drive_serial() {
    local drive="$1"
    lsblk -d -n -o SERIAL "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get drive model from lsblk
get_drive_model() {
    local drive="$1"
    lsblk -d -n -o MODEL "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get drive size
get_drive_size() {
    local drive="$1"
    lsblk -d -n -o SIZE "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get drive UUID
get_drive_uuid() {
    local drive="$1"
    lsblk -d -n -o UUID "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get drive label
get_drive_label() {
    local drive="$1"
    lsblk -d -n -o LABEL "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get drive firmware version
get_drive_firmware() {
    local drive="$1"
    run_smartctl -i "/dev/$drive" 2>/dev/null | grep -i "Firmware Version:" | awk '{print $NF}' | tr -d ' '
}

# Get drive type from lsblk
get_drive_type() {
    local drive="$1"
    lsblk -d -n -o TYPE "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get complete drive information (all fields at once - more efficient)
get_drive_info() {
    local drive="$1"
    lsblk -d -n -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,UUID,LABEL,MOUNTPOINT "/dev/$drive" 2>/dev/null
}

# Check if drive supports SMART
is_smart_capable() {
    local drive="$1"
    
    # Use run_smartctl wrapper
    run_smartctl -i "/dev/$drive" >/dev/null 2>&1
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
# PLUGIN UTILITY FUNCTIONS (SnapRAID Manager style)
# -------------------------------------------------------

# Format seconds as human-readable time (matches SnapRAID Manager)
format_seconds() {
    local total_seconds="$1"
    if ! [[ "$total_seconds" =~ ^[0-9]+$ ]]; then
        echo "0s"
        return
    fi
    local d=$((total_seconds/86400))
    local h=$(((total_seconds%86400)/3600))
    local m=$(((total_seconds%3600)/60))
    local s=$((total_seconds%60))
    local out=""
    if [ $d -gt 0 ]; then out="${d}d "; fi
    if [ $h -gt 0 ] || [ $d -gt 0 ]; then out="${out}${h}h "; fi
    if [ $m -gt 0 ] || [ $h -gt 0 ] || [ $d -gt 0 ]; then out="${out}${m}m "; fi
    out="${out}${s}s"
    echo "$out" | sed 's/ *$//'
}

# Format bytes as human-readable size (KB, MB, GB, TB, PB)
format_bytes_human() {
    local bytes="$1"
    
    # Handle invalid input
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "N/A"
        return
    fi
    
    # Define units
    local -a units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit_index=0
    local size="$bytes"
    
    # Convert to appropriate unit
    while [ "$size" -ge 1024 ] && [ $unit_index -lt 5 ]; do
        size=$((size / 1024))
        unit_index=$((unit_index + 1))
    done
    
    # Format with decimal if >= GB
    if [ $unit_index -ge 3 ]; then
        # For GB/TB/PB, show one decimal place
        local remainder=$((bytes % (1024 ** unit_index)))
        local decimal=$((remainder * 10 / (1024 ** unit_index)))
        echo "${size}.${decimal}${units[$unit_index]}"
    else
        echo "${size}${units[$unit_index]}"
    fi
}

# Format large numbers as human-readable (K, M, B for thousands, millions, billions)
format_number_human() {
    local number="$1"
    
    # Handle invalid input
    if ! [[ "$number" =~ ^[0-9]+$ ]]; then
        echo "N/A"
        return
    fi
    
    # Less than million: show as-is
    if [ "$number" -lt 1000000 ]; then
        echo "$number"
        return
    fi
    
    # Millions (1M = 1,000,000)
    if [ "$number" -lt 1000000000 ]; then
        local millions=$((number / 1000000))
        local remainder=$((number % 1000000))
        local decimal=$((remainder / 100000))
        echo "${millions}.${decimal}M"
        return
    fi
    
    # Billions (1B = 1,000,000,000)
    local billions=$((number / 1000000000))
    local remainder=$((number % 1000000000))
    local decimal=$((remainder / 100000000))
    echo "${billions}.${decimal}B"
}

################################################################################
# 3. PLUGIN UTILITIES
################################################################################

# Start plugin timing (exports global variable for later use)
start_plugin_timing() {
    export PLUGIN_START_TIME=$(date +%s)
    log_debug "Plugin timing started: $PLUGIN_START_TIME"
}

# Calculate and format plugin execution time
calculate_plugin_execution_time() {
    local start_time="${1:-$PLUGIN_START_TIME}"
    local plugin_name="${2:-PLUGIN}"
    
    if [ -z "$start_time" ]; then
        log_debug "Warning: No start time available for plugin timing"
        echo "0s"
        return 0
    fi
    
    local end_time=$(date +%s)
    local execution_seconds=$((end_time - start_time))
    
    # Ensure we never show negative time (clock issues)
    if [ $execution_seconds -lt 0 ]; then
        log_warning "Negative execution time detected, using 0s"
        execution_seconds=0
    fi
    
    local execution_time=$(format_seconds $execution_seconds)
    
    # Export the execution time with plugin-specific variable name
    local export_var="${plugin_name^^}_PLUGIN_EXECUTION_TIME"
    export "$export_var"="$execution_time"
    
    log_debug "Plugin execution time calculated: $execution_time (start: $start_time, end: $end_time)"
    echo "$execution_time"
}

# Create standardized plugin temporary directory
create_plugin_temp_dir() {
    local plugin_name="$1"
    local temp_dir="${TMP_DIR}/plugins/$plugin_name"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

# Export plugin data for notification system (like SnapRAID Manager)
export_plugin_for_notification() {
    local summary_file="$1"
    local plugin_name="$2"
    local plugin_execution_time="$3"

    # Check if summary file exists
    if [ ! -f "$summary_file" ]; then
        log_warning "Summary file not found: $summary_file"
        return 1
    fi

    # Use the already generated human-readable summary from the text file
    local output_dir="${TMP_DIR}/plugins/$plugin_name"
    local text_summary_file="$output_dir/${plugin_name}-summary-text.txt"

    local human_summary=""
    if [ -f "$text_summary_file" ]; then
        human_summary=$(cat "$text_summary_file")
    else
        log_warning "Text summary file not found: $text_summary_file"
        human_summary="No summary available"
    fi

    export ${plugin_name^^}_SUMMARY_TEXT="$human_summary"

    # Read critical values for notification from JSON
    local has_errors=$(grep -o '"has_errors": *[a-z]*' "$summary_file" | sed 's/.*: *//' | tr -d ',')
    local completed_successfully=$(grep -o '"completed_successfully": *[a-z]*' "$summary_file" | sed 's/.*: *//' | tr -d ',')

    # Export notification variables (plugin-specific)
    export ${plugin_name^^}_HAS_ERRORS="${has_errors:-false}"
    export ${plugin_name^^}_COMPLETED_SUCCESSFULLY="${completed_successfully:-true}"

    # Export execution time if provided
    export ${plugin_name^^}_PLUGIN_EXECUTION_TIME="$plugin_execution_time"

    log_debug "[${plugin_name^^}] Exported to notification system"
    return 0
}

# Format plain text content (remove literal \n, convert markdown)
format_plain_text() {
    local text="$1"
    
    # Convert markdown-style bold (**text**) to plain emphasis
    text=$(echo "$text" | sed -E 's/\*\*([^*]+)\*\*/\1/g')
    
    echo "$text"
}

################################################################################
# 4. CSV UTILITIES
################################################################################

# Escape a field for CSV format
# Handles commas, quotes, and newlines according to CSV standard
csv_escape() {
    local field="$1"
    
    # If field contains comma, quote, or newline, wrap in quotes and escape quotes
    if [[ "$field" =~ [,\"$'\n'] ]]; then
        # Escape double quotes by doubling them
        field="${field//\"/\"\"}"
        # Wrap in quotes
        echo "\"$field\""
    else
        echo "$field"
    fi
}

# Parse a CSV line into an array (handles quoted fields with commas)
# Usage: csv_parse_line "$line" result_array
csv_parse_line() {
    local line="$1"
    local -n result_array=$2
    
    result_array=()
    local field=""
    local in_quotes=false
    local i
    
    for ((i=0; i<${#line}; i++)); do
        local char="${line:i:1}"
        
        if [[ "$char" == "\"" ]]; then
            # Check for escaped quote ("")
            if [[ "${line:i+1:1}" == "\"" ]]; then
                field+="\"" 
                ((i++))
            else
                in_quotes=$( [[ "$in_quotes" == "false" ]] && echo "true" || echo "false" )
            fi
        elif [[ "$char" == "," && "$in_quotes" == "false" ]]; then
            result_array+=("$field")
            field=""
        else
            field+="$char"
        fi
    done
    
    # Add last field
    result_array+=("$field")
}

# Append a row to a CSV file
# Usage: csv_append_row <file> <field1> <field2> ...
csv_append_row() {
    local file="$1"
    shift
    
    local row=""
    local first=true
    
    for field in "$@"; do
        if [[ "$first" == "true" ]]; then
            row="$(csv_escape "$field")"
            first=false
        else
            row="$row,$(csv_escape "$field")"
        fi
    done
    
    echo "$row" >> "$file"
}

# Read a specific column from CSV file (returns all values in that column)
# Usage: csv_read_column <file> <column_number> [skip_header]
csv_read_column() {
    local file="$1"
    local column="$2"
    local skip_header="${3:-true}"
    
    [[ ! -f "$file" ]] && return 1
    
    local start_line=1
    [[ "$skip_header" == "true" ]] && start_line=2
    
    tail -n +$start_line "$file" | cut -d',' -f"$column"
}

# -------------------------------------------------------
# FILESYSTEM INFORMATION
# -------------------------------------------------------

# Get mountpoint for a drive (checks partition first, then base drive)
get_drive_mountpoint() {
    local drive="$1"
    local partition="${drive}1"
    local mountpoint
    
    # Try partition first
    mountpoint=$(lsblk -no MOUNTPOINT "/dev/$partition" 2>/dev/null | head -1)
    
    # If no partition mountpoint, try base drive
    if [ -z "$mountpoint" ]; then
        mountpoint=$(lsblk -no MOUNTPOINT "/dev/$drive" 2>/dev/null | head -1)
    fi
    
    [ -z "$mountpoint" ] && mountpoint="N/A"
    echo "$mountpoint"
}

# Get filesystem type for a drive
get_drive_fstype() {
    local drive="$1"
    local partition="${drive}1"
    local fs_type
    
    # Try partition first
    fs_type=$(lsblk -no FSTYPE "/dev/$partition" 2>/dev/null | head -1)
    
    # If no partition filesystem, try base drive
    if [ -z "$fs_type" ]; then
        fs_type=$(lsblk -no FSTYPE "/dev/$drive" 2>/dev/null | head -1)
    fi
    
    [ -z "$fs_type" ] && fs_type="N/A"
    echo "$fs_type"
}

# Get filesystem label for a drive
get_drive_fslabel() {
    local drive="$1"
    local partition="${drive}1"
    local fs_label
    
    # Try partition first
    fs_label=$(lsblk -no LABEL "/dev/$partition" 2>/dev/null | head -1)
    
    # If no partition label, try base drive
    if [ -z "$fs_label" ]; then
        fs_label=$(lsblk -no LABEL "/dev/$drive" 2>/dev/null | head -1)
    fi
    
    echo "$fs_label"
}

# Get friendly filesystem name (label or type-based name)
get_drive_fsname() {
    local drive="$1"
    local fs_label=$(get_drive_fslabel "$drive")
    
    # If label exists, use it
    if [ -n "$fs_label" ] && [ "$fs_label" != "" ]; then
        echo "$fs_label"
        return
    fi
    
    # Otherwise, generate friendly name from type
    local fs_type=$(get_drive_fstype "$drive")
    
    if [ "$fs_type" = "N/A" ]; then
        echo "N/A"
        return
    fi
    
    case "$fs_type" in
        "ext4") echo "EXT4" ;;
        "ext3") echo "EXT3" ;;
        "ext2") echo "EXT2" ;;
        "xfs") echo "XFS" ;;
        "btrfs") echo "Btrfs" ;;
        "ntfs") echo "NTFS" ;;
        "vfat"|"fat32") echo "FAT32" ;;
        "exfat") echo "exFAT" ;;
        "zfs") echo "ZFS" ;;
        "swap") echo "Swap" ;;
        *) echo "$fs_type" ;;
    esac
}

# Get OMV tag/comment for a drive
get_drive_omv_tag() {
    local drive="$1"
    local partition="${drive}1"
    
    # Check if OMV is available
    if [ ! -x "/usr/sbin/omv-confdbadm" ]; then
        echo "N/A"
        return
    fi
    
    # Try partition UUID first
    local uuid=$(lsblk -no UUID "/dev/$partition" 2>/dev/null)
    
    # If no partition UUID, try base drive
    if [ -z "$uuid" ]; then
        uuid=$(lsblk -no UUID "/dev/$drive" 2>/dev/null)
    fi
    
    if [ -z "$uuid" ]; then
        echo "N/A"
        return
    fi
    
    # Get OMV filesystem configs (requires sudo)
    local omv_all_configs
    omv_all_configs=$(sudo /usr/sbin/omv-confdbadm read "conf.system.filesystem.mountpoint" 2>/dev/null)
    
    if [ -z "$omv_all_configs" ]; then
        echo "N/A"
        return
    fi
    
    # Extract comment for this UUID
    local omv_comment
    omv_comment=$(echo "$omv_all_configs" | grep -o '"fsname": "[^"]*'"$uuid"'[^"]*"[^}]*"comment": "[^"]*"' | sed 's/.*"comment": "\([^"]*\)".*/\1/' 2>/dev/null)
    
    if [ -n "$omv_comment" ] && [ "$omv_comment" != "" ]; then
        echo "$omv_comment"
    else
        echo "N/A"
    fi
}

# Get complete filesystem information for a drive (all at once - more efficient)
# Returns: mountpoint|fs_name|fs_type|omv_tag
get_drive_filesystem_info() {
    local drive="$1"
    local partition="${drive}1"
    
    # Get all lsblk info in one call
    local lsblk_info=$(lsblk -no MOUNTPOINT,FSTYPE,LABEL "/dev/$partition" 2>/dev/null | head -1)
    
    # If no partition info, try base drive
    if [ -z "$lsblk_info" ]; then
        lsblk_info=$(lsblk -no MOUNTPOINT,FSTYPE,LABEL "/dev/$drive" 2>/dev/null | head -1)
        partition="$drive"
    fi
    
    local mountpoint=$(echo "$lsblk_info" | awk '{print $1}')
    local fs_type=$(echo "$lsblk_info" | awk '{print $2}')
    local fs_label=$(echo "$lsblk_info" | awk '{print $3}')
    
    # Default to N/A if empty
    [ -z "$mountpoint" ] && mountpoint="N/A"
    [ -z "$fs_type" ] && fs_type="N/A"
    
    # Set filesystem name from label or friendly type name
    local fs_name="N/A"
    if [ -n "$fs_label" ] && [ "$fs_label" != "" ]; then
        fs_name="$fs_label"
    elif [ "$fs_type" != "N/A" ]; then
        case "$fs_type" in
            "ext4") fs_name="EXT4" ;;
            "ext3") fs_name="EXT3" ;;
            "ext2") fs_name="EXT2" ;;
            "xfs") fs_name="XFS" ;;
            "btrfs") fs_name="Btrfs" ;;
            "ntfs") fs_name="NTFS" ;;
            "vfat"|"fat32") fs_name="FAT32" ;;
            "exfat") fs_name="exFAT" ;;
            "zfs") fs_name="ZFS" ;;
            "swap") fs_name="Swap" ;;
            *) fs_name="$fs_type" ;;
        esac
    fi
    
    # Get OMV tag/comment if available
    local omv_tag="N/A"
    if [ -x "/usr/sbin/omv-confdbadm" ]; then
        local uuid=$(lsblk -no UUID "/dev/$partition" 2>/dev/null)
        if [ -n "$uuid" ]; then
            local omv_all_configs=$(sudo /usr/sbin/omv-confdbadm read "conf.system.filesystem.mountpoint" 2>/dev/null)
            if [ -n "$omv_all_configs" ]; then
                local omv_comment=$(echo "$omv_all_configs" | grep -o '"fsname": "[^"]*'"$uuid"'[^"]*"[^}]*"comment": "[^"]*"' | sed 's/.*"comment": "\([^"]*\)".*/\1/' 2>/dev/null)
                if [ -n "$omv_comment" ] && [ "$omv_comment" != "" ]; then
                    omv_tag="$omv_comment"
                fi
            fi
        fi
    fi
    
    echo "$mountpoint|$fs_name|$fs_type|$omv_tag"
}

# -------------------------------------------------------
# SMR/CMR DETECTION
# -------------------------------------------------------

# Check if drive is SMR (Shingled Magnetic Recording) or CMR (Conventional Magnetic Recording)
# Returns: CMR, SMR-HM (host-managed), SMR-HA (host-aware), SMR, or "Run smr-check"
check_drive_recording_type() {
    local drive="$1"
    
    # Method 0: Check SMR cache first (fastest - from smr_check plugin)
    local cache_file="${CONFIG[SMR_CACHE_FILE]:-${BASE_DIR}/data/smr_check/drive_types.cache}"
    if [ -f "$cache_file" ]; then
        # Skip first two lines (hash header and column header), look for drive
        local cached_type=$(tail -n +3 "$cache_file" 2>/dev/null | grep "^${drive}|" | cut -d'|' -f4)
        if [ -n "$cached_type" ]; then
            echo "$cached_type"
            return
        fi
    fi
    
    # If no cache file exists, prompt user to run smr-check
    if [ ! -f "$cache_file" ]; then
        echo "Run smr-check"
        return
    fi
    
    # Method 1: Check kernel zoned attribute (most reliable for modern SMR drives)
    if [ -f "/sys/block/$drive/device/zoned" ]; then
        local zoned=$(cat /sys/block/$drive/device/zoned 2>/dev/null)
        case "$zoned" in
            "host-managed") echo "SMR-HM" && return ;;
            "host-aware") echo "SMR-HA" && return ;;
        esac
    fi
    
    # Method 2: Check using smr-check-omv.sh if available
    local smr_script="${BASE_DIR}/../smr-check-omv.sh"
    if [ -f "$smr_script" ]; then
        local serial=$(get_drive_serial "$drive")
        local model=$(get_drive_model "$drive")
        
        if [ -n "$serial" ] && [ -n "$model" ]; then
            local smr_output=$(bash "$smr_script" 2>/dev/null)
            
            # Check if drive appears in the SMR detection table
            if echo "$smr_output" | grep -q "Known SMR drive(s) detected"; then
                local smr_table=$(echo "$smr_output" | sed -n '/Known SMR drive(s) detected/,$p' | tail -n +3)
                if echo "$smr_table" | grep -q "$serial"; then
                    echo "SMR"
                    return
                fi
            fi
        fi
    fi
    
    # Method 3: Basic pattern matching for known SMR models
    local model=$(get_drive_model "$drive")
    if [ -n "$model" ]; then
        case "$model" in
            # Seagate Archive series (all SMR)
            *"ST8000AS"*|*"ST6000AS"*|*"ST5000AS"*|*"ST4000AS"*|*"ST3000AS"*|*"ST2000AS"*)
                echo "SMR" && return ;;
            # WD Blue SMR models
            *"WD60EZAZ"*|*"WD40EZAZ"*|*"WD30EZAZ"*|*"WD20EZAZ"*)
                echo "SMR" && return ;;
            # Seagate Barracuda known SMR models
            *"ST2000DM008"*|*"ST2000DM005"*|*"ST3000DM007"*|*"ST4000DM004"*|*"ST5000DM000"*|*"ST6000DM003"*)
                echo "SMR" && return ;;
            # Toshiba known SMR models
            *"DT01ACA"*|*"MG08ACA"*)
                echo "SMR" && return ;;
        esac
    fi
    
    # Default to CMR (assume conventional recording if no SMR indicators found)
    echo "CMR"
}

# Check and log power state of all SMART drives
# This helps track which plugins wake sleeping drives
check_drive_power_states() {
    local label="${1:-Drive Power States}"
    
    log_debug "=== $label ==="
    
    # Get list of block devices WITHOUT querying them (no wake-up)
    # Use /sys/block to find sd* devices
    local drives=$(ls /dev/sd? 2>/dev/null | sed 's|/dev/||' | sort)
    
    if [ -z "$drives" ]; then
        log_debug "No drives found"
        return 0
    fi
    
    local sleeping_count=0
    local active_count=0
    local sleeping_drives=""
    local active_drives=""
    
    for drive in $drives; do
        # Check power mode using smartctl -n standby
        local power_check_exit=0
        run_smartctl -n standby /dev/$drive >/dev/null 2>&1
        power_check_exit=$?
        
        if [ "$power_check_exit" -eq 2 ]; then
            # Drive is in STANDBY/SLEEP
            sleeping_drives+="$drive "
            ((sleeping_count++))
        else
            # Drive is ACTIVE
            active_drives+="$drive "
            ((active_count++))
        fi
    done
    
    log_debug "Sleeping drives ($sleeping_count): ${sleeping_drives:-none}"
    log_debug "Active drives ($active_count): ${active_drives:-none}"
    log_debug "=========================="
    
    return 0
}

# Version with INFO level for visibility in standard logs  
# NOTE: This checks power state after plugins run, so if drives are awake,
# it means something in the plugin woke them
check_drive_power_states_info() {
    local label="${1:-Drive Power States}"
    
    log_debug "[POWER_CHECK] Starting power state check: $label at $(date +%H:%M:%S.%N)"
    log_info "==========================="
    log_info "=== $label ==="
    
    # Get list of drives directly from /dev to avoid waking them
    local drives=$(ls /dev/sd? 2>/dev/null | sed 's|/dev/||')
    
    if [ -z "$drives" ]; then
        log_info "No drives found"
        log_info "==========================="
        return 0
    fi
    
    local sleeping_drives=()
    local active_drives=()
    
    for drive in $drives; do
        # Check using smartctl exit code only - don't capture output
        # Exit code 2 = STANDBY, 0 = ACTIVE or other state
        if run_smartctl -n standby /dev/$drive >/dev/null 2>&1; then
            active_drives+=("$drive")
        else
            local exit_code=$?
            if [ "$exit_code" -eq 2 ]; then
                sleeping_drives+=("$drive")
            else
                active_drives+=("$drive")
            fi
        fi
    done
    
    log_info "Sleeping drives (${#sleeping_drives[@]}): ${sleeping_drives[*]:-none}"
    log_info "Active drives (${#active_drives[@]}): ${active_drives[*]:-none}"
    log_info "==========================="
    log_debug "[POWER_CHECK] Completed power state check: $label at $(date +%H:%M:%S.%N)"
    log_info ""
}

################################################################################
# 5. MODULE INITIALIZATION
################################################################################

# Initialize when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Utils module loaded"
fi
