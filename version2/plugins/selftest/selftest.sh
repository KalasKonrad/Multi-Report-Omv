#!/bin/bash
################################################################################
# Multi-Report-OMV
# Self-test Plugin
# SMART drive self-test scheduler with rotation algorithm
################################################################################
#
# Table of Contents:
# 1. Configuration
# 2. History Tracking
# 3. Plugin Lifecycle
# 4. Main Plugin Execution
#
################################################################################

################################################################################
# 1. CONFIGURATION
################################################################################

# History file locations (CSV format)
SELFTEST_DATA_DIR="${CONFIG_BASE}/selftest"
DRIVES_FILE="$SELFTEST_DATA_DIR/drives.csv"
TEST_HISTORY_FILE="$SELFTEST_DATA_DIR/test_history.csv"

################################################################################
################################################################################
# 2. HISTORY TRACKING
################################################################################

# Note: Common drive helper functions (run_smartctl, get_drive_serial, etc.)
# are now provided by core/utils.sh and don't need to be redefined here.

# Get selftest history file path
################################################################################

# Helper function to call smartctl with proper privileges
run_smartctl() {
    if is_root; then
        smartctl "$@"
    else
        sudo smartctl "$@"
    fi
}

# Get drive information using lsblk (more efficient than multiple smartctl calls)
# Returns: NAME SIZE MODEL SERIAL TYPE FSTYPE UUID LABEL MOUNTPOINT (space-separated)
get_drive_info() {
    local drive="$1"
    lsblk -d -n -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,UUID,LABEL,MOUNTPOINT "/dev/$drive" 2>/dev/null
}

# Get serial number from lsblk
get_drive_serial() {
    local drive="$1"
    lsblk -d -n -o SERIAL "/dev/$drive" 2>/dev/null | tr -d ' '
}

# Get drive model
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

# Initialize history tracking (creates CSV files with headers)
init_selftest_history() {
    log_info "Initializing selftest history tracking (CSV format)"
    
    if [[ ! -d "$SELFTEST_DATA_DIR" ]]; then
        if ! mkdir -p "$SELFTEST_DATA_DIR" 2>/dev/null; then
            log_error "Failed to create history directory: $SELFTEST_DATA_DIR"
            return 1
        fi
        log_info "Created history directory: $SELFTEST_DATA_DIR"
    fi
    
    if [[ ! -f "$DRIVES_FILE" ]]; then
        if ! echo "Serial Number,Drive ID,Model,Capacity,Type,Firmware,UUID,Label,First Seen,Last Seen" > "$DRIVES_FILE"; then
            log_error "Failed to create drives file: $DRIVES_FILE"
            return 1
        fi
        chmod 644 "$DRIVES_FILE" 2>/dev/null
        log_info "Created drives CSV: $DRIVES_FILE"
    else
        # Check if migration is needed (old format without UUID,Label columns)
        local header=$(head -n 1 "$DRIVES_FILE")
        if [[ "$header" == "Serial Number,Drive ID,Model,Capacity,Type,Firmware,First Seen,Last Seen" ]]; then
            log_info "Migrating drives.csv to new format (adding UUID and Label columns)..."
            local temp_file="${DRIVES_FILE}.migration"
            local backup_file="${DRIVES_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
            
            # Backup old file
            if ! cp "$DRIVES_FILE" "$backup_file"; then
                log_error "Failed to create backup: $backup_file"
                return 1
            fi
            log_info "Created backup: $backup_file"
            
            # Write new header
            echo "Serial Number,Drive ID,Model,Capacity,Type,Firmware,UUID,Label,First Seen,Last Seen" > "$temp_file"
            
            # Migrate existing data (add empty UUID,Label columns)
            tail -n +2 "$DRIVES_FILE" | while IFS=',' read -r serial id model capacity type firmware first_seen last_seen; do
                echo "$serial,$id,$model,$capacity,$type,$firmware,,$first_seen,$last_seen"
            done >> "$temp_file"
            
            # Replace old file with migrated one
            if ! mv "$temp_file" "$DRIVES_FILE"; then
                log_error "Failed to replace drives file with migrated version"
                return 1
            fi
            
            log_success "Migration completed. Old file backed up to: $backup_file"
        fi
        # Close the outer drives-file existence check's else block
    fi
    
    if [[ ! -f "$TEST_HISTORY_FILE" ]]; then
        if ! echo "Scheduled,Drive Serial,Drive ID,Test Type,Status,Started,Completed,Duration (sec),Exit Code,Error" > "$TEST_HISTORY_FILE"; then
            log_error "Failed to create test history file: $TEST_HISTORY_FILE"
            return 1
        fi
        chmod 644 "$TEST_HISTORY_FILE" 2>/dev/null
        log_info "Created test history CSV: $TEST_HISTORY_FILE"
    fi
    
    log_success "History tracking initialized"
    return 0
}

# Register or update a drive
register_drive() {
    local drive_id="$1" serial="$2" model="$3" capacity="$4" type="$5" firmware="$6" uuid="$7" label="$8"
    [[ -z "$serial" || -z "$drive_id" ]] && { log_error "register_drive: serial and drive_id required"; return 1; }
    
    local timestamp=$(date -Iseconds)
    local existing_line=$(tail -n +2 "$DRIVES_FILE" 2>/dev/null | grep -F ",$serial,")
    
    if [[ -n "$existing_line" ]]; then
        local temp_file="${DRIVES_FILE}.tmp"
        {
            head -n 1 "$DRIVES_FILE"
            tail -n +2 "$DRIVES_FILE" | while IFS=',' read -r s_serial s_id s_model s_capacity s_type s_firmware s_uuid s_label s_first s_last; do
                if [[ "$s_serial" == "$serial" ]]; then
                    echo "$(csv_escape "$serial"),$(csv_escape "$drive_id"),$(csv_escape "$model"),$(csv_escape "$capacity"),$(csv_escape "$type"),$(csv_escape "$firmware"),$(csv_escape "$uuid"),$(csv_escape "$label"),$(csv_escape "$s_first"),$(csv_escape "$timestamp")"
                else
                    echo "$s_serial,$s_id,$s_model,$s_capacity,$s_type,$s_firmware,$s_uuid,$s_label,$s_first,$s_last"
                fi
            done
        } > "$temp_file" && mv -f "$temp_file" "$DRIVES_FILE"
        log_debug "Updated drive: $drive_id ($serial)"
    else
        echo "$(csv_escape "$serial"),$(csv_escape "$drive_id"),$(csv_escape "$model"),$(csv_escape "$capacity"),$(csv_escape "$type"),$(csv_escape "$firmware"),$(csv_escape "$uuid"),$(csv_escape "$label"),$(csv_escape "$timestamp"),$(csv_escape "$timestamp")" >> "$DRIVES_FILE"
        log_info "Registered new drive: $drive_id ($serial)"
    fi
    return 0
}

# Schedule a test
schedule_test() {
    local drive_id="$1" serial="$2" test_type="$3"
    [[ -z "$serial" || -z "$test_type" ]] && { log_error "schedule_test: serial and test_type required"; return 1; }
    
    local timestamp=$(date -Iseconds)
    echo "$(csv_escape "$timestamp"),$(csv_escape "$serial"),$(csv_escape "$drive_id"),$(csv_escape "$test_type"),scheduled,,,,," >> "$TEST_HISTORY_FILE"
    log_debug "Scheduled $test_type test for $drive_id ($serial)"
    return 0
}

# Start a test (updates status and records start time)
start_test() {
    local drive_id="$1" serial="$2" test_type="$3"
    [[ -z "$serial" || -z "$test_type" ]] && { log_error "start_test: serial and test_type required"; return 1; }
    
    local timestamp=$(date -Iseconds)
    local temp_file="${TEST_HISTORY_FILE}.tmp"
    
    # Update the most recent scheduled test for this drive/type to "running"
    {
        head -n 1 "$TEST_HISTORY_FILE"
        tail -n +2 "$TEST_HISTORY_FILE" | tac | awk -v serial="$serial" -v ttype="$test_type" -v started="$timestamp" -F',' '
            BEGIN { OFS=","; updated=0 }
            {
                if (!updated && $2 == serial && $4 == ttype && $5 == "scheduled") {
                    print $1, $2, $3, $4, "running", started, "", "", "", ""
                    updated=1
                } else {
                    print $0
                }
            }
        ' | tac
    } > "$temp_file" && mv -f "$temp_file" "$TEST_HISTORY_FILE"
    
    log_debug "Started $test_type test for $drive_id ($serial)"
    return 0
}

# Complete a test (updates status, completion time, duration, exit code)
complete_test() {
    local drive_id="$1" serial="$2" test_type="$3" exit_code="$4" error_msg="${5:-}"
    [[ -z "$serial" || -z "$test_type" ]] && { log_error "complete_test: serial and test_type required"; return 1; }
    
    local timestamp=$(date -Iseconds)
    local status="completed"
    [[ $exit_code -ne 0 ]] && status="failed"
    
    local temp_file="${TEST_HISTORY_FILE}.tmp"
    
    # Update the most recent running test for this drive/type
    {
        head -n 1 "$TEST_HISTORY_FILE"
        tail -n +2 "$TEST_HISTORY_FILE" | tac | awk -v serial="$serial" -v ttype="$test_type" -v completed="$timestamp" -v status="$status" -v exit_code="$exit_code" -v error="$error_msg" -F',' '
            BEGIN { OFS=","; updated=0 }
            {
                if (!updated && $2 == serial && $4 == ttype && $5 == "running") {
                    # Calculate duration in seconds
                    started=$6
                    gsub(/"/, "", started)
                    gsub(/"/, "", completed)
                    
                    # Simple duration calculation (may need date parsing for accuracy)
                    duration=""
                    if (started != "") {
                        cmd = "date -d \"" started "\" +%s 2>/dev/null || echo 0"
                        cmd | getline start_sec
                        close(cmd)
                        
                        cmd = "date -d \"" completed "\" +%s 2>/dev/null || echo 0"
                        cmd | getline end_sec
                        close(cmd)
                        
                        if (start_sec > 0 && end_sec > 0) {
                            duration = end_sec - start_sec
                        }
                    }
                    
                    print $1, $2, $3, $4, status, started, completed, duration, exit_code, error
                    updated=1
                } else {
                    print $0
                }
            }
        ' | tac
    } > "$temp_file" && mv -f "$temp_file" "$TEST_HISTORY_FILE"
    
    log_debug "Completed $test_type test for $drive_id ($serial) - status: $status, exit code: $exit_code"
    return 0
}

# Get serial from cache (history file) or by querying drive if not in cache
# Returns serial number or empty string
get_serial_cached() {
    local drive="$1"
    
    # First check if drive info is in history file (no wake-up needed)
    if [ -f "$TEST_HISTORY_FILE" ]; then
        local cached_serial=$(awk -F',' -v d="$drive" '$3=="\""d"\"" || $3==d {gsub(/"/, "", $2); print $2; exit}' "$TEST_HISTORY_FILE")
        if [ -n "$cached_serial" ]; then
            log_debug "Drive $drive serial found in cache: $cached_serial"
            echo "$cached_serial"
            return 0
        fi
    fi
    
    # Not in cache - need to check if it's a new drive
    log_debug "Drive $drive not in history, checking if present (may wake if sleeping)"
    
    # Check power mode first
    local power_check_exit=0
    run_smartctl -n standby /dev/$drive >/dev/null 2>&1
    power_check_exit=$?
    
    if [ "$power_check_exit" -eq 2 ]; then
        log_info "Drive $drive is sleeping and not in history - will register on next wake/test"
        echo ""
        return 1
    fi
    
    # Drive is awake, safe to query
    local serial=$(get_drive_serial "$drive")
    echo "$serial"
    return 0
}

# Register a single drive on-demand (only when needed for testing or new drive detection)
# This function will wake the drive if it's sleeping, but only when actually scheduling a test
register_drive_on_demand() {
    local drive="$1"
    local serial model size type firmware uuid label
    
    {
        log_debug "Registering drive $drive (will wake if sleeping)"
        
        serial=$(get_drive_serial "$drive")
        model=$(get_drive_model "$drive")
        size=$(get_drive_size "$drive")
        type=$(get_drive_type "$drive")
        firmware=$(get_drive_firmware "$drive")
        uuid=$(get_drive_uuid "$drive")
        label=$(get_drive_label "$drive")
        
        if [ -n "$serial" ]; then
            register_drive "$drive" "$serial" "$model" "$size" "$type" "$firmware" "$uuid" "$label"
            log_debug "Drive $drive registered: $model ($serial)"
        else
            log_warning "Could not get serial number for drive $drive"
            return 1
        fi
    } >&2
    
    # Only return the serial number to stdout (everything else went to stderr)
    echo "$serial"
    return 0
}

# Execute a SMART test using smartctl
execute_test() {
    local drive_id="$1" serial="$2" test_type="$3"
    [[ -z "$drive_id" || -z "$serial" || -z "$test_type" ]] && { 
        log_error "execute_test: drive_id, serial, and test_type required"
        return 1
    }
    
    log_info "Executing $test_type test on /dev/$drive_id"
    
    # Mark test as started
    start_test "$drive_id" "$serial" "$test_type"
    
    # Execute the test with smartctl
    local output
    local exit_code
    
    output=$(run_smartctl -t "$test_type" "/dev/$drive_id" 2>&1)
    exit_code=$?
    
    # Quick device-level verification: some drives set an execution-in-progress flag
    # before updating the self-test log text. Query `smartctl -x` to check execution status.
    # Using -x for extended info which includes vendor-specific data.
    local exec_out
    exec_out=$(run_smartctl -x "/dev/$drive_id" 2>/dev/null) || exec_out=""

    # Check if test was successfully started or device reports in-progress
    if [ $exit_code -eq 0 ] || echo "$output" | grep -qi "test has begun" || echo "$exec_out" | grep -Ei 'Self-test routine in progress|Self-test execution status:.*in progress|in progress' >/dev/null 2>&1; then
        log_success "Started $test_type test on /dev/$drive_id"
        # Status remains "running" until we check results on next plugin execution
        if echo "$output" | grep -qi "Please wait.*minutes"; then
            local wait_time=$(echo "$output" | grep -i "Please wait" | grep -oP '\\d+(?= minutes)')
            if [ -n "$wait_time" ]; then
                log_info "Test will complete in approximately $wait_time minutes"
            fi
        fi
        return 0
    elif echo "$output" | grep -qi "Self-test already in progress"; then
        log_warning "Self-test already in progress on /dev/$drive_id ($test_type)"
        # Do NOT mark as failed, just treat as busy
        return 2
    else
        # Test failed to start — capture device output for diagnostics
        local error_msg=$(echo "$output" | grep -i "error\|failed\|unavailable" | head -n 1)
        [ -z "$error_msg" ] && error_msg="Unknown error starting test"
        log_error "Failed to start $test_type test on /dev/$drive_id: $error_msg"
        # Include smartctl -x output for debugging in history
        local debug_out
        debug_out=$(echo "$exec_out" | head -n 50 | sed ':a;N;$!ba;s/\n/\\n/g')
        complete_test "$drive_id" "$serial" "$test_type" $exit_code "$error_msg - Context: $debug_out"
        return 1
    fi
}

# Check actual SMART test results from drive's self-test log
check_test_results() {
    local drive_id="$1" test_type="$2"
    [[ -z "$drive_id" || -z "$test_type" ]] && {
        log_error "check_test_results: drive_id and test_type required"
        return 1
    }
    
    # Check device-level execution status (authoritative source)
    # Use -x for extended info which includes vendor-specific data
    local exec_out
    exec_out=$(run_smartctl -x "/dev/$drive_id" 2>/dev/null) || exec_out=""

    # Extract the execution status line
    local exec_status
    exec_status=$(echo "$exec_out" | grep -E "Self-test execution status:")
    
    # If test is in progress, return immediately
    if echo "$exec_status" | grep -Ei 'in progress|[0-9]+% of test remaining|Self-test routine in progress' >/dev/null 2>&1; then
        log_debug "Device-level reports self-test in progress for /dev/$drive_id"
        return 3
    fi
    
    # If execution status shows error/failure (not code 0)
    if echo "$exec_status" | grep -Ev '\(\s*0\)' | grep -Ei 'failed|error|aborted|interrupted' >/dev/null 2>&1; then
        log_debug "Device-level reports test failure for /dev/$drive_id: $exec_status"
        return 1
    fi
    
    # If status is (0), check selftest log to verify completion and type match
    if echo "$exec_status" | grep -E '\(\s*0\)' >/dev/null 2>&1; then
        # Get the most recent self-test result from selftest log
        local test_output=$(run_smartctl -l selftest "/dev/$drive_id" 2>/dev/null)
        
        # Parse the first line of test results (most recent)
        local test_result=$(echo "$test_output" | grep -E "^# *1 " | head -n 1)
        
        if [ -z "$test_result" ]; then
            log_debug "Execution status (0) but no self-test log entries for /dev/$drive_id"
            return 2
        fi
        
        # Verify the most-recent test matches the expected type
        if [[ "$test_type" == "short" ]]; then
            if ! echo "$test_result" | grep -Eiq "\bShort\b"; then
                log_debug "Most recent test on /dev/$drive_id is not a short test"
                return 2
            fi
        elif [[ "$test_type" == "long" ]]; then
            if ! echo "$test_result" | grep -Eiq "\bExtended\b"; then
                log_debug "Most recent test on /dev/$drive_id is not an extended (long) test"
                return 2
            fi
        fi

        # Verify it completed without error
        if echo "$test_result" | grep -qi "Completed without error"; then
            log_debug "Test passed on /dev/$drive_id (type match confirmed)"
            return 0
        else
            # Log entry shows failure
            local status_snippet=$(echo "$test_result" | sed -E 's/^# *[0-9]+\s+//')
            log_warning "Test failed on /dev/$drive_id: $status_snippet"
            return 1
        fi
    fi
    
    # Fallback: execution status unclear, check selftest log
    local test_output=$(run_smartctl -l selftest "/dev/$drive_id" 2>/dev/null)
    local test_result=$(echo "$test_output" | grep -E "^# *1 " | head -n 1)
    
    if [ -z "$test_result" ]; then
        log_debug "No self-test results found for /dev/$drive_id"
        return 2
    fi
    
    # Ensure the most-recent test is the expected type for this check
    # smartctl labels tests as 'Short' or 'Extended' in the Test_Description
    if [[ "$test_type" == "short" ]]; then
        if ! echo "$test_result" | grep -Eiq "\bShort\b"; then
            log_debug "Most recent test on /dev/$drive_id is not a short test"
            return 2
        fi
    elif [[ "$test_type" == "long" ]]; then
        if ! echo "$test_result" | grep -Eiq "\bExtended\b"; then
            log_debug "Most recent test on /dev/$drive_id is not an extended (long) test"
            return 2
        fi
    fi

    # Check the status using direct text matching (more robust than field-splitting)
    if echo "$test_result" | grep -qi "Completed without error"; then
        log_debug "Test passed on /dev/$drive_id"
        return 0
    elif echo "$test_result" | grep -qi "in progress"; then
        log_debug "Test still in progress on /dev/$drive_id"
        return 3
    else
        # Any other status is considered a failure (capture the status snippet for logging)
        local status_snippet=$(echo "$test_result" | sed -E 's/^# *[0-9]+\s+//')
        log_warning "Test failed on /dev/$drive_id: $status_snippet"
        return 1
    fi
}

# Count running tests of a specific type today
count_running_tests() {
    local test_type="$1"
    [[ ! -f "$TEST_HISTORY_FILE" ]] && echo "0" && return
    # Count any running tests of the requested type regardless of when they were scheduled.
    # This prevents starting new tests when long/short tests are actively running (even if they were started on a prior day).
    local count=$(tail -n +2 "$TEST_HISTORY_FILE" | awk -F',' -v t="$test_type" '$4==t && $5=="running" {c++} END {print c+0}')
    echo "$count"
}

# Update status of all running tests by checking actual test results
update_running_tests() {
    [[ ! -f "$TEST_HISTORY_FILE" ]] && return 0
    
    log_debug "Checking status of running tests..."
    local updated_count=0
    
    # Get all running tests
    tail -n +2 "$TEST_HISTORY_FILE" | while IFS=',' read -r scheduled drive_serial drive_id ttype status started completed duration exit_code error; do
        # Remove potential quotes from CSV values
        scheduled=$(echo "$scheduled" | tr -d '"')
        drive_serial=$(echo "$drive_serial" | tr -d '"')
        drive_id=$(echo "$drive_id" | tr -d '"')
        ttype=$(echo "$ttype" | tr -d '"')
        status=$(echo "$status" | tr -d '"')
        
        if [[ "$status" == "running" ]]; then
            # Validate required fields are not empty
            if [[ -z "$drive_id" || -z "$drive_serial" || -z "$ttype" ]]; then
                log_warning "Skipping invalid running test entry: drive_id='$drive_id', serial='$drive_serial', type='$ttype'"
                continue
            fi
            
            # Check power mode - only wake drives with running tests
            local power_check_exit=0
            run_smartctl -n standby /dev/$drive_id >/dev/null 2>&1
            power_check_exit=$?
            
            if [ "$power_check_exit" -eq 2 ]; then
                log_info "Drive $drive_id is in standby but has running $ttype test - waking to check status"
            fi
            
            log_debug "Checking test status for $drive_id ($drive_serial) - $ttype test"
            
            # Check the actual test results from smartctl
            check_test_results "$drive_id" "$ttype"
            local result=$?
            
            case $result in
                0)  # Test completed successfully
                    log_info "Test completed successfully on $drive_id ($drive_serial)"
                    complete_test "$drive_id" "$drive_serial" "$ttype" 0 ""
                    ((updated_count++))
                    ;;
                1)  # Test failed
                    log_warning "Test failed on $drive_id ($drive_serial)"
                    complete_test "$drive_id" "$drive_serial" "$ttype" 1 "Test failed - check SMART log"
                    ((updated_count++))
                    ;;
                3)  # Test still in progress
                    log_debug "Test still in progress on $drive_id ($drive_serial)"
                    ;;
                *)  # No results or error
                    log_debug "Could not determine test status for $drive_id ($drive_serial)"
                    ;;
            esac
        fi
    done
    
    if [ $updated_count -gt 0 ]; then
        log_info "Updated status for $updated_count test(s)"
    else
        log_debug "No running tests to update"
    fi
    
    return 0
}

# Get last completed test date
get_last_test_date() {
    local serial="$1" test_type="$2"
    [[ ! -f "$TEST_HISTORY_FILE" ]] && return 1
    
    tail -n +2 "$TEST_HISTORY_FILE" | tac | while IFS=',' read -r scheduled drive_serial drive_id ttype status started completed duration exit_code error; do
        if [[ "$drive_serial" == "$serial" && "$ttype" == "$test_type" && "$status" == "completed" ]]; then
            echo "$completed"
            return 0
        fi
    done
    return 1
}

# Get days since last completed test
get_days_since_last_test() {
    local serial="$1" test_type="$2"
    local last_test=$(get_last_test_date "$serial" "$test_type")
    
    if [[ -z "$last_test" ]]; then
        echo "-1"
        return 1
    fi
    
    local now_sec=$(date +%s)
    local last_sec=$(date -d "$last_test" +%s 2>/dev/null || echo "0")
    [[ "$last_sec" -eq 0 ]] && { echo "-1"; return 1; }
    
    echo $(( (now_sec - last_sec) / 86400 ))
    return 0
}

# Check if drive is overdue for testing
is_drive_overdue() {
    local serial="$1" test_type="$2" max_days="$3"
    local days=$(get_days_since_last_test "$serial" "$test_type")
    [[ "$days" -eq -1 || "$days" -ge "$max_days" ]] && return 0
    return 1
}

# Get drives sorted by last test date (oldest first, never-tested first)
# Returns drives in format: "drive_id:days_since_test" sorted by priority
# This function queries drive serials by looking them up in TEST_HISTORY_FILE first
# to avoid waking sleeping drives unnecessarily
get_drives_by_priority() {
    local test_type="$1"
    shift
    local drives=("$@")
    
    declare -A drive_priorities
    declare -A drive_serials_cache  # Cache serials from history to avoid smartctl calls
    
    # First, build cache of known serials from history file (no drive wake-up needed)
    if [ -f "$TEST_HISTORY_FILE" ]; then
        while IFS=',' read -r scheduled serial drive_id rest; do
            serial=$(echo "$serial" | tr -d '"')
            drive_id=$(echo "$drive_id" | tr -d '"')
            if [ -n "$serial" ] && [ -n "$drive_id" ]; then
                drive_serials_cache["$drive_id"]="$serial"
            fi
        done < <(tail -n +2 "$TEST_HISTORY_FILE")
    fi
    
    # Calculate priority for each drive (days since last test, -1 for never tested)
    for drive in "${drives[@]}"; do
        # Try to get serial from cache first (no drive wake-up)
        local serial="${drive_serials_cache[$drive]:-}"
        
        # If not in cache, use get_serial_cached which checks power mode
        if [ -z "$serial" ]; then
            serial=$(get_serial_cached "$drive")
        fi
        
        if [ -n "$serial" ]; then
            local days=$(get_days_since_last_test "$serial" "$test_type")
            # Never tested drives get highest priority (use 999999)
            if [ "$days" -eq -1 ]; then
                drive_priorities["$drive"]=999999
            else
                drive_priorities["$drive"]=$days
            fi
        else
            # No serial (sleeping or error), assign medium priority so it's checked later
            drive_priorities["$drive"]=500
        fi
    done
    
    # Sort drives by priority (descending - oldest/never-tested first)
    for drive in "${!drive_priorities[@]}"; do
        echo "${drive_priorities[$drive]}:$drive"
    done | sort -t: -k1 -rn | cut -d: -f2
}

################################################################################
# 3. PLUGIN LIFECYCLE
################################################################################

# Plugin initialization (called once when plugin loads)
plugin_selftest_init() {
    log_debug "Initializing selftest plugin"
    
    # Initialize history tracking
    init_selftest_history || {
        log_error "Failed to initialize history tracking"
        return 1
    }
    
    log_debug "Selftest plugin initialized"
}

# Plugin cleanup (called on exit)
plugin_selftest_cleanup() {
    log_debug "Cleaning up selftest plugin"
}

################################################################################
# 4. MAIN PLUGIN EXECUTION
################################################################################

# Main plugin function (required)
plugin_selftest_main() {
    # Record plugin start time
    start_plugin_timing
    
    log_info "Self-test plugin starting"
    
    # Get configuration
    local enabled=$(get_config "SELFTEST_ENABLED" "true")
    
    if [ "$enabled" != "true" ]; then
        log_info "Self-test is disabled in configuration"
        write_plugin_summary "selftest" "summary.txt" "Self-test disabled in configuration"
        return 0
    fi
    
    # Initialize history tracking
    if ! init_selftest_history; then
        log_error "Failed to initialize history tracking"
        write_plugin_summary "selftest" "summary.txt" "ERROR: Failed to initialize history tracking"
        return 1
    fi
    
    # Check and update status of any previously running tests
    update_running_tests
    
    # Get today's day of week (1=Monday, 7=Sunday)
    local today=$(date +%u)
    
    # Get configuration for both test types
    local short_days=$(get_config "SELFTEST_SHORT_DAYS" "1,2,3,4,5")
    local short_max=$(get_config "SELFTEST_SHORT_MAX_CONCURRENT" "2")
    local short_min_days=$(get_config "SELFTEST_SHORT_MIN_DAYS" "7")
    local long_days=$(get_config "SELFTEST_LONG_DAYS" "6,7")
    local long_max=$(get_config "SELFTEST_LONG_MAX_CONCURRENT" "1")
    local long_min_days=$(get_config "SELFTEST_LONG_MIN_DAYS" "90")
    
    # Log configuration summary
    log_debug "=== Selftest Configuration ==="
    log_debug "  Short tests: Max $short_max concurrent, every $short_min_days days, on days: $short_days"
    log_debug "  Long tests: Max $long_max concurrent, every $long_min_days days, on days: $long_days"
    log_debug "  Today is day $today (1=Mon, 7=Sun)"
    log_debug "=============================="
    
    # Check if today allows short tests
    local short_allowed=false
    if [[ ",$short_days," == *",$today,"* ]]; then
        short_allowed=true
        log_info "Today (day $today) allows short tests (max: $short_max drives)"
    else
        log_info "Today (day $today) does not allow short tests (allowed days: $short_days)"
    fi
    
    # Check if today allows long tests
    local long_allowed=false
    if [[ ",$long_days," == *",$today,"* ]]; then
        long_allowed=true
        log_info "Today (day $today) allows long tests (max: $long_max drives)"
    else
        log_info "Today (day $today) does not allow long tests (allowed days: $long_days)"
    fi
    
    # If no tests allowed today, skip drive discovery entirely
    if [ "$short_allowed" = false ] && [ "$long_allowed" = false ]; then
        log_info "No tests allowed today - skipping drive checks to avoid waking sleeping drives"
        write_plugin_summary "selftest" "summary.txt" "No tests scheduled for today (day $today)"
        return 0
    fi
    
    # Get list of drives WITHOUT waking them - use /sys/block instead of smartctl queries
    local smart_drives=$(ls /dev/sd? 2>/dev/null | sed 's|/dev/||' | xargs)
    local drive_count=$(echo "$smart_drives" | wc -w)
    
    if [ $drive_count -eq 0 ]; then
        log_error "No drives found"
        write_plugin_summary "selftest" "summary.txt" "ERROR: No drives found"
        return 1
    fi
    
    log_info "Found $drive_count drive(s): $smart_drives"
    
    # Get configuration for both test types
    local short_days=$(get_config "SELFTEST_SHORT_DAYS" "1,2,3,4,5")
    local short_max=$(get_config "SELFTEST_SHORT_MAX_CONCURRENT" "2")
    local short_min_days=$(get_config "SELFTEST_SHORT_MIN_DAYS" "7")
    local long_days=$(get_config "SELFTEST_LONG_DAYS" "6,7")
    local long_max=$(get_config "SELFTEST_LONG_MAX_CONCURRENT" "1")
    local long_min_days=$(get_config "SELFTEST_LONG_MIN_DAYS" "90")
    
    # Log configuration summary
    log_debug "=== Selftest Configuration ==="
    log_debug "  Short tests: Max $short_max concurrent, every $short_min_days days, on days: $short_days"
    log_debug "  Long tests: Max $long_max concurrent, every $long_min_days days, on days: $long_days"
    log_debug "  Today is day $today (1=Mon, 7=Sun)"
    log_debug "=============================="
    
    # Check if today allows short tests
    local short_allowed=false
    if [[ ",$short_days," == *",$today,"* ]]; then
        short_allowed=true
        log_info "Today (day $today) allows short tests (max: $short_max drives)"
    else
        log_info "Today (day $today) does not allow short tests (allowed days: $short_days)"
    fi
    
    # Check if today allows long tests
    local long_allowed=false
    if [[ ",$long_days," == *",$today,"* ]]; then
        long_allowed=true
        log_info "Today (day $today) allows long tests (max: $long_max drives)"
    else
        log_info "Today (day $today) does not allow long tests (allowed days: $long_days)"
    fi
    
    # Track which drives get tests scheduled
    declare -A scheduled_drives  # Associative array to track drives with tests today
    local short_count=0
    local long_count=0
    local short_tests=""
    local long_tests=""
    
    # Check how many tests are currently running
    local running_short=$(count_running_tests "short")
    local running_long=$(count_running_tests "long")
    
    log_debug "Currently running: $running_short short test(s), $running_long long test(s)"
    
    # Schedule long tests if allowed
    if [ "$long_allowed" = true ] && [ "$long_max" -gt 0 ]; then
        # Calculate how many more we can start (max - running)
        local available_long=$((long_max - running_long))

        if [ $running_long -ge $long_max ]; then
            log_info "Cannot schedule long tests: $running_long test(s) already running (max: $long_max)"
            log_debug "Global concurrent limit reached for long tests. No new long tests will be scheduled."
        else
            log_info "Scheduling long tests (can start $available_long, $running_long already running)..."
            # Convert space-separated drives to array for priority sorting
            local drives_array=($smart_drives)
            # Get drives sorted by priority (oldest/never-tested first)
            local prioritized_drives=$(get_drives_by_priority "long" "${drives_array[@]}")
            # Debug: Show status for all drives
            log_debug "=== Long Test Status for All Drives ==="
            for drive in $prioritized_drives; do
                local serial=$(get_drive_serial "$drive")
                if [ -z "$serial" ]; then
                    log_debug "  /dev/$drive: No serial number found"
                    continue
                fi
                # Check if already scheduled short test today
                if [ "${scheduled_drives[$serial]:-}" ]; then
                    log_debug "  /dev/$drive ($serial): Skip - Already has ${scheduled_drives[$serial]} test scheduled today"
                    continue
                fi
                local days=$(get_days_since_last_test "$serial" "long")
                if [ "$days" -eq -1 ]; then
                    log_debug "  /dev/$drive ($serial): NEEDS TESTING - Never tested"
                elif [ "$days" -ge "$long_min_days" ]; then
                    local overdue=$((days - long_min_days))
                    log_debug "  /dev/$drive ($serial): NEEDS TESTING - Last tested $days days ago (overdue by $overdue days)"
                else
                    local wait_days=$((long_min_days - days))
                    log_debug "  /dev/$drive ($serial): Skip - Last tested $days days ago (needs $wait_days more days)"
                fi
            done
            log_debug "========================================="
            # Schedule tests for highest priority drives
            for drive in $prioritized_drives; do
                # Stop if we've scheduled enough
                if [ $long_count -ge $available_long ]; then
                    log_debug "Reached available long test slots for today ($long_count started, $running_long running, max: $long_max)"
                    break
                fi

                # Register drive on-demand (this will wake it if sleeping)
                log_info "Drive $drive needs long test - registering (will wake if sleeping)"
                local serial=$(register_drive_on_demand "$drive")
                [ -z "$serial" ] && continue

                # Check if drive already scheduled today (mutual exclusion)
                if [ "${scheduled_drives[$serial]:-}" ]; then
                    log_debug "Drive $drive already has test scheduled today, skipping long test"
                    continue
                fi

                # Check if drive has ANY running test (long or short)
                if tail -n +2 "$TEST_HISTORY_FILE" | awk -F',' -v s="$serial" '$2==s && $5=="running" { found=1 } END { exit !found }'; then
                    log_debug "Drive $drive ($serial) already has a running test, skipping long test"
                    continue
                fi

                # Get days since last test
                local days=$(get_days_since_last_test "$serial" "long")

                # Check if drive was tested too recently
                if [ "$days" -ne -1 ] && [ "$days" -lt "$long_min_days" ]; then
                    log_debug "Drive $drive was tested $days days ago (minimum: $long_min_days days), skipping"
                    continue
                fi

                # Prepare logging message
                local days_msg="never tested"
                if [ "$days" -ne -1 ]; then
                    days_msg="$days days ago"
                fi

                # Schedule and execute the test
                schedule_test "$drive" "$serial" "long"

                # Execute the test
                if execute_test "$drive" "$serial" "long"; then
                    scheduled_drives[$serial]="long"
                    long_tests+="$drive "
                    ((long_count++))
                    log_info "Executed long test for /dev/$drive ($serial) - last test: $days_msg"
                else
                    log_warning "Failed to execute long test for /dev/$drive ($serial)"
                    # Still mark as scheduled to prevent retry in same run
                    scheduled_drives[$serial]="long"
                fi
            done
            if [ $long_count -eq 0 ]; then
                log_info "No long tests executed (all drives tested within last $long_min_days days or max reached)"
            else
                log_success "Executed $long_count long test(s): $long_tests"
            fi
        fi
    fi
    # Schedule short tests if allowed
    if [ "$short_allowed" = true ] && [ "$short_max" -gt 0 ]; then
        # Calculate how many more we can start (max - running)
        local available_short=$((short_max - running_short))

        if [ $running_short -ge $short_max ]; then
            log_info "Cannot schedule short tests: $running_short test(s) already running (max: $short_max)"
        else
            log_info "Scheduling short tests (can start $available_short, $running_short already running)..."
            # Convert space-separated drives to array for priority sorting
            local drives_array=($smart_drives)
            
            # Get drives sorted by priority (oldest/never-tested first)
            local prioritized_drives=$(get_drives_by_priority "short" "${drives_array[@]}")
            
            # Debug: Show status for all drives
            log_debug "=== Short Test Status for All Drives ==="
            for drive in $prioritized_drives; do
                local serial=$(get_drive_serial "$drive")
                if [ -z "$serial" ]; then
                    log_debug "  /dev/$drive: No serial number found"
                    continue
                fi
                
                local days=$(get_days_since_last_test "$serial" "short")
                if [ "$days" -eq -1 ]; then
                    log_debug "  /dev/$drive ($serial): NEEDS TESTING - Never tested"
                elif [ "$days" -ge "$short_min_days" ]; then
                    local overdue=$((days - short_min_days))
                    log_debug "  /dev/$drive ($serial): NEEDS TESTING - Last tested $days days ago (overdue by $overdue days)"
                else
                    local wait_days=$((short_min_days - days))
                    log_debug "  /dev/$drive ($serial): Skip - Last tested $days days ago (needs $wait_days more days)"
                fi
            done
            log_debug "========================================="
            
            # Schedule tests for highest priority drives
            for drive in $prioritized_drives; do
                # Stop if we've scheduled enough
                if [ $short_count -ge $available_short ]; then
                    log_debug "Reached available short test slots for today ($short_count started, $running_short running, max: $short_max)"
                    break
                fi
            
                # Register drive on-demand (this will wake it if sleeping)
                log_info "Drive $drive needs short test - registering (will wake if sleeping)"
                local serial=$(register_drive_on_demand "$drive")
                if [ -z "$serial" ]; then
                    log_debug "Drive $drive: No serial number found, skipping"
                    continue
                fi
                
                # Check if drive already scheduled today (mutual exclusion)
                if [ "${scheduled_drives[$serial]:-}" ]; then
                    log_debug "Drive $drive already has test scheduled today, skipping short test"
                    continue
                fi
                
                # Check if drive has ANY running test (long or short)
                if tail -n +2 "$TEST_HISTORY_FILE" | awk -F',' -v s="$serial" '$2==s && $5=="running" { found=1 } END { exit !found }'; then
                    log_debug "Drive $drive ($serial) already has a running test, skipping short test"
                    continue
                fi
                
                # Get days since last test
                local days=$(get_days_since_last_test "$serial" "short")
                
                # Check if drive was tested too recently
                if [ "$days" -ne -1 ] && [ "$days" -lt "$short_min_days" ]; then
                    log_debug "Drive $drive ($serial): Tested $days days ago, needs $((short_min_days - days)) more days"
                    continue
                fi
                
                # Prepare logging message
                local days_msg="never tested"
                if [ "$days" -ne -1 ]; then
                    days_msg="tested $days days ago"
                fi
                
                log_debug "Drive $drive ($serial): Eligible for short test ($days_msg)"
                
                # Schedule and execute the test
                schedule_test "$drive" "$serial" "short"
                
                # Execute the test
                if execute_test "$drive" "$serial" "short"; then
                    scheduled_drives[$serial]="short"
                    short_tests+="$drive "
                    ((short_count++))
                    log_info "Executed short test for /dev/$drive ($serial) - last test: $days_msg"
                else
                    log_warning "Failed to execute short test for /dev/$drive ($serial)"
                    # Still mark as scheduled to prevent retry in same run
                    scheduled_drives[$serial]="short"
                fi
            done
            
            if [ $short_count -eq 0 ]; then
                log_info "No short tests executed (all drives tested within last $short_min_days days or max reached)"
            else
                log_success "Executed $short_count short test(s): $short_tests"
            fi
        fi
    fi

    
    # Create summary
    local summary_dir=$(create_plugin_temp_dir "selftest")
    local total_executed=$((short_count + long_count))
    
    # Build human-readable summary
    local summary_text=""
    summary_text+="**SMART Self-Test Summary:**"$'\n'
    summary_text+="-----------------------------"$'\n'
    summary_text+="Today: $(date '+%A, %B %d, %Y') (Day $today)"$'\n'
    summary_text+="Total Drives: $drive_count"$'\n'
    summary_text+="Tests Executed: $total_executed"$'\n'
    summary_text+=""$'\n'
    
    if [ $short_count -gt 0 ]; then
        summary_text+="**Short Tests ($short_count):**"$'\n'
        for drive in $short_tests; do
            summary_text+="  - /dev/$drive"$'\n'
        done
        summary_text+=""$'\n'
    fi
    
    if [ $long_count -gt 0 ]; then
        summary_text+="**Long Tests ($long_count):**"$'\n'
        for drive in $long_tests; do
            summary_text+="  - /dev/$drive"$'\n'
        done
        summary_text+=""$'\n'
    fi
    
    if [ $total_executed -eq 0 ]; then
        summary_text+="No tests executed today."$'\n'
        if [ "$short_allowed" = false ] && [ "$long_allowed" = false ]; then
            summary_text+="Reason: Today is not configured for testing."$'\n'
            summary_text+="  Short test days: $short_days"$'\n'
            summary_text+="  Long test days: $long_days"$'\n'
        fi
    fi
    
    # Calculate plugin execution time
    local plugin_execution_time=$(calculate_plugin_execution_time)
    summary_text+=""$'\n'
    summary_text+="Execution Time: $plugin_execution_time"$'\n'
    summary_text+=""$'\n'
    summary_text+="Note: Tests run in the background on drives."$'\n'
    summary_text+="Results will be visible in the next SMART report."$'\n'
    
    # Create JSON summary
    local summary_json="$summary_dir/selftest-summary.json"
    cat > "$summary_json" <<EOF
{
    "plugin": "selftest",
    "command": "selftest",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "has_errors": false,
    "completed_successfully": true,
    "day_of_week": $today,
    "total_drives": $drive_count,
    "short_tests_executed": $short_count,
    "long_tests_executed": $long_count,
    "total_executed": $total_executed,
    "short_test_allowed": $short_allowed,
    "long_test_allowed": $long_allowed,
    "execution_time": "$plugin_execution_time"
}
EOF
    
    log_debug "Created JSON summary: $summary_json"
    
    # Write text summary
    echo "$summary_text" > "$summary_dir/selftest-summary-text.txt"
    log_debug "Saved text summary: $summary_dir/selftest-summary-text.txt"
    
    # Write to default summary.txt for backward compatibility
    write_plugin_summary "selftest" "summary.txt" "$summary_text"
    
    # Export for notification system (like SnapRAID Manager does)
    export SELFTEST_SUMMARY_TEXT="$summary_text"
    export SELFTEST_HAS_ERRORS="false"
    export SELFTEST_COMPLETED_SUCCESSFULLY="true"
    export SELFTEST_DRIVES_TESTED="$total_executed"
    export SELFTEST_PLUGIN_EXECUTION_TIME="$plugin_execution_time"
    
    log_debug "[SELFTEST] Exported to notification system"
    
    log_info "Self-test plugin completed (tested $total_executed drives)"
    return 0
}
