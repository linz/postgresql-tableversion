# Change Log

All notable changes for the PostgreSQL table version extension are documented 
in this file.

## [1.7.0dev] - 2019-MM-DD
### Added
- New function `ver_log_modified_tables`
- Ability for `table_version-loader` to upgrade between dev versions
- Ability to delete an empty revision by its creator (#178)
### Changed
- `table_version-loader` will CREATE EXTENSION from unpackaged
  when --no-extension is NOT given and db already has the
  extension-less support (#168)
- Only the creator of a revision can complete it (#181)
- In-progress revisions cannot be deleted (#178)
### Improved
- Progress message from `table_version-loader` (#177)
- Forbid deleting an in-progress revision (#181)

## [1.6.0] - 2019-01-09
### IMPORTANT
- Drop of versioned tables is now forbidden,
  CASCADE will not help. This is done to avoid
  writing into system catalogs, which is forbidden
  on some platforms, like AWS (#122)
### Improved
- Add stdout support in `table_version-loader` (#146)

## [1.5.0] - 2018-09-26
### IMPORTANT
- If coming from 1.3.0, 1.3.1 or 1.4.0, make sure to call
  `SELECT ver_fix_revision_disorder()` right after upgrade
### Changed
- Functions `ver_enable_versioning`, `ver_disable_versioning`
  `ver_versioned_table_add_column`, `ver_versioned_table_drop_column`,
  `ver_versioned_table_change_column_type` and
  `ver_create_version_trigger` are now security definer,
  allowing `table_version` usage to under-provileged users: as long as
  you own a table you can now also version/unversion (#100) and
  add/drop/change cols on it (#113)
### Improved
- Do not assume consistent ordering of revision table columns (#109)
- Loader script now installs by default in /usr/local/bin/
  and does not depend on `pg_config` anymore (#67)
- Testing framework switched to `pg_prove` (#74)
- Made `ver_disable_versioning` cleanup `tables_changed` and
  `versioned_tables` (#89)
### Added
- More functions accepting regclass parameter (#13):
    - `ver_disable_versioning`
    - `ver_versioned_table_add_column`
    - `ver_versioned_table_drop_column`
    - `ver_versioned_table_change_column_type`
    - `ver_create_version_trigger`

## [1.4.0] - 2017-11-15
### Added
- Loader script `table_version-loader` (#59)
- Working upgrade path from unpackaged (#62)
### Changed
- Dropping and recreating versioned tables is now recoverable (#57)
### Added
- A version of `ver_enable_versioning` taking a regclass parameter (#13)

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

