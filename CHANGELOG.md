# Change Log

All notable changes for the PostgreSQL table version extension are documented
in this file.

## [1.3.3] - YYYY-MM-DD
### Fixed
- Fix db corruption by `ver_fix_revision_disorder` (#115)

## [1.3.2] - 2018-02-19
### IMPORTANT
- If coming from 1.3.0 or 1.3.1, make sure to call
  `SELECT ver_fix_revision_disorder()` right after upgrade
### Fixed
- Revision sequence reset on upgrade from previous versions (#77)
### Added
- Function `ver_fix_revision_disorder` to fix bug introduced by
  upgrades to version 1.3.0, 1.3.1 or 1.4.0 (#77)

## [1.3.1] - 2017-09-26
### Fixed
- Do not install META.json and 20-version.sql (#54)
- Fix revision detection from git tags containing slashes (#48)

## [1.3.0] - 2017-08-30
### Added
- `ver_version` function

### Changed
- Upgrade scripts are now generated (#35)
- Performance of `ver_get_table_differences` improved (#15)

### Fixed
- Swapped insert/delete count from `ver_apply_table_differences` (#39)

## [1.2.0] - 2016-09-13
### Added
- Added support for `table_drop_column` function

### Fixed
- Revisioning a table with only a primary key column causes an error. Issue #7
- Error creating revision when table is given access to 'public' role. Issue #8

## [1.1.3] - 2016-05-17
### Fixed
- Enable versioning: Quoting of user role when replicating table permission during
- Fixed blocking of versioning queries. Issue #2

## [1.1.2] - 2016-05-02
### Fixed
- Improved software version management

## [1.1.1] - 2016-03-27
### Fixed
- Documentation fixes

## [1.1.0] - 2016-03-23
### Added
- Added support user name revision tracking and text primary keys
- Added support functions for diff functions
- Added tests for diff functions and permissions changes

### Changed
- Improve markup formatting and documentation
- Changed functions to remove security definer
- Improved permission controls for accessing metadata tables and executing difference functions. Remove old internal hard coded permissions
- Remove invalid echo command in makefile. Closes #1
- Replace hard coded schema path with PG installed extension variable

## [1.0.1] - 2016-01-25
### Added
- Initial release

