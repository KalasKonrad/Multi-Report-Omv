#!/bin/bash
#
# report.sh - Automated Drive Health Report Plugin
# Part of Multi-Report-OMV v2.0
#
# Generates scheduled reports (weekly, monthly, quarterly, yearly, custom)
# with configurable metrics and email delivery.
#

# Core modules (logger, utils, config) are sourced by main script
# Plugins are always loaded via execute_plugin() which ensures core modules are available

# Plugin metadata
PLUGIN_NAME="report"
PLUGIN_VERSION="1.0.0"

# Data directory for timestamp tracking
REPORT_DATA_DIR="${BASE_DIR}/data/report"
mkdir -p "$REPORT_DATA_DIR"

# ============================================================================
# Configuration Loading
# ============================================================================

load_report_config() {
    REPORT_ENABLED="${CONFIG[REPORT_ENABLED]:-true}"
    REPORT_EMAIL="${CONFIG[REPORT_EMAIL]:-${CONFIG[EMAIL_TO]}}"
    REPORT_FORMAT="${CONFIG[REPORT_FORMAT]:-html}"
    
    # Weekly
    REPORT_WEEKLY_ENABLED="${CONFIG[REPORT_WEEKLY_ENABLED]:-true}"
    REPORT_WEEKLY_DAY="${CONFIG[REPORT_WEEKLY_DAY]:-1}"
    REPORT_WEEKLY_METRICS="${CONFIG[REPORT_WEEKLY_METRICS]:-temp,workload,errors,tests}"
    
    # Monthly
    REPORT_MONTHLY_ENABLED="${CONFIG[REPORT_MONTHLY_ENABLED]:-true}"
    REPORT_MONTHLY_DAY="${CONFIG[REPORT_MONTHLY_DAY]:-1}"
    REPORT_MONTHLY_METRICS="${CONFIG[REPORT_MONTHLY_METRICS]:-temp,workload,errors,tests,wear,helium}"
    
    # Quarterly
    REPORT_QUARTERLY_ENABLED="${CONFIG[REPORT_QUARTERLY_ENABLED]:-false}"
    REPORT_QUARTERLY_MONTH="${CONFIG[REPORT_QUARTERLY_MONTH]:-1,4,7,10}"
    REPORT_QUARTERLY_DAY="${CONFIG[REPORT_QUARTERLY_DAY]:-1}"
    REPORT_QUARTERLY_METRICS="${CONFIG[REPORT_QUARTERLY_METRICS]:-all}"
    
    # Yearly
    REPORT_YEARLY_ENABLED="${CONFIG[REPORT_YEARLY_ENABLED]:-false}"
    REPORT_YEARLY_MONTH="${CONFIG[REPORT_YEARLY_MONTH]:-1}"
    REPORT_YEARLY_DAY="${CONFIG[REPORT_YEARLY_DAY]:-1}"
    REPORT_YEARLY_METRICS="${CONFIG[REPORT_YEARLY_METRICS]:-all}"
    
    # Custom
    REPORT_CUSTOM_ENABLED="${CONFIG[REPORT_CUSTOM_ENABLED]:-false}"
    REPORT_CUSTOM_SCHEDULE="${CONFIG[REPORT_CUSTOM_SCHEDULE]:-14}"
    REPORT_CUSTOM_PERIOD_DAYS="${CONFIG[REPORT_CUSTOM_PERIOD_DAYS]:-14}"
    REPORT_CUSTOM_NAME="${CONFIG[REPORT_CUSTOM_NAME]:-Custom Period Report}"
    REPORT_CUSTOM_METRICS="${CONFIG[REPORT_CUSTOM_METRICS]:-temp,workload,errors}"
    
    # Metrics
    REPORT_INCLUDE_TEMP="${CONFIG[REPORT_INCLUDE_TEMP]:-true}"
    REPORT_INCLUDE_WORKLOAD="${CONFIG[REPORT_INCLUDE_WORKLOAD]:-true}"
    REPORT_INCLUDE_ERRORS="${CONFIG[REPORT_INCLUDE_ERRORS]:-true}"
    REPORT_INCLUDE_TESTS="${CONFIG[REPORT_INCLUDE_TESTS]:-true}"
    REPORT_INCLUDE_WEAR_LEVEL="${CONFIG[REPORT_INCLUDE_WEAR_LEVEL]:-true}"
    REPORT_INCLUDE_HELIUM="${CONFIG[REPORT_INCLUDE_HELIUM]:-true}"
    REPORT_INCLUDE_FLEET_STATS="${CONFIG[REPORT_INCLUDE_FLEET_STATS]:-true}"
    
    # Alerts
    REPORT_ALERT_TEMP_MAX="${CONFIG[REPORT_ALERT_TEMP_MAX]:-50}"
    REPORT_ALERT_NEW_REALLOCATED="${CONFIG[REPORT_ALERT_NEW_REALLOCATED]:-true}"
    REPORT_ALERT_PENDING_SECTORS="${CONFIG[REPORT_ALERT_PENDING_SECTORS]:-true}"
    REPORT_ALERT_CRC_ERRORS="${CONFIG[REPORT_ALERT_CRC_ERRORS]:-true}"
    REPORT_ALERT_TEST_FAILURES="${CONFIG[REPORT_ALERT_TEST_FAILURES]:-true}"
    
    # Get stats file location
    STATS_HISTORY_FILE="${CONFIG[STATS_HISTORY_FILE]:-${BASE_DIR}/data/statistical_data/history_raw.csv}"
    
    log_debug "Report configuration loaded"
    log_debug "  Enabled: $REPORT_ENABLED"
    log_debug "  Email: $REPORT_EMAIL"
    log_debug "  Format: $REPORT_FORMAT"
}

# ============================================================================
# Schedule Checking Functions
# ============================================================================

# Get timestamp file for report type
get_timestamp_file() {
    local report_type="$1"
    echo "$REPORT_DATA_DIR/last_${report_type}.timestamp"
}

# Get last run timestamp
get_last_run() {
    local report_type="$1"
    local timestamp_file=$(get_timestamp_file "$report_type")
    
    if [ -f "$timestamp_file" ]; then
        cat "$timestamp_file"
    else
        echo "0"
    fi
}

# Update last run timestamp
update_last_run() {
    local report_type="$1"
    local timestamp_file=$(get_timestamp_file "$report_type")
    date +%s > "$timestamp_file"
    log_debug "Updated $report_type timestamp: $(date)"
}

# Check if weekly report is due
is_weekly_due() {
    log_debug "    Checking weekly schedule..."
    [ "$REPORT_WEEKLY_ENABLED" != "true" ] && log_debug "      Not enabled" && return 1
    
    local current_dow=$(date +%u)  # 1=Monday, 7=Sunday
    local last_run=$(get_last_run "weekly")
    local current_time=$(date +%s)
    local days_since=$((  (current_time - last_run) / 86400 ))
    
    log_debug "      Current day: $current_dow, Configured day: $REPORT_WEEKLY_DAY"
    log_debug "      Days since last run: $days_since"
    
    # Run if it's the configured day and at least 6 days since last run
    if [ "$current_dow" = "$REPORT_WEEKLY_DAY" ] && [ $days_since -ge 6 ]; then
        log_debug "      Weekly report IS due"
        return 0
    fi
    
    log_debug "      Weekly report is NOT due"
    return 1
}

# Check if monthly report is due
is_monthly_due() {
    [ "$REPORT_MONTHLY_ENABLED" != "true" ] && return 1
    
    local current_dom=$(date +%d)  # Day of month
    local current_dom_int=$((10#$current_dom))  # Remove leading zero
    local target_day=$((10#$REPORT_MONTHLY_DAY))
    local last_run=$(get_last_run "monthly")
    local current_time=$(date +%s)
    local days_since=$(( (current_time - last_run) / 86400 ))
    
    # Run if it's the configured day and at least 25 days since last run
    if [ $current_dom_int -eq $target_day ] && [ $days_since -ge 25 ]; then
        return 0
    fi
    
    return 1
}

# Check if quarterly report is due
is_quarterly_due() {
    [ "$REPORT_QUARTERLY_ENABLED" != "true" ] && return 1
    
    local current_month=$(date +%m)
    local current_month_int=$((10#$current_month))
    local current_dom=$(date +%d)
    local current_dom_int=$((10#$current_dom))
    local target_day=$((10#$REPORT_QUARTERLY_DAY))
    local last_run=$(get_last_run "quarterly")
    local current_time=$(date +%s)
    local days_since=$(( (current_time - last_run) / 86400 ))
    
    # Check if current month is in the configured list
    local is_quarter_month=false
    IFS=',' read -ra MONTHS <<< "$REPORT_QUARTERLY_MONTH"
    for month in "${MONTHS[@]}"; do
        month_int=$((10#$month))
        if [ $current_month_int -eq $month_int ]; then
            is_quarter_month=true
            break
        fi
    done
    
    # Run if it's a quarter month, the configured day, and at least 80 days since last run
    if [ "$is_quarter_month" = "true" ] && [ $current_dom_int -eq $target_day ] && [ $days_since -ge 80 ]; then
        return 0
    fi
    
    return 1
}

# Check if yearly report is due
is_yearly_due() {
    [ "$REPORT_YEARLY_ENABLED" != "true" ] && return 1
    
    local current_month=$(date +%m)
    local current_month_int=$((10#$current_month))
    local target_month=$((10#$REPORT_YEARLY_MONTH))
    local current_dom=$(date +%d)
    local current_dom_int=$((10#$current_dom))
    local target_day=$((10#$REPORT_YEARLY_DAY))
    local last_run=$(get_last_run "yearly")
    local current_time=$(date +%s)
    local days_since=$(( (current_time - last_run) / 86400 ))
    
    # Run if it's the configured month/day and at least 350 days since last run
    if [ $current_month_int -eq $target_month ] && [ $current_dom_int -eq $target_day ] && [ $days_since -ge 350 ]; then
        return 0
    fi
    
    return 1
}

# Check if custom report is due
is_custom_due() {
    log_debug "    Checking custom schedule..."
    [ "$REPORT_CUSTOM_ENABLED" != "true" ] && log_debug "      Not enabled" && return 1
    
    local last_run=$(get_last_run "custom")
    local current_time=$(date +%s)
    local days_since=$(( (current_time - last_run) / 86400 ))
    local schedule_days=$((10#$REPORT_CUSTOM_SCHEDULE))
    
    log_debug "      Days since last run: $days_since, Schedule: every $schedule_days days"
    
    # Run if configured number of days have passed
    if [ $days_since -ge $schedule_days ]; then
        log_debug "      Custom report IS due"
        return 0
    fi
    
    log_debug "      Custom report is NOT due"
    return 1
}

# ============================================================================
# CSV Data Query Functions
# ============================================================================

# Get date range for query (format: YYYY-MM-DD)
# For a 7-day period, we want the last 7 complete days (not including today)
get_date_range() {
    local days_back="$1"
    local end_date=$(date -d "1 day ago" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)
    local start_date=$(date -d "$days_back days ago" +%Y-%m-%d 2>/dev/null || date -v-${days_back}d +%Y-%m-%d 2>/dev/null)
    
    echo "$start_date|$end_date"
}

# Get actual date range from CSV data (what dates are actually present)
get_actual_date_range() {
    local start_date="$1"
    local end_date="$2"
    
    if [ ! -f "$STATS_HISTORY_FILE" ]; then
        echo "$start_date|$end_date"
        return
    fi
    
    # Get actual min and max dates from CSV within the requested range
    local actual_range=$(awk -F',' -v start="$start_date" -v end="$end_date" '
        NR==1 {next}  # Skip header
        $1 >= start && $1 <= end {
            if (min == "" || $1 < min) min = $1
            if (max == "" || $1 > max) max = $1
        }
        END {
            if (min != "" && max != "") {
                print min "|" max
            } else {
                print start "|" end
            }
        }
    ' "$STATS_HISTORY_FILE")
    
    echo "$actual_range"
}

# Get unique list of drives from CSV
get_drive_list() {
    if [ ! -f "$STATS_HISTORY_FILE" ]; then
        log_error "Stats history file not found: $STATS_HISTORY_FILE"
        return 1
    fi
    
    # Get unique drive IDs (column 3), skip header
    tail -n +2 "$STATS_HISTORY_FILE" | cut -d',' -f3 | sort -u
}

# Query CSV for specific drive and date range
# Returns all matching rows
query_drive_data() {
    local drive_id="$1"
    local start_date="$2"
    local end_date="$3"
    
    if [ ! -f "$STATS_HISTORY_FILE" ]; then
        return 1
    fi
    
    # Extract rows for this drive within date range
    awk -F',' -v drive="$drive_id" -v start="$start_date" -v end="$end_date" '
        NR==1 {next}  # Skip header
        $3 == drive && $1 >= start && $1 <= end {print}
    ' "$STATS_HISTORY_FILE"
}

# Get most recent entry for a drive
get_latest_drive_data() {
    local drive_id="$1"
    
    if [ ! -f "$STATS_HISTORY_FILE" ]; then
        return 1
    fi
    
    # Get last row for this drive
    awk -F',' -v drive="$drive_id" '
        NR==1 {next}  # Skip header
        $3 == drive {last=$0}
        END {if (last) print last}
    ' "$STATS_HISTORY_FILE"
}

# ============================================================================
# Statistics Calculation Functions
# ============================================================================

# Calculate temperature statistics
calc_temp_stats() {
    local drive_data="$1"
    
    # Column 13 = current temp
    # We need: min, max, avg, current
    echo "$drive_data" | awk -F',' '
    BEGIN {
        min=999; max=0; sum=0; count=0; current="N/A"
    }
    {
        temp = $13
        if (temp != "N/A" && temp != "") {
            gsub(/[^0-9]/, "", temp)  # Remove non-numeric
            if (temp > 0) {
                if (temp < min) min = temp
                if (temp > max) max = temp
                sum += temp
                count++
                current = temp
            }
        }
    }
    END {
        avg = (count > 0) ? int(sum/count) : 0
        if (min == 999) min = 0
        printf "%s,%s,%s,%s\n", current, min, max, avg
    }
    '
}

# Calculate workload statistics
calc_workload_stats() {
    local drive_data="$1"
    local first_row=$(echo "$drive_data" | head -1)
    local last_row=$(echo "$drive_data" | tail -1)
    
    # Columns: 20=power_hours, 50=lbas_written, 51=lbas_read
    local power_start=$(echo "$first_row" | cut -d',' -f20)
    local power_end=$(echo "$last_row" | cut -d',' -f20)
    local lbas_written_start=$(echo "$first_row" | cut -d',' -f50)
    local lbas_written_end=$(echo "$last_row" | cut -d',' -f50)
    local lbas_read_start=$(echo "$first_row" | cut -d',' -f51)
    local lbas_read_end=$(echo "$last_row" | cut -d',' -f51)
    
    # Calculate deltas
    local power_delta=0
    if [ "$power_start" != "N/A" ] && [ "$power_end" != "N/A" ] && [ -n "$power_start" ] && [ -n "$power_end" ]; then
        power_delta=$((power_end - power_start))
    fi
    
    local written_delta=0
    if [ "$lbas_written_start" != "N/A" ] && [ "$lbas_written_end" != "N/A" ] && [ -n "$lbas_written_start" ] && [ -n "$lbas_written_end" ]; then
        written_delta=$((lbas_written_end - lbas_written_start))
    fi
    
    local read_delta=0
    if [ "$lbas_read_start" != "N/A" ] && [ "$lbas_read_end" != "N/A" ] && [ -n "$lbas_read_start" ] && [ -n "$lbas_read_end" ]; then
        read_delta=$((lbas_read_end - lbas_read_start))
    fi
    
    # Convert LBAs to human readable (512-byte sectors)
    local written_bytes=$((written_delta * 512))
    local read_bytes=$((read_delta * 512))
    local written_human=$(format_bytes_human "$written_bytes")
    local read_human=$(format_bytes_human "$read_bytes")
    
    echo "$power_delta|$written_human|$read_human"
}

# Calculate error statistics
calc_error_stats() {
    local drive_data="$1"
    local first_row=$(echo "$drive_data" | head -1)
    local last_row=$(echo "$drive_data" | tail -1)
    
    # Columns: 27=read_errors, 29=write_errors, 30=reallocated, 33=pending, 34=uncorrectable, 37=udma_crc
    local read_start=$(echo "$first_row" | cut -d',' -f27)
    local read_end=$(echo "$last_row" | cut -d',' -f27)
    local write_start=$(echo "$first_row" | cut -d',' -f29)
    local write_end=$(echo "$last_row" | cut -d',' -f29)
    local realloc_start=$(echo "$first_row" | cut -d',' -f30)
    local realloc_end=$(echo "$last_row" | cut -d',' -f30)
    local pending=$(echo "$last_row" | cut -d',' -f33)
    local uncorrectable=$(echo "$last_row" | cut -d',' -f34)
    local crc_start=$(echo "$first_row" | cut -d',' -f37)
    local crc_end=$(echo "$last_row" | cut -d',' -f37)
    
    # Calculate new errors
    local new_realloc=0
    if [ "$realloc_start" != "N/A" ] && [ "$realloc_end" != "N/A" ] && [ -n "$realloc_start" ] && [ -n "$realloc_end" ]; then
        new_realloc=$((realloc_end - realloc_start))
        [ $new_realloc -lt 0 ] && new_realloc=0
    fi
    
    local new_crc=0
    if [ "$crc_start" != "N/A" ] && [ "$crc_end" != "N/A" ] && [ -n "$crc_start" ] && [ -n "$crc_end" ]; then
        new_crc=$((crc_end - crc_start))
        [ $new_crc -lt 0 ] && new_crc=0
    fi
    
    local new_read=0
    if [ "$read_start" != "N/A" ] && [ "$read_end" != "N/A" ] && [ -n "$read_start" ] && [ -n "$read_end" ]; then
        new_read=$((read_end - read_start))
        [ $new_read -lt 0 ] && new_read=0
    fi
    
    local new_write=0
    if [ "$write_start" != "N/A" ] && [ "$write_end" != "N/A" ] && [ -n "$write_start" ] && [ -n "$write_end" ]; then
        new_write=$((write_end - write_start))
        [ $new_write -lt 0 ] && new_write=0
    fi
    
    # Clean up N/A values for totals
    [ "$realloc_end" = "N/A" ] || [ -z "$realloc_end" ] && realloc_end=0
    [ "$pending" = "N/A" ] || [ -z "$pending" ] && pending=0
    [ "$uncorrectable" = "N/A" ] || [ -z "$uncorrectable" ] && uncorrectable=0
    [ "$crc_end" = "N/A" ] || [ -z "$crc_end" ] && crc_end=0
    [ "$read_end" = "N/A" ] || [ -z "$read_end" ] && read_end=0
    [ "$write_end" = "N/A" ] || [ -z "$write_end" ] && write_end=0
    
    echo "$realloc_end|$new_realloc|$pending|$uncorrectable|$crc_end|$new_crc|$read_end|$new_read|$write_end|$new_write"
}

# Get drive info (model, mount, status, etc.)
get_drive_info() {
    local latest_data="$1"
    
    # Columns: 5=model, 6=mountpoint, 7=fs_name, 10=drive_type, 12=smart_status, 20=power_hours, 50=smr_status
    local model=$(echo "$latest_data" | cut -d',' -f5)
    local mountpoint=$(echo "$latest_data" | cut -d',' -f6)
    local fs_name=$(echo "$latest_data" | cut -d',' -f7)
    local smart_status=$(echo "$latest_data" | cut -d',' -f12)
    local power_hours=$(echo "$latest_data" | cut -d',' -f20)
    local smr_status=$(echo "$latest_data" | cut -d',' -f50)
    local drive_type=$(echo "$latest_data" | cut -d',' -f10)
    
    # Calculate drive age in years, months, days
    local drive_age="0y 0m 0d"
    if [ "$power_hours" != "N/A" ] && [ -n "$power_hours" ]; then
        drive_age=$(format_hours_to_age "$power_hours")
    fi
    
    echo "$model|$mountpoint|$fs_name|$smart_status|$power_hours|$drive_age|$smr_status|$drive_type"
}

# Format hours into years, months, days
format_hours_to_age() {
    local hours="$1"
    
    if [ -z "$hours" ] || [ "$hours" = "N/A" ]; then
        echo "0y 0m 0d"
        return
    fi
    
    # Calculate years (8760 hours per year)
    local years=$((hours / 8760))
    local remaining=$((hours % 8760))
    
    # Calculate months (730 hours per month average)
    local months=$((remaining / 730))
    remaining=$((remaining % 730))
    
    # Calculate days (24 hours per day)
    local days=$((remaining / 24))
    
    echo "${years}y ${months}m ${days}d"
}

# Get SSD/Helium specific stats
get_special_stats() {
    local latest_data="$1"
    
    # Columns: 23=helium_level, 24=wear_level
    local helium=$(echo "$latest_data" | cut -d',' -f23)
    local wear=$(echo "$latest_data" | cut -d',' -f24)
    
    [ "$helium" = "N/A" ] || [ -z "$helium" ] && helium=""
    [ "$wear" = "N/A" ] || [ -z "$wear" ] && wear=""
    
    echo "$helium|$wear"
}

# Get skip counter stats for a drive
get_skip_stats() {
    local drive_serial="$1"
    local start_date="$2"
    local end_date="$3"
    local skip_counter_file="$(dirname "$STATS_HISTORY_FILE")/skip_counters.csv"
    local skip_history_file="$(dirname "$STATS_HISTORY_FILE")/skip_history.csv"
    
    # Get current skip count
    local current_skip_count=0
    if [ -f "$skip_counter_file" ]; then
        current_skip_count=$(awk -F',' -v s="$drive_serial" '$1 == s {print $2; exit}' "$skip_counter_file" 2>/dev/null)
        current_skip_count="${current_skip_count:-0}"
    fi
    
    # Get skip/collect counts during report period
    local times_skipped=0
    local times_collected=0
    
    if [ -f "$skip_history_file" ]; then
        # Count skipped events in period
        times_skipped=$(awk -F',' -v s="$drive_serial" -v start="$start_date" -v end="$end_date" '
            $2 == s && $1 >= start && $1 <= end && $4 == "skipped" {count++}
            END {print count+0}
        ' "$skip_history_file")
        
        # Count collected events in period
        times_collected=$(awk -F',' -v s="$drive_serial" -v start="$start_date" -v end="$end_date" '
            $2 == s && $1 >= start && $1 <= end && $4 == "collected" {count++}
            END {print count+0}
        ' "$skip_history_file")
    fi
    
    # Return: current_count|times_skipped|times_collected
    echo "$current_skip_count|$times_skipped|$times_collected"
}

# ============================================================================
# Alert Detection Functions
# ============================================================================

# Check for alerts on a drive
check_drive_alerts() {
    local drive_id="$1"
    local temp_max="$2"
    local realloc_total="$3"
    local new_realloc="$4"
    local pending="$5"
    local crc_total="$6"
    local crc_new="$7"
    local read_total="$8"
    local read_new="$9"
    local write_total="${10}"
    local write_new="${11}"
    local smart_status="${12}"
    local smr_status="${13}"
    
    local alerts=""
    local alert_mode="${REPORT_ALERT_MODE:-new}"
    local smr_alert_enabled="${REPORT_ALERT_SMR:-true}"
    
    # Check if drive is in suppression list
    local suppress_drives="${REPORT_ALERT_SUPPRESS_DRIVES}"
    if [ -n "$suppress_drives" ]; then
        if echo ",$suppress_drives," | grep -q ",$drive_id,"; then
            log_debug "Drive $drive_id is in suppression list, skipping alerts"
            return 0
        fi
    fi
    
    # SMR Drive alert (only alert if drive is actually SMR, not CMR)
    if [ "$smr_alert_enabled" = "true" ]; then
        if [ -n "$smr_status" ] && [ "$smr_status" != "N/A" ] && [ "$smr_status" != "Unknown" ] && [ "$smr_status" != "CMR" ]; then
            alerts="${alerts}SMR drive detected ($smr_status); "
        fi
    fi
    
    # Temperature alert
    local temp_threshold="${REPORT_ALERT_TEMP_MAX:-50}"
    if [ -n "$temp_threshold" ] && [ "$temp_max" != "N/A" ] && [ $temp_max -gt $temp_threshold ]; then
        alerts="${alerts}High temperature (max: ${temp_max}°C); "
    fi
    
    # Reallocated sectors alerts
    local realloc_total_threshold="${REPORT_ALERT_REALLOC_TOTAL_THRESHOLD:-10}"
    local realloc_new_threshold="${REPORT_ALERT_REALLOC_NEW_THRESHOLD:-1}"
    
    case "$alert_mode" in
        new)
            if [ $new_realloc -ge $realloc_new_threshold ]; then
                alerts="${alerts}${new_realloc} new reallocated sector(s); "
            fi
            ;;
        total)
            if [ $realloc_total -ge $realloc_total_threshold ]; then
                alerts="${alerts}${realloc_total} total reallocated sector(s); "
            fi
            ;;
        both)
            if [ $new_realloc -ge $realloc_new_threshold ] || [ $realloc_total -ge $realloc_total_threshold ]; then
                alerts="${alerts}${realloc_total} reallocated sectors (${new_realloc} new); "
            fi
            ;;
    esac
    
    # Pending sectors (always alert on any pending)
    if [ $pending -gt 0 ]; then
        alerts="${alerts}${pending} pending sector(s); "
    fi
    
    # CRC errors alerts
    local crc_total_threshold="${REPORT_ALERT_CRC_TOTAL_THRESHOLD:-100}"
    local crc_new_threshold="${REPORT_ALERT_CRC_NEW_THRESHOLD:-1}"
    
    case "$alert_mode" in
        new)
            if [ $crc_new -ge $crc_new_threshold ]; then
                alerts="${alerts}${crc_new} new CRC error(s); "
            fi
            ;;
        total)
            if [ $crc_total -ge $crc_total_threshold ]; then
                alerts="${alerts}${crc_total} total CRC error(s); "
            fi
            ;;
        both)
            if [ $crc_new -ge $crc_new_threshold ] || [ $crc_total -ge $crc_total_threshold ]; then
                alerts="${alerts}${crc_total} CRC errors (${crc_new} new); "
            fi
            ;;
    esac
    
    # Read errors alerts
    local read_total_threshold="${REPORT_ALERT_READ_TOTAL_THRESHOLD:-100}"
    local read_new_threshold="${REPORT_ALERT_READ_NEW_THRESHOLD:-1}"
    
    case "$alert_mode" in
        new)
            if [ $read_new -ge $read_new_threshold ]; then
                alerts="${alerts}${read_new} new read error(s); "
            fi
            ;;
        total)
            if [ $read_total -ge $read_total_threshold ]; then
                alerts="${alerts}${read_total} total read error(s); "
            fi
            ;;
        both)
            if [ $read_new -ge $read_new_threshold ] || [ $read_total -ge $read_total_threshold ]; then
                alerts="${alerts}${read_total} read errors (${read_new} new); "
            fi
            ;;
    esac
    
    # Write errors alerts
    local write_total_threshold="${REPORT_ALERT_WRITE_TOTAL_THRESHOLD:-100}"
    local write_new_threshold="${REPORT_ALERT_WRITE_NEW_THRESHOLD:-1}"
    
    case "$alert_mode" in
        new)
            if [ $write_new -ge $write_new_threshold ]; then
                alerts="${alerts}${write_new} new write error(s); "
            fi
            ;;
        total)
            if [ $write_total -ge $write_total_threshold ]; then
                alerts="${alerts}${write_total} total write error(s); "
            fi
            ;;
        both)
            if [ $write_new -ge $write_new_threshold ] || [ $write_total -ge $write_total_threshold ]; then
                alerts="${alerts}${write_total} write errors (${write_new} new); "
            fi
            ;;
    esac
    
    # SMART status
    if [ "$smart_status" != "PASSED" ]; then
        alerts="${alerts}SMART status: ${smart_status}; "
    fi
    
    echo "$alerts"
}

# ============================================================================
# Report Generation Functions
# ============================================================================

# Generate report
generate_report() {
    local report_type="$1"
    local period_days="$2"
    local metrics="$3"
    local report_name="$4"
    
    log_info "Generating $report_type report (period: $period_days days)"
    log_debug "  Metrics: $metrics"
    log_debug "  Report name: $report_name"
    
    # Get intended date range for query
    local date_range=$(get_date_range "$period_days")
    local query_start=$(echo "$date_range" | cut -d'|' -f1)
    local query_end=$(echo "$date_range" | cut -d'|' -f2)
    
    log_debug "  Intended date range: $query_start to $query_end"
    
    # Get actual date range from data
    local actual_range=$(get_actual_date_range "$query_start" "$query_end")
    local start_date=$(echo "$actual_range" | cut -d'|' -f1)
    local end_date=$(echo "$actual_range" | cut -d'|' -f2)
    
    log_debug "  Actual date range: $start_date to $end_date"
    
    # Get list of drives
    local drives=$(get_drive_list)
    if [ -z "$drives" ]; then
        log_error "No drives found in statistics data"
        return 1
    fi
    
    local drive_count=$(echo "$drives" | wc -l)
    log_debug "  Found $drive_count drive(s)"
    
    # Collect data for all drives
    local report_data=""
    local alert_data=""
    local total_alerts=0
    local total_datapoints=0
    
    for drive in $drives; do
        log_debug "  Processing drive: $drive"
        
        # Get drive data for period (use query range to get all possible data)
        local drive_data=$(query_drive_data "$drive" "$query_start" "$query_end")
        if [ -z "$drive_data" ]; then
            log_debug "    No data for $drive in period"
            continue
        fi
        
        # Count datapoints for this drive
        local drive_datapoints=$(echo "$drive_data" | wc -l)
        total_datapoints=$((total_datapoints + drive_datapoints))
        log_debug "    Found $drive_datapoints datapoint(s) for $drive"
        
        # Get latest data
        local latest=$(get_latest_drive_data "$drive")
        
        # Calculate statistics
        local temp_stats=$(calc_temp_stats "$drive_data")
        local workload_stats=$(calc_workload_stats "$drive_data")
        local error_stats=$(calc_error_stats "$drive_data")
        local drive_info=$(get_drive_info "$latest")
        local special_stats=$(get_special_stats "$latest")
        
        # Parse stats
        local temp_current=$(echo "$temp_stats" | cut -d',' -f1)
        local temp_min=$(echo "$temp_stats" | cut -d',' -f2)
        local temp_max=$(echo "$temp_stats" | cut -d',' -f3)
        local temp_avg=$(echo "$temp_stats" | cut -d',' -f4)
        
        local power_delta=$(echo "$workload_stats" | cut -d'|' -f1)
        local data_written=$(echo "$workload_stats" | cut -d'|' -f2)
        local data_read=$(echo "$workload_stats" | cut -d'|' -f3)
        
        local realloc_total=$(echo "$error_stats" | cut -d'|' -f1)
        local realloc_new=$(echo "$error_stats" | cut -d'|' -f2)
        local pending=$(echo "$error_stats" | cut -d'|' -f3)
        local uncorrectable=$(echo "$error_stats" | cut -d'|' -f4)
        local crc_total=$(echo "$error_stats" | cut -d'|' -f5)
        local crc_new=$(echo "$error_stats" | cut -d'|' -f6)
        local read_total=$(echo "$error_stats" | cut -d'|' -f7)
        local read_new=$(echo "$error_stats" | cut -d'|' -f8)
        local write_total=$(echo "$error_stats" | cut -d'|' -f9)
        local write_new=$(echo "$error_stats" | cut -d'|' -f10)
        
        local model=$(echo "$drive_info" | cut -d'|' -f1)
        local mountpoint=$(echo "$drive_info" | cut -d'|' -f2)
        local fs_name=$(echo "$drive_info" | cut -d'|' -f3)
        local smart_status=$(echo "$drive_info" | cut -d'|' -f4)
        local power_hours=$(echo "$drive_info" | cut -d'|' -f5)
        local drive_age=$(echo "$drive_info" | cut -d'|' -f6)
        local smr_status=$(echo "$drive_info" | cut -d'|' -f7)
        local drive_type=$(echo "$drive_info" | cut -d'|' -f8)
        
        local helium=$(echo "$special_stats" | cut -d'|' -f1)
        local wear=$(echo "$special_stats" | cut -d'|' -f2)
        
        # Get drive serial for skip counter lookup (column 11 in CSV)
        local drive_serial=$(echo "$latest" | cut -d',' -f11)
        local skip_stats=$(get_skip_stats "$drive_serial" "$start_date" "$end_date")
        local skip_current=$(echo "$skip_stats" | cut -d'|' -f1)
        local skip_times_skipped=$(echo "$skip_stats" | cut -d'|' -f2)
        local skip_times_collected=$(echo "$skip_stats" | cut -d'|' -f3)
        
        # Check for alerts
        local alerts=$(check_drive_alerts "$drive" "$temp_max" "$realloc_total" "$realloc_new" "$pending" "$crc_total" "$crc_new" "$read_total" "$read_new" "$write_total" "$write_new" "$smart_status" "$smr_status")
        if [ -n "$alerts" ]; then
            alert_data="${alert_data}${drive}|${model}|${alerts}\n"
            total_alerts=$((total_alerts + 1))
        fi
        
        # Store drive data (pipe-delimited for easy parsing in template)
        report_data="${report_data}DRIVE|${drive}|${model}|${fs_name}|${smart_status}|${drive_type}\n"
        report_data="${report_data}TEMP|${temp_current}|${temp_min}|${temp_max}|${temp_avg}\n"
        report_data="${report_data}WORKLOAD|${power_delta}|${data_written}|${data_read}|${power_hours}|${drive_age}\n"
        report_data="${report_data}ERRORS|${realloc_total}|${realloc_new}|${pending}|${uncorrectable}|${crc_total}|${crc_new}|${read_total}|${read_new}|${write_total}|${write_new}\n"
        report_data="${report_data}SPECIAL|${helium}|${wear}|${smr_status}\n"
        report_data="${report_data}SKIPCOUNT|${skip_current}|${skip_times_skipped}|${skip_times_collected}\n"
        report_data="${report_data}---\n"
    done
    
    # Generate report based on format
    local report_file="$REPORT_DATA_DIR/${report_type}_report_$(date +%Y%m%d).txt"
    
    log_debug "  Total datapoints collected: $total_datapoints"
    log_debug "  Total alerts: $total_alerts"
    log_debug "  Report format: $REPORT_FORMAT"
    log_debug "  Report file: $report_file"
    
    if [ "$REPORT_FORMAT" = "html" ]; then
        log_debug "  Generating HTML report..."
        generate_html_report "$report_name" "$start_date" "$end_date" "$period_days" "$drive_count" "$total_datapoints" "$total_alerts" "$alert_data" "$report_data" > "$report_file"
        local gen_result=$?
        log_debug "  HTML generation result: $gen_result"
    else
        log_debug "  Generating text report..."
        generate_text_report "$report_name" "$start_date" "$end_date" "$period_days" "$drive_count" "$total_datapoints" "$total_alerts" "$alert_data" "$report_data" > "$report_file"
        local gen_result=$?
        log_debug "  Text generation result: $gen_result"
    fi
    
    if [ ! -f "$report_file" ]; then
        log_error "Report file was not created: $report_file"
        return 1
    fi
    
    local file_size=$(stat -f%z "$report_file" 2>/dev/null || stat -c%s "$report_file" 2>/dev/null)
    log_debug "  Report file size: $file_size bytes"
    
    if [ "$file_size" -eq 0 ]; then
        log_error "Report file is empty"
        return 1
    fi
    
    log_info "Report saved to: $report_file"
    
    # Send email (pass alert count for proper severity detection)
    send_report_email "$report_name" "$report_file" "$total_alerts"
    
    return 0
}

# ============================================================================
# Report Formatting Functions
# ============================================================================

# Generate text report
generate_text_report() {
    local report_name="$1"
    local start_date="$2"
    local end_date="$3"
    local period_days="$4"
    local drive_count="$5"
    local datapoint_count="$6"
    local alert_count="$7"
    local alert_data="$8"
    local report_data="$9"
    
    cat << EOF
================================================================================
$report_name - Drive Health Report
================================================================================
Report Period: $start_date to $end_date ($period_days days)
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Total Drives: $drive_count
Data Points: $datapoint_count
System Alerts: $alert_count

EOF

    # System Health Alerts section
    if [ $alert_count -gt 0 ]; then
        cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ SYSTEM HEALTH ALERTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
        echo -e "$alert_data" | while IFS='|' read -r drive model alerts; do
            [ -z "$drive" ] && continue
            cat << EOF
Drive: $drive ($model)
Alerts: $alerts

EOF
        done
    fi
    
    # Drive Details section
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 DRIVE DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    # Parse and format drive data
    echo -e "$report_data" | while IFS='|' read -r type field1 field2 field3 field4 field5 field6 field7 field8 field9 field10; do
        case "$type" in
            DRIVE)
                [ -z "$field1" ] && continue
                cat << EOF

────────────────────────────────────────────────────────────────────────────────
Drive ID:     $field1
Model:        $field2
Filesystem:   $field3
SMART Status: $field4
Drive Type:   $field5
────────────────────────────────────────────────────────────────────────────────

EOF
                ;;
            TEMP)
                cat << EOF
🌡️  Temperature Statistics:
   Current:  ${field1}°C
   Minimum:  ${field2}°C
   Maximum:  ${field3}°C
   Average:  ${field4}°C

EOF
                ;;
            WORKLOAD)
                cat << EOF
💾 Workload During Period:
   Power Hours:  ${field1}h
   Data Written: $field2
   Data Read:    $field3
   Total Hours:  ${field4}h (${field5} years)

EOF
                ;;
            ERRORS)
                echo "⚠️  Health & Errors:"
                # Reallocated Sectors
                if [ "$field1" -gt 0 ]; then
                    echo "   Reallocated Sectors: $field2 new ($field1 total)"
                else
                    echo "   Reallocated Sectors: $field2 new"
                fi
                # Pending Sectors (current state, not accumulated)
                echo "   Pending Sectors:     $field3"
                # Uncorrectable (current state)
                echo "   Uncorrectable:       $field4"
                # CRC Errors
                if [ "$field5" -gt 0 ]; then
                    echo "   CRC Errors:          $field6 new ($field5 total)"
                else
                    echo "   CRC Errors:          $field6 new"
                fi
                # Read Errors
                if [ "$field7" -gt 0 ]; then
                    echo "   Read Errors:         $field8 new ($field7 total)"
                else
                    echo "   Read Errors:         $field8 new"
                fi
                # Write Errors
                if [ "$field9" -gt 0 ]; then
                    echo "   Write Errors:        ${field10} new ($field9 total)"
                else
                    echo "   Write Errors:        ${field10} new"
                fi
                echo ""
                ;;
            SPECIAL)
                if [ -n "$field1" ] || [ -n "$field2" ] || [ -n "$field3" ]; then
                    echo "📌 Drive-Specific:"
                    [ -n "$field1" ] && echo "   Helium Level:    ${field1}%"
                    [ -n "$field2" ] && echo "   Wear Level:      ${field2}%"
                    # Only show SMR status if drive is actually SMR (not N/A or empty)
                    if [ -n "$field3" ] && [ "$field3" != "N/A" ] && [ "$field3" != "Unknown" ]; then
                        echo "   ⚠️  SMR Drive:   $field3"
                    fi
                    echo ""
                fi
                ;;
            SKIPCOUNT)
                # Show skip counter if configured with "counted" mode
                if [ "${CONFIG[STATS_SKIP_SLEEPING_DRIVES]}" = "counted" ]; then
                    echo "💤 Sleep Protection:"
                    echo "   Current Skip Counter: $field1 / ${CONFIG[STATS_SKIP_MAX_COUNT]:-10}"
                    local total_attempts=$((field2 + field3))
                    if [ "$total_attempts" -gt 0 ]; then
                        echo "   During Report Period:"
                        echo "     Times Skipped:   $field2"
                        echo "     Times Collected: $field3"
                        echo "     Total Attempts:  $total_attempts"
                        local collection_rate=$((field3 * 100 / total_attempts))
                        echo "     Collection Rate: ${collection_rate}%"
                    fi
                    if [ "$field1" -eq 0 ]; then
                        echo "   Status: Drive has been active recently"
                    else
                        echo "   Status: Will wake after ${CONFIG[STATS_SKIP_MAX_COUNT]:-10} skips"
                    fi
                    echo ""
                fi
                ;;
        esac
    done
    
    cat << EOF

================================================================================
End of Report
================================================================================
Generated by Multi-Report-OMV v2 - Automated Drive Monitoring System
EOF
}

# Generate HTML report
generate_html_report() {
    local report_name="$1"
    local start_date="$2"
    local end_date="$3"
    local period_days="$4"
    local drive_count="$5"
    local datapoint_count="$6"
    local alert_count="$7"
    local alert_data="$8"
    local report_data="$9"
    
    cat << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Drive Health Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        
        /* Responsive layout for larger screens */
        @media (min-width: 768px) {
            body {
                max-width: 900px;
                padding: 30px;
            }
        }
        
        @media (min-width: 1200px) {
            body {
                max-width: 1400px;
                padding: 40px;
            }
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 {
            margin: 0 0 10px 0;
            font-size: 2em;
        }
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .info-box {
            background: rgba(255,255,255,0.1);
            padding: 10px 15px;
            border-radius: 5px;
        }
        .info-box label {
            font-size: 0.85em;
            opacity: 0.9;
        }
        .info-box value {
            display: block;
            font-size: 1.2em;
            font-weight: bold;
        }
        .alert-section {
            background: #fff3cd;
            border-left: 5px solid #ff6b6b;
            padding: 20px;
            margin-bottom: 30px;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .alert-section h2 {
            color: #d9534f;
            margin-top: 0;
        }
        .alert-item {
            background: white;
            padding: 15px;
            margin: 10px 0;
            border-radius: 5px;
            border-left: 3px solid #ff6b6b;
        }
        .alert-item strong {
            color: #d9534f;
        }
        .drive-section {
            background: white;
            padding: 25px;
            margin-bottom: 25px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .drive-header {
            background: linear-gradient(135deg, #3a7bd5 0%, #00d2ff 100%);
            color: white;
            padding: 15px 20px;
            margin: -25px -25px 20px -25px;
            border-radius: 8px 8px 0 0;
        }
        .drive-header h3 {
            margin: 0;
            font-size: 1.3em;
        }
        .drive-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
            margin-bottom: 15px;
            padding: 10px;
            background: #f8f9fa;
            border-radius: 5px;
        }
        .stat-group {
            margin: 20px 0;
        }
        .stat-group h4 {
            color: #667eea;
            margin: 0 0 10px 0;
            font-size: 1.1em;
        }
        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 8px 10px;
            border-bottom: 1px solid #e9ecef;
        }
        .stat-row:last-child {
            border-bottom: none;
        }
        .stat-label {
            color: #6c757d;
        }
        .stat-label::after {
            content: ": ";
        }
        .stat-value {
            font-weight: 600;
            color: #333;
        }
        .status-passed {
            color: #28a745;
            font-weight: bold;
        }
        .status-failed {
            color: #dc3545;
            font-weight: bold;
        }
        .footer {
            text-align: center;
            padding: 20px;
            color: #6c757d;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
HTMLEOF

    # Header
    cat << EOF
    <div class="header">
        <h1>$report_name</h1>
        <p>Drive Health Report</p>
        <div class="header-info">
            <div class="info-box">
                <label>Report Period</label>
                <value>$start_date to $end_date</value>
            </div>
            <div class="info-box">
                <label>Period Duration</label>
                <value>$period_days days</value>
            </div>
            <div class="info-box">
                <label>Total Drives</label>
                <value>$drive_count</value>
            </div>
            <div class="info-box">
                <label>Data Points</label>
                <value>$datapoint_count</value>
            </div>
            <div class="info-box">
                <label>System Alerts</label>
                <value>$alert_count</value>
            </div>
            <div class="info-box">
                <label>Generated</label>
                <value>$(date '+%Y-%m-%d %H:%M:%S')</value>
            </div>
        </div>
    </div>
EOF

    # Alerts section
    if [ $alert_count -gt 0 ]; then
        cat << EOF
    <div class="alert-section">
        <h2>⚠️ System Health Alerts</h2>
EOF
        echo -e "$alert_data" | while IFS='|' read -r drive model alerts; do
            [ -z "$drive" ] && continue
            cat << EOF
        <div class="alert-item">
            <strong>Drive: $drive</strong> ($model)<br>
            Alerts: $alerts
        </div>
EOF
        done
        echo "    </div>"
    fi
    
    # Drive details
    local in_drive=""
    echo -e "$report_data" | while IFS='|' read -r type field1 field2 field3 field4 field5 field6 field7 field8 field9 field10; do
        case "$type" in
            DRIVE)
                [ -z "$field1" ] && continue
                # Close previous drive section if exists
                [ -n "$in_drive" ] && echo "    </div>"
                in_drive=1
                
                local status_class="status-passed"
                [ "$field4" != "PASSED" ] && status_class="status-failed"
                
                cat << EOF
    <div class="drive-section">
        <div class="drive-header">
            <h3>$field1 - $field2</h3>
        </div>
        <div class="drive-info">
            <div><strong>Filesystem:</strong> $field3</div>
            <div><strong>SMART Status:</strong> <span class="$status_class">$field4</span></div>
            <div><strong>Drive Type:</strong> $field5</div>
        </div>
EOF
                ;;
            TEMP)
                cat << EOF
        <div class="stat-group">
            <h4>🌡️ Temperature Statistics</h4>
            <div class="stat-row">
                <span class="stat-label">Current Temperature</span>
                <span class="stat-value">${field1}°C</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Minimum Temperature</span>
                <span class="stat-value">${field2}°C</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Maximum Temperature</span>
                <span class="stat-value">${field3}°C</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Average Temperature</span>
                <span class="stat-value">${field4}°C</span>
            </div>
        </div>
EOF
                ;;
            WORKLOAD)
                cat << EOF
        <div class="stat-group">
            <h4>💾 Workload During Period</h4>
            <div class="stat-row">
                <span class="stat-label">Power Hours (Period)</span>
                <span class="stat-value">${field1}h</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Data Written</span>
                <span class="stat-value">$field2</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Data Read</span>
                <span class="stat-value">$field3</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Total Power Hours</span>
                <span class="stat-value">${field4}h (${field5} years)</span>
            </div>
        </div>
EOF
                ;;
            ERRORS)
                echo '        <div class="stat-group">'
                echo '            <h4>⚠️ Health & Errors</h4>'
                # Reallocated Sectors
                echo '            <div class="stat-row">'
                echo '                <span class="stat-label">Reallocated Sectors</span>'
                if [ "$field1" -gt 0 ]; then
                    echo "                <span class=\"stat-value\">$field2 new ($field1 total)</span>"
                else
                    echo "                <span class=\"stat-value\">$field2 new</span>"
                fi
                echo '            </div>'
                # Pending Sectors
                echo '            <div class="stat-row">'
                echo '                <span class="stat-label">Pending Sectors</span>'
                echo "                <span class=\"stat-value\">$field3</span>"
                echo '            </div>'
                # Uncorrectable
                echo '            <div class="stat-row">'
                echo '                <span class="stat-label">Uncorrectable Errors</span>'
                echo "                <span class=\"stat-value\">$field4</span>"
                echo '            </div>'
                # CRC Errors
                echo '            <div class="stat-row">'
                echo '                <span class="stat-label">CRC Errors</span>'
                if [ "$field5" -gt 0 ]; then
                    echo "                <span class=\"stat-value\">$field6 new ($field5 total)</span>"
                else
                    echo "                <span class=\"stat-value\">$field6 new</span>"
                fi
                echo '            </div>'
                # Read Errors
                echo '            <div class="stat-row">'
                echo '                <span class="stat-label">Read Errors</span>'
                if [ "$field7" -gt 0 ]; then
                    echo "                <span class=\"stat-value\">$field8 new ($field7 total)</span>"
                else
                    echo "                <span class=\"stat-value\">$field8 new</span>"
                fi
                echo '            </div>'
                # Write Errors
                echo '            <div class="stat-row">'
                echo '                <span class="stat-label">Write Errors</span>'
                if [ "$field9" -gt 0 ]; then
                    echo "                <span class=\"stat-value\">${field10} new ($field9 total)</span>"
                else
                    echo "                <span class=\"stat-value\">${field10} new</span>"
                fi
                echo '            </div>'
                echo '        </div>'
                ;;
            SPECIAL)
                # Check if there's actually displayable content
                local has_content=false
                [ -n "$field1" ] && has_content=true
                [ -n "$field2" ] && has_content=true
                if [ -n "$field3" ] && [ "$field3" != "N/A" ] && [ "$field3" != "Unknown" ]; then
                    has_content=true
                fi
                
                if [ "$has_content" = "true" ]; then
                    cat << EOF
        <div class="stat-group">
            <h4>📌 Drive-Specific Metrics</h4>
EOF
                    [ -n "$field1" ] && cat << EOF
            <div class="stat-row">
                <span class="stat-label">Helium Level</span>
                <span class="stat-value">${field1}%</span>
            </div>
EOF
                    [ -n "$field2" ] && cat << EOF
            <div class="stat-row">
                <span class="stat-label">Wear Level</span>
                <span class="stat-value">${field2}%</span>
            </div>
EOF
                    # Only show SMR if drive is actually SMR
                    if [ -n "$field3" ] && [ "$field3" != "N/A" ] && [ "$field3" != "Unknown" ]; then
                        cat << EOF
            <div class="stat-row">
                <span class="stat-label">⚠️ SMR Drive</span>
                <span class="stat-value">$field3</span>
            </div>
EOF
                    fi
                    echo "        </div>"
                fi
                ;;
            SKIPCOUNT)
                # Show skip counter if configured with "counted" mode
                if [ "${CONFIG[STATS_SKIP_SLEEPING_DRIVES]}" = "counted" ]; then
                    local skip_max="${CONFIG[STATS_SKIP_MAX_COUNT]:-10}"
                    local total_attempts=$((field2 + field3))
                    local collection_rate=0
                    [ "$total_attempts" -gt 0 ] && collection_rate=$((field3 * 100 / total_attempts))
                    
                    cat << EOF
        <div class="stat-group">
            <h4>💤 Sleep Protection</h4>
            <div class="stat-row">
                <span class="stat-label">Current Skip Counter</span>
                <span class="stat-value">$field1 / $skip_max</span>
            </div>
EOF
                    if [ "$total_attempts" -gt 0 ]; then
                        cat << EOF
            <div class="stat-row">
                <span class="stat-label">Times Skipped (Period)</span>
                <span class="stat-value">$field2</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Times Collected (Period)</span>
                <span class="stat-value">$field3</span>
            </div>
            <div class="stat-row">
                <span class="stat-label">Collection Rate</span>
                <span class="stat-value">${collection_rate}%</span>
            </div>
EOF
                    fi
                    cat << EOF
            <div class="stat-row">
                <span class="stat-label">Status</span>
                <span class="stat-value">$([ "$field1" -eq 0 ] && echo "Active recently" || echo "Will wake after $skip_max skips")</span>
            </div>
        </div>
EOF
                fi
                ;;
        esac
    done
    
    # Close last drive section
    [ -n "$in_drive" ] && echo "    </div>"
    
    cat << 'EOF'
    
    <div class="footer">
        Generated by Multi-Report-OMV v2 - Automated Drive Monitoring System
    </div>
</body>
</html>
EOF
}

# Send report via email (uses notification system)
send_report_email() {
    local report_name="$1"
    local report_file="$2"
    local alert_count="${3:-0}"
    
    log_debug "  Email function called"
    log_debug "    Report name: $report_name"
    log_debug "    Report file: $report_file"
    log_debug "    REPORT_EMAIL: $REPORT_EMAIL"
    
    if [ -z "$REPORT_EMAIL" ] || [ "$REPORT_EMAIL" = "" ]; then
        log_debug "No email configured, skipping email delivery"
        return 0
    fi
    
    if [ ! -f "$report_file" ]; then
        log_error "Report file does not exist: $report_file"
        return 1
    fi
    
    log_info "Sending report notification"
    
    # Use notification system if available
    if type send_report_notification &>/dev/null; then
        # Determine if report has errors based on actual alert count
        local has_errors="false"
        if [ "$alert_count" -gt 0 ]; then
            has_errors="true"
        fi
        
        send_report_notification "$report_name" "$report_file" "$has_errors"
        return $?
    else
        # Fallback to direct mail command if notification system not available
        log_warning "Notification system not available, using direct mail command"
        
        local subject="$report_name - $(date '+%Y-%m-%d')"
        
        if [ "$REPORT_FORMAT" = "html" ]; then
            mail -s "$subject" -a "Content-Type: text/html" "$REPORT_EMAIL" < "$report_file"
        else
            mail -s "$subject" "$REPORT_EMAIL" < "$report_file"
        fi
        
        local mail_result=$?
        
        if [ $mail_result -eq 0 ]; then
            log_info "Report emailed successfully"
        else
            log_error "Failed to send report email (exit code: $mail_result)"
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# Main Plugin Function
# ============================================================================

# Main plugin entry point (called by auto command)
plugin_report_main() {
    log_info "Report Plugin: Checking for due reports"
    
    load_report_config
    
    log_debug "  REPORT_ENABLED=$REPORT_ENABLED"
    log_debug "  REPORT_EMAIL=$REPORT_EMAIL"
    
    if [ "$REPORT_ENABLED" != "true" ]; then
        log_debug "Report plugin is disabled"
        return 0
    fi
    
    if [ -z "$REPORT_EMAIL" ]; then
        log_warning "Report email not configured, skipping reports"
        return 0
    fi
    
    local reports_generated=0
    
    # Check each report type
    log_debug "Checking weekly report..."
    log_debug "  REPORT_WEEKLY_ENABLED=$REPORT_WEEKLY_ENABLED"
    if is_weekly_due; then
        log_info "Weekly report is due"
        generate_report "weekly" "7" "$REPORT_WEEKLY_METRICS" "Weekly Drive Summary"
        update_last_run "weekly"
        reports_generated=$((reports_generated + 1))
    else
        log_debug "  Weekly report is not due"
    fi
    
    log_debug "Checking monthly report..."
    log_debug "  REPORT_MONTHLY_ENABLED=$REPORT_MONTHLY_ENABLED"
    if is_monthly_due; then
        log_info "Monthly report is due"
        local prev_month=$(date -d "last month" +%B' '%Y 2>/dev/null || date -v-1m +%B' '%Y 2>/dev/null || echo "Previous Month")
        generate_report "monthly" "30" "$REPORT_MONTHLY_METRICS" "Monthly Drive Summary - $prev_month"
        update_last_run "monthly"
        reports_generated=$((reports_generated + 1))
    else
        log_debug "  Monthly report is not due"
    fi
    
    log_debug "Checking quarterly report..."
    log_debug "  REPORT_QUARTERLY_ENABLED=$REPORT_QUARTERLY_ENABLED"
    if is_quarterly_due; then
        log_info "Quarterly report is due"
        local quarter=$(( ($(date +%-m) - 1) / 3 + 1 ))
        generate_report "quarterly" "90" "$REPORT_QUARTERLY_METRICS" "Quarterly Drive Summary - Q${quarter} $(date +%Y)"
        update_last_run "quarterly"
        reports_generated=$((reports_generated + 1))
    else
        log_debug "  Quarterly report is not due"
    fi
    
    log_debug "Checking yearly report..."
    log_debug "  REPORT_YEARLY_ENABLED=$REPORT_YEARLY_ENABLED"
    if is_yearly_due; then
        log_info "Yearly report is due"
        local prev_year=$(date -d "last year" +%Y 2>/dev/null || date -v-1y +%Y 2>/dev/null || echo "Previous Year")
        generate_report "yearly" "365" "$REPORT_YEARLY_METRICS" "Annual Drive Summary - $prev_year"
        update_last_run "yearly"
        reports_generated=$((reports_generated + 1))
    else
        log_debug "  Yearly report is not due"
    fi
    
    log_debug "Checking custom report..."
    log_debug "  REPORT_CUSTOM_ENABLED=$REPORT_CUSTOM_ENABLED"
    if is_custom_due; then
        log_info "Custom report is due"
        generate_report "custom" "$REPORT_CUSTOM_PERIOD_DAYS" "$REPORT_CUSTOM_METRICS" "$REPORT_CUSTOM_NAME"
        update_last_run "custom"
        reports_generated=$((reports_generated + 1))
    else
        log_debug "  Custom report is not due"
    fi
    
    if [ $reports_generated -eq 0 ]; then
        log_info "No reports are due at this time"
    else
        log_info "Generated $reports_generated report(s)"
    fi
    
    return 0
}

# Plugin entry point
# Always called via: ./bin/multi-report-omv auto
# Or directly via: ./bin/multi-report-omv report
