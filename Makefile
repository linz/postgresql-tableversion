EXTVERSION   = 1.3.0
REVISION=$(shell test -d .git && which git > /dev/null && git describe --always)

META         = META.json
EXTENSION    = $(shell grep -m 1 '"name":' $(META).in | sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')

TGT_VERSION=$(subst dev,,$(EXTVERSION))
PREV_VERSION=$(shell ls sql/table_version--*--*.sql | sed 's/.*$(EXTENSION)--.*--//;s/\.sql//' | grep -Fv $(TGT_VERSION) | sort -n | tail -1)

SED = sed

UPGRADEABLE_VERSIONS = 1.2.0 1.3.0dev

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

DATA_built = $(EXTENSION)--$(EXTVERSION).sql $(META) \
  $(SQLSCRIPTS_built) \
  $(wildcard upgrade-scripts/*--*.sql)

DATA = $(wildcard sql/*--*.sql)
EXTRA_CLEAN = \
    sql/$(EXTENSION)--$(EXTVERSION).sql \
    sql/$(EXTENSION).sql \
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
    else \
      cat; \
    fi | \
	  $(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' -e 's/@@FROM_VERSION@@//' > $@

installcheck-upgrade:
	PREPAREDB_UPGRADE=1 make installcheck

.PHONY: upgrade-scripts
upgrade-scripts: $(EXTENSION)--$(EXTVERSION).sql
	mkdir -p upgrade-scripts
	for OLD_VERSION in $(UPGRADEABLE_VERSIONS); do \
		cat $< > upgrade-scripts/$(EXTENSION)--$$OLD_VERSION--$(EXTVERSION).sql; \
	done
	# allow upgrading to same version (for same-version-but-different-revision)
	cat $< > upgrade-scripts/$(EXTENSION)--$(EXTVERSION)--$(EXTVERSION)next.sql
	cat $< > upgrade-scripts/$(EXTENSION)--$(EXTVERSION)next--$(EXTVERSION).sql

all: upgrade-scripts


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

