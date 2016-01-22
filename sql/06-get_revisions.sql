/**
* Get the revision information for the given revision ID.
*
* @param p_revision       The revision ID
* @param id               The returned revision id
* @param revision_time    The returned revision datetime
* @param start_time       The returned start time of when revision record was created
* @param schema_change    The returned flag if the revision had a schema change
* @param comment          The returned revision comment
*/
CREATE OR REPLACE FUNCTION ver_get_revision(
    p_revision        INTEGER, 
    OUT id            INTEGER, 
    OUT revision_time TIMESTAMP,
    OUT start_time    TIMESTAMP,
    OUT schema_change BOOLEAN,
    OUT comment       TEXT
) AS $$
    SELECT
        id,
        revision_time,
        start_time,
        schema_change,
        comment
    FROM
        table_version.revision
    WHERE
        id = $1
$$ LANGUAGE sql SECURITY DEFINER;

/**
* Get all revisions.
* 
* @param p_revisions      An array of revision ids
* @return                 A tableset of revisions records.
*/
CREATE OR REPLACE FUNCTION ver_get_revisions(p_revisions INTEGER[]) 
RETURNS TABLE(
    id             INTEGER,
    revision_time  TIMESTAMP,
    start_time     TIMESTAMP,
    schema_change  BOOLEAN,
    comment        TEXT
) AS $$
    SELECT
        id,
        revision_time,
        start_time,
        schema_change,
        comment
    FROM
        table_version.revision
    WHERE
        id = ANY($1)
    ORDER BY
        revision DESC;
$$ LANGUAGE sql SECURITY DEFINER;


/**
* Get revisions for a given date range
*
* @param p_start_date     The start datetime for the range of revisions
* @param p_end_date       The end datetime for the range of revisions
* @return                 A tableset of revision records
*/
CREATE OR REPLACE FUNCTION ver_get_revisions(
    p_start_date TIMESTAMP,
    p_end_date   TIMESTAMP
)
RETURNS TABLE(
    id             INTEGER
) AS $$
    SELECT
        id
    FROM
        table_version.revision
    WHERE
        revision_time >= $1 AND
        revision_time <= $2
    ORDER BY
        revision DESC;
$$ LANGUAGE sql SECURITY DEFINER;

/**
* Get the last revision for the given datetime. If no revision is recorded at
* the datetime, then the next oldest revision is returned.
*
* @param p_date_time      The datetime for the revision required.
* @return                 The revision id
*/
CREATE OR REPLACE FUNCTION ver_get_revision(
    p_date_time       TIMESTAMP
) 
RETURNS INTEGER AS 
$$
    SELECT
        id
    FROM
        table_version.revision
    WHERE
        id IN (
            SELECT max(id) 
            FROM   table_version.revision
            WHERE  revision_time <= $1
        );
$$ LANGUAGE sql SECURITY DEFINER;

/**
* Get the last revision.
*
* @return               The revision id
*/
CREATE OR REPLACE FUNCTION ver_get_last_revision() 
RETURNS INTEGER AS 
$$
    SELECT
        id
    FROM
        table_version.revision
    WHERE
        id IN (
            SELECT max(id) 
            FROM   table_version.revision
        );
$$ LANGUAGE sql SECURITY DEFINER;

/**
* Get the base revision for a given table.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The revision id
*/
CREATE OR REPLACE FUNCTION ver_get_table_base_revision(
    p_schema          NAME,
    p_table           NAME
)
RETURNS INTEGER AS
$$
DECLARE
    v_id INTEGER;
BEGIN
    IF NOT table_version.ver_is_table_versioned(p_schema, p_table) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;
    
    SELECT
        VER.id
    INTO
        v_id
    FROM
        table_version.revision VER
    WHERE
        VER.id IN (
            SELECT min(TBC.revision)
            FROM   table_version.versioned_tables VTB,
                   table_version.tables_changed TBC
            WHERE  VTB.schema_name = p_schema
            AND    VTB.table_name = p_table
            AND    VTB.id = TBC.table_id
        );
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


/**
* Get the last revision for a given table.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The revision id
* @throws RAISE_EXCEPTION If the table is not versioned
*/
CREATE OR REPLACE FUNCTION ver_get_table_last_revision(
    p_schema          NAME,
    p_table           NAME
) 
RETURNS INTEGER AS
$$
DECLARE
    v_id INTEGER;
BEGIN
    IF NOT table_version.ver_is_table_versioned(p_schema, p_table) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;
    
    SELECT
        VER.id
    INTO
        v_id
    FROM
        table_version.revision VER
    WHERE
        VER.id IN (
            SELECT max(TBC.revision)
            FROM   table_version.versioned_tables VTB,
                   table_version.tables_changed TBC
            WHERE  VTB.schema_name = p_schema
            AND    VTB.table_name = p_table
            AND    VTB.id = TBC.table_id
        );
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

