/**
* Check if table is versioned
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 If the table is versioned
*/
CREATE OR REPLACE FUNCTION ver_is_table_versioned(
    p_schema NAME,
    p_table  NAME
)
RETURNS BOOLEAN AS 
$$
DECLARE
    v_is_versioned BOOLEAN;
BEGIN
    SELECT
        versioned
    INTO
        v_is_versioned
    FROM 
        table_version.versioned_tables 
    WHERE
        schema_name = p_schema AND
        table_name = p_table;

    IF v_is_versioned IS NULL THEN
        v_is_versioned := FALSE;
    END IF;

    RETURN v_is_versioned;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

