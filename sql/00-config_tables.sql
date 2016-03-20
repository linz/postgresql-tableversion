--------------------------------------------------------------------------------

-- postgresql-table_version - PostgreSQL table versioning extension
--
-- Copyright 2016 Crown copyright (c)
-- Land Information New Zealand and the New Zealand Government.
-- All rights reserved
--
-- This software is released under the terms of the new BSD license. See the 
-- LICENSE file for more information.
--
--------------------------------------------------------------------------------

CREATE TABLE revision (
    id SERIAL NOT NULL PRIMARY KEY,
    revision_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    start_time TIMESTAMP NOT NULL DEFAULT clock_timestamp(),
    user_name TEXT NOT NULL DEFAULT CURRENT_USER,
    schema_change BOOLEAN NOT NULL,
    comment TEXT
);

GRANT SELECT ON TABLE revision TO public;

SELECT setval('@extschema@.revision_id_seq', 1000, true);

COMMENT ON TABLE revision IS $$
Defines a revision represents a amendment to table or series of tables held 
within the database. Each revision is identified by an id.  

The revision_time is the datetime of the revision.

The start_time is the datetime of when the revision record was created.

The user_name is the database user who created the revision
$$;

SELECT pg_catalog.pg_extension_config_dump('revision', '');

CREATE TABLE versioned_tables (	
    id SERIAL NOT NULL PRIMARY KEY,
    schema_name NAME NOT NULL,
    table_name NAME NOT NULL,
    key_column VARCHAR(64) NOT NULL,
    versioned BOOLEAN NOT NULL,
    CONSTRAINT versioned_tables_name_key UNIQUE (schema_name, table_name)
);

GRANT SELECT ON TABLE versioned_tables TO public;

COMMENT ON TABLE versioned_tables IS $$
Defines if a table is versioned. Each table is identified by an id. 

The column used to define primary key
for the table is defined in key_column. This key does not actually have to be
table primary key, rather itneeds to be a unique non-composite integer or bigint
column.
$$;

SELECT pg_catalog.pg_extension_config_dump('versioned_tables', '');

CREATE TABLE tables_changed (
    revision INTEGER NOT NULL REFERENCES revision,
    table_id INTEGER NOT NULL REFERENCES versioned_tables,
    PRIMARY KEY (revision, table_id)
);

GRANT SELECT ON TABLE tables_changed TO public;

COMMENT ON TABLE tables_changed IS $$
Defines which tables are modified by a given revision.
$$;

SELECT pg_catalog.pg_extension_config_dump('tables_changed', '');


