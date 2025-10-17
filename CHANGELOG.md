# Changelog
## [v1.2.3] - 2025-09-09
### Fixed
- Critical bug in drive selftest scheduling logic that prevented drives from being selected for testing in Mode 1 (spread across period)
- Fixed drive rotation calculation for weekly and quarterly test periods
- Drives with overdue tests will now be properly scheduled and tested

## [v1.2.2] - 2025-07-19
### Added
- Email summary now explicitly lists which drives have warnings or critical issues, including the drive name and reason, instead of a generic monitoring message.

## [v1.2.1] - 2025-07-14
### Fixed
- Robust HTML and plain text email formatting for notifications
- Unicode and emoji support in email notifications
- Line breaks and formatting preserved in all email clients
- Subject and Content-Type headers handled correctly for both HTML and plain text
- No more missing or malformed email bodies

### Improved
- More reliable notification delivery for OMV health and SMART reports

## [v1.2.0] - 2025-07-05
### Added
- Initial public release of Multi-Report OMV Fork v1.2
- OMV health and SMART monitoring with email notifications
- CSV logging of drive statistics
- SMR drive detection and reporting
- Configurable email, logging, and test scheduling
- Compatibility with OMV 6.x/7.x and SnapRAID manager integration

---
