# Change Log

All notable changes for the PostgreSQL table version extension are documented in this file.

## [1.10.4] - 2023-03-22

### Improved

- Test upgrade between Debian packages
- Release for Ubuntu 22.04 (Jammy)

### Removed

- Drop Ubuntu 18.04 support after
  [GitHub dropped their runner support](https://github.com/actions/runner-images/issues/6002).

## [1.10.3] - 2022-05-03

### Fixed

- Force pushing changes to origin remote

## [1.10.2] - 2022-03-21

### Improved

- Update GitHub actions
- Remove obsolete docs
- Fixed parallel release run issue
- Simplify Makefile
- Use linz-software-repository to test packaging

## [1.10.1] (_broken_) - 2022-02-23

### Added

- Package for Ubuntu 20.04 (Focal)
- Support PostgreSQL 13 and 14
- Enable automerge with Kodiak
- Enable automatic GitHub action upgrades with Dependabot
- Upgraded GitHub actions
- Lint using nixpkgs-fmt, Prettier, and ShellCheck in a Nix shell
- Run pipeline weekly for sanity check
- Run tests for recent versions of the package
- Merge in 1.9.0 release branch

### Removed

- Remove broken release 1.10.0
- Remove Travis CI configuration
- Avoid referencing Git revision in package versions
- Remove unreachable/redundant code
- Remove reference to PostgreSQL 9
- Only build/test the two most recent versions

### Improved

- Build package using the linz-software-repository action rather that a Makefile target
- Modify a copy of the repo rather than the original repo during tests
- Use strong Bash safety pragmas
- Use more modern Bash syntax
- Use consistent script formatting
- Split and document pipeline steps
- Pull out scripts for complex Makefile targets
- Sort tags by version, so that 1.10 comes after 1.9
- Make test output more verbose for debugging purposes
- Run tests in Docker containers

## [1.10.0] (_broken_) - 2021-12-09

### Added

- Support PostgreSQL 11.
- Run tests on Ubuntu 20.04.

### Removed

- Dropped support for PostgreSQL 9.

## [1.9.0] - 2021-01-05

### Added

- [debian] provide a postgresql-agnostic package "tableversion"

## [1.8.0] - 2020-02-11

### Improved

- Forbid TRUNCATE on versioned tables (#204)

## [1.7.1] - 2019-07-29

### Fixed

- Upgrade of existing revision triggers to skip empty updates (#192)

## [1.7.0] - 2019-07-25

### Added

- New function `ver_log_modified_tables`
- Ability for `table_version-loader` to upgrade between dev versions
- Ability to delete an empty revision by its creator (#178)

### Changed

- `table_version-loader` will CREATE EXTENSION from unpackaged when --no-extension is NOT given and
  db already has the extension-less support (#168)
- Only the creator of a revision can complete it (#181)
- In-progress revisions cannot be deleted (#178)
- UPDATEs to versioned tables that do not really change record values are now skipped and don't
  record the (fake) change in revision tables and `tables_changed` (#186)

### Improved

- Progress message from `table_version-loader` (#177)
- Forbid deleting an in-progress revision (#181)

## [1.6.0] - 2019-01-09

### IMPORTANT

- Drop of versioned tables is now forbidden, CASCADE will not help. This is done to avoid writing
  into system catalogs, which is forbidden on some platforms, like AWS (#122)

### Improved

- Add stdout support in `table_version-loader` (#146)

## [1.5.0] - 2018-09-26

### IMPORTANT

- If coming from 1.3.0, 1.3.1 or 1.4.0, make sure to call `SELECT ver_fix_revision_disorder()` right
  after upgrade

### Changed

- Functions `ver_enable_versioning`, `ver_disable_versioning` `ver_versioned_table_add_column`,
  `ver_versioned_table_drop_column`, `ver_versioned_table_change_column_type` and
  `ver_create_version_trigger` are now security definer, allowing `table_version` usage to
  under-provileged users: as long as you own a table you can now also version/unversion (#100) and
  add/drop/change cols on it (#113)

### Improved

- Do not assume consistent ordering of revision table columns (#109)
- Loader script now installs by default in /usr/local/bin/ and does not depend on `pg_config`
  anymore (#67)
- Testing framework switched to `pg_prove` (#74)
- Made `ver_disable_versioning` cleanup `tables_changed` and `versioned_tables` (#89)

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
- Improved permission controls for accessing metadata tables and executing difference functions.
  Remove old internal hard coded permissions
- Remove invalid echo command in makefile. Closes #1
- Replace hard coded schema path with PG installed extension variable

## [1.0.1] - 2016-01-25

### Added

- Initial release
