#!/bin/bash
# Multi-Report-OMV v2.0
# Core logger module
# Based on SnapRAID Manager logger architecture

# Detect script location
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Ensure log directory exists
LOG_DIR="${LOG_BASE:-$BASE_DIR/logs}"
mkdir -p "$LOG_DIR" 2>/dev/null || {
    echo "WARNING: Cannot create log directory: $LOG_DIR"
    LOG_DIR="/tmp"
    echo "Logging to temporary directory: $LOG_DIR"
}

# Log levels
declare -A LOG_LEVELS
LOG_LEVELS=([debug]=0 [info]=1 [warning]=2 [error]=3)

# Default log level
CURRENT_LOG_LEVEL=1  # info

# Current log file
LOG_FILE=""

# ANSI color codes
TEXT_RESET='\033[0m'
TEXT_RED='\033[0;31m'
TEXT_GREEN='\033[0;32m'
TEXT_YELLOW='\033[0;33m'
TEXT_BLUE='\033[0;34m'
TEXT_PURPLE='\033[0;35m'
TEXT_CYAN='\033[0;36m'
TEXT_WHITE='\033[0;37m'

# Initialize the logging system
init_logging() {
    # If a log file is already set and exists, don't create a new one
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        # Just make sure the initialization flag is set
        export LOGGING_INITIALIZED="true"
        log_debug "Reusing existing log file: $LOG_FILE"
        return 0
    fi
    
    # Create log directory if it doesn't exist
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    # Generate timestamp for log file name
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    export LOG_FILE="${LOG_DIR}/multi-report-omv-${timestamp}.log"
    
    # Create log header
    {
        echo "========================================" 
        echo "Multi-Report-OMV Log"
        echo "Version: $(get_version 2>/dev/null || echo 'Unknown')"
        echo "Started: $(date)"
        echo "========================================" 
        echo ""
    } > "$LOG_FILE"
    
    export LOGGING_INITIALIZED="true"
    log_debug "Logging initialized: $LOG_FILE"
    
    return 0
}

# Core logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    # Check if this log level should be displayed
    if [ "${LOG_LEVELS[$level]}" -lt "$CURRENT_LOG_LEVEL" ]; then
        return 0
    fi
    
    # Format timestamp
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Choose color based on level
    local color=""
    case "$level" in
        debug)   color="$TEXT_CYAN" ;;
        info)    color="$TEXT_GREEN" ;;
        warning) color="$TEXT_YELLOW" ;;
        error)   color="$TEXT_RED" ;;
        *)       color="$TEXT_WHITE" ;;
    esac
    
    # Format level for display
    local level_display=$(echo "$level" | tr '[:lower:]' '[:upper:]')
    
    # Write to console with color
    echo -e "${color}[$timestamp] [$level_display]${TEXT_RESET} $message"
    
    # Write to log file without color
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$level_display] $message" >> "$LOG_FILE"
    fi
}

# Log only to file (no console output)
log_file_only() {
    local level="$1"
    shift
    local message="$*"
    
    # Check log level
    local msg_level="${LOG_LEVELS[$level]:-1}"
    if [ "$msg_level" -lt "$CURRENT_LOG_LEVEL" ]; then
        return 0
    fi
    
    # Format timestamp
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Format level for display
    local level_display=$(echo "$level" | tr '[:lower:]' '[:upper:]')
    
    # Write to log file only
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$level_display] $message" >> "$LOG_FILE"
    fi
}

# Convenience functions
log_debug() {
    log "debug" "$@"
}

log_info() {
    log "info" "$@"
}

log_warning() {
    log "warning" "$@"
}

log_error() {
    log "error" "$@"
}

# Set log level
set_log_level() {
    local level="$1"
    if [ -n "${LOG_LEVELS[$level]}" ]; then
        CURRENT_LOG_LEVEL="${LOG_LEVELS[$level]}"
        log_debug "Log level set to: $level"
    else
        log_error "Invalid log level: $level"
        return 1
    fi
}

# Clean up old log files
cleanup_old_logs() {
    local retention_days="${1:-30}"
    
    log_debug "Cleaning up log files older than $retention_days days"
    
    if [ ! -d "$LOG_DIR" ]; then
        log_debug "Log directory does not exist: $LOG_DIR"
        return 0
    fi
    
    # Find and delete old log files
    local deleted_count=0
    while IFS= read -r -d '' logfile; do
        rm -f "$logfile"
        ((deleted_count++))
        log_debug "Deleted old log file: $(basename "$logfile")"
    done < <(find "$LOG_DIR" -name "multi-report-omv-*.log" -type f -mtime +"$retention_days" -print0 2>/dev/null)
    
    if [ "$deleted_count" -gt 0 ]; then
        log_debug "Deleted $deleted_count old log file(s)"
    else
        log_debug "No log files older than $retention_days days found"
    fi
}

# Initialize logging by default when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    echo "$(get_full_version 2>/dev/null || echo "Multi-Report-OMV Unknown") - Logger Module"
    echo "This module should be sourced, not executed directly."
else
    # Only initialize if not already initialized
    if [ -z "$LOGGING_INITIALIZED" ] || [ -z "$LOG_FILE" ]; then
        init_logging
    fi
fi
