#!/bin/bash
#
# statistical_data.sh - Statistical SMART Data Collection Plugin
# Part of Multi-Report-OMV v2.0
#
# Collects comprehensive SMART attribute data and device statistics
# for long-term trending, analysis, and predictive failure detection.
#

# Core modules (logger, utils, config) are sourced by main script
# Plugins are always loaded via execute_plugin() which ensures core modules are available

# Plugin metadata
PLUGIN_NAME="statistical_data"
PLUGIN_VERSION="1.0.0"

# ============================================================================
# Configuration
# ============================================================================

# Load plugin configuration from main config system
load_statistical_config() {
    # Configuration values come from core config system via CONFIG array
    # These should be set by config.sh before calling this plugin
    
    # Use CONFIG array values (already loaded by core)
    STATS_ENABLE="${CONFIG[STATS_ENABLED]:-true}"
    STATS_HISTORY_FILE="${CONFIG[STATS_HISTORY_FILE]:-$SCRIPT_DIR/../../data/statistical_data/history_raw.csv}"
    STATS_HISTORY_HUMAN_FILE="${CONFIG[STATS_HISTORY_HUMAN_FILE]:-$SCRIPT_DIR/../../data/statistical_data/history.csv}"
    STATS_HUMAN_READABLE="${CONFIG[STATS_HUMAN_READABLE]:-true}"
    STATS_RETENTION_DAYS="${CONFIG[STATS_RETENTION_DAYS]:-730}"
    STATS_COLLECT_ON_SELFTEST="${CONFIG[STATS_COLLECT_ON_SELFTEST]:-true}"
    STATS_DAILY_COLLECTION="${CONFIG[STATS_DAILY_COLLECTION]:-true}"
    STATS_SKIP_SLEEPING_DRIVES="${CONFIG[STATS_SKIP_SLEEPING_DRIVES]:-counted}"
    STATS_SKIP_MAX_COUNT="${CONFIG[STATS_SKIP_MAX_COUNT]:-10}"
    
    # File to track skip counts per drive
    STATS_SKIP_COUNTER_FILE="$(dirname "$STATS_HISTORY_FILE")/skip_counters.csv"
    
    # File to track skip history with timestamps
    STATS_SKIP_HISTORY_FILE="$(dirname "$STATS_HISTORY_FILE")/skip_history.csv"
    
    log_debug "Statistical data configuration loaded from main config"
    log_debug "  Enabled: $STATS_ENABLE"
    log_debug "  History file (raw): $STATS_HISTORY_FILE"
    log_debug "  History file (human): $STATS_HISTORY_HUMAN_FILE"
    log_debug "  Human-readable: $STATS_HUMAN_READABLE"
    log_debug "  Retention: $STATS_RETENTION_DAYS days"
    log_info "Sleep protection mode: $STATS_SKIP_SLEEPING_DRIVES (max skips: $STATS_SKIP_MAX_COUNT)"
    log_debug "  Skip sleeping drives: $STATS_SKIP_SLEEPING_DRIVES"
    log_debug "  Skip max count: $STATS_SKIP_MAX_COUNT"
    
    # Ensure data directory exists
    mkdir -p "$(dirname "$STATS_HISTORY_FILE")"
    mkdir -p "$(dirname "$STATS_HISTORY_HUMAN_FILE")"
}

# ============================================================================
# CSV Schema Version and Migration
# ============================================================================

# Current schema version
STATS_CSV_VERSION="2"

# Get current CSV version from header
get_csv_version() {
    local csv_file="$1"
    
    if [ ! -f "$csv_file" ]; then
        echo "0"
        return
    fi
    
    local header=$(head -1 "$csv_file")
    
    # Check for version 2 markers (Device Path, Drive Model, Helium_Level, SMART IDs in header)
    if echo "$header" | grep -q "Device Path" && echo "$header" | grep -q "Drive Model" && echo "$header" | grep -q "Helium_Level"; then
        echo "2"
    # Check for version 1 (has Device ID but not the new fields)
    elif echo "$header" | grep -q "Device ID"; then
        echo "1"
    else
        echo "0"
    fi
}

# Migration from version 1 to version 2
migrate_v1_to_v2() {
    local input_file="$1"
    local output_file="$2"
    
    log_info "  Executing v1 → v2 migration"
    
    # Write v2 header
    cat > "$output_file" <<'EOF'
Date,Time,Device ID,Device Path,Drive Model,Mountpoint,Filesystem Name,Filesystem Type,OMV Tag,Drive Type,Serial Number,SMART Status,Temp (194),Airflow_Temp (190),Temp_Min,Temp_Max,Temp_Avg_Short,Temp_Avg_Long,Time_Over_Temp,Power On Hours (9),Head_Flying_Hours (240),Power_Cycle_Count (12),Helium_Level (22),Wear Level (177/231/233),Start Stop Count (4),Load Cycle (193),Power_Off_Retract_Count (192),Spin Retry (10),Mechanical_Start_Failures,Reallocated Sectors (5),Reallocated Sector Events (196),Realloc_Candidate_Sectors,Pending Sectors (197),Offline Uncorrectable (198),Reported_Uncorrect (187),Read_Recovery_Attempts,UDMA CRC Errors (199),Interface_CRC_Errors,Command_Timeout (188),End_to_End_Error (184),Hardware_Resets,ASR_Events,COMRESET_Events,Seek Error Rate (7),Multi Zone Errors (200),Read Error Rate (1),Hardware_ECC_Recovered (195),G_Sense_Error_Rate (191),High_Fly_Writes (189),SMR Status,Data Written (241),Data Read (242),Write_Commands,Read_Commands
EOF
    
    # Migrate data: v1 has 50 columns, v2 adds 3 columns at positions 4, 5, and 23
    tail -n +2 "$input_file" | awk -F',' 'BEGIN {OFS=","} {
        # Read old columns (50 total)
        date=$1; time=$2; device_id=$3; mountpoint=$4; fs_name=$5; fs_type=$6
        omv_tag=$7; drive_type=$8; serial=$9; smart_status=$10
        temp=$11; airflow_temp=$12; temp_min=$13; temp_max=$14
        temp_avg_short=$15; temp_avg_long=$16; time_over_temp=$17
        power_hours=$18; head_flying_hours=$19; power_cycle=$20
        wear_level=$21; start_stop=$22; load_cycle=$23; power_off_retract=$24
        spin_retry=$25; mech_start_fail=$26
        reallocated=$27; realloc_events=$28; realloc_candidate=$29
        pending=$30; uncorrectable=$31; reported_uncorrect=$32
        read_recovery=$33
        udma_crc=$34; interface_crc=$35; cmd_timeout=$36; e2e_error=$37
        hw_resets=$38; asr_events=$39; comreset_events=$40
        seek_error=$41; multi_zone=$42; read_error=$43; hw_ecc=$44
        g_sense=$45; high_fly=$46
        smr_status=$47
        total_lbas_written=$48; total_lbas_read=$49; write_commands=$50; read_commands=$51
        
        # Generate new columns
        device_path="/dev/" device_id
        drive_model="N/A"
        helium_level="N/A"
        
        # Print in new format (53 columns)
        print date, time, device_id, device_path, drive_model, mountpoint, fs_name, fs_type, omv_tag, \
              drive_type, serial, smart_status, \
              temp, airflow_temp, temp_min, temp_max, temp_avg_short, temp_avg_long, time_over_temp, \
              power_hours, head_flying_hours, power_cycle, \
              helium_level, wear_level, start_stop, load_cycle, power_off_retract, \
              spin_retry, mech_start_fail, \
              reallocated, realloc_events, realloc_candidate, \
              pending, uncorrectable, reported_uncorrect, \
              read_recovery, \
              udma_crc, interface_crc, cmd_timeout, e2e_error, \
              hw_resets, asr_events, comreset_events, \
              seek_error, multi_zone, read_error, hw_ecc, \
              g_sense, high_fly, \
              smr_status, \
              total_lbas_written, total_lbas_read, write_commands, read_commands
    }' >> "$output_file"
    
    return $?
}

# Example for future: Migration from version 2 to version 3
# migrate_v2_to_v3() {
#     local input_file="$1"
#     local output_file="$2"
#     
#     log_info "  Executing v2 → v3 migration"
#     
#     # Write v3 header with new columns
#     cat > "$output_file" <<'EOF'
# Date,Time,Device ID,...new columns...
# EOF
#     
#     # Transform v2 data to v3 format using awk
#     tail -n +2 "$input_file" | awk -F',' 'BEGIN {OFS=","} {
#         # Map v2 columns to v3 format, add new columns
#         print ...
#     }' >> "$output_file"
#     
#     return $?
# }

# Migrate CSV through version chain
migrate_csv_schema() {
    local csv_file="$1"
    local current_version=$(get_csv_version "$csv_file")
    
    if [ "$current_version" = "$STATS_CSV_VERSION" ]; then
        log_debug "CSV schema is up to date (v$STATS_CSV_VERSION)"
        return 0
    fi
    
    log_info "Migrating CSV schema from v$current_version to v$STATS_CSV_VERSION"
    
    # Create backup
    local backup_file="${csv_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$csv_file" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Migration chain: apply each migration step sequentially
    local working_file="$csv_file"
    local temp_file=$(mktemp)
    local version=$current_version
    
    # Apply migrations in sequence until we reach target version
    while [ "$version" != "$STATS_CSV_VERSION" ]; do
        case "$version" in
            1)
                migrate_v1_to_v2 "$working_file" "$temp_file" || {
                    log_error "Migration v1→v2 failed"
                    rm -f "$temp_file"
                    return 1
                }
                version="2"
                ;;
            2)
                # When v3 exists, add: migrate_v2_to_v3 "$working_file" "$temp_file"
                log_error "No migration path from v$version to v$STATS_CSV_VERSION"
                rm -f "$temp_file"
                return 1
                ;;
            *)
                log_error "Unknown CSV version: v$version"
                rm -f "$temp_file"
                return 1
                ;;
        esac
        
        # Use temp file as input for next migration
        if [ "$version" != "$STATS_CSV_VERSION" ]; then
            mv "$temp_file" "${temp_file}.working"
            working_file="${temp_file}.working"
            temp_file=$(mktemp)
        fi
    done
    
    # Verify migration success
    local line_count=$(wc -l < "$temp_file")
    local old_line_count=$(wc -l < "$csv_file")
    
    if [ "$line_count" -lt "$old_line_count" ]; then
        log_error "Migration failed: Output file has fewer lines ($line_count) than input ($old_line_count)"
        rm -f "$temp_file" "${temp_file}.working"
        return 1
    fi
    
    # Replace original file
    mv "$temp_file" "$csv_file"
    rm -f "${temp_file}.working"
    
    log_info "✓ CSV migration completed successfully (v$current_version → v$STATS_CSV_VERSION)"
    log_info "  Migrated $((line_count - 1)) data rows"
    log_info "  Backup saved to: $backup_file"
    
    return 0
}

# ============================================================================
# Initialize CSV file with headers
# ============================================================================

# Initialize CSV file with headers
initialize_history_file() {
    # Check and migrate raw file if needed
    if [ -f "$STATS_HISTORY_FILE" ]; then
        log_debug "History file exists: $STATS_HISTORY_FILE"
        
        # Check if migration is needed
        local csv_version=$(get_csv_version "$STATS_HISTORY_FILE")
        if [ "$csv_version" != "$STATS_CSV_VERSION" ]; then
            log_info "CSV schema version mismatch (current: v$csv_version, required: v$STATS_CSV_VERSION)"
            migrate_csv_schema "$STATS_HISTORY_FILE"
        fi
        
        # Ensure human-readable file also exists if enabled
        if [ "$STATS_HUMAN_READABLE" = "true" ] && [ ! -f "$STATS_HISTORY_HUMAN_FILE" ]; then
            log_info "Creating missing human-readable CSV file"
            cat > "$STATS_HISTORY_HUMAN_FILE" <<'EOF'
Date,Time,Device ID,Device Path,Drive Model,Mountpoint,Filesystem Name,Filesystem Type,OMV Tag,Drive Type,Serial Number,SMART Status,Temp (194),Airflow_Temp (190),Temp_Min,Temp_Max,Temp_Avg_Short,Temp_Avg_Long,Time_Over_Temp,Power On Hours (9),Head_Flying_Hours (240),Power_Cycle_Count (12),Helium_Level (22),Wear Level (177/231/233),Start Stop Count (4),Load Cycle (193),Power_Off_Retract_Count (192),Spin Retry (10),Mechanical_Start_Failures,Reallocated Sectors (5),Reallocated Sector Events (196),Realloc_Candidate_Sectors,Pending Sectors (197),Offline Uncorrectable (198),Reported_Uncorrect (187),Read_Recovery_Attempts,UDMA CRC Errors (199),Interface_CRC_Errors,Command_Timeout (188),End_to_End_Error (184),Hardware_Resets,ASR_Events,COMRESET_Events,Seek Error Rate (7),Multi Zone Errors (200),Read Error Rate (1),Hardware_ECC_Recovered (195),G_Sense_Error_Rate (191),High_Fly_Writes (189),SMR Status,Data Written (241),Data Read (242),Write_Commands,Read_Commands
EOF
        fi
        
        return 0
    fi
    
    log_info "Creating statistical data history files"
    
    # Create RAW CSV (no units, raw numbers)
    log_debug "  Creating raw CSV: $STATS_HISTORY_FILE"
    cat > "$STATS_HISTORY_FILE" <<'EOF'
Date,Time,Device ID,Device Path,Drive Model,Mountpoint,Filesystem Name,Filesystem Type,OMV Tag,Drive Type,Serial Number,SMART Status,Temp (194),Airflow_Temp (190),Temp_Min,Temp_Max,Temp_Avg_Short,Temp_Avg_Long,Time_Over_Temp,Power On Hours (9),Head_Flying_Hours (240),Power_Cycle_Count (12),Helium_Level (22),Wear Level (177/231/233),Start Stop Count (4),Load Cycle (193),Power_Off_Retract_Count (192),Spin Retry (10),Mechanical_Start_Failures,Reallocated Sectors (5),Reallocated Sector Events (196),Realloc_Candidate_Sectors,Pending Sectors (197),Offline Uncorrectable (198),Reported_Uncorrect (187),Read_Recovery_Attempts,UDMA CRC Errors (199),Interface_CRC_Errors,Command_Timeout (188),End_to_End_Error (184),Hardware_Resets,ASR_Events,COMRESET_Events,Seek Error Rate (7),Multi Zone Errors (200),Read Error Rate (1),Hardware_ECC_Recovered (195),G_Sense_Error_Rate (191),High_Fly_Writes (189),SMR Status,Total LBAs Written (241),Total LBAs Read (242),Write_Commands,Read_Commands
EOF
    
    local raw_status=$?
    
    # Create HUMAN-READABLE CSV (with units) if enabled
    if [ "$STATS_HUMAN_READABLE" = "true" ]; then
        log_debug "  Creating human-readable CSV: $STATS_HISTORY_HUMAN_FILE"
        cat > "$STATS_HISTORY_HUMAN_FILE" <<'EOF'
Date,Time,Device ID,Device Path,Drive Model,Mountpoint,Filesystem Name,Filesystem Type,OMV Tag,Drive Type,Serial Number,SMART Status,Temp (194),Airflow_Temp (190),Temp_Min,Temp_Max,Temp_Avg_Short,Temp_Avg_Long,Time_Over_Temp,Power On Hours (9),Head_Flying_Hours (240),Power_Cycle_Count (12),Helium_Level (22),Wear Level (177/231/233),Start Stop Count (4),Load Cycle (193),Power_Off_Retract_Count (192),Spin Retry (10),Mechanical_Start_Failures,Reallocated Sectors (5),Reallocated Sector Events (196),Realloc_Candidate_Sectors,Pending Sectors (197),Offline Uncorrectable (198),Reported_Uncorrect (187),Read_Recovery_Attempts,UDMA CRC Errors (199),Interface_CRC_Errors,Command_Timeout (188),End_to_End_Error (184),Hardware_Resets,ASR_Events,COMRESET_Events,Seek Error Rate (7),Multi Zone Errors (200),Read Error Rate (1),Hardware_ECC_Recovered (195),G_Sense_Error_Rate (191),High_Fly_Writes (189),SMR Status,Data Written (241),Data Read (242),Write_Commands,Read_Commands
EOF
    fi
    
    if [ $raw_status -eq 0 ]; then
        log_info "History files created successfully"
        return 0
    else
        log_error "Failed to create history files"
        return 1
    fi
}

# Initialize skip history file if it doesn't exist
init_skip_history_file() {
    if [ ! -f "$STATS_SKIP_HISTORY_FILE" ]; then
        log_debug "Creating skip history file: $STATS_SKIP_HISTORY_FILE"
        echo "timestamp,serial,drive_id,action,power_mode" > "$STATS_SKIP_HISTORY_FILE"
    fi
}

# Log skip event to history
log_skip_event() {
    local serial="$1"
    local drive_id="$2"
    local action="$3"  # "skipped" or "collected"
    local power_mode="$4"
    
    init_skip_history_file
    
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp,$serial,$drive_id,$action,$power_mode" >> "$STATS_SKIP_HISTORY_FILE"
    
    log_debug "  Logged skip event: $action for $drive_id ($power_mode)"
}

# Initialize skip counter file if it doesn't exist
init_skip_counter_file() {
    if [ ! -f "$STATS_SKIP_COUNTER_FILE" ]; then
        log_debug "Creating skip counter file: $STATS_SKIP_COUNTER_FILE"
        echo "serial,skip_count" > "$STATS_SKIP_COUNTER_FILE"
    fi
}

# Get current skip count for a drive
get_skip_count() {
    local serial="$1"
    init_skip_counter_file
    
    local count=$(awk -F',' -v s="$serial" '$1 == s {print $2; exit}' "$STATS_SKIP_COUNTER_FILE")
    echo "${count:-0}"
}

# Increment skip count for a drive
increment_skip_count() {
    local serial="$1"
    init_skip_counter_file
    
    local current=$(get_skip_count "$serial")
    local new_count=$((current + 1))
    
    # Update or add entry
    if grep -q "^$serial," "$STATS_SKIP_COUNTER_FILE" 2>/dev/null; then
        # Update existing entry
        sed -i "s/^$serial,.*/$serial,$new_count/" "$STATS_SKIP_COUNTER_FILE"
    else
        # Add new entry
        echo "$serial,$new_count" >> "$STATS_SKIP_COUNTER_FILE"
    fi
    
    log_debug "  Skip counter for $serial: $current -> $new_count"
    echo "$new_count"
}

# Reset skip count for a drive
reset_skip_count() {
    local serial="$1"
    init_skip_counter_file
    
    if grep -q "^$serial," "$STATS_SKIP_COUNTER_FILE" 2>/dev/null; then
        sed -i "s/^$serial,.*/$serial,0/" "$STATS_SKIP_COUNTER_FILE"
        log_debug "  Reset skip counter for $serial to 0"
    fi
}

# Check if we should skip a sleeping drive based on configuration
should_skip_sleeping_drive() {
    local serial="$1"
    local power_mode="$2"
    
    # If disabled, never skip
    if [ "$STATS_SKIP_SLEEPING_DRIVES" = "never" ] || [ "$STATS_SKIP_SLEEPING_DRIVES" = "false" ]; then
        return 1  # Don't skip
    fi
    
    # If "always", always skip sleeping drives
    if [ "$STATS_SKIP_SLEEPING_DRIVES" = "always" ] || [ "$STATS_SKIP_SLEEPING_DRIVES" = "true" ]; then
        return 0  # Skip
    fi
    
    # If "counted", check the skip counter
    if [ "$STATS_SKIP_SLEEPING_DRIVES" = "counted" ]; then
        local skip_count=$(get_skip_count "$serial")
        local max_skips="${STATS_SKIP_MAX_COUNT:-10}"
        
        if [ "$skip_count" -lt "$max_skips" ]; then
            # Increment and skip
            increment_skip_count "$serial"
            return 0  # Skip
        else
            # Reached limit, don't skip (will wake drive)
            return 1  # Don't skip
        fi
    fi
    
    # Default: skip
    return 0
}

# Collect data for a single drive
collect_drive_data() {
    local drive_id="$1"
    
    if [ -z "$drive_id" ]; then
        log_error "collect_drive_data: No drive ID provided"
        return 1
    fi
    
    log_info "Collecting data from drive: $drive_id"
    
    # Check power mode FIRST, before any other smartctl calls that might wake the drive
    log_debug "  → Checking power mode with: smartctl -n standby /dev/$drive_id"
    local power_check_output
    local power_check_exit
    # Capture both output and exit code properly
    power_check_output=$(run_smartctl -n standby /dev/$drive_id 2>&1; echo "|||$?")
    power_check_exit="${power_check_output##*|||}"
    power_check_output="${power_check_output%|||*}"
    local power_mode=""
    
    log_debug "  → Power check exit code: $power_check_exit"
    log_debug "  → Power check output: $power_check_output"
    
    # Exit code 2 means drive is in STANDBY/SLEEP
    if [ "$power_check_exit" -eq 2 ]; then
        if echo "$power_check_output" | grep -qi "STANDBY"; then
            power_mode="STANDBY"
        elif echo "$power_check_output" | grep -qi "SLEEP"; then
            power_mode="SLEEP"
        else
            power_mode="LOW_POWER"
        fi
        log_debug "  → Detected sleeping drive: $power_mode"
    else
        # Drive is active, extract actual power mode if available
        power_mode=$(echo "$power_check_output" | grep "Power mode" | sed 's/.*Power mode is: *//;s/ *$//')
        [ -z "$power_mode" ] && power_mode="ACTIVE"
        log_debug "  → Detected active drive: $power_mode"
    fi
    
    # Check if drive is sleeping and if we should skip it
    if [[ "$power_mode" =~ STANDBY|SLEEP|IDLE_B|IDLE_C|LOW_POWER ]]; then
        log_info "  Drive $drive_id is sleeping ($power_mode) - checking skip policy..."
        
        # Get serial from power check output if available, or use cached value
        local serial=$(echo "$power_check_output" | grep -i "serial" | sed 's/.*Serial Number: *//;s/ *$//')
        if [ -z "$serial" ]; then
            # Try to get from cache/history without waking drive
            # Column 3 is Device ID, Column 11 is Serial Number
            serial=$(awk -F',' -v d="$drive_id" '$3==d {print $11; exit}' "$STATS_HISTORY_FILE" 2>/dev/null | head -1)
        fi
        
        log_debug "  Serial number for $drive_id: ${serial:-NOT FOUND}"
        
        # Check if we should skip based on configuration
        if should_skip_sleeping_drive "$serial" "$power_mode"; then
            log_info "  ✓ Skipping drive $drive_id to preserve sleep state (mode: $STATS_SKIP_SLEEPING_DRIVES, skip count: $(get_skip_count "$serial")/$STATS_SKIP_MAX_COUNT)"
            # Log skip event
            log_skip_event "$serial" "$drive_id" "skipped" "$power_mode"
            return 0
        else
            log_info "  ⚠ Waking drive $drive_id for data collection (skip limit reached: $(get_skip_count "$serial")/$STATS_SKIP_MAX_COUNT)"
            # Reset counter since we're collecting data now
            reset_skip_count "$serial"
            # Log collect event
            log_skip_event "$serial" "$drive_id" "collected" "$power_mode"
        fi
    fi
    
    # Get timestamp
    local datestamp=$(date +%Y-%m-%d)
    local timestamp=$(date +%H:%M:%S)
    
    # Now safe to get drive info (drive is awake or we decided to wake it)
    local serial=$(get_drive_serial "$drive_id")
    local model=$(get_drive_model "$drive_id")
    
    log_debug "  Drive model: ${model:-unknown}"
    log_debug "  Serial: ${serial:-unknown}"
    
    if [ -z "$serial" ]; then
        log_warning "Could not get serial number for $drive_id, skipping"
        return 1
    fi
    
    # Determine drive type
    local drive_type="HDD"
    if echo "$model" | grep -qi "ssd\|solid"; then
        drive_type="SSD"
    elif echo "$drive_id" | grep -q "nvme"; then
        drive_type="NVMe"
    fi
    
    log_debug "  Drive type: $drive_type"
    
    # Power mode was already checked at the start of this function
    # If we reach here, drive is either awake or we decided to wake it
    log_debug "  Power mode: ${power_mode:-ACTIVE}"
    
    # Get SMART status
    local smart_status=$(run_smartctl -H /dev/$drive_id 2>/dev/null | grep "SMART overall-health" | awk '{print $NF}')
    [ -z "$smart_status" ] && smart_status="UNKNOWN"
    
    log_debug "  SMART status: $smart_status"
    
    # Get filesystem information using helper functions
    local fs_info=$(get_drive_filesystem_info "$drive_id")
    local mountpoint=$(echo "$fs_info" | cut -d'|' -f1)
    local fs_name=$(echo "$fs_info" | cut -d'|' -f2)
    local fs_type=$(echo "$fs_info" | cut -d'|' -f3)
    local omv_tag=$(echo "$fs_info" | cut -d'|' -f4)
    
    log_debug "  Mountpoint: $mountpoint"
    log_debug "  Filesystem name: $fs_name"
    log_debug "  Filesystem type: $fs_type"
    log_debug "  OMV tag: $omv_tag"
    
    # Initialize all attributes with N/A
    local temp="N/A" airflow_temp="N/A" temp_min="N/A" temp_max="N/A"
    local temp_avg_short="N/A" temp_avg_long="N/A" time_over_temp="N/A"
    local power_hours="N/A" head_flying_hours="N/A" power_cycle="N/A"
    local helium_level="N/A"
    local wear_level="N/A" start_stop="N/A" load_cycle="N/A" power_off_retract="N/A"
    local spin_retry="N/A" mech_start_fail="N/A"
    local reallocated="N/A" realloc_events="N/A" realloc_candidate="N/A"
    local pending="N/A" uncorrectable="N/A" reported_uncorrect="N/A"
    local read_recovery="N/A"
    local udma_crc="N/A" interface_crc="N/A" cmd_timeout="N/A" e2e_error="N/A"
    local hw_resets="N/A" asr_events="N/A" comreset_events="N/A"
    local seek_error="N/A" multi_zone="N/A" read_error="N/A" hw_ecc="N/A"
    local g_sense="N/A" high_fly="N/A"
    local smr_status="N/A"
    local total_lbas_written="N/A" total_lbas_read="N/A"
    local write_commands="N/A" read_commands="N/A"
    
    # Get smartctl output in JSON format for easier parsing
    local smartctl_json=$(run_smartctl -x -j /dev/$drive_id 2>/dev/null)
    
    if [ -z "$smartctl_json" ]; then
        log_warning "Could not get SMART data for $drive_id"
    else
        log_debug "  Retrieved SMART data successfully"
        
        # Save JSON output in debug mode for troubleshooting
        if [ "${CONFIG[LOG_LEVEL]}" = "debug" ]; then
            local json_debug_dir="$(dirname "$STATS_HISTORY_FILE")/debug_json"
            mkdir -p "$json_debug_dir"
            local json_file="$json_debug_dir/${drive_id}_latest.json"
            echo "$smartctl_json" > "$json_file"
            log_debug "  Saved JSON output to: $json_file"
        fi
        
        # Check if jq is available for JSON parsing
        if command -v jq >/dev/null 2>&1; then
            # Use jq for reliable JSON parsing
            log_debug "Using JSON parsing with jq for $drive_id"
            temp=$(echo "$smartctl_json" | jq -r '.temperature.current // empty' 2>/dev/null)
            power_hours=$(echo "$smartctl_json" | jq -r '.power_on_time.hours // empty' 2>/dev/null)
            power_cycle=$(echo "$smartctl_json" | jq -r '.power_cycle_count // empty' 2>/dev/null)
            
            # SMART attributes by ID (using raw.value for actual counts)
            # Note: For temperature attributes (190, 194), use .value which is the actual temperature
            # For ID 240 (Head_Flying_Hours), the raw.string contains the actual hours
            airflow_temp=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==190) | .value' 2>/dev/null)
            reallocated=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==5) | .raw.value' 2>/dev/null)
            pending=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==197) | .raw.value' 2>/dev/null)
            uncorrectable=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==198) | .raw.value' 2>/dev/null)
            realloc_events=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==196) | .raw.value' 2>/dev/null)
            udma_crc=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==199) | .raw.value' 2>/dev/null)
            start_stop=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==4) | .raw.value' 2>/dev/null)
            load_cycle=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==193) | .raw.value' 2>/dev/null)
            spin_retry=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==10) | .raw.value' 2>/dev/null)
            power_off_retract=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==192) | .raw.value' 2>/dev/null)
            # Head Flying Hours: raw.string can be "45211h+54m+08.236s" or just a number, extract hours only
            head_flying_hours=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==240) | .raw.string' 2>/dev/null | sed 's/h.*//')
            reported_uncorrect=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==187) | .raw.value' 2>/dev/null)
            cmd_timeout=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==188) | .raw.value' 2>/dev/null)
            e2e_error=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==184) | .raw.value' 2>/dev/null)
            multi_zone=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==200) | .raw.value' 2>/dev/null)
            hw_ecc=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==195) | .raw.value' 2>/dev/null)
            g_sense=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==191) | .raw.value' 2>/dev/null)
            high_fly=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==189) | .raw.value' 2>/dev/null)
            
            # Helium level for helium-filled drives (different vendors use different attributes)
            # ID 22: Standard helium level (WD, some Seagate)
            # ID 23: Helium_Condition_Lower (Toshiba)
            # ID 24: Helium_Condition_Upper (Toshiba)
            helium_level=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==22) | .value' 2>/dev/null)
            if [ -z "$helium_level" ] || [ "$helium_level" = "null" ]; then
                # Try Toshiba helium attributes (23 and 24) - use the lower value as indicator
                local helium_lower=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==23) | .value' 2>/dev/null)
                local helium_upper=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==24) | .value' 2>/dev/null)
                if [ -n "$helium_lower" ] && [ "$helium_lower" != "null" ] && [ -n "$helium_upper" ] && [ "$helium_upper" != "null" ]; then
                    # Use the minimum of the two values as the helium condition
                    helium_level=$(( helium_lower < helium_upper ? helium_lower : helium_upper ))
                fi
            fi
            
            # For seek_error and read_error, use the string value (first part before space)
            seek_error=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==7) | .raw.string' 2>/dev/null | awk '{print $1}')
            read_error=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==1) | .raw.string' 2>/dev/null | awk '{print $1}')
            
            # Temperature details - prefer ata_sct_status for more accurate data
            if echo "$smartctl_json" | jq -e '.ata_sct_status' >/dev/null 2>&1; then
                temp_min=$(echo "$smartctl_json" | jq -r '.ata_sct_status.temperature.lifetime_min // empty' 2>/dev/null)
                temp_max=$(echo "$smartctl_json" | jq -r '.ata_sct_status.temperature.lifetime_max // empty' 2>/dev/null)
            else
                temp_min=$(echo "$smartctl_json" | jq -r '.temperature.lifetime_min // empty' 2>/dev/null)
                temp_max=$(echo "$smartctl_json" | jq -r '.temperature.lifetime_max // empty' 2>/dev/null)
            fi
            
            # Device Statistics
            if echo "$smartctl_json" | jq -e '.ata_device_statistics' >/dev/null 2>&1; then
                # Temperature stats
                temp_avg_short=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Average Short Term Temperature") | .value' 2>/dev/null | head -1)
                temp_avg_long=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Average Long Term Temperature") | .value' 2>/dev/null | head -1)
                time_over_temp=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Time in Over-Temperature") | .value' 2>/dev/null | head -1)
                
                # I/O Statistics
                total_lbas_written=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Logical Sectors Written") | .value' 2>/dev/null | head -1)
                total_lbas_read=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Logical Sectors Read") | .value' 2>/dev/null | head -1)
                write_commands=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of Write Commands") | .value' 2>/dev/null | head -1)
                read_commands=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of Read Commands") | .value' 2>/dev/null | head -1)
                
                # Error stats
                hw_resets=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of Hardware Resets") | .value' 2>/dev/null | head -1)
                interface_crc=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of Interface CRC Errors") | .value' 2>/dev/null | head -1)
                read_recovery=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Read Recovery Attempts") | .value' 2>/dev/null | head -1)
                asr_events=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of ASR Events") | .value' 2>/dev/null | head -1)
                
                # Mechanical stats
                mech_start_fail=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of Mechanical Start Failures") | .value' 2>/dev/null | head -1)
                realloc_candidate=$(echo "$smartctl_json" | jq -r '.ata_device_statistics.pages[].table[]? | select(.name=="Number of Reallocation Candidate Logical Sectors") | .value' 2>/dev/null | head -1)
            fi
            
            # SATA Phy Event Counters
            if echo "$smartctl_json" | jq -e '.sata_phy_event_counters' >/dev/null 2>&1; then
                comreset_events=$(echo "$smartctl_json" | jq -r '.sata_phy_event_counters.table[]? | select(.name | contains("COMRESET")) | .value' 2>/dev/null | head -1)
                log_debug "  Parsed SATA Phy Event Counters"
            fi
            
            # SSD-specific attributes
            if [ "$drive_type" = "SSD" ] || [ "$drive_type" = "NVMe" ]; then
                wear_level=$(echo "$smartctl_json" | jq -r '.ata_smart_attributes.table[] | select(.id==177 or .id==231 or .id==233) | .raw.value' 2>/dev/null | head -1)
            fi
            
            # Ensure empty values are set to N/A or 0 as appropriate
            [ -z "$airflow_temp" ] && airflow_temp="N/A"
            [ -z "$temp_min" ] && temp_min="N/A"
            [ -z "$temp_max" ] && temp_max="N/A"
            [ -z "$temp_avg_short" ] && temp_avg_short="N/A"
            [ -z "$temp_avg_long" ] && temp_avg_long="N/A"
            [ -z "$time_over_temp" ] && time_over_temp="N/A"
            [ -z "$head_flying_hours" ] && head_flying_hours="N/A"
            [ -z "$helium_level" ] && helium_level="N/A"
            [ -z "$wear_level" ] && wear_level="N/A"
            [ -z "$power_off_retract" ] && power_off_retract="N/A"
            [ -z "$mech_start_fail" ] && mech_start_fail="N/A"
            [ -z "$realloc_candidate" ] && realloc_candidate="N/A"
            [ -z "$read_recovery" ] && read_recovery="N/A"
            [ -z "$e2e_error" ] && e2e_error="N/A"
            [ -z "$asr_events" ] && asr_events="N/A"
            [ -z "$multi_zone" ] && multi_zone="N/A"
            [ -z "$hw_ecc" ] && hw_ecc="N/A"
            [ -z "$g_sense" ] && g_sense="N/A"
            [ -z "$high_fly" ] && high_fly="N/A"
            
            # Zero-default for countable errors
            [ -z "$reallocated" ] && reallocated="0"
            [ -z "$realloc_events" ] && realloc_events="0"
            [ -z "$pending" ] && pending="0"
            [ -z "$uncorrectable" ] && uncorrectable="0"
            [ -z "$reported_uncorrect" ] && reported_uncorrect="0"
            [ -z "$udma_crc" ] && udma_crc="0"
            [ -z "$interface_crc" ] && interface_crc="0"
            [ -z "$cmd_timeout" ] && cmd_timeout="0"
            [ -z "$hw_resets" ] && hw_resets="0"
            [ -z "$comreset_events" ] && comreset_events="0"
            [ -z "$spin_retry" ] && spin_retry="0"
            
            # N/A for rate-based attributes (these are normalized values, not counts)
            [ -z "$seek_error" ] && seek_error="N/A"
            [ -z "$read_error" ] && read_error="N/A"
            
            log_debug "  Key metrics - Temp: ${temp:-N/A}°C, Power Hours: ${power_hours:-N/A}, Reallocated: ${reallocated:-0}"
            
        else
            # Fallback to text parsing if jq not available
            log_debug "jq not available, using text parsing for $drive_id"
            local smartctl_output=$(run_smartctl -x /dev/$drive_id 2>/dev/null)
            
            # Extract SMART attributes (ID-based) - column 10 is RAW_VALUE
            # Use sed to extract just the first number before any parentheses or text
            temp=$(echo "$smartctl_output" | grep "Temperature_Celsius" | awk '{print $10}' | sed 's/(.*//' | head -1)
            airflow_temp=$(echo "$smartctl_output" | grep "Airflow_Temperature_Cel" | awk '{print $10}' | sed 's/(.*//' | head -1)
        power_hours=$(echo "$smartctl_output" | grep "Power_On_Hours" | awk '{print $10}' | sed 's/(.*//' | head -1)
        power_cycle=$(echo "$smartctl_output" | grep "Power_Cycle_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        start_stop=$(echo "$smartctl_output" | grep "Start_Stop_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        load_cycle=$(echo "$smartctl_output" | grep "Load_Cycle_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        power_off_retract=$(echo "$smartctl_output" | grep "Power-Off_Retract_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        spin_retry=$(echo "$smartctl_output" | grep "Spin_Retry_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        reallocated=$(echo "$smartctl_output" | grep "Reallocated_Sector" | awk '{print $10}' | sed 's/(.*//' | head -1)
        realloc_events=$(echo "$smartctl_output" | grep "Reallocated_Event_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        pending=$(echo "$smartctl_output" | grep "Current_Pending_Sector" | awk '{print $10}' | sed 's/(.*//' | head -1)
        uncorrectable=$(echo "$smartctl_output" | grep "Offline_Uncorrectable" | awk '{print $10}' | sed 's/(.*//' | head -1)
        reported_uncorrect=$(echo "$smartctl_output" | grep "Reported_Uncorrect" | awk '{print $10}' | sed 's/(.*//' | head -1)
        udma_crc=$(echo "$smartctl_output" | grep "UDMA_CRC_Error_Count" | awk '{print $10}' | sed 's/(.*//' | head -1)
        cmd_timeout=$(echo "$smartctl_output" | grep "Command_Timeout" | awk '{print $10}' | sed 's/(.*//' | head -1)
        e2e_error=$(echo "$smartctl_output" | grep "End-to-End_Error" | awk '{print $10}' | sed 's/(.*//' | head -1)
        seek_error=$(echo "$smartctl_output" | grep "Seek_Error_Rate" | awk '{print $10}' | sed 's/(.*//' | head -1)
        multi_zone=$(echo "$smartctl_output" | grep "Multi_Zone_Error_Rate" | awk '{print $10}' | sed 's/(.*//' | head -1)
        read_error=$(echo "$smartctl_output" | grep "Raw_Read_Error_Rate" | awk '{print $10}' | sed 's/(.*//' | head -1)
        hw_ecc=$(echo "$smartctl_output" | grep "Hardware_ECC_Recovered" | awk '{print $10}' | sed 's/(.*//' | head -1)
        g_sense=$(echo "$smartctl_output" | grep "G-Sense_Error_Rate" | awk '{print $10}' | sed 's/(.*//' | head -1)
        high_fly=$(echo "$smartctl_output" | grep "High_Fly_Writes" | awk '{print $10}' | sed 's/(.*//' | head -1)
        head_flying_hours=$(echo "$smartctl_output" | grep "Head_Flying_Hours" | awk '{print $10}' | sed 's/(.*//' | head -1)
        
        # SSD/NVMe specific
        if [ "$drive_type" = "SSD" ] || [ "$drive_type" = "NVMe" ]; then
            wear_level=$(echo "$smartctl_output" | grep -E "Wear_Leveling_Count|SSD_Life_Left|Percent_Lifetime_Remain" | awk '{print $10}' | head -1)
            total_lbas_written=$(echo "$smartctl_output" | grep -E "Total_LBAs_Written|Data_Units_Written" | awk '{print $10}' | head -1)
            total_lbas_read=$(echo "$smartctl_output" | grep -E "Total_LBAs_Read|Data_Units_Read" | awk '{print $10}' | head -1)
        else
            # HDD: Get from attributes or Device Statistics
            total_lbas_written=$(echo "$smartctl_output" | grep "Total_LBAs_Written" | awk '{print $10}' | head -1)
            total_lbas_read=$(echo "$smartctl_output" | grep "Total_LBAs_Read" | awk '{print $10}' | head -1)
        fi
        
        # Extract Device Statistics (GP Log 0x04)
        if echo "$smartctl_output" | grep -q "Device Statistics"; then
            # Temperature Statistics (Page 0x05)
            # Extract numeric values, skip dashes and "N--" type entries
            temp_min=$(echo "$smartctl_output" | grep "Lowest Temperature" | awk '{if ($4 !~ /^-/ && $4 !~ /N/) print $4}' | head -1)
            temp_max=$(echo "$smartctl_output" | grep "Highest Temperature" | awk '{if ($4 !~ /^-/ && $4 !~ /N/) print $4}' | head -1)
            temp_avg_short=$(echo "$smartctl_output" | grep "Average Short Term Temperature" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            temp_avg_long=$(echo "$smartctl_output" | grep "Average Long Term Temperature" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            time_over_temp=$(echo "$smartctl_output" | grep "Time in Over-Temperature" | awk '{if ($4 !~ /^-/ && $4 !~ /N/) print $4}' | head -1)
            
            # Rotating Media Statistics (Page 0x03)
            read_recovery=$(echo "$smartctl_output" | grep "Read Recovery Attempts" | awk '{if ($4 !~ /^-/ && $4 !~ /N/) print $4}' | head -1)
            mech_start_fail=$(echo "$smartctl_output" | grep "Mechanical Start Failures" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            realloc_candidate=$(echo "$smartctl_output" | grep "Realloc. Candidate" | awk '{if ($6 !~ /^-/ && $6 !~ /N/) print $6}' | head -1)
            
            # General Statistics (Page 0x01)
            write_commands=$(echo "$smartctl_output" | grep "Number of Write Commands" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            read_commands=$(echo "$smartctl_output" | grep "Number of Read Commands" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            
            # Also try Logical Sectors if LBAs not found
            if [ "$total_lbas_written" = "N/A" ]; then
                total_lbas_written=$(echo "$smartctl_output" | grep "Logical Sectors Written" | awk '{if ($4 !~ /^-/ && $4 !~ /N/) print $4}' | head -1)
            fi
            if [ "$total_lbas_read" = "N/A" ]; then
                total_lbas_read=$(echo "$smartctl_output" | grep "Logical Sectors Read" | awk '{if ($4 !~ /^-/ && $4 !~ /N/) print $4}' | head -1)
            fi
            
            # Transport Statistics (Page 0x06)
            hw_resets=$(echo "$smartctl_output" | grep "Number of Hardware Resets" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            asr_events=$(echo "$smartctl_output" | grep "Number of ASR Events" | awk '{if ($5 !~ /^-/ && $5 !~ /N/) print $5}' | head -1)
            interface_crc=$(echo "$smartctl_output" | grep "Number of Interface CRC Errors" | awk '{if ($6 !~ /^-/ && $6 !~ /N/) print $6}' | head -1)
        fi
        
        # Extract SATA Phy Event Counters (GP Log 0x11)
        if echo "$smartctl_output" | grep -q "SATA Phy Event Counters"; then
            comreset_events=$(echo "$smartctl_output" | grep "COMRESET" | awk '{print $3}' | head -1)
            # Note: Interface CRC from Phy Events (if not already set from Device Stats)
            if [ "$interface_crc" = "N/A" ]; then
                interface_crc=$(echo "$smartctl_output" | grep "ICRC error" | awk '{print $3}' | head -1)
            fi
        fi
        
        log_debug "  Key metrics (text parsing) - Temp: ${temp:-N/A}°C, Power Hours: ${power_hours:-N/A}"
        fi  # End of jq availability check
    fi  # End of smartctl_json check
    
    # Get SMR status using helper function
    smr_status=$(check_drive_recording_type "$drive_id")
    
    log_debug "  SMR Status: $smr_status"
    
    # Clean up empty values
    [ -z "$temp" ] && temp="N/A"
    [ -z "$airflow_temp" ] && airflow_temp="N/A"
    [ -z "$power_hours" ] && power_hours="N/A"
    [ -z "$serial" ] && serial="N/A"
    
    # Save raw values for raw CSV file
    local temp_raw="$temp"
    local airflow_temp_raw="$airflow_temp"
    local temp_min_raw="$temp_min"
    local temp_max_raw="$temp_max"
    local temp_avg_short_raw="$temp_avg_short"
    local temp_avg_long_raw="$temp_avg_long"
    local power_hours_raw="$power_hours"
    local head_flying_hours_raw="$head_flying_hours"
    local helium_level_raw="$helium_level"
    local wear_level_raw="$wear_level"
    local total_lbas_written_raw="$total_lbas_written"
    local total_lbas_read_raw="$total_lbas_read"
    local write_commands_raw="$write_commands"
    local read_commands_raw="$read_commands"
    
    log_debug "  Writing raw data to CSV: $STATS_HISTORY_FILE"
    
    # Write RAW CSV (no formatting, original values)
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$datestamp" "$timestamp" "$drive_id" "/dev/$drive_id" "$model" "$mountpoint" "$fs_name" "$fs_type" "$omv_tag" \
        "$drive_type" "$serial" "$smart_status" \
        "$temp_raw" "$airflow_temp_raw" "$temp_min_raw" "$temp_max_raw" "$temp_avg_short_raw" "$temp_avg_long_raw" "$time_over_temp" \
        "$power_hours_raw" "$head_flying_hours_raw" "$power_cycle" \
        "$helium_level_raw" "$wear_level_raw" "$start_stop" "$load_cycle" "$power_off_retract" \
        "$spin_retry" "$mech_start_fail" \
        "$reallocated" "$realloc_events" "$realloc_candidate" \
        "$pending" "$uncorrectable" "$reported_uncorrect" \
        "$read_recovery" \
        "$udma_crc" "$interface_crc" "$cmd_timeout" "$e2e_error" \
        "$hw_resets" "$asr_events" "$comreset_events" \
        "$seek_error" "$multi_zone" "$read_error" "$hw_ecc" \
        "$g_sense" "$high_fly" \
        "$smr_status" \
        "$total_lbas_written_raw" "$total_lbas_read_raw" "$write_commands_raw" "$read_commands_raw" \
        >> "$STATS_HISTORY_FILE"
    
    local raw_write_status=$?
    
    # Write HUMAN-READABLE CSV (formatted values with units) if enabled
    if [ "$STATS_HUMAN_READABLE" = "true" ]; then
        log_debug "  Writing human-readable data to CSV: $STATS_HISTORY_HUMAN_FILE"
        
        # Add units to values for readability
        # Temperature values: add °C
        [ "$temp" != "N/A" ] && temp="${temp}°C"
        [ "$airflow_temp" != "N/A" ] && airflow_temp="${airflow_temp}°C"
        [ "$temp_min" != "N/A" ] && temp_min="${temp_min}°C"
        [ "$temp_max" != "N/A" ] && temp_max="${temp_max}°C"
        [ "$temp_avg_short" != "N/A" ] && temp_avg_short="${temp_avg_short}°C"
        [ "$temp_avg_long" != "N/A" ] && temp_avg_long="${temp_avg_long}°C"
        
        # Time values: add hours
        [ "$power_hours" != "N/A" ] && power_hours="${power_hours}h"
        [ "$head_flying_hours" != "N/A" ] && head_flying_hours="${head_flying_hours}h"
        
        # Percentage values: add %
        [ "$helium_level" != "N/A" ] && helium_level="${helium_level}%"
        [ "$wear_level" != "N/A" ] && wear_level="${wear_level}%"
        
        # Convert LBAs to human-readable data sizes (assuming 512-byte sectors)
        if [ "$total_lbas_written" != "N/A" ] && [ -n "$total_lbas_written" ]; then
            local bytes_written=$((total_lbas_written * 512))
            total_lbas_written=$(format_bytes_human "$bytes_written")
        fi
        if [ "$total_lbas_read" != "N/A" ] && [ -n "$total_lbas_read" ]; then
            local bytes_read=$((total_lbas_read * 512))
            total_lbas_read=$(format_bytes_human "$bytes_read")
        fi
        
        # Convert command counts to millions/billions for readability
        if [ "$write_commands" != "N/A" ] && [ -n "$write_commands" ] && [ "$write_commands" -gt 1000000 ]; then
            write_commands=$(format_number_human "$write_commands")
        fi
        if [ "$read_commands" != "N/A" ] && [ -n "$read_commands" ] && [ "$read_commands" -gt 1000000 ]; then
            read_commands=$(format_number_human "$read_commands")
        fi
        
        # Write formatted CSV
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$datestamp" "$timestamp" "$drive_id" "/dev/$drive_id" "$model" "$mountpoint" "$fs_name" "$fs_type" "$omv_tag" \
            "$drive_type" "$serial" "$smart_status" \
            "$temp" "$airflow_temp" "$temp_min" "$temp_max" "$temp_avg_short" "$temp_avg_long" "$time_over_temp" \
            "$power_hours" "$head_flying_hours" "$power_cycle" \
            "$helium_level" "$wear_level" "$start_stop" "$load_cycle" "$power_off_retract" \
            "$spin_retry" "$mech_start_fail" \
            "$reallocated" "$realloc_events" "$realloc_candidate" \
            "$pending" "$uncorrectable" "$reported_uncorrect" \
            "$read_recovery" \
            "$udma_crc" "$interface_crc" "$cmd_timeout" "$e2e_error" \
            "$hw_resets" "$asr_events" "$comreset_events" \
            "$seek_error" "$multi_zone" "$read_error" "$hw_ecc" \
            "$g_sense" "$high_fly" \
            "$smr_status" \
            "$total_lbas_written" "$total_lbas_read" "$write_commands" "$read_commands" \
            >> "$STATS_HISTORY_HUMAN_FILE"
    fi
    
    if [ $raw_write_status -eq 0 ]; then
        log_info "✓ Data collected for $drive_id ($model, $smart_status)"
        return 0
    else
        log_error "Failed to write statistical data for $drive_id"
        return 1
    fi
}

# Get filesystem information for a drive
get_filesystem_info() {
    local drive="$1"
    local mountpoint="N/A"
    local fs_name="N/A"
    local fs_type="N/A"
    local omv_label="N/A"
    
    # Try main partition first (e.g., sda1)
    local partition="${drive}1"
    local partition_info=$(lsblk -no MOUNTPOINT,FSTYPE,LABEL /dev/$partition 2>/dev/null | head -1)
    
    if [ -n "$partition_info" ]; then
        mountpoint=$(echo "$partition_info" | awk '{print $1}')
        fs_type=$(echo "$partition_info" | awk '{print $2}')
        fs_name=$(echo "$partition_info" | awk '{print $3}')
        [ -z "$mountpoint" ] && mountpoint="N/A"
        [ -z "$fs_type" ] && fs_type="N/A"
        [ -z "$fs_name" ] && fs_name="N/A"
    else
        # Fallback: check base drive
        partition_info=$(lsblk -no MOUNTPOINT,FSTYPE,LABEL /dev/$drive 2>/dev/null | head -1)
        if [ -n "$partition_info" ]; then
            mountpoint=$(echo "$partition_info" | awk '{print $1}')
            fs_type=$(echo "$partition_info" | awk '{print $2}')
            fs_name=$(echo "$partition_info" | awk '{print $3}')
            [ -z "$mountpoint" ] && mountpoint="N/A"
            [ -z "$fs_type" ] && fs_type="N/A"
            [ -z "$fs_name" ] && fs_name="N/A"
        fi
    fi
    
    # Get OMV tag if available
    if command -v omv-confdbadm &> /dev/null; then
        local uuid=$(lsblk -no UUID /dev/$partition 2>/dev/null)
        if [ -n "$uuid" ]; then
            omv_label=$(omv-confdbadm read "conf.system.filesystem.mountpoint" --filter "uuid==\"$uuid\"" 2>/dev/null | grep -oP '"comment":\s*"\K[^"]+' || echo "N/A")
        fi
    fi
    
    echo "${mountpoint}|${fs_name}|${fs_type}|${omv_label}"
}

# Collect data for all drives
collect_all_drives() {
    log_info "Starting statistical data collection for all drives"
    
    # Check if jq is available and log once
    if command -v jq >/dev/null 2>&1; then
        log_info "JSON parsing available (jq found) - using structured smartctl output"
    else
        log_info "JSON parsing unavailable (jq not found) - falling back to text parsing"
    fi
    
    # Get drives from /dev/sd? directly to avoid waking them
    # Don't use get_smart_drives() as it queries each drive with smartctl which wakes them
    local drives=$(ls /dev/sd? 2>/dev/null | sed 's|/dev/||' | xargs)
    local count=0
    local success=0
    
    if [ -z "$drives" ]; then
        log_warning "No SMART-capable drives found"
        return 0
    fi
    
    local drive_list=$(echo $drives | tr ' ' ',')
    log_info "Found $(echo $drives | wc -w) drive(s) to process: $drive_list"
    
    for drive in $drives; do
        ((count++))
        log_debug "Processing drive $count of $(echo $drives | wc -w): $drive"
        if collect_drive_data "$drive"; then
            ((success++))
        else
            log_warning "Failed to collect data from $drive"
        fi
    done
    
    log_info "Statistical data collection complete: $success/$count drives successful"
    return 0
}

# Purge old data based on retention policy
purge_old_data() {
    if [ ! -f "$STATS_HISTORY_FILE" ]; then
        log_debug "No history file to purge"
        return 0
    fi
    
    if [ -z "$STATS_RETENTION_DAYS" ] || [ "$STATS_RETENTION_DAYS" -le 0 ]; then
        log_debug "Data retention disabled (retention_days: ${STATS_RETENTION_DAYS:-not set})"
        return 0
    fi
    
    log_info "Checking for data older than $STATS_RETENTION_DAYS days"
    log_debug "History file: $STATS_HISTORY_FILE"
    
    local cutoff_date=$(date -d "$STATS_RETENTION_DAYS days ago" +%Y-%m-%d 2>/dev/null)
    if [ -z "$cutoff_date" ]; then
        log_error "Failed to calculate cutoff date"
        return 1
    fi
    
    log_debug "Cutoff date: $cutoff_date (purging older records)"
    
    local temp_file=$(mktemp)
    
    # Keep header
    head -1 "$STATS_HISTORY_FILE" > "$temp_file"
    
    # Keep only records newer than cutoff
    tail -n +2 "$STATS_HISTORY_FILE" | awk -F',' -v cutoff="$cutoff_date" '$1 >= cutoff' >> "$temp_file"
    
    local old_lines=$(wc -l < "$STATS_HISTORY_FILE")
    local new_lines=$(wc -l < "$temp_file")
    local purged=$((old_lines - new_lines))
    
    if [ $purged -gt 0 ]; then
        mv "$temp_file" "$STATS_HISTORY_FILE"
        log_info "✓ Purged $purged old record(s), retained $((new_lines - 1)) record(s)"
    else
        rm -f "$temp_file"
        log_info "No old records to purge (all data within retention period)"
    fi
    
    return 0
}

# ============================================================================
# Cleanup debug JSON files
# ============================================================================
cleanup_debug_json() {
    local json_debug_dir="$(dirname "$STATS_HISTORY_FILE")/debug_json"
    
    if [ -d "$json_debug_dir" ]; then
        log_debug "Cleaning up debug JSON files from: $json_debug_dir"
        rm -rf "$json_debug_dir"
        log_debug "Debug JSON directory removed"
    fi
}

# ============================================================================
# Plugin System Entry Point (called by multi-report-omv auto)
# ============================================================================

plugin_statistical_data_main() {
    local start_time=$(date +%s)
    
    log_info "[STATS] Statistical data collection plugin starting"
    
    # Check if enabled (from config, not manifest)
    local enabled=$(get_config "STATS_ENABLED" "true")
    
    if [ "$enabled" != "true" ]; then
        log_info "[STATS] Statistical data collection is disabled"
        write_plugin_summary "statistical_data" "summary.txt" "Statistical data collection disabled in configuration"
        return 0
    fi
    
    # Load configuration
    load_statistical_config
    
    # Initialize history file
    initialize_history_file || {
        log_error "[STATS] Failed to initialize history file"
        return 1
    }
    
    # Collect data from all drives
    local drive_count=0
    local success_count=0
    local error_count=0
    
    log_info "[STATS] Collecting SMART data from all drives"
    collect_all_drives
    
    # Count drives processed (approximate from CSV if available)
    if [ -f "$STATS_HISTORY_FILE" ]; then
        # Get unique devices from today's entries
        drive_count=$(grep "^$(date +%Y-%m-%d)" "$STATS_HISTORY_FILE" 2>/dev/null | cut -d',' -f3 | sort -u | wc -l)
        success_count=$drive_count
    fi
    
    # Purge old data if retention is configured
    if [ "$STATS_RETENTION_DAYS" -gt 0 ]; then
        log_info "[STATS] Purging data older than $STATS_RETENTION_DAYS days"
        purge_old_data
    fi
    
    # Cleanup debug JSON files if not in debug mode
    if [ "${CONFIG[LOG_LEVEL]}" != "debug" ]; then
        cleanup_debug_json
    fi
    
    # Calculate execution time
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    # Create summary text
    local summary_text=""
    summary_text+="Statistical Data Collection Summary"$'\n'
    summary_text+="==================================="$'\n'
    summary_text+=""$'\n'
    summary_text+="Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"$'\n'
    summary_text+="Drives processed: $drive_count"$'\n'
    summary_text+="Successful collections: $success_count"$'\n'
    summary_text+="Errors: $error_count"$'\n'
    summary_text+="History file: $STATS_HISTORY_FILE"$'\n'
    summary_text+="Retention policy: $STATS_RETENTION_DAYS days"$'\n'
    summary_text+="Execution time: ${execution_time}s"$'\n'
    summary_text+=""$'\n'
    summary_text+="Data collected: 46+ metrics per drive (16 SMART attributes, Device Statistics, SATA Phy counters)"$'\n'
    summary_text+="Including: Temperature profiles, power metrics, sector health,"$'\n'
    summary_text+="           mechanical wear, error rates, performance stats"$'\n'
    
    # Create JSON summary
    local summary_json="$PLUGIN_SUMMARY_DIR/statistical_data-summary.json"
    cat > "$summary_json" <<EOF
{
    "plugin": "statistical_data",
    "command": "statistical_data",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "has_errors": false,
    "completed_successfully": true,
    "drives_processed": $drive_count,
    "successful_collections": $success_count,
    "errors": $error_count,
    "history_file": "$STATS_HISTORY_FILE",
    "retention_days": $STATS_RETENTION_DAYS,
    "execution_time": "$execution_time"
}
EOF
    
    log_debug "Created JSON summary: $summary_json"
    
    # Write text summary
    echo "$summary_text" > "$PLUGIN_SUMMARY_DIR/statistical_data-summary-text.txt"
    log_debug "Saved text summary: $PLUGIN_SUMMARY_DIR/statistical_data-summary-text.txt"
    
    # Write to default summary.txt for backward compatibility
    write_plugin_summary "statistical_data" "summary.txt" "$summary_text"
    
    # Export for notification system
    export STATS_SUMMARY_TEXT="$summary_text"
    export STATS_HAS_ERRORS="false"
    export STATS_COMPLETED_SUCCESSFULLY="true"
    export STATS_DRIVES_PROCESSED="$drive_count"
    export STATS_PLUGIN_EXECUTION_TIME="$execution_time"
    
    log_debug "[STATS] Exported to notification system"
    
    log_info "[STATS] Statistical data collection plugin completed ($drive_count drives, ${execution_time}s)"
    
    return 0
}

# ============================================================================
# Standalone Entry Point (for direct execution)
# ============================================================================

# Main plugin entry point
main() {
    local action="${1:-collect}"
    
    log_info "Statistical Data Plugin v$PLUGIN_VERSION - Action: $action"
    
    # Load configuration
    load_statistical_config
    
    if [ "$STATS_ENABLE" != "true" ]; then
        log_info "Statistical data collection is disabled"
        return 0
    fi
    
    # Initialize history file if needed
    initialize_history_file || return 1
    
    case "$action" in
        collect)
            collect_all_drives
            purge_old_data
            ;;
        collect-drive)
            local drive_id="$2"
            if [ -z "$drive_id" ]; then
                log_error "No drive ID provided for collect-drive action"
                return 1
            fi
            collect_drive_data "$drive_id"
            ;;
        purge)
            purge_old_data
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Usage: $0 {collect|collect-drive <drive>|purge}"
            return 1
            ;;
    esac
    
    return $?
}

# Plugin entry point
# Always called via: ./bin/multi-report-omv auto
# Or directly via: ./bin/multi-report-omv statistical_data
