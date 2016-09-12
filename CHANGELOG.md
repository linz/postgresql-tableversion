# Change Log

All notable changes for the PostgreSQL table version extension are documented 
in this file.

## [Unreleased] - xxxx-xx-xx
### Added
- Added support for table_drop_column function

### Fixed
- Revsioning a table with only a primary key column causes an error. Issue #7
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

