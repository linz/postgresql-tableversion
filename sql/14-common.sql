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
    v_sql := @extschema@.ver_ExpandTemplate( p_template, p_params );
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
    SELECT '@extschema@.' || @extschema@.ver_get_version_table($1, $2);
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
    SELECT ('@extschema@.' || quote_ident('ver_get_' || $1 || '_' || $2 || '_diff') || '(p_revision1 INTEGER, p_revision2 INTEGER)');
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
    SELECT ('@extschema@.' || quote_ident('ver_get_' || $1 || '_' || $2 || '_revision') || '(p_revision INTEGER)');
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
$$ LANGUAGE plpgsql;

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

CREATE TYPE ATTRIBUTE AS (
    att_name NAME,
    att_type NAME,
    att_not_null BOOLEAN
);

CREATE OR REPLACE FUNCTION ver_get_table_differences(
    p_table1      REGCLASS,
    p_table2      REGCLASS,
    p_compare_key NAME
)
RETURNS SETOF RECORD
AS $$
DECLARE
    v_table_1_cols  @extschema@.ATTRIBUTE[];
    v_table_1_uniq  @extschema@.ATTRIBUTE[];
    v_table_2_cols  @extschema@.ATTRIBUTE[];
    v_common_cols   @extschema@.ATTRIBUTE[];
    v_unique_cols   @extschema@.ATTRIBUTE[];
    v_sql           TEXT;
    v_table_cur1    REFCURSOR;
    v_table_cur2    REFCURSOR;
    v_table_record1 RECORD;
    v_table_record2 RECORD;
    v_i             INT8;
    v_diff_count    INT8;
    v_error         TEXT;
    v_return        RECORD;
BEGIN
    IF p_table1 = p_table2 THEN
        RETURN;
    END IF;

    v_sql := '';

    IF NOT @extschema@.ver_table_key_is_valid(p_table1, p_compare_key) THEN
        RAISE EXCEPTION
            '''%'' is not a unique non-compostite integer, bigint, text, or varchar column for %',
            p_compare_key, CAST(p_table1 AS TEXT);
    END IF;

    IF NOT @extschema@.ver_table_key_is_valid(p_table2, p_compare_key) THEN
        RAISE EXCEPTION
            '''%'' is not a  unique non-compostite integer, bigint, text, or varchar column for %',
            p_compare_key, CAST(p_table2 AS TEXT);
    END IF;
    
    SELECT @extschema@._ver_get_table_columns(p_table1)
    INTO v_table_1_cols;
    
    SELECT @extschema@._ver_get_table_columns(p_table2)
    INTO v_table_2_cols;
    
    SELECT @extschema@._ver_get_table_unique_constraint_columns(p_table1)
    INTO v_table_1_uniq;

    SELECT ARRAY(
        SELECT ROW(ATT.att_name, ATT.att_type, ATT.att_not_null) 
        FROM   unnest(v_table_1_cols) AS ATT 
        WHERE  ATT.att_name IN 
            (SELECT (unnest(v_table_2_cols)).att_name)
        AND ATT.att_name NOT IN
            (SELECT (unnest(v_table_1_uniq)).att_name)
        AND ATT.att_name <> p_compare_key
    )
    INTO v_common_cols;

    SELECT ARRAY(
        SELECT ROW(ATT.att_name, ATT.att_type, ATT.att_not_null) 
        FROM   unnest(v_table_1_cols) AS ATT 
        WHERE  ATT.att_name IN 
            (SELECT (unnest(v_table_2_cols)).att_name)
        AND ATT.att_name IN
            (SELECT (unnest(v_table_1_uniq)).att_name)
        AND ATT.att_name <> p_compare_key
    )
    INTO v_unique_cols;
    
    SELECT @extschema@._ver_get_compare_select_sql(
        p_table1, p_compare_key, v_common_cols, v_unique_cols
    )
    INTO v_sql;
    OPEN v_table_cur1 NO SCROLL FOR EXECUTE v_sql;
    
    SELECT @extschema@._ver_get_compare_select_sql(
        p_table2, p_compare_key, v_common_cols, v_unique_cols
    )
    INTO v_sql;
    OPEN v_table_cur2 NO SCROLL FOR EXECUTE v_sql;
    v_sql := '';
    
    FETCH FIRST FROM v_table_cur1 INTO v_table_record1;
    FETCH FIRST FROM v_table_cur2 INTO v_table_record2;
    
    v_i := 0;
    v_diff_count := 0;
    WHILE v_table_record1 IS NOT NULL AND v_table_record2 IS NOT NULL LOOP
        IF v_table_record1.id < v_table_record2.id THEN
            SELECT 'D'::CHAR(1) AS action, v_table_record1.id INTO v_return;
            v_diff_count := v_diff_count + 1;
            RETURN NEXT v_return;
            FETCH NEXT FROM v_table_cur1 INTO v_table_record1;
            CONTINUE;
        ELSIF v_table_record2.id < v_table_record1.id THEN
            SELECT 'I'::CHAR(1) AS action, v_table_record2.id INTO v_return;
            v_diff_count := v_diff_count + 1;
            RETURN NEXT v_return;
            FETCH NEXT FROM v_table_cur2 INTO v_table_record2;
            CONTINUE;
        ELSIF v_table_record1.check_uniq <> v_table_record2.check_uniq THEN
            SELECT 'X'::CHAR(1) AS action, v_table_record1.id INTO v_return;
            v_diff_count := v_diff_count + 1;
            RETURN NEXT v_return;
        ELSIF v_table_record1.check_sum <> v_table_record2.check_sum THEN
            SELECT 'U'::CHAR(1) AS action, v_table_record1.id INTO v_return;
            v_diff_count := v_diff_count + 1;
            RETURN NEXT v_return;
        END IF;
        FETCH NEXT FROM v_table_cur1 INTO v_table_record1;
        FETCH NEXT FROM v_table_cur2 INTO v_table_record2;
        v_i := v_i + 1;
        IF (v_i % 100000 = 0) THEN
            RAISE DEBUG 'Compared % records, % differences', v_i, v_diff_count;
        END IF;
    END LOOP;

    WHILE v_table_record1 IS NOT NULL LOOP
        SELECT 'D'::CHAR(1) AS action, v_table_record1.id INTO v_return;
        RETURN NEXT v_return;
        FETCH NEXT FROM v_table_cur1 INTO v_table_record1;
    END LOOP;
    
    WHILE v_table_record2 IS NOT NULL LOOP
        SELECT 'I'::CHAR(1) AS action, v_table_record2.id INTO v_return;
        RETURN NEXT v_return;
        FETCH NEXT FROM v_table_cur2 INTO v_table_record2;
    END LOOP;
    
    CLOSE v_table_cur1;
    CLOSE v_table_cur2;
    
    RETURN;
EXCEPTION
    WHEN others THEN
        GET STACKED DIAGNOSTICS v_error = PG_EXCEPTION_CONTEXT;
        RAISE EXCEPTION E'Failed comparing tables\n%\nERROR: %', v_error, SQLERRM;
END;
$$ LANGUAGE plpgsql;
    
CREATE OR REPLACE FUNCTION ver_apply_table_differences(
    p_original_table   REGCLASS,
    p_new_table        REGCLASS,
    p_key_column       NAME,
    OUT number_inserts BIGINT,
    OUT number_deletes BIGINT,
    OUT number_updates BIGINT
)
AS $$
DECLARE
    v_nuniqf  BIGINT DEFAULT 0;
BEGIN
    
    RAISE NOTICE 'Generating difference data for %', p_original_table;
    
    PERFORM @extschema@.ver_ExecuteTemplate( $sql$
        CREATE TEMP TABLE table_diff AS
        SELECT
            T.id,
            T.action
        FROM
            @extschema@.ver_get_table_differences(
                '%1%', '%2%', '%3%'
            ) AS T (action CHAR(1), id %4%)
        ORDER BY
            T.action,
            T.id;
        $sql$,
        ARRAY[
            p_original_table::TEXT,
            p_new_table::TEXT,
            p_key_column::TEXT,
            @extschema@.ver_table_key_datatype(p_original_table, p_key_column)
        ]
    );
    
    RAISE NOTICE 'Completed generating difference data for %', p_original_table;
    
    ALTER TABLE table_diff ADD PRIMARY KEY (id);
    ANALYSE table_diff;
    
    SELECT * FROM @extschema@._ver_apply_changes(
        p_original_table, p_new_table, 'table_diff', p_key_column
    )
    INTO number_deletes, number_inserts, number_updates;

    DROP TABLE table_diff;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;
            
            
CREATE OR REPLACE FUNCTION _ver_apply_changes(
    p_original_table REGCLASS,
    p_new_table REGCLASS,
    p_diff_table NAME,
    p_key_column NAME,
    OUT number_inserts BIGINT,
    OUT number_deletes BIGINT,
    OUT number_updates BIGINT
)
    AS $$
DECLARE
    v_nuniqf  BIGINT DEFAULT 0;
    v_count   BIGINT;
BEGIN

    number_inserts := 0;
    number_deletes := 0;
    number_updates := 0;
    
    EXECUTE 'SELECT 1 FROM ' || p_diff_table || ' LIMIT 1'
    INTO v_count;
   
    IF v_count THEN
        EXECUTE 'SELECT count(*) FROM ' || p_diff_table || ' WHERE action=' || quote_literal('X')
        INTO v_nuniqf;
        
        IF v_nuniqf > 0 THEN
            RAISE NOTICE
                '% updates changed to delete/insert in % to avoid potential uniqueness constraint errors',
                v_nuniqf, p_original_table;
        END IF;
        
        RAISE NOTICE 'Deleting from % using difference data', p_original_table;
        
        number_deletes := @extschema@._ver_apply_inc_delete(
            p_original_table, p_diff_table, p_key_column
        );
        
        RAISE NOTICE 'Updating % using difference data', p_original_table;
        
        number_updates :=  @extschema@._ver_apply_inc_update(
            p_original_table, p_diff_table, p_new_table, p_key_column
        );
        
        RAISE NOTICE 'Inserting into % using difference data', p_original_table;
        
        number_inserts := @extschema@._ver_apply_inc_insert(
            p_original_table, p_diff_table, p_new_table, p_key_column
        );
        
        RAISE NOTICE 'Finished updating % using difference data', p_original_table;

        number_deletes := number_deletes - v_nuniqf;
        number_inserts := number_inserts - v_nuniqf;
        number_updates := number_updates + v_nuniqf;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION _ver_apply_inc_delete(
    p_delete_table REGCLASS,
    p_inc_change_table NAME,
    p_key_column NAME
)
RETURNS
    BIGINT
AS
$$
BEGIN
    RETURN @extschema@.ver_ExecuteTemplate( $sql$
        DELETE FROM %1% AS T
        USING %2% AS INC
        WHERE T.%3% = INC.id
        AND  INC.action IN ('D','X')
        $sql$,
        ARRAY[p_delete_table::text,p_inc_change_table,quote_ident(p_key_column)]
    );
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _ver_apply_inc_update(
    p_update_table REGCLASS,
    p_inc_change_table NAME,
    p_inc_data_table REGCLASS,
    p_key_column NAME
)
RETURNS
    BIGINT
AS
$$
DECLARE
    v_sql TEXT;
    v_update_col_txt TEXT;
    v_table_cols @extschema@.ATTRIBUTE[];
    v_col @extschema@.ATTRIBUTE;
BEGIN
    v_table_cols := @extschema@._ver_get_table_columns(p_update_table);
    IF v_table_cols IS NULL THEN
        RAISE EXCEPTION 'Could not find any table columns for %',
            p_update_table;
    END IF;
    
    v_update_col_txt := '';
    FOR v_col IN SELECT * FROM unnest(v_table_cols) LOOP
        IF v_update_col_txt != '' THEN
            v_update_col_txt := v_update_col_txt || ',';
        END IF;
        v_update_col_txt := v_update_col_txt || quote_ident(v_col.att_name) ||
            ' = NEW_DAT.' || quote_ident(v_col.att_name);
    END LOOP;
    
    RETURN @extschema@.ver_ExecuteTemplate( $sql$
        UPDATE %1% AS CUR
        SET %2%
        FROM %3% AS NEW_DAT,
             %4% AS INC
        WHERE INC.id = CUR.%5% 
        AND   NEW_DAT.%5% = CUR.%5%
        AND   INC.action = 'U'
        $sql$,
        ARRAY[
            p_update_table::text,
            v_update_col_txt,
            p_inc_data_table::text,
            p_inc_change_table,
            quote_ident(p_key_column)
        ]
    );
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _ver_apply_inc_insert(
    p_insert_table REGCLASS,
    p_inc_change_table NAME,
    p_inc_data_table REGCLASS,
    p_key_column NAME
)
RETURNS
    BIGINT
AS
$$
DECLARE
    v_table_cols text;
BEGIN
    SELECT array_to_string(array_agg(quote_ident(att_name)), ',') 
    INTO v_table_cols
    FROM unnest(@extschema@._ver_get_table_columns(p_insert_table));
        
    IF v_table_cols = '' THEN
        RAISE EXCEPTION 'Could not find any table columns for %',
            p_insert_table;
    END IF;
    
    RETURN @extschema@.ver_ExecuteTemplate( $sql$
        INSERT INTO %1% (%2%)
        SELECT %2% FROM %3%
        WHERE %4% IN
          (SELECT id FROM %5% WHERE action IN ('I','X'))
        $sql$,
        ARRAY[
            p_insert_table::text,
            v_table_cols,
            p_inc_data_table::text,
            quote_ident(p_key_column),
            p_inc_change_table
        ]
    );
END;
$$
LANGUAGE plpgsql;
    
CREATE OR REPLACE FUNCTION ver_table_key_datatype(
    p_table      REGCLASS,
    p_key_column NAME
)
RETURNS TEXT AS
$$
    SELECT
        format_type(ATT.atttypid, NULL)
    FROM
        pg_index IDX,
        pg_attribute ATT
    WHERE
        IDX.indrelid = $1 AND
        ATT.attrelid = $1 AND
        ATT.attnum = ANY(IDX.indkey) AND
        ATT.attnotnull = TRUE AND
        IDX.indisunique = TRUE AND
        IDX.indexprs IS NULL AND
        IDX.indpred IS NULL AND
        array_length(IDX.indkey::INTEGER[], 1) = 1 AND
        LOWER(ATT.attname) = LOWER($2)
    ORDER BY
        IDX.indisprimary DESC;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION ver_table_key_is_valid(
    p_table      REGCLASS,
    p_key_column NAME
)
RETURNS BOOLEAN AS
$$
    SELECT EXISTS (
        SELECT
            TRUE
        FROM
            pg_index IDX,
            pg_attribute ATT
        WHERE
            IDX.indrelid = $1 AND
            ATT.attrelid = $1 AND
            ATT.attnum = ANY(IDX.indkey) AND
            ATT.attnotnull = TRUE AND
            IDX.indisunique = TRUE AND
            IDX.indexprs IS NULL AND
            IDX.indpred IS NULL AND
            format_type(ATT.atttypid, NULL) IN (
                'integer', 'bigint', 'text', 'character varying'
            ) AND
            array_length(IDX.indkey::INTEGER[], 1) = 1 AND
            LOWER(ATT.attname) = LOWER($2)
        ORDER BY
            IDX.indisprimary DESC
    );
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION _ver_get_compare_select_sql(
    p_table       REGCLASS,
    p_key_column  NAME,
    p_columns     @extschema@.ATTRIBUTE[],
    p_unique_cols @extschema@.ATTRIBUTE[]
)
RETURNS TEXT AS 
$$
BEGIN
    RETURN @extschema@.ver_ExpandTemplate( $sql$
        SELECT 
           %1% AS ID,
           CAST(%2% AS TEXT) AS check_sum,
           CAST(%3% AS TEXT) AS check_uniq
        FROM 
           %4% AS T
        ORDER BY
           %1% ASC
        $sql$,
        ARRAY[
            quote_ident(p_key_column),
            @extschema@._ver_get_compare_sql(p_columns,'T'),
            @extschema@._ver_get_compare_sql(p_unique_cols,'T'),
            p_table::text
            ]);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _ver_get_compare_sql(
    p_columns     @extschema@.ATTRIBUTE[],
    p_table_alias TEXT
)
RETURNS TEXT AS 
$$
DECLARE
    v_sql          TEXT;
    v_col_name     NAME;
    v_col_type     TEXT;
    v_col_not_null BOOLEAN;
BEGIN
    IF array_ndims(p_columns) IS NULL THEN
        RETURN quote_literal('');
    END IF;
    v_sql := '';
    FOR v_col_name, v_col_type, v_col_not_null IN
        SELECT
            att_name,
            att_type,
            att_not_null
        FROM
            unnest(p_columns)
        ORDER BY
            att_name,
            att_type,
            att_not_null
    LOOP
        IF v_sql != '' THEN
            v_sql := v_sql || ' || ';
        END IF;

        IF v_col_not_null THEN
            v_sql := v_sql || '''|V'' || ' || 'CAST(' || p_table_alias ||
                '.' || quote_ident(v_col_name) || ' AS TEXT)';
        ELSE
            v_sql := v_sql || 'COALESCE(''V|'' || CAST(' || p_table_alias ||
                '.' || quote_ident(v_col_name) || ' AS TEXT), ''|N'')';
        END IF;
    END LOOP;

    RETURN v_sql;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION _ver_get_table_unique_constraint_columns(
    p_table REGCLASS,
    p_key_column NAME = NULL,
    p_return_comp_keys BOOLEAN = TRUE
)
RETURNS @extschema@.ATTRIBUTE[] AS
$$
    SELECT array_agg(
        CAST((attname, type, attnotnull) AS @extschema@.ATTRIBUTE)
    )
    FROM
        (
        SELECT
            ATT.attname,
            format_type(ATT.atttypid, ATT.atttypmod) as type,
            ATT.attnotnull
        FROM
            pg_index IDX,
            pg_attribute ATT
        WHERE
            ATT.attrelid = $1 AND
            (p_key_column IS NULL OR ATT.attname <> $2) AND
            IDX.indrelid = ATT.attrelid AND
            IDX.indisunique = TRUE AND
            IDX.indexprs IS NULL AND
            IDX.indpred IS NULL AND
            ATT.attnum IN (
                SELECT IDX.indkey[i]
                FROM   generate_series(0, IDX.indnatts) AS i
                WHERE  ($3 OR array_length(IDX.indkey,1) = 1)
            )
        UNION
        SELECT
            ATT.attname,
            format_type(ATT.atttypid, ATT.atttypmod) as type,
            ATT.attnotnull
        FROM
            pg_attribute ATT
        WHERE
            ATT.attnum > 0 AND
            (p_key_column IS NULL OR ATT.attname <> $2) AND
            NOT ATT.attisdropped AND
            ATT.attrelid = $1 AND
            ATT.attnum IN
            (SELECT unnest(conkey)
             FROM pg_constraint
             WHERE 
                conrelid = p_table AND
                contype in ('p','u') AND
                ($3 OR array_length(conkey,1) = 1))
    ) AS ATT
$$ LANGUAGE sql;


-- Return a list of columns for a table as an array of ATTRIBUTE entries

CREATE OR REPLACE FUNCTION _ver_get_table_columns(
    p_table REGCLASS
)
RETURNS @extschema@.ATTRIBUTE[] AS
$$
    SELECT array_agg(
        CAST((ATT.attname, format_type(ATT.atttypid, ATT.atttypmod), 
         ATT.attnotnull) AS @extschema@.ATTRIBUTE))
    FROM
        pg_attribute ATT
    WHERE
        ATT.attnum > 0 AND
        NOT ATT.attisdropped AND
        ATT.attrelid = p_table;
$$ LANGUAGE sql;

