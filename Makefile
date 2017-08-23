EXTVERSION   = 1.3.0dev

META         = META.json
EXTENSION    = $(shell grep -m 1 '"name":' $(META).in | sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')

TGT_VERSION=$(subst dev,,$(EXTVERSION))
PREV_VERSION=$(shell ls sql/table_version--*--*.sql | sed 's/.*$(EXTENSION)--.*--//;s/\.sql//' | grep -Fv $(TGT_VERSION) | sort -n | tail -1)

SED = sed

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

DATA_built = $(EXTENSION)--$(EXTVERSION).sql $(META)

ifeq ($(findstring dev,$(EXTVERSION)),dev)
  DATA_built += $(EXTENSION)--$(PREV_VERSION)--$(EXTVERSION).sql
endif

sql/$(EXTENSION).sql: $(SQLSCRIPTS) $(META)
	echo '\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \quit' > $@
	cat $(SQLSCRIPTS) >> $@
	echo "GRANT USAGE ON SCHEMA table_version TO public;" >> $@

$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

$(EXTENSION)--$(PREV_VERSION)--$(EXTVERSION).sql:
	echo "-- Fake upgrade for dev version" > $@
	WIP_UPGRADE_FILE=sql/$(EXTENSION)--$(PREV_VERSION)--$(TGT_VERSION).sql; \
	if test -f "$$WIP_UPGRADE_FILE"; then \
    cat $$WIP_UPGRADE_FILE >> $@; \
  fi
	
$(META): $(META).in
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

$(EXTENSION).control: $(EXTENSION).control.in
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@
	
DATA = $(wildcard sql/*--*.sql)
EXTRA_CLEAN = \
    sql/$(EXTENSION)--$(EXTVERSION).sql \
    sql/$(EXTENSION).sql \
    $(EXTENSION).control \
    $(META)
endif

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
      sed "s/^--UPGRADE-- //;s/@@FROM_VERSION@@/$$UPGRADE_FROM/"; \
    else \
      cat; \
    fi | \
	  $(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' > $@

installcheck-upgrade:
	PREPAREDB_UPGRADE=1 make installcheck



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

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

