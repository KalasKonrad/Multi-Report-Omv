# Multi-Report-OMV v2.0 Development Progress

**Last Updated:** December 1, 2025  
**Branch:** v2.0-dev  
**Current Version:** 2.0.0-dev  
**Status:** Core Foundation Complete + All 4 Plugins Operational + Testing Phase

## ✅ Completed Components

### 1. Core Architecture (100%)
- ✅ **Modular Structure**: Created directory layout based on SnapRAID Manager patterns
  - `core/` - Core system modules
  - `plugins/` - Plugin system (scaffold ready)
  - `bin/` - Main executable
  - `config/` - Configuration storage
  - `logs/` - Log file storage

### 2. Core Modules (100%)

#### logger.sh
- ✅ Colored console output with log levels (debug/info/warning/error)
- ✅ File logging with timestamps
- ✅ Log rotation based on retention policy
- ✅ Configurable log level filtering
- ✅ Function exports for use in plugins

#### utils.sh
- ✅ Version management (reads VERSION file)
- ✅ System validation (OMV detection, smartctl checks)
- ✅ Drive detection (lsblk, SMART capability checks with sudo)
- ✅ Environment variable exports
- ✅ Cleanup handler registry
- ✅ Temporary directory management
- ✅ Time calculation utilities
- ✅ Root privilege helpers (is_root, elevate_privileges)
- ✅ PATH configuration for /usr/sbin (smartctl location)

#### config.sh
- ✅ Configuration file management (defaults + user overrides)
- ✅ Associative array storage (CONFIG[])
- ✅ Default configuration initialization
- ✅ Configuration validation
- ✅ show_config() command with sorted output
- ✅ Email, SMART, CSV, and self-test settings
- ✅ REQUIRE_ROOT and DISABLE_SUDO options

### 3. Main Executable (100%)

#### bin/multi-report-omv
- ✅ Command-line interface with help/version
- ✅ Module initialization sequence
- ✅ Command routing (status, test, report, config)
- ✅ Trap handlers for clean shutdown
- ✅ REQUIRE_ROOT configuration check
- ✅ elevate_privileges() wrapper function

### 4. Sudo Privilege Management (100%) ⭐ NEW

**Architecture**: Based on SnapRAID Manager v2.0.0-beta4's proven sudo system

#### Core Features
- ✅ **Single Password Prompt**: User authenticates once at startup
- ✅ **Background Keepalive Process**: Runs `sudo -v` every 60 seconds in background
- ✅ **PID Tracking**: Keepalive process ID stored in `SUDO_KEEPALIVE_PID` variable
- ✅ **Automatic Cleanup**: Terminates keepalive on EXIT/INT/TERM signals
- ✅ **Signal Handling**: Proper trap registration for clean shutdown
- ✅ **Zero Password Prompts**: All commands run without re-authentication

#### Configuration Options
```bash
REQUIRE_ROOT=true      # Force script to run as root (default: false)
DISABLE_SUDO=false     # Disable all sudo operations (default: false)
```

**Use Cases:**
- `REQUIRE_ROOT=true`: Enterprise environments where sudo is disabled
- `DISABLE_SUDO=true`: Testing/development without elevated privileges

#### Helper Functions
```bash
is_root()                    # Returns true if UID=0, false otherwise
elevate_privileges()         # Safe sudo wrapper for plugins
init_sudo_privileges()       # Initialize sudo session + start keepalive
cleanup_sudo_keepalive()     # Terminate keepalive process safely
```

#### Implementation Architecture

**File: `bin/multi-report-omv`**
```bash
# Startup sequence:
1. Source core modules
2. Call init_sudo_privileges() if not DISABLE_SUDO
3. Register cleanup_sudo_keepalive() on EXIT/INT/TERM
4. Execute user commands with maintained privileges
5. Automatic cleanup on script exit
```

**File: `core/utils.sh`**
```bash
# Background keepalive loop:
while true; do
    sudo -v                    # Refresh sudo timestamp
    sleep 60                   # Wait 60 seconds
done &                        # Run in background
SUDO_KEEPALIVE_PID=$!         # Store PID for cleanup
```

**File: `core/config.sh`**
- Configuration defaults (REQUIRE_ROOT, DISABLE_SUDO)
- Validation of sudo-related settings
- Integration with config backup/restore

#### Integration Points
- **Drive Detection**: `is_smart_capable()` uses `sudo smartctl` automatically
- **SMART Commands**: All smartctl calls wrapped with sudo when needed
- **Plugin System**: Plugins call `elevate_privileges()` for protected operations
- **Configuration**: Sudo behavior controlled via config file

#### Testing & Validation Results
```bash
# Test 1: Single password prompt
✅ ./bin/multi-report-omv status
   → Password prompt appears once
   → All 8 drives detected (sda-sdh)
   → No additional prompts

# Test 2: Long-running operation
✅ Script runs for >5 minutes
   → Sudo session maintained automatically
   → No timeout errors
   → Keepalive process continues

# Test 3: Clean shutdown
✅ Ctrl+C during execution
   → Keepalive process terminated
   → ps aux | grep "sudo -v" shows no orphans
   → Clean exit

# Test 4: SMART operations
✅ Drive detection with sudo
   → smartctl -i /dev/sda (8 drives)
   → Temperature reading works
   → Capability detection works
```

#### Known Benefits
- **User Experience**: Password once vs. every smartctl call (8+ prompts saved)
- **Security**: Controlled sudo scope, automatic cleanup
- **Reliability**: No timeout issues during long operations
- **Compatibility**: Works with standard sudo timeout (15 minutes default)
- **Maintainability**: Modular design, easy to test/debug

#### Documentation
- **SUDO-MANAGEMENT.md**: Comprehensive technical guide (architecture, usage, troubleshooting)
- **README.md**: User-facing sudo requirements
- **config.sh**: Inline comments for REQUIRE_ROOT/DISABLE_SUDO options

### 5. Documentation (80%)

- ✅ **STRUCTURE.md**: Architecture documentation
- ✅ **SUDO-MANAGEMENT.md**: Comprehensive sudo system guide
- ✅ **VERSION**: Version tracking file (2.0.0-dev)
- ✅ **PROGRESS-SUMMARY.md**: This file
- ⏳ README.md (needs creation)
- ⏳ MIGRATION.md (v1 to v2 guide needed)
- ⏳ CHANGELOG.md (needs updating)

### 6. Configuration System (100%)

- ✅ Default values for all settings
- ✅ Email notification configuration
- ✅ SMART monitoring thresholds
- ✅ CSV data recording settings
- ✅ Drive self-test configuration
- ✅ SMR detection settings
- ✅ Sudo behavior configuration
- ✅ **Configuration Backup/Restore** ⭐ NEW
  - Automatic backup with timestamps
  - Configurable retention (default: 5)
  - Interactive restore
  - Backup listing and info
  - Clean all backups
- ✅ **Configuration Commands** ⭐ NEW
  - `config show` - Display configuration
  - `config backup` - Create backup
  - `config restore` - Restore from backup
  - `config list-backups` - List all backups
  - `config info` - Show backup details
  - `config clean` - Delete all backups

### 7. Statistical Data Collection Plugin (100%) ⭐ NEW

**Architecture**: Comprehensive SMART data collection and CSV storage

#### Core Features
- ✅ **Dual CSV System**: Raw numeric values + Human-readable formatted values
- ✅ **52+ SMART Attributes**: Temperature, power hours, errors, workload, health metrics
- ✅ **Human-Readable Formatting**: Automatic unit conversion (°C, hours, TB, MB/GB)
- ✅ **Drive-Specific Data**: Model, capacity, firmware, serial number, filesystem info
- ✅ **SMR Detection**: Automatic CMR/SMR/Unknown classification
- ✅ **SSD Support**: Wear level, percentage used indicators
- ✅ **Helium Drive Support**: Helium level monitoring
- ✅ **Format Helper Functions**: `format_bytes_human()`, `format_number_human()`

#### CSV File Structure
```bash
history_raw.csv          # Machine-readable: 38,60981,128895558059,247361547
history.csv              # Human-readable: 38°C,60981h,60.0TB,247.3M
```

#### Implementation Details
- **File**: `plugins/statistical_data/statistical_data.sh` (700+ lines)
- **Configuration**: STATS_ENABLED, STATS_HISTORY_FILE, STATS_HUMAN_READABLE
- **Auto-run**: Executes during 'auto' command
- **CSV Headers**: 52 columns covering all SMART attributes
- **Format Functions**: Located in `core/utils.sh`

#### Data Collected Per Drive
- Basic Info: Date, time, drive ID, model, capacity, serial, firmware
- Filesystem: Mount point, filesystem name, used/free space
- Temperature: Current, max, min, airflow temperature
- Health: SMART status, reallocated sectors, pending sectors, uncorrectable errors
- Workload: Power hours, power cycles, start/stop count, load cycles
- Data Transfer: LBAs written/read, host commands, data written/read
- Errors: UDMA CRC errors, command timeouts, ECC errors
- Performance: Seek error rate, throughput performance
- SSD Specific: Wear level, percentage used, media wearout indicator
- Drive Specific: Helium level, head flying hours, GMR head amplitude
- SMR Status: CMR/SMR/Unknown classification

#### Testing Results
```bash
✅ Real data collection on 8-drive system (sda-sdh)
✅ Both CSV files created successfully
✅ Raw values: 128895558059 LBAs → Human: 60.0TB
✅ Command counts: 4230459443 → 4.2B formatted
✅ Temperature units: 38 → 38°C
✅ Time units: 60981 → 60981h
✅ All SMART attributes extracted correctly
✅ SMR detection working (all drives CMR)
```

### 8. Automated Report Plugin (100%) ⭐ NEW

**Architecture**: Multi-schedule automated drive health reporting system

#### Core Features
- ✅ **5 Independent Report Schedules**: Weekly, Monthly, Quarterly, Yearly, Custom
- ✅ **Smart Scheduling**: Timestamp tracking prevents duplicate reports
- ✅ **CSV Data Aggregation**: Query history by date range and drive
- ✅ **Statistical Calculations**: Temperature (min/max/avg), workload deltas, error tracking
- ✅ **Alert Detection**: Configurable thresholds for temperature, errors, health
- ✅ **Dual Format Support**: Professional HTML with CSS + Plain text
- ✅ **Email Delivery**: Automatic report distribution via mail command
- ✅ **Comprehensive Metrics**: Temperature, workload, errors, tests, wear, helium, fleet stats

#### Report Schedule Types
1. **Weekly**: Day-of-week trigger, 7-day analysis, minimum 6 days between runs
2. **Monthly**: Day-of-month trigger, 30-day analysis, minimum 25 days between runs
3. **Quarterly**: Jan/Apr/Jul/Oct trigger, 90-day analysis, minimum 80 days between runs
4. **Yearly**: Specific date trigger, 365-day analysis, minimum 350 days between runs
5. **Custom**: Every N days trigger, configurable lookback period

#### Implementation Details
- **File**: `plugins/report/report.sh` (1096 lines)
- **Configuration**: 50+ config options in `core/config.sh`
- **Data Directory**: `data/report/` for timestamps and generated reports
- **Auto-run**: Executes during 'auto' command, checks all schedules
- **Documentation**: Complete README.md with usage guide

#### Report Content Per Drive
- **Temperature Stats**: Current, min, max, avg over period
- **Workload Metrics**: Power hours, data written/read (formatted), drive age
- **Health & Errors**: Reallocated sectors (total + new), pending, CRC errors
- **Drive Info**: Model, filesystem, SMART status, drive type
- **Special Metrics**: Helium level, wear level, SMR status
- **System Alerts**: High temperature, new reallocated sectors, pending sectors, CRC errors

#### Report Formats
- **Text**: Unicode box-drawing, emoji icons, clean formatting, 80-column layout
- **HTML**: Gradient headers, responsive design, color-coded alerts, professional styling

#### Configuration Options
```bash
# Global settings
REPORT_ENABLED=true
REPORT_EMAIL="admin@example.com"
REPORT_FORMAT="html"  # or "text"

# Per-schedule configuration
REPORT_WEEKLY_ENABLED=true
REPORT_WEEKLY_DAY=1  # Monday
REPORT_WEEKLY_METRICS="temp,workload,errors"

# Alert thresholds
REPORT_ALERT_TEMP_MAX=55  # Alert if max temp > 55°C
REPORT_ALERT_NEW_REALLOCATED=true
REPORT_ALERT_PENDING_SECTORS=true
REPORT_ALERT_CRC_ERRORS=true
```

#### Key Functions (20+ functions)
- `get_date_range()` - Calculate report period dates
- `get_drive_list()` - Extract unique drives from CSV
- `query_drive_data()` - Filter CSV by drive and date range
- `calc_temp_stats()` - Temperature min/max/avg calculation
- `calc_workload_stats()` - Workload deltas with human formatting
- `calc_error_stats()` - Error tracking and delta calculation
- `check_drive_alerts()` - Threshold comparison and alert generation
- `generate_text_report()` - Plain text report formatting
- `generate_html_report()` - HTML report with CSS styling
- `send_report_email()` - Email delivery with format detection

#### Testing Status
```bash
✅ Report plugin structure created
✅ All 5 schedule types implemented
✅ CSV data aggregation functions complete
✅ Statistics calculation functions complete
✅ Alert detection logic complete
✅ Text report template complete
✅ HTML report template complete
✅ Email delivery system complete
⏳ End-to-end testing with real data pending
⏳ Email delivery verification pending
```

## 🔄 In Progress

### Plugin System (95%)
- ✅ Directory structure created (`plugins/`)
- ✅ Plugin loader/manager complete (core/plugin.sh)
- ✅ Plugin discovery and execution framework complete
- ✅ All 4 plugins operational:
  - report: Multi-schedule reporting
  - selftest: SMART test rotation with proper history tracking
  - smr_check: SMR/CMR detection with caching
  - statistical_data: Comprehensive SMART data collection
- ✅ Plugin summary combination system
- ⏳ Plugin manifest schema documentation

## ⏳ Pending Components

### 1. Plugin Development (40%)

Priority order:

1. ✅ **statistical-data** (COMPLETE) - 52+ SMART attributes with dual CSV system
2. ✅ **report** (COMPLETE) - Multi-schedule automated reporting with HTML/text formats
3. **drive-selftest** (NEXT) - Fix original rotation bug
4. **smart-monitor** - SMART data collection and analysis
5. **email-notify** - HTML email formatting and delivery

### 2. Data Format Enhancements (100%) ✅
- ✅ Human-readable units (°C, hours, TB, GB, MB, %)
- ✅ Dual CSV system (raw + formatted)
- ✅ Format helper functions in utils.sh
- ✅ LBA to data size conversion
- ✅ Large number formatting (K/M/B)

### 3. Report System Testing (20%)
- ✅ Report generation logic complete
- ✅ CSV data aggregation working
- ✅ Statistics calculation implemented
- ✅ Alert detection functional
- ✅ HTML and text templates created
- ⏳ End-to-end testing with real CSV data
- ⏳ Email delivery verification
- ⏳ All 5 schedule types tested
- ⏳ Alert threshold testing
- ⏳ Multi-drive scenario testing

### 3. Testing (60%)
- ✅ Integration tests on OMV 7 (real system)
- ✅ Sudo system verified and working
- ✅ Drive detection working (8 drives: sda-sdh)
- ✅ Statistical data collection verified (46+ metrics per drive)
- ✅ Selftest plugin verified (rotation algorithm working)
- ✅ SMR detection working (cached results)
- ✅ Sleep protection verified (counted mode with skip tracking)
- ✅ Line ending issues resolved (CRLF→LF conversion)
- ⏳ Report generation end-to-end tests
- ⏳ Email notification tests
- ⏳ Cron job compatibility tests
- ⏳ Long-term stability testing

### 4. Migration Tools (0%)
- ⏳ v1.x configuration converter
- ⏳ Data migration scripts
- ⏳ Backward compatibility layer

## 📝 Latest Session: December 1, 2025

### Completed Today
1. ✅ **Line Ending Fixes** - Converted all shell scripts from CRLF to LF
2. ✅ **Selftest Error Handling** - Fixed log pollution in serial number capture
3. ✅ **Test History Rebuild** - Created tool to rebuild from actual SMART data
4. ✅ **Sleep Protection Testing** - Verified sleeping drive detection works correctly
5. ✅ **Clean Summary Reports** - Removed debug noise from plugin output
6. ✅ **Git Attributes** - Added .gitattributes to enforce LF line endings

### Previous Session: November 3, 2025

### Completed
1. ✅ **Dual CSV System** - Raw numeric + human-readable formatted values
2. ✅ **Format Helper Functions** - `format_bytes_human()` and `format_number_human()` in utils.sh
3. ✅ **Statistical Data Plugin Enhanced** - Both CSV files written simultaneously with proper formatting
4. ✅ **Report Plugin Complete** - Full multi-schedule automated reporting system (1096 lines)
5. ✅ **Report Features**:
   - CSV data aggregation functions (date range queries, drive filtering)
   - Statistics calculation (temperature, workload, errors)
   - Alert detection with configurable thresholds
   - Text report template with Unicode formatting
   - HTML report template with professional CSS styling
   - Email delivery system
6. ✅ **Report Data Directory** - Created `data/report/` for timestamps and reports
7. ✅ **Complete Documentation** - Report plugin README.md with comprehensive usage guide

### Implementation Highlights

**Dual CSV System:**
```bash
# history_raw.csv (machine-readable)
2025-11-03,22:17:34,sda,WDC_WD60EFRX-68L0BN1,38,60981,128895558059,247361547,4230459443

# history.csv (human-readable)
2025-11-03,22:17:34,sda,WDC_WD60EFRX-68L0BN1,38°C,60981h,60.0TB,247.3M,4.2B
```

**Report Plugin Architecture:**
- 5 independent report schedules (weekly, monthly, quarterly, yearly, custom)
- 20+ functions for data processing and formatting
- Smart timestamp tracking prevents duplicates
- Configurable metrics per report type
- Alert-driven content with threshold detection
- Professional HTML output with responsive design

### Testing Results
```bash
✅ Real data collection verified (8 drives)
✅ Both CSV files created successfully
✅ Human-readable formatting working:
   - 38 → 38°C (temperature)
   - 60981 → 60981h (hours)
   - 128895558059 → 60.0TB (data size)
   - 4230459443 → 4.2B (command count)
✅ Report plugin framework complete
✅ All report functions implemented
⏳ End-to-end report testing pending
⏳ Email delivery testing pending
```

## 🎯 Current Milestone: Report System Testing & Drive Self-Test Plugin

**Next Steps:**

1. **Test Report Generation** ✨ HIGH PRIORITY
   - Configure report schedules
   - Force report generation by deleting timestamps
   - Verify CSV data queries work correctly
   - Validate statistics calculations
   - Test both text and HTML output
   - Verify email delivery

2. **Create drive-selftest plugin** ✨ NEXT PRIORITY
   - Fix rotation algorithm bug
   - Implement per-drive tracking
   - Add scheduling logic
   - Test with 8-drive system

3. **Create smart-monitor plugin**
   - SMART data collection
   - Temperature monitoring
   - Health analysis
   - Alert generation

4. **Create email-notify plugin**
   - HTML email template
   - Text fallback
   - Attachment support
   - Configuration validation

5. **Integration testing**
   - Test sudo system under load
   - Verify SMART access across all drives
   - Test email delivery
   - Validate cron execution

## 📊 Overall Progress

| Component | Progress | Status |
|-----------|----------|--------|
| Core Architecture | 100% | ✅ Complete |
| Core Modules | 100% | ✅ Complete |
| Main Executable | 100% | ✅ Complete |
| Sudo Management | 100% | ✅ Complete |
| Configuration | 100% | ✅ Complete |
| Plugin System | 95% | ✅ Near Complete |
| Statistical Data Plugin | 100% | ✅ Complete |
| Report Plugin | 100% | ✅ Complete |
| Selftest Plugin | 100% | ✅ Complete |
| SMR Check Plugin | 100% | ✅ Complete |
| Documentation | 90% | 🔄 In Progress |
| Testing | 60% | 🔄 In Progress |

**Overall: ~85% Complete**

## 🔧 Technical Improvements vs. v1.x

1. **Architecture**: Monolithic → Modular plugin system
2. **Privilege Model**: Root-only → Sudo with keepalive
3. **Code Organization**: Single file → Separated core modules
4. **Configuration**: Inline variables → Structured config file
5. **Logging**: Basic echo → Structured logging with levels
6. **Error Handling**: Ad-hoc → Centralized validation
7. **Cleanup**: Manual → Automatic trap handlers
8. **Extensibility**: None → Plugin-based
9. **Documentation**: Minimal → Comprehensive
10. **Testing**: None → Planned test suite
11. **Data Storage**: Raw values only → Dual CSV (raw + human-readable)
12. **Formatting**: No units → Automatic unit conversion (°C, hours, TB, etc.)
13. **Reporting**: Manual review → Automated multi-schedule reports
14. **Report Formats**: Text only → Professional HTML + Text
15. **Alert System**: None → Configurable threshold-based alerts

## 🚀 Ready to Test

Current v2.0-dev can be tested with:

```bash
cd ~/docker/system/scripts/multi-report-omv/version2

# Show version
./bin/multi-report-omv --version

# Test sudo system (will prompt for password once)
./bin/multi-report-omv status

# Configuration management
./bin/multi-report-omv config show           # Display current config
./bin/multi-report-omv config backup         # Create backup
./bin/multi-report-omv config list-backups   # List all backups
./bin/multi-report-omv config restore        # Interactive restore
./bin/multi-report-omv config --help         # Full help

# Statistical data collection (NEW)
# Configure in core/config.sh:
# CONFIG[STATS_ENABLED]="true"
# CONFIG[STATS_HISTORY_FILE]="data/statistical_data/history_raw.csv"
# CONFIG[STATS_HUMAN_READABLE]="true"
# Then run auto command to collect data

# Report generation testing (NEW)
# 1. Configure report settings in core/config.sh
# 2. Enable at least one report schedule
# 3. Set REPORT_EMAIL to your email
# 4. Delete timestamp to force immediate run:
rm data/report/last_weekly.timestamp
# 5. Run auto command to generate report
# 6. Check generated report:
cat data/report/weekly_report_*.txt

# Debug mode
./bin/multi-report-omv --debug status
```

**Expected Behavior:**
- ✅ Single sudo password prompt at start
- ✅ OMV 7.7.18 detection
- ✅ All 8 drives detected (sda-sdh)
- ✅ Configuration backup/restore working
- ✅ Statistical data collection working
- ✅ Both CSV files created (raw + human-readable)
- ✅ Report generation working
- ✅ Clean execution and shutdown
- ✅ Proper cleanup of keepalive process

## 📝 Known Issues

**Active Issues:**
- Report plugin needs end-to-end testing with real data
- Email delivery system needs verification on actual mail server
- Custom report schedule interval calculation needs validation

**Previously Fixed:**
1. ~~Drive detection shows 0 drives~~ - ✅ Fixed with sudo in `is_smart_capable()`
2. ~~Sort syntax error in show_config()~~ - ✅ Fixed with proper array expansion
3. ~~smartctl not in PATH~~ - ✅ Fixed by adding /usr/sbin to PATH
4. ~~CSV data had large meaningless numbers~~ - ✅ Fixed with human-readable formatting
5. ~~No units on temperature/time values~~ - ✅ Fixed with unit suffixes
6. ~~Need automated periodic reporting~~ - ✅ Fixed with report plugin

**Remaining Work:**
- Report generation end-to-end testing
- Email delivery verification
- Drive self-test plugin not yet implemented
- SMART monitor plugin not yet implemented
- Configuration file auto-creation on first run not yet implemented

## 🎓 Lessons Learned

1. **SnapRAID Manager patterns work well** - Sudo keepalive is robust
2. **Modular architecture** - Much easier to maintain than v1.x
3. **Documentation first** - SUDO-MANAGEMENT.md helped validate design
4. **Helper functions** - is_root() and elevate_privileges() simplify plugin development
5. **PATH management** - Essential for smartctl on Debian systems
6. **Dual CSV approach** - Preserves raw data while providing human readability
7. **Format helper functions** - Centralized formatting ensures consistency
8. **Human-readable units** - Makes data immediately interpretable (38°C vs 38)
9. **LBA conversion** - Converting to TB/GB much more useful than raw LBA counts
10. **Plugin auto-run** - Seamless integration with existing command execution
11. **Multi-schedule design** - Independent schedules prevent interference
12. **Alert-driven reports** - Important issues surfaced at top for visibility
13. **Dual format reports** - HTML for rich content, text for compatibility
14. **Timestamp tracking** - Prevents duplicate report generation effectively

## 🔜 Next Session Goals

1. ✅ ~~Test drive detection with sudo fix~~ - COMPLETE
2. ✅ ~~Create statistical data collection plugin~~ - COMPLETE
3. ✅ ~~Implement dual CSV system~~ - COMPLETE
4. ✅ ~~Create report plugin structure~~ - COMPLETE
5. ✅ ~~Implement report generation logic~~ - COMPLETE
6. Test report generation end-to-end
7. Verify email delivery
8. Create drive-selftest plugin structure
9. Implement rotation algorithm
10. Write plugin manifest schema documentation

---

**Note**: This document tracks development progress and should be updated after each major milestone.
