--------------------------------------------------------------------------------

-- postgresql-table_version - PostgreSQL database patch change management extension
--
-- Copyright 2016 Crown copyright (c)
-- Land Information New Zealand and the New Zealand Government.
-- All rights reserved
--
-- This software is released under the terms of the new BSD license. See the 
-- LICENSE file for more information.
--
--------------------------------------------------------------------------------

-- Add support for the user who created the revision
ALTER TABLE @extschema@.revision
   ADD COLUMN user_name TEXT;

ALTER TABLE @extschema@.revision 
    ALTER COLUMN user_name SET DEFAULT CURRENT_USER;


-- Add support returning for the user_name from the get revision functions.
-- Need to drop and recreate the functions due to the return type changes.
DROP FUNCTION @extschema@.ver_get_revisions(INTEGER[]);
DROP FUNCTION @extschema@.ver_get_revision(INTEGER);

CREATE OR REPLACE FUNCTION ver_get_revision(
    p_revision        INTEGER, 
    OUT id            INTEGER, 
    OUT revision_time TIMESTAMP,
    OUT start_time    TIMESTAMP,
    OUT schema_change BOOLEAN,
    OUT comment       TEXT,
    OUT user_name     TEXT
) AS $$
    SELECT
        id,
        revision_time,
        start_time,
        schema_change,
        comment,
        user_name
    FROM
        table_version.revision
    WHERE
        id = $1
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION ver_get_revisions(p_revisions INTEGER[]) 
RETURNS TABLE(
    id             INTEGER,
    revision_time  TIMESTAMP,
    start_time     TIMESTAMP,
    schema_change  BOOLEAN,
    comment        TEXT,
    user_name      TEXT
) AS $$
    SELECT
        id,
        revision_time,
        start_time,
        schema_change,
        comment,
        user_name
    FROM
        table_version.revision
    WHERE
        id = ANY($1)
    ORDER BY
        revision DESC;
$$ LANGUAGE sql SECURITY DEFINER;


