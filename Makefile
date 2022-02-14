EXTVERSION   = 1.10.0dev

META         = META.json
EXTENSION    = $(shell grep -m 1 '"name":' $(META).in | sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')

TGT_VERSION=$(subst dev,,$(EXTVERSION))
PREV_VERSION=$(shell ls sql/table_version--*--*.sql | sed 's/.*$(EXTENSION)--.*--//;s/\.sql//' | grep -Fv $(TGT_VERSION) | sort -n | tail -1)

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

SED = sed

# List of known versions from which we're capable
# to upgrade automatically from. This should be
# any version from 1.2.0 onward.
#
UPGRADEABLE_VERSIONS = \
    1.2.0 \
    1.3.0dev 1.3.0 1.3.1dev 1.3.1 \
    1.4.0dev 1.4.0 1.4.1dev 1.4.1 1.4.2dev 1.4.2 1.4.3dev 1.4.3 \
    1.5.0dev 1.5.0 1.5.1dev 1.5.1 \
    1.6.0dev 1.6.0 1.6.1dev \
    1.7.0dev 1.7.0 \
    1.8.0dev 1.8.0 \
    1.9.0dev 1.9.0 \
    1.10.0dev

SQLSCRIPTS_built = \
    sql/20-version.sql \
    $(END)

TESTS_built = test/sql/version.pg

SQLSCRIPTS = \
    sql/[0-9][0-9]-*.sql \
    $(END)

DOCS         = $(wildcard doc/table_version.md)
TESTS        = $(wildcard test/sql/*.sql)
REGRESS_PREP = testdeps

#
# Uncomment the MODULES line if you are adding C files
# to your extension.
#
#MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    ?= pg_config

EXTNDIR     = $(shell $(PG_CONFIG) --sharedir)
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)

ifeq ($(PG91),yes)

PREFIX ?= /usr/local
LOCAL_BINDIR = $(PREFIX)/bin
LOCAL_SHAREDIR = $(PREFIX)/share/$(EXTENSION)
LOCAL_SHARES = $(EXTENSION)-$(EXTVERSION).sql.tpl

LOCAL_SCRIPTS_built = $(EXTENSION)-loader

LOCAL_BINS = $(LOCAL_SCRIPTS_built)

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
    $(LOCAL_SCRIPTS_built) \
    sql/$(EXTENSION)--$(EXTVERSION).sql \
    sql/$(EXTENSION).sql \
    sql/20-version.sql \
    $(EXTENSION).control \
    upgrade-scripts \
    *.tpl \
    *.sql \
    $(META)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

sql/$(EXTENSION).sql: $(SQLSCRIPTS) $(META) $(SQLSCRIPTS_built)
	printf '\\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \\quit\n' > $@
	cat $(SQLSCRIPTS) >> $@
	echo "GRANT USAGE ON SCHEMA table_version TO public;" >> $@

upgrade-scripts/$(EXTENSION)--unpackaged--$(EXTVERSION).sql: sql/$(EXTENSION).sql Makefile
	mkdir -p upgrade-scripts
	printf '\\echo Use "CREATE EXTENSION $(EXTENSION) FROM unpackaged" to load this file. \\quit\n' > $@
	echo "---- TABLES -- " >> $@
	cat $< | grep '^CREATE TABLE' | \
		sed -e 's/^CREATE /ALTER EXTENSION table_version ADD /' \
		    -e 's/ IF NOT EXISTS//' \
		    -e 's/(.*/;/' \
		>> $@
	echo "---- FUNCTIONS -- " >> $@
	cat $< | grep -A10 '^CREATE OR REPLACE FUNCTION [^%]' | \
		tr '\n' '\r' | \
		sed -e 's/CREATE OR REPLACE/\nALTER EXTENSION table_version ADD/g' \
		    -e 's/ IF NOT EXISTS//g' \
		    -e 's/)[^\r]*\r/);\n/g' | \
		grep '^ALTER EXTENSION' | \
		sed -e 's/\r/ /g' \
		    -e 's/  */ /g' \
		    -e 's/ DEFAULT [^,)]*//g' \
		    -e 's/ = [^,)]*//g' \
		>> $@

$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

%.sql: %.sql.in Makefile
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

%.pg: %.pg.in Makefile
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

$(META): $(META).in Makefile
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

$(EXTENSION).control: $(EXTENSION).control.in Makefile
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

.PHONY: check_control
check_control:
	grep -q "pgTAP" $(META)

test/sql/version.pg: Makefile

# This is phony because it depends on env variables
.PHONY: test/sql/preparedb
test/sql/preparedb: test/sql/preparedb.in
	cat $< | \
	  if test "${PREPAREDB_UPGRADE}" = 1; then \
        if test -n "${PREPAREDB_UPGRADE_FROM}"; then \
          UPGRADE_FROM="version '${PREPAREDB_UPGRADE_FROM}'"; \
        else \
          UPGRADE_FROM=""; \
        fi; \
        $(SED) -e 's/^--UPGRADE-- //' -e "s/@@FROM_VERSION@@/$$UPGRADE_FROM/"; \
	  elif test "${PREPAREDB_NOEXTENSION}" = 1; then \
        grep -v table_version; \
      else \
        cat; \
      fi | \
	  $(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' -e 's/@@FROM_VERSION@@//' > $@

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
	mkdir -p upgrade-scripts
	for OLD_VERSION in $(UPGRADEABLE_VERSIONS); do \
		cat $< > upgrade-scripts/$(EXTENSION)--$$OLD_VERSION--$(EXTVERSION).sql; \
	done
	# allow upgrading to same version (for same-version-but-different-revision)
	cat $< > upgrade-scripts/$(EXTENSION)--$(EXTVERSION)--$(EXTVERSION)next.sql
	cat $< > upgrade-scripts/$(EXTENSION)--$(EXTVERSION)next--$(EXTVERSION).sql

all: upgrade_scripts

deb-check:
	# Test postgresql dependent packages do NOT contain loader
	@for pkg in build-area/postgresql-*tableversion_*.deb; do \
		dpkg -c $$pkg > $$pkg.contents || break; \
		if grep -q loader $$pkg.contents; then  \
                echo "Package $$pkg contains loader" >&2 \
                && false; \
		fi; \
	done
	# Test postgresql-agnostic package DOES contain loader
	@for pkg in build-area/tableversion_*.deb; do \
		dpkg -c $$pkg > $$pkg.contents || break; \
			if grep -q loader $$pkg.contents; then  \
				:; \
			else \
				echo "Package $$pkg does NOT contain loader" >&2 \
				&& false; \
			fi; \
		done

dist: distclean $(DISTFILES)
	mkdir $(EXTENSION)-$(EXTVERSION)
	cp -r $(DISTFILES) $(EXTENSION)-$(EXTVERSION)
	zip -r $(EXTENSION)-$(EXTVERSION).zip $(EXTENSION)-$(EXTVERSION)
	rm -rf $(EXTENSION)-$(EXTVERSION)

#
# testdeps
# Hook for test to ensure dependencies in control file are set correctly
#
.PHONY: testdeps
testdeps: test/sql/preparedb


$(EXTENSION)-$(EXTVERSION).sql.tpl: $(EXTENSION)--$(EXTVERSION).sql Makefile sql/noextension.sql.in
	echo "BEGIN;" > $@
	cat sql/noextension.sql.in >> $@
	grep -v 'CREATE EXTENSION' $< \
  | grep -v 'pg_extension_config_dump' \
	>> $@
	echo "COMMIT;" >> $@

$(EXTENSION)-loader: $(EXTENSION)-loader.bash Makefile
	cat $< | sed 's|@@LOCAL_SHAREDIR@@|$(LOCAL_SHAREDIR)|' > $@
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
