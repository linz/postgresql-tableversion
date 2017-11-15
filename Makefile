EXTVERSION   = 1.4.0dev
REVISION=$(shell test -d .git && which git > /dev/null && git describe --always)

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
	table_version-loader.sh \
	table_version.control.in \
	$(NULL)

SED = sed

UPGRADEABLE_VERSIONS = 1.2.0 1.3.0dev 1.3.0

SQLSCRIPTS_built = \
    sql/20-version.sql \
    test/sql/version.sql \
    $(END)

SQLSCRIPTS = \
    sql/[0-9][0-9]-*.sql \
    $(END)

DOCS         = $(wildcard doc/*.md)
TESTS        = $(wildcard test/sql/*.sql)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test --load-language=plpgsql
REGRESS_PREP = testdeps

#
# Uncomment the MODULES line if you are adding C files
# to your extension.
#
#MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    = pg_config

EXTNDIR     = $(shell $(PG_CONFIG) --sharedir)
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)

ifeq ($(PG91),yes)

SCRIPTS_built = $(EXTENSION)-loader

# This is a workaround for a bug in "install" rule in
# PostgreSQL 9.4 and lower
SCRIPTS = $(SCRIPTS_built)

DATA_built = \
  $(EXTENSION)--$(EXTVERSION).sql \
  $(EXTENSION)-$(EXTVERSION).sql.tpl \
  $(wildcard upgrade-scripts/*--*.sql)

DATA = $(wildcard sql/*--*.sql)
EXTRA_CLEAN = \
    sql/$(EXTENSION)--$(EXTVERSION).sql \
    sql/$(EXTENSION).sql \
		sql/20-version.sql \
    $(EXTENSION).control \
    upgrade-scripts \
    $(META)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

sql/$(EXTENSION).sql: $(SQLSCRIPTS) $(META) $(SQLSCRIPTS_built)
	echo '\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \quit' > $@
	cat $(SQLSCRIPTS) >> $@
	echo "GRANT USAGE ON SCHEMA table_version TO public;" >> $@

upgrade-scripts/$(EXTENSION)--unpackaged--$(EXTVERSION).sql: sql/$(EXTENSION).sql Makefile
	mkdir -p upgrade-scripts
	echo '\echo Use "CREATE EXTENSION $(EXTENSION) FROM unpackaged" to load this file. \quit' > $@
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

%.sql: %.sql.in
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/;s|@@REVISION@@|$(REVISION)|' $< > $@
	
$(META): $(META).in
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

$(EXTENSION).control: $(EXTENSION).control.in
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@
	
.PHONY: check_control
check_control:
	grep -q "pgTAP" $(META)

test/sql/version.sql: Makefile

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

check-noext: table_version-loader
	PREPAREDB_NOEXTENSION=1 $(MAKE) test/sql/preparedb
	dropdb --if-exists contrib_regression
	createdb contrib_regression
	TABLE_VERSION_EXT_DIR=. \
		./table_version-loader --no-extension contrib_regression
	$(pg_regress_installcheck) $(REGRESS_OPTS) --use-existing $(REGRESS)
	dropdb contrib_regression

installcheck-upgrade:
	PREPAREDB_UPGRADE=1 make installcheck

installcheck-loader: table_version-loader
	PREPAREDB_NOEXTENSION=1 make test/sql/preparedb
	dropdb --if-exists contrib_regression
	createdb contrib_regression
	`pg_config --bindir`/table_version-loader $(TABLE_VERSION_OPTS) contrib_regression
	$(pg_regress_installcheck) $(REGRESS_OPTS) --use-existing $(REGRESS)
	dropdb contrib_regression

installcheck-loader-noext: table_version-loader
	$(MAKE) installcheck-loader TABLE_VERSION_OPTS=--no-extension

.PHONY: upgrade-scripts
upgrade-scripts: upgrade-scripts/$(EXTENSION)--unpackaged--$(EXTVERSION).sql
upgrade-scripts: $(EXTENSION)--$(EXTVERSION).sql
	mkdir -p upgrade-scripts
	for OLD_VERSION in $(UPGRADEABLE_VERSIONS); do \
		cat $< > upgrade-scripts/$(EXTENSION)--$$OLD_VERSION--$(EXTVERSION).sql; \
	done
	# allow upgrading to same version (for same-version-but-different-revision)
	cat $< > upgrade-scripts/$(EXTENSION)--$(EXTVERSION)--$(EXTVERSION)next.sql
	cat $< > upgrade-scripts/$(EXTENSION)--$(EXTVERSION)next--$(EXTVERSION).sql

all: upgrade-scripts

deb:
	pg_buildext updatecontrol
	# The -b switch is beacause only binary package works,
	# See https://github.com/linz/postgresql-tableversion/issues/29
	dpkg-buildpackage -us -uc -b

dist: distclean $(DISTFILES)
	mkdir $(EXTENSION)-$(EXTVERSION)
	cp -r $(DISTFILES) $(EXTENSION)-$(EXTVERSION)
	tar czf $(EXTENSION)-$(EXTVERSION).tar.gz $(EXTENSION)-$(EXTVERSION)
	rm -rf $(EXTENSION)-$(EXTVERSION)

#
# pgtap
#
.PHONY: pgtap
pgtap: $(EXTNDIR)/extension/pgtap.control

$(EXTNDIR)/extension/pgtap.control:
	pgxn install pgtap

#
# testdeps
# Hook for test to ensure dependencies in control file are set correctly
#
.PHONY: testdeps
testdeps: pgtap test/sql/preparedb


$(EXTENSION)-$(EXTVERSION).sql.tpl: $(EXTENSION)--$(EXTVERSION).sql Makefile sql/noextension.sql.in
	echo "BEGIN;" > $@
	cat sql/noextension.sql.in >> $@
	grep -v 'CREATE EXTENSION' $< \
  | grep -v 'pg_extension_config_dump' \
	>> $@
	echo "COMMIT;" >> $@

$(EXTENSION)-loader: $(EXTENSION)-loader.sh Makefile
	cat $< > $@
	chmod +x $@
