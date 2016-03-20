META         = META.json
EXTENSION    = $(shell grep -m 1 '"name":' $(META) | sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')
EXTVERSION   = $(shell grep -m 1 '"version":' $(META) | sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",/\1/')

SED = sed

SQLSCRIPTS = \
    sql/[0-9][0-9]-*.sql \
    $(END)

DOCS         = $(wildcard doc/*.md)
TESTS        = $(wildcard test/sql/*.sql)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test --load-language=plpgsql

#
# Uncoment the MODULES line if you are adding C files
# to your extention.
#
#MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    = pg_config

EXTNDIR     = $(shell $(PG_CONFIG) --sharedir)
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)

ifeq ($(PG91),yes)

DATA_built = sql/$(EXTENSION)--$(EXTVERSION).sql
	
sql/$(EXTENSION).sql: $(SQLSCRIPTS)
	echo '\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \quit' > $@
	cat $(SQLSCRIPTS) >> $@
	echo "GRANT USAGE ON SCHEMA table_version TO public;" >> $@

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@
	
$(EXTENSION).control: $(EXTENSION).control.in
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@
	
DATA = $(wildcard sql/*--*.sql)
EXTRA_CLEAN = \
    sql/$(EXTENSION)--$(EXTVERSION).sql \
    sql/$(EXTENSION).sql \
    $(EXTENSION).control
endif

# Hook for test to ensure dependencies in control file are set correctly
testdeps: check_control

.PHONY: check_control
check_control:
	grep -q "pgTAP" $(META)

#
# pgtap
#
.PHONY: pgtap
pgtap: $(EXTNDIR)/extension/pgtap.control

$(EXTNDIR)/extension/pgtap.control:
	pgxn install pgtap

#
# testdeps
#
.PHONY: testdeps
testdeps: pgtap

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

