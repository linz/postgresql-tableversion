EXTVERSION   = 1.10.0dev

META         = META.json
EXTENSION    = $(shell grep -m 1 '"name":' $(META).in | sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')

DISTFILES = \
	doc \
	sql \
	test \
	LICENSE \
	Makefile \
	$(META) \
	$(META).in \
	README.md \
	table_version-loader.bash \
	table_version.control.in \
	$(NULL)

# List of known versions from which we're capable
# to upgrade automatically from. This should be
# any version from 1.2.0 onward.
#
UPGRADEABLE_VERSIONS = \
    1.2.0 \
    1.3.0dev 1.3.0 1.3.1dev 1.3.1 1.3.2dev 1.3.2 1.3.3dev 1.3.3 \
    1.4.0dev 1.4.0 1.4.1dev 1.4.1 1.4.2dev 1.4.2 1.4.3dev 1.4.3 \
    1.5.0dev 1.5.0 1.5.1dev 1.5.1 \
    1.6.0dev 1.6.0 \
    1.7.0dev 1.7.0 1.7.1dev 1.7.1 \
    1.8.0dev 1.8.0 \
    1.9.0dev 1.9.0 \
    1.10.0dev

SQLSCRIPTS_built = sql/20-version.sql

TESTS_built = test/sql/version.pg

SQLSCRIPTS = \
	sql/00-common.sql \
	sql/00-config_tables.sql \
	sql/01-enable_versioning.sql \
	sql/02-disable_versioning.sql \
	sql/03-create_revision.sql \
	sql/04-complete_revision.sql \
	sql/05-delete_revision.sql \
	sql/06-get_revisions.sql \
	sql/07-get_modified_tables.sql \
	sql/08-is_table_versioned.sql \
	sql/09-table_change_column_type.sql \
	sql/10-table_add_column.sql \
	sql/11-get_versioned_tables.sql \
	sql/12-create_table_functions.sql \
	sql/13-create_version_trigger.sql \
	sql/14-common.sql \
	sql/15-table_diff_functions.sql \
	sql/16-table_drop_column.sql \
	sql/17-fix_revision_disorder.sql \
	sql/18-log_modified_tables.sql \
	$(SQLSCRIPTS_built)

DOCS         = doc/table_version.md
TESTS        = \
	test/sql/upgrade-pre.sql \
	test/sql/upgrade-post.sql

#
# Uncomment the MODULES line if you are adding C files
# to your extension.
#
#MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    ?= pg_config

EXTNDIR     = $(shell $(PG_CONFIG) --sharedir)

PREFIX ?= /usr/local
LOCAL_BINDIR = $(PREFIX)/bin
LOCAL_SHAREDIR = $(PREFIX)/share/$(EXTENSION)
LOCAL_SHARES = $(EXTENSION)-$(EXTVERSION).sql.tpl

LOCAL_BINS = $(EXTENSION)-loader

UPGRADE_SCRIPTS_BUILT = $(patsubst %,upgrade-scripts/$(EXTENSION)--%--$(EXTVERSION).sql,$(UPGRADEABLE_VERSIONS))
UPGRADE_SCRIPTS_BUILT += upgrade-scripts/$(EXTENSION)--$(EXTVERSION)--$(EXTVERSION)next.sql
UPGRADE_SCRIPTS_BUILT += upgrade-scripts/$(EXTENSION)--$(EXTVERSION)next--$(EXTVERSION).sql
UPGRADE_SCRIPTS_BUILT += upgrade-scripts/$(EXTENSION)--unpackaged--$(EXTVERSION).sql

DATA_built = \
  $(EXTENSION)--$(EXTVERSION).sql \
  $(UPGRADE_SCRIPTS_BUILT)

DATA = $(wildcard sql/*--*.sql)
EXTRA_CLEAN = \
    $(SQLSCRIPTS_built) \
    $(TESTS_built) \
    $(LOCAL_BINS) \
    sql/$(EXTENSION)--$(EXTVERSION).sql \
    sql/$(EXTENSION).sql \
    sql/20-version.sql \
    $(EXTENSION).control \
    upgrade-scripts \
    *.tpl \
    *.sql \
    $(META)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

foo:
	printf '\\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \\quit\n'

sql/$(EXTENSION).sql: $(SQLSCRIPTS)
	./create-extension-sql.bash $(EXTENSION) $(SQLSCRIPTS) > $@

upgrade-scripts/$(EXTENSION)--unpackaged--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	mkdir -p upgrade-scripts
	./create-update-script-sql.bash $(EXTENSION) $< > $@

$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

%.sql: %.sql.in
	sed -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

%.pg: %.pg.in
	sed -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

$(META): $(META).in
	sed -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

$(EXTENSION).control: $(EXTENSION).control.in
	sed -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

# This is phony because it depends on env variables
.PHONY: test/sql/preparedb
test/sql/preparedb: test/sql/preparedb.in
	./create-prepare-db-sql.bash "$(PREPAREDB_UPGRADE)" "$(PREPAREDB_UPGRADE_FROM)" "$(PREPAREDB_NOEXTENSION)" "$(EXTVERSION)" < $< > $@

check: check-noext

installcheck: $(TESTS_built)
	$(MAKE) test/sql/preparedb
	dropdb --if-exists contrib_regression
	createdb contrib_regression
	pg_prove --dbname=contrib_regression --verbose test/sql
	dropdb contrib_regression

check-noext: $(TESTS_built) table_version-loader
	PREPAREDB_NOEXTENSION=1 $(MAKE) test/sql/preparedb
	dropdb --if-exists contrib_regression
	createdb contrib_regression
	TABLE_VERSION_EXT_DIR=. \
		./table_version-loader --no-extension contrib_regression
	pg_prove --dbname=contrib_regression --verbose test/sql
	dropdb contrib_regression

installcheck-upgrade:
	PREPAREDB_UPGRADE=1 $(MAKE) installcheck

installcheck-loader: $(TESTS_built) table_version-loader
	PREPAREDB_NOEXTENSION=1 $(MAKE) test/sql/preparedb
	dropdb --if-exists contrib_regression
	createdb contrib_regression
	PATH="$$PATH:$(LOCAL_BINDIR)" table_version-loader $(TABLE_VERSION_OPTS) contrib_regression
	pg_prove --dbname=contrib_regression --verbose test/sql
	dropdb contrib_regression

#
# Check functionality when loading and upgrading via table_version-loader
#
# Version to upgrade from MUST be specified via PREPAREDB_UPGRADE_FROM
# environment variable.
#
# Custom switches can be passed to table_version-loader via the
# TABLE_VERSION_OPTS env variable (for example --no-extension)
#
installcheck-loader-upgrade: $(TESTS_built) table_version-loader
	PREPAREDB_NOEXTENSION=1 $(MAKE) test/sql/preparedb
	dropdb --if-exists contrib_regression
	createdb contrib_regression
	PATH="$$PATH:$(LOCAL_BINDIR)" \
	TABLE_VERSION_EXT_DIR=$(PREPAREDB_UPGRADE_FROM_EXT_DIR) \
	    table_version-loader --version $(PREPAREDB_UPGRADE_FROM) \
        $(TABLE_VERSION_OPTS) contrib_regression
	psql -f test/sql/preparedb contrib_regression
	rm -rf test/sql-loader-upgrade
	cp -a test/sql test/sql-loader-upgrade
	psql -f test/sql/preparedb contrib_regression
	psql -f test/sql/upgrade-pre.sql contrib_regression
	PATH="$$PATH:$(LOCAL_BINDIR)" \
		table_version-loader --version $(EXTVERSION) \
		$(TABLE_VERSION_OPTS) contrib_regression
	psql -f test/sql/upgrade-post.sql contrib_regression
	sed -ie 's/^\\i test.sql.preparedb//' test/sql-loader-upgrade/base.pg
	pg_prove --dbname=contrib_regression --verbose test/sql-loader-upgrade
	dropdb contrib_regression

installcheck-loader-noext: table_version-loader
	$(MAKE) installcheck-loader TABLE_VERSION_OPTS=--no-extension

installcheck-loader-upgrade-noext:
	$(MAKE) installcheck-loader-upgrade TABLE_VERSION_OPTS=--no-extension

$(UPGRADE_SCRIPTS_BUILT): upgrade_scripts

.PHONY: upgrade_scripts
upgrade_scripts: upgrade-scripts/$(EXTENSION)--unpackaged--$(EXTVERSION).sql
upgrade_scripts: $(EXTENSION)--$(EXTVERSION).sql
	./create-upgrade-scripts.bash $< $(EXTENSION) $(EXTVERSION) $(UPGRADEABLE_VERSIONS)

all: upgrade_scripts

deb-check:
	./check-packages.bash

dist: distclean $(DISTFILES)
	mkdir $(EXTENSION)-$(EXTVERSION)
	cp -r $(DISTFILES) $(EXTENSION)-$(EXTVERSION)
	zip -r $(EXTENSION)-$(EXTVERSION).zip $(EXTENSION)-$(EXTVERSION)
	rm -rf $(EXTENSION)-$(EXTVERSION)

$(EXTENSION)-$(EXTVERSION).sql.tpl: $(EXTENSION)--$(EXTVERSION).sql sql/noextension.sql.in
	./create-version-template.bash < $< > $@

$(EXTENSION)-loader: $(EXTENSION)-loader.bash
	sed 's|@@LOCAL_SHAREDIR@@|$(LOCAL_SHAREDIR)|' $< > $@
	chmod +x $@

all: $(LOCAL_BINS) $(LOCAL_SHARES)

install: local-install
uninstall: local-uninstall

local-install:
	$(INSTALL) -d $(DESTDIR)$(LOCAL_BINDIR)
	$(INSTALL) $(LOCAL_BINS) $(DESTDIR)$(LOCAL_BINDIR)
	$(INSTALL) -d $(DESTDIR)$(LOCAL_SHAREDIR)
	$(INSTALL) -m 644 $(LOCAL_SHARES) $(DESTDIR)$(LOCAL_SHAREDIR)

local-uninstall:
	for b in $(LOCAL_BINS); do rm -f $(DESTIDIR)$(LOCAL_BINDIR)/$$b; done
	for b in $(LOCAL_SHARES); do rm -f $(DESTIDIR)$(LOCAL_SHAREDIR)/$$b; done
