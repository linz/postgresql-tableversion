
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

