#!/bin/bash
# Multi-Report-OMV v2.0
# Core configuration module
# Based on SnapRAID Manager config architecture

# Detect script location
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Current configuration version (increment when config format changes)
CURRENT_CONFIG_VERSION="2.0"

# Configuration paths
CONFIG_DIR="${CONFIG_BASE:-$BASE_DIR/config}"
mkdir -p "$CONFIG_DIR" 2>/dev/null || {
    echo "WARNING: Cannot create config directory: $CONFIG_DIR"
    CONFIG_DIR="/tmp"
    echo "Using temporary directory for configuration: $CONFIG_DIR"
}

DEFAULT_CONFIG="${CONFIG_DIR}/defaults.conf"
USER_CONFIG="${CONFIG_DIR}/multi-report-omv.conf"

# Configuration storage
declare -A CONFIG

# Default configuration values
init_default_config() {
    # Core settings
    CONFIG["LOG_LEVEL"]="info"
    CONFIG["LOG_RETENTION_DAYS"]="30"
    CONFIG["CONFIG_BACKUP_RETENTION"]="5"  # Number of config backups to keep
    CONFIG["REQUIRE_ROOT"]="false"  # Set to true to require root instead of sudo
    CONFIG["DISABLE_SUDO"]="false"  # Set to true to disable sudo elevation
    
    # Email notification settings
    CONFIG["EMAIL_ENABLED"]="false"
    CONFIG["EMAIL_TO"]=""
    CONFIG["EMAIL_FROM"]="multi-report-omv@$(hostname)"
    CONFIG["EMAIL_SUBJECT_PREFIX"]="[Multi-Report-OMV]"
    CONFIG["EMAIL_USE_HTML"]="true"
    CONFIG["EMAIL_LEVEL"]="always"  # always, warning, error
    
    # SMART monitoring settings
    CONFIG["SMART_ENABLED"]="true"
    CONFIG["TEMP_WARN_HDD"]="45"
    CONFIG["TEMP_CRIT_HDD"]="50"
    CONFIG["TEMP_WARN_SSD"]="50"
    CONFIG["TEMP_CRIT_SSD"]="60"
    CONFIG["TEMP_WARN_NVME"]="60"
    CONFIG["TEMP_CRIT_NVME"]="70"
    
    # CSV data settings
    CONFIG["CSV_ENABLED"]="true"
    CONFIG["CSV_FILE"]="${BASE_DIR}/data/csv/smart-data.csv"
    CONFIG["CSV_RETENTION_DAYS"]="730"
    CONFIG["CSV_OWNER"]="1000"
    CONFIG["CSV_GROUP"]="1000"
    CONFIG["CSV_PERMISSIONS"]="660"
    
    # Drive self-test settings
    CONFIG["SELFTEST_ENABLED"]="true"
    CONFIG["SELFTEST_SHORT_MODE"]="1"  # 1=spread, 2=all
    CONFIG["SELFTEST_SHORT_DRIVES_PER_DAY"]="2"
    CONFIG["SELFTEST_SHORT_PERIOD"]="Week"
    CONFIG["SELFTEST_SHORT_DAYS"]="1,2,3,4,5"  # Mon-Fri
    
    CONFIG["SELFTEST_LONG_MODE"]="1"
    CONFIG["SELFTEST_LONG_DRIVES_PER_DAY"]="1"
    CONFIG["SELFTEST_LONG_PERIOD"]="Quarter"
    CONFIG["SELFTEST_LONG_DAYS"]="6,7"  # Sat-Sun
    
    # SMR detection settings
    CONFIG["SMR_CHECK_ENABLED"]="true"
    CONFIG["SMR_AUTO_UPDATE"]="true"
    CONFIG["SMR_IGNORE_ALARMS"]="false"
    
    # SCT settings
    CONFIG["SCT_ENABLED"]="true"
    CONFIG["SCT_DELTA_HDD"]="10"
    CONFIG["SCT_DELTA_SSD"]="10"
    CONFIG["SCT_DELTA_NVME"]="15"
}

# Load configuration from file
load_config_file() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_debug "Config file not found: $config_file"
        return 1
    fi
    
    log_debug "Loading configuration from: $config_file"
    
    # Read config file line by line
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        # Remove quotes from value
        value="${value%\"}"
        value="${value#\"}"
        
        # Store in CONFIG array
        CONFIG["$key"]="$value"
        
    done < "$config_file"
    
    log_debug "Configuration loaded from: $config_file"
    return 0
}

# Load all configuration
load_config() {
    local skip_validation="${1:-false}"
    
    log_debug "Initializing configuration system"
    
    # Initialize defaults
    init_default_config
    
    # Create config files if they don't exist
    init_config_files
    
    # Load user config if exists
    if [ -f "$USER_CONFIG" ]; then
        load_config_file "$USER_CONFIG"
    else
        log_warning "User config not found: $USER_CONFIG"
        log_info "Using default configuration"
    fi
    
    # Validate configuration
    if [ "$skip_validation" != "true" ]; then
        validate_config
    fi
    
    # Apply log level
    if [ -n "${CONFIG[LOG_LEVEL]}" ]; then
        set_log_level "${CONFIG[LOG_LEVEL]}"
    fi
    
    log_debug "Configuration system initialized"
    return 0
}

# Get configuration value
get_config() {
    local key="$1"
    local default="${2:-}"
    
    if [ -n "${CONFIG[$key]}" ]; then
        echo "${CONFIG[$key]}"
    else
        echo "$default"
    fi
}

# Set configuration value
set_config() {
    local key="$1"
    local value="$2"
    
    CONFIG["$key"]="$value"
    log_debug "Configuration set: $key=$value"
}

# Validate configuration
validate_config() {
    log_debug "Validating configuration"
    
    local has_errors=false
    
    # Validate email settings if enabled
    if [ "${CONFIG[EMAIL_ENABLED]}" = "true" ]; then
        if [ -z "${CONFIG[EMAIL_TO]}" ]; then
            log_error "EMAIL_ENABLED is true but EMAIL_TO is not set"
            has_errors=true
        fi
    fi
    
    # Validate temperature thresholds
    if [ "${CONFIG[TEMP_WARN_HDD]}" -ge "${CONFIG[TEMP_CRIT_HDD]}" ]; then
        log_error "TEMP_WARN_HDD must be less than TEMP_CRIT_HDD"
        has_errors=true
    fi
    
    if [ "${CONFIG[TEMP_WARN_SSD]}" -ge "${CONFIG[TEMP_CRIT_SSD]}" ]; then
        log_error "TEMP_WARN_SSD must be less than TEMP_CRIT_SSD"
        has_errors=true
    fi
    
    if [ "${CONFIG[TEMP_WARN_NVME]}" -ge "${CONFIG[TEMP_CRIT_NVME]}" ]; then
        log_error "TEMP_WARN_NVME must be less than TEMP_CRIT_NVME"
        has_errors=true
    fi
    
    if [ "$has_errors" = true ]; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    log_debug "Configuration validation passed"
    return 0
}

# Save configuration to file
save_config() {
    local config_file="${1:-$USER_CONFIG}"
    
    log_info "Saving configuration to: $config_file"
    
    # Create config directory
    mkdir -p "$(dirname "$config_file")"
    
    # Write configuration
    {
        echo "# Multi-Report-OMV Configuration"
        echo "# Generated: $(date)"
        echo ""
        
        for key in "${!CONFIG[@]}"; do
            echo "${key}=\"${CONFIG[$key]}\""
        done
    } > "$config_file"
    
    log_info "Configuration saved"
    return 0
}

# Display current configuration
show_config() {
    log_info "Current Configuration:"
    log_info "===================="
    
    for key in $(echo "${!CONFIG[@]}" | tr ' ' '\n' | sort); do
        log_info "  $key = ${CONFIG[$key]}"
    done
}

# -------------------------------------------------------
# CONFIGURATION FILE CREATION
# -------------------------------------------------------

# Write default configuration file with comments
write_default_config() {
    local config_file="${1:-$DEFAULT_CONFIG}"
    
    log_info "Creating default configuration file: $config_file"
    
    # Create config directory
    mkdir -p "$(dirname "$config_file")"
    
    # Write configuration with detailed comments
    cat > "$config_file" << 'EOF'
# Multi-Report-OMV Default Configuration
# This file contains all default values
# DO NOT EDIT - Copy settings to multi-report-omv.conf instead
# Generated by Multi-Report-OMV v2.0

# -------------------------------------------------------
# CORE SETTINGS
# -------------------------------------------------------

# Logging level: debug, info, warning, error
LOG_LEVEL="info"

# Number of days to retain log files
LOG_RETENTION_DAYS="30"

# Number of configuration backups to keep
CONFIG_BACKUP_RETENTION="5"

# Require root user (no sudo) - set to true in restricted environments
REQUIRE_ROOT="false"

# Disable sudo elevation - set to true for testing without privileges
DISABLE_SUDO="false"

# Configuration version (auto-managed)
CONFIG_VERSION="2.0"

# -------------------------------------------------------
# EMAIL NOTIFICATION SETTINGS
# -------------------------------------------------------

# Enable email notifications
EMAIL_ENABLED="false"

# Email recipient address(es) - comma separated
EMAIL_TO=""

# Email sender address
EMAIL_FROM="multi-report-omv@$(hostname)"

# Email subject prefix
EMAIL_SUBJECT_PREFIX="[Multi-Report-OMV]"

# Use HTML email format (true) or plain text (false)
EMAIL_USE_HTML="true"

# When to send emails: always, warning, error
EMAIL_LEVEL="always"

# -------------------------------------------------------
# SMART MONITORING SETTINGS
# -------------------------------------------------------

# Enable SMART monitoring
SMART_ENABLED="true"

# HDD temperature thresholds (Celsius)
TEMP_WARN_HDD="45"
TEMP_CRIT_HDD="50"

# SSD temperature thresholds (Celsius)
TEMP_WARN_SSD="50"
TEMP_CRIT_SSD="60"

# NVMe temperature thresholds (Celsius)
TEMP_WARN_NVME="60"
TEMP_CRIT_NVME="70"

# -------------------------------------------------------
# CSV DATA RECORDING SETTINGS
# -------------------------------------------------------

# Enable CSV data recording
CSV_ENABLED="true"

# CSV file location
CSV_FILE="${BASE_DIR}/data/csv/smart-data.csv"

# Number of days to retain CSV data
CSV_RETENTION_DAYS="730"

# CSV file ownership and permissions
CSV_OWNER="1000"
CSV_GROUP="1000"
CSV_PERMISSIONS="660"

# -------------------------------------------------------
# DRIVE SELF-TEST SETTINGS
# -------------------------------------------------------

# Enable automatic drive self-tests
SELFTEST_ENABLED="true"

# SHORT TEST SETTINGS
# Mode: 1=spread tests across days, 2=test all drives at once
SELFTEST_SHORT_MODE="1"

# Number of drives to test per day (mode 1 only)
SELFTEST_SHORT_DRIVES_PER_DAY="2"

# Test period: Day, Week, Month, Quarter, Year
SELFTEST_SHORT_PERIOD="Week"

# Active days (1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun)
SELFTEST_SHORT_DAYS="1,2,3,4,5"

# LONG TEST SETTINGS
SELFTEST_LONG_MODE="1"
SELFTEST_LONG_DRIVES_PER_DAY="1"
SELFTEST_LONG_PERIOD="Quarter"
SELFTEST_LONG_DAYS="6,7"

# -------------------------------------------------------
# SMR DETECTION SETTINGS
# -------------------------------------------------------

# Enable SMR (Shingled Magnetic Recording) detection
SMR_CHECK_ENABLED="true"

# Automatically update SMR database
SMR_AUTO_UPDATE="true"

# Ignore SMR detection alarms
SMR_IGNORE_ALARMS="false"

# -------------------------------------------------------
# SCT (SMART Command Transport) SETTINGS
# -------------------------------------------------------

# Enable SCT temperature management
SCT_ENABLED="true"

# Temperature delta for SCT operations (Celsius)
SCT_DELTA_HDD="10"
SCT_DELTA_SSD="10"
SCT_DELTA_NVME="15"
EOF

    log_info "Default configuration file created: $config_file"
    return 0
}

# Create user configuration file from defaults
create_user_config() {
    local config_file="${1:-$USER_CONFIG}"
    local additional_header="$2"
    
    # Only check if file exists when creating the default user config
    if [ "$config_file" = "$USER_CONFIG" ] && [ -f "$USER_CONFIG" ]; then
        log_debug "User configuration already exists at $USER_CONFIG"
        return 0
    fi
    
    log_info "Creating user configuration template at $config_file"
    
    # Create config directory
    mkdir -p "$(dirname "$config_file")"
    
    # Write comprehensive user configuration with ALL options commented out
    cat > "$config_file" << 'EOF'
# Multi-Report-OMV User Configuration
# Created: $(date)
# This file contains your custom settings.
# Settings here override the defaults in config/defaults.conf
CONFIG_VERSION="2.0"

# -------------------------------------------------------
# CORE SETTINGS
# -------------------------------------------------------
# Logging level: debug, info, warning, error
#LOG_LEVEL="info"

# Number of days to retain log files
#LOG_RETENTION_DAYS="30"

# Number of configuration backups to keep
#CONFIG_BACKUP_RETENTION="5"

# Require root user (no sudo) - set to true in restricted environments
#REQUIRE_ROOT="false"

# Disable sudo elevation - set to true for testing without privileges
#DISABLE_SUDO="false"

# -------------------------------------------------------
# EMAIL NOTIFICATION SETTINGS
# -------------------------------------------------------
# Enable email notifications
#EMAIL_ENABLED="false"

# Email recipient address(es) - comma separated
#EMAIL_TO=""

# Email sender address (defaults to multi-report-omv@hostname if empty)
#EMAIL_FROM=""

# Email subject prefix
#EMAIL_SUBJECT_PREFIX="[Multi-Report-OMV]"

# Use HTML email format (true) or plain text (false)
#EMAIL_USE_HTML="true"

# When to send emails: always, warning, error
#EMAIL_LEVEL="always"

# -------------------------------------------------------
# SMART MONITORING SETTINGS
# -------------------------------------------------------
# Enable SMART monitoring
#SMART_ENABLED="true"

# HDD temperature thresholds (Celsius)
#TEMP_WARN_HDD="45"
#TEMP_CRIT_HDD="50"

# SSD temperature thresholds (Celsius)
#TEMP_WARN_SSD="50"
#TEMP_CRIT_SSD="60"

# NVMe temperature thresholds (Celsius)
#TEMP_WARN_NVME="60"
#TEMP_CRIT_NVME="70"

# -------------------------------------------------------
# CSV DATA RECORDING SETTINGS
# -------------------------------------------------------
# Enable CSV data recording
#CSV_ENABLED="true"

# CSV file location
#CSV_FILE="${BASE_DIR}/data/csv/smart-data.csv"

# Number of days to retain CSV data
#CSV_RETENTION_DAYS="730"

# CSV file ownership and permissions
#CSV_OWNER="1000"
#CSV_GROUP="1000"
#CSV_PERMISSIONS="660"

# -------------------------------------------------------
# DRIVE SELF-TEST SETTINGS
# -------------------------------------------------------
# Enable automatic drive self-tests
#SELFTEST_ENABLED="true"

# SHORT TEST SETTINGS
# Mode: 1=spread tests across days, 2=test all drives at once
#SELFTEST_SHORT_MODE="1"

# Number of drives to test per day (mode 1 only)
#SELFTEST_SHORT_DRIVES_PER_DAY="2"

# Test period: Day, Week, Month, Quarter, Year
#SELFTEST_SHORT_PERIOD="Week"

# Active days (1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun)
#SELFTEST_SHORT_DAYS="1,2,3,4,5"

# LONG TEST SETTINGS
#SELFTEST_LONG_MODE="1"
#SELFTEST_LONG_DRIVES_PER_DAY="1"
#SELFTEST_LONG_PERIOD="Quarter"
#SELFTEST_LONG_DAYS="6,7"

# -------------------------------------------------------
# SMR DETECTION SETTINGS
# -------------------------------------------------------
# Enable SMR (Shingled Magnetic Recording) detection
#SMR_CHECK_ENABLED="true"

# Automatically update SMR database
#SMR_AUTO_UPDATE="true"

# Ignore SMR detection alarms
#SMR_IGNORE_ALARMS="false"

# -------------------------------------------------------
# SCT (SMART Command Transport) SETTINGS
# -------------------------------------------------------
# Enable SCT temperature management
#SCT_ENABLED="true"

# Temperature delta for SCT operations (Celsius)
#SCT_DELTA_HDD="10"
#SCT_DELTA_SSD="10"
#SCT_DELTA_NVME="15"

# -------------------------------------------------------
# YOUR CUSTOM SETTINGS
# -------------------------------------------------------
# Add your custom configuration overrides below this line
# Uncomment and modify any setting above, or add new ones here

EOF

    log_info "User configuration template created with all available options"
    log_info "Edit $config_file to customize your settings (uncomment and modify as needed)"
    return 0
}

# Initialize configuration files if they don't exist
init_config_files() {
    local created=false
    
    # Create defaults.conf if missing
    if [ ! -f "$DEFAULT_CONFIG" ]; then
        write_default_config "$DEFAULT_CONFIG"
        created=true
    fi
    
    # Create multi-report-omv.conf if missing
    if [ ! -f "$USER_CONFIG" ]; then
        create_user_config "$USER_CONFIG"
        created=true
    fi
    
    if [ "$created" = true ]; then
        log_info "Configuration files initialized in: $CONFIG_DIR"
    fi
    
    return 0
}

# -------------------------------------------------------
# CONFIGURATION BACKUP & RESTORE
# -------------------------------------------------------

# Get backup directory
get_backup_dir() {
    local backup_dir="$CONFIG_DIR/backups"
    echo "$backup_dir"
}

# Get backup retention count
get_backup_retention() {
    local retention=$(get_config "CONFIG_BACKUP_RETENTION" "5")
    echo "$retention"
}

# Generate backup filename with timestamp
generate_backup_filename() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    echo "multi-report-omv.conf.backup.$timestamp"
}

# Create configuration backup
# Usage: backup_config [reason]
backup_config() {
    local reason="${1:-manual backup}"
    local config_file="$USER_CONFIG"
    local backup_dir=$(get_backup_dir)
    local backup_file="$backup_dir/$(generate_backup_filename)"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    mkdir -p "$backup_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup directory: $backup_dir"
        return 1
    fi
    
    log_info "Creating configuration backup: $reason"
    cp "$config_file" "$backup_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup file: $backup_file"
        return 1
    fi
    
    log_info "Configuration backed up to: $backup_file"
    
    # Rotate old backups
    rotate_backups
    
    return 0
}

# Rotate backups based on retention policy
rotate_backups() {
    local backup_dir=$(get_backup_dir)
    local retention=$(get_backup_retention)
    
    local backup_count=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f 2>/dev/null | wc -l)
    
    if [ "$backup_count" -le "$retention" ]; then
        return 0
    fi
    
    log_debug "Rotating backups (keeping last $retention of $backup_count)"
    
    local backups_to_delete=$((backup_count - retention))
    find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort | \
        head -n "$backups_to_delete" | \
        cut -d' ' -f2- | \
        while IFS= read -r old_backup; do
            log_debug "Removing old backup: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
    
    return 0
}

# List available configuration backups
list_config_backups() {
    local backup_dir=$(get_backup_dir)
    
    if [ ! -d "$backup_dir" ]; then
        echo "No backups directory found."
        return 1
    fi
    
    local backups=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort -r | \
        cut -d' ' -f2-)
    
    if [ -z "$backups" ]; then
        echo "No configuration backups found."
        return 1
    fi
    
    echo "Available configuration backups:"
    echo "================================"
    echo
    
    local count=1
    while IFS= read -r backup_file; do
        local filename=$(basename "$backup_file")
        local timestamp=$(echo "$filename" | sed 's/multi-report-omv.conf.backup.\(.*\)/\1/')
        local date_str=$(echo "$timestamp" | sed 's/\([0-9]\{8\}\)-\([0-9]\{6\}\)/\1 \2/')
        local formatted_date=$(date -d "${date_str:0:8} ${date_str:9:2}:${date_str:11:2}:${date_str:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
        local size=$(stat -c%s "$backup_file" 2>/dev/null || echo "unknown")
        
        printf "%2d) %s (%s bytes)\n" "$count" "$formatted_date" "$size"
        printf "    File: %s\n" "$filename"
        echo
        
        count=$((count + 1))
    done <<< "$backups"
    
    return 0
}

# Get backup file by number
get_backup_by_number() {
    local number="$1"
    local backup_dir=$(get_backup_dir)
    
    if [ ! -d "$backup_dir" ]; then
        echo ""
        return 1
    fi
    
    local backup=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort -r | \
        sed -n "${number}p" | \
        cut -d' ' -f2-)
    
    echo "$backup"
    [ -n "$backup" ]
}

# Validate backup file
validate_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    if [ ! -r "$backup_file" ]; then
        log_error "Backup file not readable: $backup_file"
        return 1
    fi
    
    if [ ! -s "$backup_file" ]; then
        log_error "Backup file is empty: $backup_file"
        return 1
    fi
    
    # Basic validation
    if ! grep -q "^#.*Multi-Report-OMV" "$backup_file" 2>/dev/null; then
        log_warning "Backup file may not be a valid Multi-Report-OMV configuration"
        log_warning "File: $backup_file"
    fi
    
    return 0
}

# Restore configuration from backup
restore_config() {
    local backup_file="$1"
    local skip_backup="${2:-}"
    local config_file="$USER_CONFIG"
    
    if ! validate_backup "$backup_file"; then
        return 1
    fi
    
    # Backup current config before restoring
    if [ "$skip_backup" != "--no-backup" ] && [ -f "$config_file" ]; then
        log_info "Backing up current configuration before restore..."
        backup_config "pre-restore backup"
    fi
    
    log_info "Restoring configuration from: $(basename "$backup_file")"
    cp "$backup_file" "$config_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to restore configuration from backup"
        return 1
    fi
    
    log_info "Configuration restored successfully"
    log_info "Reloading configuration..."
    
    load_config
    
    return 0
}

# Show backup information
show_backup_info() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo "Backup file not found: $backup_file"
        return 1
    fi
    
    echo "Backup File Information"
    echo "======================="
    echo
    echo "File: $(basename "$backup_file")"
    echo "Path: $backup_file"
    echo "Size: $(stat -c%s "$backup_file" 2>/dev/null || echo "unknown") bytes"
    echo "Modified: $(stat -c%y "$backup_file" 2>/dev/null | cut -d. -f1)"
    echo
    echo "Active Settings (non-commented):"
    echo "--------------------------------"
    grep -v "^#" "$backup_file" | grep "=" | head -n 20
    local total_settings=$(grep -v "^#" "$backup_file" | grep "=" | wc -l)
    if [ "$total_settings" -gt 20 ]; then
        echo "... and $((total_settings - 20)) more settings"
    fi
    echo
    
    return 0
}

# Clean all backups with confirmation
clean_all_backups() {
    local force="${1:-}"
    local backup_dir=$(get_backup_dir)
    
    if [ ! -d "$backup_dir" ]; then
        echo "No backups directory found."
        return 0
    fi
    
    local backup_count=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f 2>/dev/null | wc -l)
    
    if [ "$backup_count" -eq 0 ]; then
        echo "No backups to clean."
        return 0
    fi
    
    if [ "$force" != "--force" ]; then
        echo "Found $backup_count backup(s)."
        read -p "Delete all backups? This cannot be undone. [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "Clean cancelled."
            return 1
        fi
    fi
    
    find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -delete
    echo "All backups deleted."
    
    return 0
}

# Initialize when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Config module loaded"
fi
