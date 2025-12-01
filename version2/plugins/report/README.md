# Report Plugin - Automated Drive Health Reports

## Overview

The Report Plugin automatically generates and emails comprehensive drive health summaries on configurable schedules. It analyzes historical SMART data collected by the statistical_data plugin and provides insights into temperature trends, workload patterns, errors, and overall drive health.

## Features

- **5 Independent Report Schedules**: Weekly, Monthly, Quarterly, Yearly, and Custom
- **Configurable Metrics**: Select which data points to include per report type
- **Alert Detection**: Automatically highlights concerning trends and issues
- **Dual Format Support**: Text and HTML email formats
- **Smart Scheduling**: Prevents duplicate reports with timestamp tracking
- **Comprehensive Statistics**: Temperature, workload, errors, wear levels, and more

## Configuration

All configuration is in `version2/core/config.sh`:

### Global Settings

```bash
CONFIG[REPORT_ENABLED]="true"                    # Enable/disable entire plugin
CONFIG[REPORT_EMAIL]="admin@example.com"         # Destination email address
CONFIG[REPORT_FORMAT]="html"                     # "text" or "html"
```

### Weekly Report

```bash
CONFIG[REPORT_WEEKLY_ENABLED]="true"
CONFIG[REPORT_WEEKLY_DAY]="1"                    # Day of week (1=Monday, 7=Sunday)
CONFIG[REPORT_WEEKLY_METRICS]="temp,workload,errors"
```

### Monthly Report

```bash
CONFIG[REPORT_MONTHLY_ENABLED]="true"
CONFIG[REPORT_MONTHLY_DAY]="1"                   # Day of month (1-28)
CONFIG[REPORT_MONTHLY_METRICS]="temp,workload,errors,tests"
```

### Quarterly Report

```bash
CONFIG[REPORT_QUARTERLY_ENABLED]="true"
CONFIG[REPORT_QUARTERLY_DAY]="1"                 # Day of month in Jan/Apr/Jul/Oct
CONFIG[REPORT_QUARTERLY_METRICS]="temp,workload,errors,tests,wear,helium"
```

### Yearly Report

```bash
CONFIG[REPORT_YEARLY_ENABLED]="true"
CONFIG[REPORT_YEARLY_MONTH]="1"                  # Month (1-12)
CONFIG[REPORT_YEARLY_DAY]="1"                    # Day of month
CONFIG[REPORT_YEARLY_METRICS]="temp,workload,errors,tests,wear,helium,fleet_stats"
```

### Custom Report

```bash
CONFIG[REPORT_CUSTOM_ENABLED]="false"
CONFIG[REPORT_CUSTOM_NAME]="Biweekly Summary"
CONFIG[REPORT_CUSTOM_SCHEDULE]="14"              # Run every N days
CONFIG[REPORT_CUSTOM_PERIOD_DAYS]="14"           # Analyze last N days
CONFIG[REPORT_CUSTOM_METRICS]="temp,errors"
```

### Alert Thresholds

```bash
CONFIG[REPORT_ALERT_TEMP_MAX]="55"               # Alert if max temp > 55°C
CONFIG[REPORT_ALERT_NEW_REALLOCATED]="true"      # Alert on new reallocated sectors
CONFIG[REPORT_ALERT_PENDING_SECTORS]="true"      # Alert on pending sectors
CONFIG[REPORT_ALERT_CRC_ERRORS]="true"           # Alert on CRC errors
CONFIG[REPORT_ALERT_TEST_FAILURES]="true"        # Alert on failed SMART tests
```

## Available Metrics

- `temp` - Temperature statistics (min/max/avg)
- `workload` - Data written/read, power hours
- `errors` - Reallocated sectors, pending sectors, CRC errors
- `tests` - Last SMART test dates and results
- `wear` - SSD wear level percentage
- `helium` - Helium drive level percentage
- `fleet_stats` - Comparison across all drives

## How It Works

### Automatic Execution

The plugin runs automatically when the `auto` command executes. It:

1. Checks if the report plugin is enabled
2. Loads configuration settings
3. Checks each report type to see if it's due
4. Generates reports for any due schedules
5. Updates timestamp files to prevent duplicates

### Schedule Checking

Each report type uses intelligent scheduling:

- **Weekly**: Runs on specified day of week + minimum 6 days since last run
- **Monthly**: Runs on specified day of month + minimum 25 days since last run
- **Quarterly**: Runs on specified day in Jan/Apr/Jul/Oct + minimum 80 days since last run
- **Yearly**: Runs on specified month/day + minimum 350 days since last run
- **Custom**: Runs every N days based on custom schedule

Timestamp files in `version2/data/report/` track the last run time for each report type.

### Data Collection

The plugin queries `history_raw.csv` for the specified time period and:

1. Extracts all matching rows for each drive
2. Calculates temperature statistics (min/max/avg)
3. Computes workload deltas (data written/read, power hours)
4. Tracks error count changes (reallocated, pending, CRC)
5. Collects drive information (model, SMART status, type)
6. Gathers special metrics (helium level, wear level, SMR status)

### Alert Detection

The plugin compares metrics against configured thresholds:

- Temperature exceeding maximum
- New reallocated sectors detected
- Pending sectors present
- CRC errors present
- SMART status not PASSED

Alerts are highlighted at the top of the report for immediate visibility.

### Report Generation

#### Text Format

Plain text report with:
- Header with report period and summary stats
- System Health Alerts section (if any alerts)
- Drive Details section with per-drive statistics
- Clean formatting with Unicode box-drawing characters
- Emoji icons for visual organization

#### HTML Format

Professional styled HTML report with:
- Gradient header with summary information grid
- Color-coded alert section with highlighted warnings
- Per-drive sections with gradient headers
- Organized stat groups with labeled rows
- Responsive design for mobile viewing
- Print-friendly styling

### Email Delivery

Reports are emailed using the `mail` command with:
- Descriptive subject line including report name and date
- Content-Type header for HTML format
- Attachment of generated report file
- Error handling and logging

## Report Content

Each report includes per-drive:

### Temperature Statistics
- Current temperature
- Minimum temperature during period
- Maximum temperature during period
- Average temperature during period

### Workload Metrics
- Power hours during period
- Data written during period (human-readable)
- Data read during period (human-readable)
- Total power hours (lifetime)
- Drive age in years

### Health & Errors
- Total reallocated sectors
- New reallocated sectors during period
- Current pending sectors
- Uncorrectable errors
- CRC error count

### Drive Information
- Drive ID
- Model
- Filesystem name
- SMART status
- Drive type (HDD/SSD)

### Drive-Specific Metrics (if applicable)
- Helium level percentage (helium HDDs)
- Wear level percentage (SSDs)
- SMR status (SMR HDDs)

## Testing

To test report generation without waiting for schedules:

1. **Manually trigger a report**:
   ```bash
   # Edit report.sh and temporarily set a schedule to trigger
   CONFIG[REPORT_WEEKLY_ENABLED]="true"
   CONFIG[REPORT_WEEKLY_DAY]="1"  # Set to today
   ```

2. **Delete timestamp files** to force regeneration:
   ```bash
   rm version2/data/report/last_*.timestamp
   ```

3. **Run auto command**:
   ```bash
   cd version2
   ./multi_report_omv.sh auto
   ```

4. **Check generated reports**:
   ```bash
   ls -lh version2/data/report/
   cat version2/data/report/weekly_report_*.txt
   ```

## Troubleshooting

### No reports generated

- Check `REPORT_ENABLED` is set to "true"
- Verify `REPORT_EMAIL` is configured
- Check individual schedule `*_ENABLED` settings
- Verify correct day/month settings for schedules
- Check logs for schedule checking messages

### Reports not emailed

- Verify `mail` command is available on system
- Check email configuration in system
- Test email manually: `echo "test" | mail -s "Test" your@email.com`
- Check report file was created in `data/report/`

### Missing data in reports

- Verify `history_raw.csv` has data for the period
- Check CSV file has data for all drives
- Verify date range calculation is correct
- Check logs for CSV query errors

### Duplicate reports

- Check timestamp files are being created in `data/report/`
- Verify timestamp update function is working
- Check for multiple auto command runs close together

## File Structure

```
plugins/report/
├── manifest.json           # Plugin metadata
├── report.sh              # Main plugin code (1079 lines)
└── README.md              # This file

data/report/
├── last_weekly.timestamp       # Last weekly report time
├── last_monthly.timestamp      # Last monthly report time
├── last_quarterly.timestamp    # Last quarterly report time
├── last_yearly.timestamp       # Last yearly report time
├── last_custom.timestamp       # Last custom report time
├── weekly_report_YYYYMMDD.txt  # Generated reports
├── monthly_report_YYYYMMDD.txt
└── ...
```

## Dependencies

- `awk` - CSV parsing and data extraction
- `date` - Date calculations and formatting
- `mail` - Email delivery
- `bc` - Floating point calculations (drive age)
- `cut` - Field extraction
- `sort` - Drive list sorting

## Version History

- **1.0.0** (Current) - Initial release
  - 5 independent report schedules
  - Text and HTML format support
  - Alert detection and highlighting
  - Comprehensive statistics
  - Email delivery

## Future Enhancements

Potential features for future versions:

- **Fleet Statistics**: Hottest drive, most active, total system stats
- **Graphs/Charts**: Visual temperature trends, workload charts
- **Report History**: Archive of past reports with comparison
- **Notification Options**: Webhook, Slack, SMS in addition to email
- **Custom Templates**: User-defined report layouts
- **PDF Export**: Generate PDF reports for archival
- **Performance Optimization**: Handle large CSV files more efficiently
- **Test Results**: Include detailed SMART test results in reports
