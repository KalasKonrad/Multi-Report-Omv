#!/bin/bash
# Multi-Report-OMV - Core configuration module
#
# This module handles all configuration management for Multi-Report-OMV.
# Functions are organized into logical sections for easy navigation and maintenance.
# Version is dynamically read from VERSION file.

# =======================================================
# TABLE OF CONTENTS
# =======================================================
#
# 1. INITIALIZATION & CONSTANTS
#    - Script location detection
#    - Configuration paths setup
#    - Configuration storage arrays
#
# 2. DEFAULT CONFIGURATION VALUES
#    - init_default_config
#
# 3. CONFIGURATION FILE WRITERS
#    - write_default_config
#    - create_user_config
#    - init_config_files
#
# 4. CONFIGURATION FILE READERS
#    - load_config_file
#    - load_config
#
# 5. CONFIGURATION VALIDATION
#    - validate_config
#
# 6. CONFIGURATION MANAGEMENT
#    - get_config
#    - set_config
#    - save_config
#    - show_config
#
# =======================================================

# -------------------------------------------------------
# 1. INITIALIZATION & CONSTANTS
# -------------------------------------------------------

# Detect script location
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Current configuration version (increment when config format changes)
CURRENT_CONFIG_VERSION="2.3"

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

# -------------------------------------------------------
# 2. DEFAULT CONFIGURATION VALUES
# -------------------------------------------------------

# Default configuration values
init_default_config() {
    # Core settings
    CONFIG["LOG_LEVEL"]="info"
    CONFIG["LOG_RETENTION_DAYS"]="30"
    CONFIG["CONFIG_BACKUP_RETENTION"]="5"  # Number of config backups to keep
    CONFIG["REQUIRE_ROOT"]="false"  # Set to true to require root instead of sudo
    CONFIG["DISABLE_SUDO"]="false"  # Set to true to disable sudo elevation
    CONFIG["KEEP_TEMP_FILES"]="false"  # Set to true to preserve temp files for debugging
    
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
    CONFIG["SELFTEST_HISTORY_RETENTION_DAYS"]="365"
    
    # Short test configuration
    CONFIG["SELFTEST_SHORT_MAX_CONCURRENT"]="2"
    CONFIG["SELFTEST_SHORT_DAYS"]="1,2,3,4,5"
    CONFIG["SELFTEST_SHORT_MIN_DAYS"]="7"
    
    # Long test configuration
    CONFIG["SELFTEST_LONG_MAX_CONCURRENT"]="1"
    CONFIG["SELFTEST_LONG_DAYS"]="6,7"
    CONFIG["SELFTEST_LONG_MIN_DAYS"]="90"
    
    # SMR detection settings
    CONFIG["SMR_CHECK_ENABLED"]="true"
    CONFIG["SMR_AUTO_UPDATE"]="true"
    CONFIG["SMR_IGNORE_ALARMS"]="false"
    
    # Statistical data collection settings
    CONFIG["STATS_ENABLED"]="true"
    CONFIG["STATS_HISTORY_FILE"]="${BASE_DIR}/data/statistical_data/history_raw.csv"
    CONFIG["STATS_HISTORY_HUMAN_FILE"]="${BASE_DIR}/data/statistical_data/history.csv"
    CONFIG["STATS_HUMAN_READABLE"]="true"
    CONFIG["STATS_RETENTION_DAYS"]="730"
    CONFIG["STATS_COLLECT_ON_SELFTEST"]="true"
    CONFIG["STATS_DAILY_COLLECTION"]="true"
    CONFIG["STATS_SKIP_SLEEPING_DRIVES"]="counted"
    CONFIG["STATS_SKIP_MAX_COUNT"]="10"
    
    # SMR check settings
    CONFIG["SMR_CHECK_ENABLED"]="true"
    CONFIG["SMR_CACHE_FILE"]="${BASE_DIR}/data/smr_check/drive_types.cache"
    CONFIG["SMR_WARN_ON_DETECTION"]="true"
    CONFIG["SMR_AUTO_UPDATE_DB"]="false"
    
    # SCT settings
    CONFIG["SCT_ENABLED"]="true"
    CONFIG["SCT_DELTA_HDD"]="10"
    CONFIG["SCT_DELTA_SSD"]="10"
    CONFIG["SCT_DELTA_NVME"]="15"
    
    # Report System Configuration
    CONFIG["REPORT_ENABLED"]="true"
    CONFIG["REPORT_EMAIL"]=""
    CONFIG["REPORT_FORMAT"]="html"
    
    # Weekly Report
    CONFIG["REPORT_WEEKLY_ENABLED"]="true"
    CONFIG["REPORT_WEEKLY_DAY"]="1"
    CONFIG["REPORT_WEEKLY_METRICS"]="temp,workload,errors,tests"
    
    # Monthly Report
    CONFIG["REPORT_MONTHLY_ENABLED"]="true"
    CONFIG["REPORT_MONTHLY_DAY"]="1"
    CONFIG["REPORT_MONTHLY_METRICS"]="temp,workload,errors,tests,wear,helium"
    
    # Quarterly Report
    CONFIG["REPORT_QUARTERLY_ENABLED"]="false"
    CONFIG["REPORT_QUARTERLY_MONTH"]="1,4,7,10"
    CONFIG["REPORT_QUARTERLY_DAY"]="1"
    CONFIG["REPORT_QUARTERLY_METRICS"]="all"
    
    # Yearly Report
    CONFIG["REPORT_YEARLY_ENABLED"]="false"
    CONFIG["REPORT_YEARLY_MONTH"]="1"
    CONFIG["REPORT_YEARLY_DAY"]="1"
    CONFIG["REPORT_YEARLY_METRICS"]="all"
    
    # Custom Report
    CONFIG["REPORT_CUSTOM_ENABLED"]="false"
    CONFIG["REPORT_CUSTOM_SCHEDULE"]="14"
    CONFIG["REPORT_CUSTOM_PERIOD_DAYS"]="14"
    CONFIG["REPORT_CUSTOM_NAME"]="Custom Period Report"
    CONFIG["REPORT_CUSTOM_METRICS"]="temp,workload,errors"
    
    # Metric Inclusions
    CONFIG["REPORT_INCLUDE_TEMP"]="true"
    CONFIG["REPORT_INCLUDE_WORKLOAD"]="true"
    CONFIG["REPORT_INCLUDE_ERRORS"]="true"
    CONFIG["REPORT_INCLUDE_TESTS"]="true"
    CONFIG["REPORT_INCLUDE_WEAR_LEVEL"]="true"
    CONFIG["REPORT_INCLUDE_HELIUM"]="true"
    CONFIG["REPORT_INCLUDE_FLEET_STATS"]="true"
    
    # Alert Thresholds
    CONFIG["REPORT_ALERT_TEMP_MAX"]="50"
    CONFIG["REPORT_ALERT_NEW_REALLOCATED"]="true"
    CONFIG["REPORT_ALERT_PENDING_SECTORS"]="true"
    CONFIG["REPORT_ALERT_CRC_ERRORS"]="true"
    CONFIG["REPORT_ALERT_TEST_FAILURES"]="true"
    
    # Alert Mode and Thresholds
    CONFIG["REPORT_ALERT_MODE"]="new"
    CONFIG["REPORT_ALERT_CRC_TOTAL_THRESHOLD"]="100"
    CONFIG["REPORT_ALERT_CRC_NEW_THRESHOLD"]="1"
    CONFIG["REPORT_ALERT_READ_TOTAL_THRESHOLD"]="100"
    CONFIG["REPORT_ALERT_READ_NEW_THRESHOLD"]="1"
    CONFIG["REPORT_ALERT_WRITE_TOTAL_THRESHOLD"]="100"
    CONFIG["REPORT_ALERT_WRITE_NEW_THRESHOLD"]="1"
    CONFIG["REPORT_ALERT_REALLOC_TOTAL_THRESHOLD"]="10"
    CONFIG["REPORT_ALERT_REALLOC_NEW_THRESHOLD"]="1"
    CONFIG["REPORT_ALERT_SMR"]="true"
    
    # Alert Suppressions
    CONFIG["REPORT_ALERT_SUPPRESS_DRIVES"]=""
}

# -------------------------------------------------------
# 3. CONFIGURATION FILE WRITERS
# -------------------------------------------------------

# Write default configuration file with comments
write_default_config() {
    local config_file="${1:-$DEFAULT_CONFIG}"
    
    log_info "Creating default configuration file: $config_file"
    
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" << 'EOF'
# Multi-Report-OMV Default Configuration
# This file contains all default values
# DO NOT EDIT - Copy settings to multi-report-omv.conf instead

CONFIG_VERSION="2.3"
LOG_LEVEL="info"
LOG_RETENTION_DAYS="30"
CONFIG_BACKUP_RETENTION="5"
REQUIRE_ROOT="false"
DISABLE_SUDO="false"
KEEP_TEMP_FILES="false"

# Email settings
EMAIL_ENABLED="false"
EMAIL_TO=""
EMAIL_FROM="multi-report-omv@$(hostname)"
EMAIL_SUBJECT_PREFIX="[Multi-Report-OMV]"
EMAIL_USE_HTML="true"
EMAIL_LEVEL="always"

# SMART monitoring
SMART_ENABLED="true"
TEMP_WARN_HDD="45"
TEMP_CRIT_HDD="50"
TEMP_WARN_SSD="50"
TEMP_CRIT_SSD="60"
TEMP_WARN_NVME="60"
TEMP_CRIT_NVME="70"

# Statistical data collection
STATS_ENABLED="true"
STATS_SKIP_SLEEPING_DRIVES="counted"
STATS_SKIP_MAX_COUNT="10"
STATS_RETENTION_DAYS="730"
STATS_HUMAN_READABLE="true"

# Self-test settings
SELFTEST_ENABLED="true"
SELFTEST_SHORT_MAX_CONCURRENT="2"
SELFTEST_SHORT_DAYS="1,2,3,4,5"
SELFTEST_SHORT_MIN_DAYS="7"
SELFTEST_LONG_MAX_CONCURRENT="1"
SELFTEST_LONG_DAYS="6,7"
SELFTEST_LONG_MIN_DAYS="90"

# Report settings
REPORT_ENABLED="true"
REPORT_FORMAT="html"
REPORT_WEEKLY_ENABLED="true"
REPORT_WEEKLY_DAY="1"
REPORT_MONTHLY_ENABLED="true"
REPORT_MONTHLY_DAY="1"
REPORT_ALERT_MODE="new"
REPORT_ALERT_SMR="true"
EOF

    log_info "Default configuration file created: $config_file"
    return 0
}

# Create user configuration file
create_user_config() {
    log_info "Creating user configuration file: $USER_CONFIG"
    
    mkdir -p "$(dirname "$USER_CONFIG")"
    
    cat > "$USER_CONFIG" << 'EOF'
# Multi-Report-OMV User Configuration
# This file contains your custom settings.
# Settings here override the defaults in config/defaults.conf

CONFIG_VERSION="2.3"

# -------------------------------------------------------
# CORE SETTINGS
# -------------------------------------------------------
#LOG_LEVEL="info"
#LOG_RETENTION_DAYS="30"

# -------------------------------------------------------
# EMAIL NOTIFICATION SETTINGS
# -------------------------------------------------------
#EMAIL_ENABLED="false"
#EMAIL_TO=""
#EMAIL_FROM=""

# -------------------------------------------------------
# STATISTICAL DATA COLLECTION
# -------------------------------------------------------
#STATS_ENABLED="true"
#STATS_SKIP_SLEEPING_DRIVES="counted"
#STATS_SKIP_MAX_COUNT="10"

# -------------------------------------------------------
# DRIVE SELF-TEST SETTINGS
# -------------------------------------------------------
#SELFTEST_ENABLED="true"
#SELFTEST_SHORT_MAX_CONCURRENT="2"
#SELFTEST_SHORT_MIN_DAYS="7"
#SELFTEST_LONG_MAX_CONCURRENT="1"
#SELFTEST_LONG_MIN_DAYS="90"

# -------------------------------------------------------
# AUTOMATED REPORTS
# -------------------------------------------------------
#REPORT_ENABLED="true"
#REPORT_WEEKLY_ENABLED="true"
#REPORT_MONTHLY_ENABLED="true"
#REPORT_ALERT_SMR="true"

# -------------------------------------------------------
# YOUR CUSTOM SETTINGS
# -------------------------------------------------------
# Add your custom configuration overrides below this line

EOF

    log_info "User configuration file created"
    return 0
}

# Initialize configuration files if they don't exist
init_config_files() {
    local created=false
    
    if [ ! -f "$DEFAULT_CONFIG" ]; then
        write_default_config "$DEFAULT_CONFIG"
        created=true
    fi
    
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
# 4. CONFIGURATION FILE READERS
# -------------------------------------------------------

# Load configuration from file
load_config_file() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_debug "Config file not found: $config_file"
        return 1
    fi
    
    log_debug "Loading configuration from: $config_file"
    
    while IFS='=' read -r key value; do
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        value="${value%\"}"
        value="${value#\"}"
        
        CONFIG["$key"]="$value"
        
    done < "$config_file"
    
    log_debug "Configuration loaded from: $config_file"
    return 0
}

# Load all configuration
load_config() {
    local skip_validation="${1:-false}"
    
    log_debug "Initializing configuration system"
    
    init_default_config
    init_config_files
    
    if [ -f "$USER_CONFIG" ]; then
        load_config_file "$USER_CONFIG"
    else
        log_warning "User config not found: $USER_CONFIG"
        log_info "Creating new user configuration file"
        create_user_config
    fi
    
    # Check for configuration migration (if migration module is loaded)
    if type check_migration_on_startup >/dev/null 2>&1; then
        check_migration_on_startup
    fi
    
    if [ "$skip_validation" != "true" ]; then
        validate_config
    fi
    
    if [ -n "${CONFIG[LOG_LEVEL]}" ]; then
        set_log_level "${CONFIG[LOG_LEVEL]}"
    fi
    
    log_debug "Configuration system initialized"
    return 0
}

# -------------------------------------------------------
# 5. CONFIGURATION VALIDATION
# -------------------------------------------------------

# Validate configuration
validate_config() {
    log_debug "Validating configuration"
    
    local has_errors=false
    
    if [ "${CONFIG[EMAIL_ENABLED]}" = "true" ]; then
        if [ -z "${CONFIG[EMAIL_TO]}" ]; then
            log_error "EMAIL_ENABLED is true but EMAIL_TO is not set"
            has_errors=true
        fi
    fi
    
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

# -------------------------------------------------------
# 6. CONFIGURATION MANAGEMENT
# -------------------------------------------------------

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

# Save configuration to file
save_config() {
    local config_file="${1:-$USER_CONFIG}"
    
    log_info "Saving configuration to: $config_file"
    
    mkdir -p "$(dirname "$config_file")"
    
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

# Module initialization
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if type log_debug >/dev/null 2>&1; then
        log_debug "Config module loaded"
    fi
fi
