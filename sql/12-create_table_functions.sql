/**
* Creates functions required for versioning the table.
*
* @param p_schema         The table schema
* @param p_table          The table name
* @param p_key_col        The unique non-compostite integer column key.
* @return                 If creating the functions was successful.
* @throws RAISE_EXCEPTION If the table is not versioned
* @throws RAISE_EXCEPTION If the table column definition could not be found
*/
CREATE OR REPLACE FUNCTION ver_create_table_functions(
    p_schema  NAME, 
    p_table   NAME, 
    p_key_col NAME
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_revision_table      TEXT;
    v_sql                 TEXT;
    v_col_cur             refcursor;
    v_column_name         NAME;
    v_column_type         TEXT;
    v_table_columns       TEXT;
    v_select_columns_diff TEXT;
    v_select_columns_rev  TEXT;
BEGIN
    IF NOT table_version.ver_is_table_versioned(p_schema, p_table) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;
    
    v_revision_table := table_version.ver_get_version_table_full(p_schema, p_table);
    v_table_columns := '';
    v_select_columns_diff := '';
    v_select_columns_rev := '';
    
    OPEN v_col_cur FOR
    SELECT column_name, column_type
    FROM table_version._ver_get_table_cols(p_schema, p_table);

    FETCH FIRST IN v_col_cur INTO v_column_name, v_column_type;
    LOOP
        v_select_columns_rev := v_select_columns_rev || REPEAT(' ', 16) || 'T.' || quote_ident(v_column_name);
        v_select_columns_diff := v_select_columns_diff || REPEAT(' ', 16) || 'TL.' || quote_ident(v_column_name);
        v_table_columns := v_table_columns || '    ' || quote_ident(v_column_name) || ' ' || v_column_type;
        FETCH v_col_cur INTO v_column_name, v_column_type;
        IF FOUND THEN
            v_select_columns_rev :=  v_select_columns_rev || ', ' || E'\n';
            v_select_columns_diff :=  v_select_columns_diff || ', ' || E'\n';
            v_table_columns :=   v_table_columns  || ', ' || E'\n';
        ELSE
            v_table_columns  :=  v_table_columns  || E'\n';
            EXIT;
        END IF;
    END LOOP;
    
    CLOSE v_col_cur;

    -- Create difference function for table called:
    -- ver_get_$schema$_$table$_diff(p_revision1 integer, p_revision2 integer)
    v_sql := $template$
    
CREATE OR REPLACE FUNCTION %func_sig%
RETURNS TABLE(
    _diff_action CHAR(1),
    %table_columns%
) 
AS $FUNC$
    DECLARE
        v_revision1      INTEGER;
        v_revision2      INTEGER;
        v_temp           INTEGER;
        v_base_version   INTEGER;
        v_revision_table TEXT;
    BEGIN
        IF NOT table_version.ver_is_table_versioned(%schema_name%, %table_name%) THEN
            RAISE EXCEPTION 'Table %full_table_name% is not versioned';
        END IF;
        
        v_revision1 := p_revision1;
        v_revision2 := p_revision2;
        IF v_revision1 = v_revision2 THEN
            RETURN;
        END IF;
        
        IF v_revision1 > v_revision2 THEN
            RAISE EXCEPTION 'Revision 1 (%) is greater than revision 2 (%)', v_revision1, v_revision2;
        END IF;
        
        SELECT table_version.ver_get_table_base_revision(%schema_name%, %table_name%)
        INTO   v_base_version;
        IF v_base_version > v_revision2 THEN
            RETURN;
        END IF;
        
        RETURN QUERY EXECUTE
        table_version.ver_ExpandTemplate(
            $sql$
            WITH changed_within_range AS (
                SELECT 
                    T.%key_col%,
                    min(T._revision_created) <= %1% AS existed,
                    max(T._revision_created) AS last_update_revision
                FROM
                    %revision_table% AS T
                WHERE (
                    (T._revision_created <= %1% AND T._revision_expired > %1% AND T._revision_expired <= %2%) OR
                    (T._revision_created > %1%  AND T._revision_created <= %2%)
                )
                GROUP BY
                    T.%key_col%
            )
            SELECT
                CAST(
                    CASE
                       WHEN TL._revision_expired <= %2% THEN 'D'
                       WHEN C.existed THEN 'U'
                       ELSE 'I'
                    END
                AS CHAR(1)) AS action,
%select_columns%
            FROM
                changed_within_range C
                JOIN %revision_table% AS TL ON TL.%key_col% = C.%key_col% AND TL._revision_created = C.last_update_revision
            WHERE
                C.existed OR
                (TL._revision_expired IS NULL OR TL._revision_expired > %2%);
            $sql$,
            ARRAY[
                v_revision1::TEXT,
                v_revision2::TEXT
            ]
        );
        RETURN;
    END;
$FUNC$ LANGUAGE plpgsql SECURITY DEFINER;

    $template$;
    
    v_sql := REPLACE(v_sql, '%func_sig%',       table_version._ver_get_diff_function(p_schema, p_table));
    v_sql := REPLACE(v_sql, '%table_columns%',  v_table_columns);
    v_sql := REPLACE(v_sql, '%schema_name%',    quote_literal(p_schema));
    v_sql := REPLACE(v_sql, '%table_name%',     quote_literal(p_table));
    v_sql := REPLACE(v_sql, '%full_table_name%', quote_ident(p_schema) || '.' || quote_ident(p_table));
    v_sql := REPLACE(v_sql, '%select_columns%', v_select_columns_diff);
    v_sql := REPLACE(v_sql, '%key_col%',        quote_ident(p_key_col));
    v_sql := REPLACE(v_sql, '%revision_table%', v_revision_table);
    
    EXECUTE 'DROP FUNCTION IF EXISTS ' || table_version._ver_get_diff_function(p_schema, p_table);
    EXECUTE v_sql;
    
    EXECUTE 'REVOKE ALL ON FUNCTION ' || table_version._ver_get_diff_function(p_schema, p_table)||' FROM PUBLIC;';
	EXECUTE 'GRANT EXECUTE ON FUNCTION ' || table_version._ver_get_diff_function(p_schema, p_table)||' TO bde_admin;';
	EXECUTE 'GRANT EXECUTE ON FUNCTION ' || table_version._ver_get_diff_function(p_schema, p_table)||' TO bde_user;';

    -- Create get version function for table called: 
    -- ver_get_$schema$_$table$_revision(p_revision integer)
    v_sql := $template$
    
CREATE OR REPLACE FUNCTION %func_sig%
RETURNS TABLE(
    %table_columns%
) AS
$FUNC$
BEGIN
    RETURN QUERY EXECUTE
    table_version.ver_ExpandTemplate(
        $sql$
            SELECT
%select_columns%
            FROM
                %revision_table% AS T
            WHERE
                _revision_created <= %1% AND
                (_revision_expired > %1% OR _revision_expired IS NULL)
        $sql$,
        ARRAY[
            p_revision::TEXT
        ]
    );
END;
$FUNC$ LANGUAGE plpgsql SECURITY DEFINER;

    $template$;
    
    v_sql := REPLACE(v_sql, '%func_sig%', table_version._ver_get_revision_function(p_schema, p_table));
    v_sql := REPLACE(v_sql, '%table_columns%', v_table_columns);
    v_sql := REPLACE(v_sql, '%select_columns%', v_select_columns_rev);
    v_sql := REPLACE(v_sql, '%revision_table%', v_revision_table);
    
    EXECUTE 'DROP FUNCTION IF EXISTS ' || table_version._ver_get_revision_function(p_schema, p_table);
    EXECUTE v_sql;
    
	EXECUTE 'REVOKE ALL ON FUNCTION ' || table_version._ver_get_revision_function(p_schema, p_table) || ' FROM PUBLIC;';
	EXECUTE 'GRANT EXECUTE ON FUNCTION ' || table_version._ver_get_revision_function(p_schema, p_table) || ' TO bde_admin;';
	EXECUTE 'GRANT EXECUTE ON FUNCTION ' || table_version._ver_get_revision_function(p_schema, p_table) || ' TO bde_user;';

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

