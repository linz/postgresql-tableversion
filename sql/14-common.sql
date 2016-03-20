/**
* Processes a text template given a set of input template parameters. Template 
* parameters within the text are substituted content must be written as '%1%' 
* to '%n%' where n is the number of text parameters.
*
* @param p_template       The template text
* @param p_params         The template parameters
* @return                 The expanded template text
*/
CREATE OR REPLACE FUNCTION ver_ExpandTemplate (
    p_template TEXT,
    p_params TEXT[]
)
RETURNS
    TEXT AS
$$
DECLARE 
    v_expanded TEXT;
BEGIN
    v_expanded := p_template;
    FOR i IN 1 .. array_length(p_params,1) LOOP
        v_expanded := REPLACE( v_expanded, '%' || i || '%', p_params[i]);
    END LOOP;
    RETURN v_expanded;
END;
$$
LANGUAGE plpgsql;

/**
* Executes a text template given a set of input template parameters. Template 
* parameters within the text are substituted content must be written as '%1%' 
* to '%n%' where n is the number of text parameters.
*
* @param p_template       The template text
* @param p_params         The template parameters
* @return                 The number of rows affected by running the template
*/

CREATE OR REPLACE FUNCTION ver_ExecuteTemplate(
    p_template TEXT,
    p_params TEXT[])
RETURNS
    BIGINT AS
$$
DECLARE
    v_sql TEXT;
    v_count BIGINT;
BEGIN
    v_sql := table_version.ver_ExpandTemplate( p_template, p_params );
    BEGIN
        EXECUTE v_sql;
    EXCEPTION
        WHEN others THEN
            RAISE EXCEPTION E'Error executing template SQL: %\nError: %',
            v_sql, SQLERRM;
    END;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN v_count;
END;
$$
LANGUAGE plpgsql;
  
/**
* Gets the tablename for the tables revision data.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The revision data table name
*/
CREATE OR REPLACE FUNCTION ver_get_version_table(
    p_schema NAME,
    p_table NAME
) 
RETURNS VARCHAR AS $$
    SELECT quote_ident($1 || '_' || $2 || '_revision');
$$ LANGUAGE sql IMMUTABLE;

/**
* Gets the fully qualified tablename for the tables revision data.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The revision data fully qualified table name
*/
CREATE OR REPLACE FUNCTION ver_get_version_table_full(
    p_schema NAME,
    p_table NAME
) 
RETURNS VARCHAR AS $$
    SELECT 'table_version.' || table_version.ver_get_version_table($1, $2);
$$ LANGUAGE sql IMMUTABLE;

/**
* Gets the trigger name that is created on the versioned table.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The trigger name
*/
CREATE OR REPLACE FUNCTION _ver_get_version_trigger(
    p_schema NAME,
    p_table NAME
)
RETURNS VARCHAR AS $$
    SELECT quote_ident($1 || '_' || $2 || '_revision_trg');
$$ LANGUAGE sql IMMUTABLE;

/**
* Gets the changset difference function name and signature that is created for the versioned table.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The function name and signature
*/
CREATE OR REPLACE FUNCTION _ver_get_diff_function(
    p_schema NAME,
    p_table NAME
)
RETURNS VARCHAR AS $$
    SELECT ('table_version.' || quote_ident('ver_get_' || $1 || '_' || $2 || '_diff') || '(p_revision1 INTEGER, p_revision2 INTEGER)');
$$ LANGUAGE sql IMMUTABLE;

/**
* Gets the revision function name and signature that is created for the versioned table.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @return                 The function name and signature
*/
CREATE OR REPLACE FUNCTION _ver_get_revision_function(
    p_schema NAME,
    p_table NAME
)
RETURNS VARCHAR AS $$
    SELECT ('table_version.' || quote_ident('ver_get_' || $1 || '_' || $2 || '_revision') || '(p_revision INTEGER)');
$$ LANGUAGE sql IMMUTABLE;

/**
* Determine if a temp table exists within the current SQL session.
*
* @param p_table_name     The name of the temp table
* @return                 If true if the table exists.
*/
CREATE OR REPLACE FUNCTION _ver_get_reversion_temp_table(
    p_table_name NAME
)
RETURNS BOOLEAN AS
$$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT
        TRUE
    INTO
        v_exists
    FROM
        pg_catalog.pg_class c
        LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE
        n.nspname LIKE 'pg_temp_%' AND
        pg_catalog.pg_table_is_visible(c.oid) AND
        c.relkind = 'r' AND
        c.relname = p_table_name;

    IF v_exists IS NULL THEN
        v_exists := FALSE;
    END IF;

    RETURN v_exists;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

/**
* Get the owner for a table
*
* @param p_table          The table
* @return                 Table owner rolename
*/
CREATE OR REPLACE FUNCTION _ver_get_table_owner(
    p_table REGCLASS
)
RETURNS TEXT AS
$$
    SELECT  quote_ident(r.rolname)
    FROM   pg_catalog.pg_class c
    JOIN   pg_catalog.pg_roles r on (c.relowner = r.oid)
    WHERE  c.oid = p_table
$$ LANGUAGE sql;

