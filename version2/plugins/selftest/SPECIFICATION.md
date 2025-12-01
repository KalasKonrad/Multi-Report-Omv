# Self-Test Plugin Specification v2.0

## Overview
The selftest plugin manages SMART drive self-testing with intelligent rotation algorithms to distribute tests across time periods, minimizing system impact while ensuring comprehensive drive health monitoring.

## Core Capabilities

### 1. **Drive Discovery & Management**
- Automatically discover all SMART-capable drives (HDD, SSD, NVMe)
- Support for drive filtering:
  - By drive type (HDD/SSD/NVMe only)
  - By serial number (ignore list)
  - By SMART capability
- Handle multiple interface types (auto, sat, atacam, scsi, nvme)

### 2. **Test Types**
Two independent test schedules:

#### **Short Tests**
- Quick tests (1-2 minutes per drive)
- Default: Run on all drives daily or spread across week
- Minimal system impact
- Good for frequent health checks

#### **Long/Extended Tests**
- Comprehensive tests (hours per drive)
- Default: Spread across longer periods (Month/Quarter/Biannual/Annual)
- Maximum system impact, most thorough
- Recommended frequency based on array size:
  - Small arrays (<10 drives): Quarterly
  - Medium arrays (10-30 drives): Biannually  
  - Large arrays (30+ drives): Annually

### 3. **Test Distribution Modes**

#### **Mode 1: Spread Testing** (Most Common)
Distributes drive tests across a time period to minimize concurrent load:

**Features:**
- Configurable period: Week, Month, Quarter, Biannual, Annual
- Configurable drives per day
- Ensures each drive tested exactly once per period
- Accounts for active days only (e.g., Mon-Fri only)
- Smart distribution algorithm:
  - If fewer drives than active days: 1 drive per day until done
  - If more drives than active days: Evenly distribute across days
  - Extra drives distributed to early days in period

**Sorting Options:**
- **DriveID**: Tests in order (sda, sdb, sdc...) - predictable
- **Serial**: Tests sorted by serial number - pseudo-random to distribute physical location

**Period Calculation:**
- Week: Uses day of week (1-7) for positioning
- Month: Uses day of month (1-28) modulo for positioning  
- Quarter/Biannual/Annual: Uses day of year (1-365) for positioning

#### **Mode 2: All Drives**
- Tests all drives on specified days
- Ignores distribution settings
- Maximum system impact
- Use for small arrays or maintenance windows

#### **Mode 3: No Testing**
- Disables this test type entirely
- Useful to disable short or long tests independently

### 4. **Intelligent Scheduling**

#### **Day of Week Filtering**
- Specify which days tests can run: `1,2,3,4,5,6,7` (Mon-Sun)
- Examples:
  - `1,2,3,4,5` = Weekdays only
  - `6,7` = Weekends only
  - `1,2,3,4,5,6,7` = Every day

#### **Scrub/Resilver Awareness**
**SCRUB_Minutes_Remaining Configuration:**
- `0` = No SMART tests during any scrub/resilver (safest)
- `1-9999` = Run SHORT test instead of LONG if scrub has > X minutes remaining
- Protects pool integrity operations from additional I/O load

**SCRUB_RESILVER_OVERRIDE:**
- When enabled, ignores scrub status completely
- **NOT RECOMMENDED** - can impact resilver performance

#### **Duplicate Test Prevention**
- Automatically removes drives from short test if already scheduled for long test same day
- Prevents redundant testing and wasted resources

### 5. **Execution Control**

#### **Delays & Timing**
- **Between Drives**: Configurable delay (seconds) before starting next test
  - Allows drives to spin up if idle
  - Prevents simultaneous test starts
  - Reduces power surge
  
- **Short Test Completion Delay**: 
  - Waits for short tests to complete before returning to main script
  - Default: 30 seconds (short tests typically 1-2 minutes)
  - Ensures test completion before proceeding with monitoring

#### **Demo Mode**
- Simulated drives for testing configuration
- No actual SMART commands executed
- Shows which drives would be tested
- Perfect for testing rotation algorithms

### 6. **Logging & Reporting**

#### **Log Files**
- One log file per day of month: `drive_test_01.txt` through `drive_test_31.txt`
- Automatic rotation (overwrites after 31 days)
- Located in: `$LOG_DIR/DS_Logs/`

#### **Output Formats**
- **JSON Summary**: Machine-readable data
  - Test results
  - Drive counts
  - Execution times
  - Error status
  
- **Text Summary**: Human-readable format
  - Clear test status
  - Drive lists with formatting
  - Execution metrics
  - Ready for email notifications

#### **Silent Mode**
- Suppress normal output
- Only show errors
- Useful for cron jobs

### 7. **Advanced Features**

#### **Interface Fallback**
Automatically tries multiple interface types if default fails:
```
auto → sat → atacam → scsi → nvme
```

#### **NVMe-Only Mode**
- Test only NVMe drives
- Useful when HDD/SSD testing handled by other tools
- Common in mixed environments

#### **Configuration Priority**
1. External config file (`multi_report_omv_config.txt`)
2. Plugin configuration
3. Script defaults

## Configuration Schema

### Short Test Settings
```bash
SELFTEST_SHORT_ENABLED=true           # Enable short tests
SELFTEST_SHORT_MODE=2                 # 1=Spread, 2=All, 3=None
SELFTEST_SHORT_TYPE="short"           # Test type
SELFTEST_SHORT_DELAY=1                # Seconds between drive starts
SELFTEST_SHORT_ORDER="DriveID"        # Sort: "DriveID" or "Serial"
SELFTEST_SHORT_DRIVES_PER_DAY=1       # For Mode 1
SELFTEST_SHORT_PERIOD="Week"          # Week/Month/Quarter/Biannual/Annual
SELFTEST_SHORT_DAYS="1,2,3,4,5,6,7"  # Days of week to run
SELFTEST_SHORT_COMPLETION_DELAY=30    # Wait time for tests to complete
```

### Long Test Settings
```bash
SELFTEST_LONG_ENABLED=true            # Enable long tests
SELFTEST_LONG_MODE=1                  # 1=Spread, 2=All, 3=None
SELFTEST_LONG_TYPE="long"             # Test type
SELFTEST_LONG_DELAY=1                 # Seconds between drive starts
SELFTEST_LONG_ORDER="Serial"          # Sort: "DriveID" or "Serial"
SELFTEST_LONG_DRIVES_PER_DAY=1        # For Mode 1
SELFTEST_LONG_PERIOD="Quarter"        # Week/Month/Quarter/Biannual/Annual
SELFTEST_LONG_DAYS="1,2,3,4,5,6,7"   # Days of week to run
```

### Global Settings
```bash
SELFTEST_IGNORE_DRIVES=""             # Comma-separated serial numbers
SELFTEST_NVME_ONLY=false              # Test only NVMe drives
SELFTEST_SCRUB_MINUTES=0              # 0=disable during scrub, >0=short if scrub>X min
SELFTEST_SCRUB_OVERRIDE=false         # Override scrub detection
SELFTEST_INTERFACE_OPTIONS="auto,sat,atacam,scsi,nvme"  # Interface fallback order
```

## Data Output Specification

### JSON Summary Structure
```json
{
    "plugin": "selftest",
    "command": "selftest",
    "timestamp": "2025-10-19T12:34:56Z",
    "has_errors": false,
    "completed_successfully": true,
    
    "short_tests": {
        "enabled": true,
        "mode": 2,
        "mode_description": "All Drives",
        "period": "Week",
        "active_days": "Mon, Tue, Wed, Thu, Fri, Sat, Sun",
        "today_is_active": true,
        "drives_tested": ["sda", "sdb", "sdc"],
        "drives_skipped": [],
        "test_failures": []
    },
    
    "long_tests": {
        "enabled": true,
        "mode": 1,
        "mode_description": "Spread across Quarter",
        "period": "Quarter",
        "drives_per_day": 1,
        "active_days": "Mon, Tue, Wed, Thu, Fri, Sat, Sun",
        "today_is_active": true,
        "today_position": 5,
        "drives_tested": ["sdd"],
        "drives_skipped": [],
        "test_failures": []
    },
    
    "drive_summary": {
        "total_drives": 8,
        "short_tested": 3,
        "long_tested": 1,
        "duplicates_removed": 0,
        "scrub_in_progress": false,
        "nvme_count": 0,
        "hdd_count": 6,
        "ssd_count": 2
    },
    
    "execution_time": "2s"
}
```

### Text Summary Format
```
**SMART Self-Test Summary:**
-----------------------------
Date: 2025-10-19 12:34:56
Total Drives: 8 (6 HDD, 2 SSD, 0 NVMe)

**Short Tests:**
  Mode: All Drives
  Period: Week
  Active Days: Mon, Tue, Wed, Thu, Fri, Sat, Sun
  Status: ✓ Tests started on 3 drives
  Drives: sda, sdb, sdc

**Long Tests:**
  Mode: Spread across Quarter (1 drive per day)
  Period: Quarter (90 days)
  Active Days: Mon, Tue, Wed, Thu, Fri, Sat, Sun
  Today: Day 5 of cycle
  Status: ✓ Tests started on 1 drive
  Drives: sdd

**Notes:**
  - No scrub/resilver in progress
  - 0 duplicate tests removed
  - Execution Time: 2s
```

## Implementation Requirements

### Phase 1: Core Functionality
- [x] Drive discovery (get_smart_drives)
- [ ] Configuration loading
- [ ] Basic test execution (smartctl interface)
- [ ] Simple rotation algorithm (Mode 1 for Week period)
- [ ] JSON + Text summary generation

### Phase 2: Advanced Features
- [ ] All test modes (1, 2, 3)
- [ ] All period types (Week, Month, Quarter, Biannual, Annual)
- [ ] Sorting options (DriveID, Serial)
- [ ] Scrub detection and handling
- [ ] Duplicate test removal
- [ ] Interface fallback logic

### Phase 3: Polish
- [ ] Demo mode
- [ ] Enhanced logging
- [ ] Error recovery
- [ ] Performance optimization
- [ ] Comprehensive testing

## Testing Scenarios

### Scenario 1: Small Home Server
- 4 drives total
- Short: Mode 2 (all drives daily)
- Long: Mode 1, Quarter period, 1 drive/day, Mon-Fri only
- Expected: Each drive long-tested once every ~90 days

### Scenario 2: Medium NAS
- 12 drives total
- Short: Mode 1, Week period, 2 drives/day, Mon-Sun
- Long: Mode 1, Biannual period, 1 drive/day, Mon-Fri only
- Expected: Short tests cycle weekly, long tests every 6 months

### Scenario 3: Large Array
- 40 drives total
- Short: Mode 1, Month period, 2 drives/day, Mon-Fri only
- Long: Mode 1, Annual period, 1 drive/day, Mon-Fri only
- Expected: Minimal daily impact, comprehensive annual coverage

### Scenario 4: Mixed Environment
- 6 HDD + 2 NVMe
- NVMe tested separately by vendor tools
- Use SELFTEST_NVME_ONLY=false for HDD only
- Or run twice: once for each type

## Integration Points

### With Multi-Report-OMV Core
- Uses `get_smart_drives()` from utils
- Uses `get_config()` for settings
- Uses logging system (log_info, log_error, log_debug)
- Exports variables for notification system
- Respects KEEP_TEMP_FILES for debugging

### With Notification System
Exports these variables:
- `SELFTEST_SUMMARY_TEXT`: Full formatted summary
- `SELFTEST_HAS_ERRORS`: Boolean error status
- `SELFTEST_COMPLETED_SUCCESSFULLY`: Boolean success status  
- `SELFTEST_SHORT_TESTED`: Count of short tests
- `SELFTEST_LONG_TESTED`: Count of long tests
- `SELFTEST_PLUGIN_EXECUTION_TIME`: Formatted time

### With Other Plugins
- Can be disabled via config
- Runs before smart-report (test results visible in next report)
- Aware of system load (scrub detection)

## Migration from v1.x

### Configuration Mapping
```
v1.x                              → v2.0
-------------------------------------→----------------------------------------
Short_Test_Mode                   → SELFTEST_SHORT_MODE
Short_Drives_to_Test_Per_Day      → SELFTEST_SHORT_DRIVES_PER_DAY
Short_Drives_Test_Period          → SELFTEST_SHORT_PERIOD
Short_Drives_Tested_Days_of_Week  → SELFTEST_SHORT_DAYS
Long_Test_Mode                    → SELFTEST_LONG_MODE
Long_Drives_to_Test_Per_Day       → SELFTEST_LONG_DRIVES_PER_DAY
Long_Drives_Test_Period           → SELFTEST_LONG_PERIOD
Long_Drives_Tested_Days_of_Week   → SELFTEST_LONG_DAYS
Ignore_Drives_List                → SELFTEST_IGNORE_DRIVES
Test_ONLY_NVMe_Drives             → SELFTEST_NVME_ONLY
```

### Behavioral Changes
- v1.x: Standalone script
- v2.0: Plugin integrated with multi-report system
- v1.x: Uses own logging
- v2.0: Uses centralized logging
- v1.x: Manual configuration
- v2.0: Config system with backup/restore

## Success Criteria
1. Correctly distributes tests across all period types
2. Respects day-of-week restrictions
3. Prevents duplicate testing
4. Handles scrub/resilver gracefully
5. Generates accurate JSON and text summaries
6. Integrates seamlessly with notification system
7. Provides clear status in logs
8. Demo mode accurately simulates real behavior

## Future Enhancements
- [ ] Test result monitoring (detect failed tests)
- [ ] Smart rescheduling (retest failed drives sooner)
- [ ] Temperature-aware scheduling (avoid hot days)
- [ ] Load-aware scheduling (check system load)
- [ ] Historical tracking (last test date per drive)
- [ ] Email alerts for overdue tests
- [ ] Web UI for configuration
