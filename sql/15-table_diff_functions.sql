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

DO $$ BEGIN IF NOT EXISTS (
  SELECT t.oid
  FROM pg_type t, pg_namespace n
  WHERE n.oid = t.typnamespace
    AND n.nspname = '@extschema@'
    AND t.typname = 'attribute'
) THEN
  CREATE TYPE ATTRIBUTE AS (
      att_name NAME,
      att_type NAME,
      att_not_null BOOLEAN
  );
END IF;
END; $$;

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
    v_error         TEXT;
    v_geom_col      TEXT;
BEGIN
    IF p_table1 = p_table2 THEN
        RETURN;
    END IF;

    v_sql := '';

    IF NOT @extschema@.ver_table_key_is_valid(p_table1, p_compare_key) THEN
        RAISE EXCEPTION
            '''%'' is not a unique non-composite integer, bigint, text, or varchar column for %',
            p_compare_key, CAST(p_table1 AS TEXT);
    END IF;

    IF NOT @extschema@.ver_table_key_is_valid(p_table2, p_compare_key) THEN
        RAISE EXCEPTION
            '''%'' is not a  unique non-composite integer, bigint, text, or varchar column for %',
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
    
    v_sql := table_version.ver_ExpandTemplate( $sql$
	SELECT
	    CASE WHEN t2.%1% IS NULL THEN
		    CAST('D' AS CHAR(1))
	    WHEN t1.%1% IS NULL THEN
		    CAST('I' AS CHAR(1))
	    WHEN CAST(%2% AS TEXT) <> CAST(%2% AS TEXT) THEN
		    CAST('X' AS CHAR(1))
	    ELSE
		    CAST('U' AS CHAR(1))
	    END AS action,
	    CASE WHEN t2.%1% IS NULL THEN
		    t1.%1%
	    ELSE
		    t2.%1%
	    END AS id
	FROM
	    (SELECT %3% FROM %4%) AS t1
	    FULL OUTER JOIN
	    (SELECT %3% FROM %5%) AS t2
	    ON t2.%1% = t1.%1%
	WHERE
	    t1.%1% IS NULL OR
	    t2.%1% IS NULL OR
	    CAST(%2% AS TEXT) <> CAST(%2% AS TEXT) OR
	    NOT COALESCE(t1.* = t2.*, FALSE)
        $sql$,
        ARRAY[
            quote_ident(p_compare_key),
            @extschema@._ver_get_compare_sql(v_unique_cols,'T'),
            (SELECT array_to_string(array_agg(att_name), ',') att_name FROM unnest(v_common_cols)),
            p_table1::TEXT,
            p_table2::TEXT
        ]
    );
    
    FOR v_geom_col IN
        SELECT att_name
        FROM   unnest(v_common_cols)
        WHERE  att_type LIKE 'geometry%'
    LOOP
        -- binary compare of PostGIS geometry including SRID (faster than text compare)
        v_sql := v_sql || ' OR ST_AsEWKB(t1.' || v_geom_col || ') <> ST_AsEWKB(t2.' || v_geom_col || ')';
    END LOOP;

    RAISE DEBUG 'diff sql = %', v_sql;

    RETURN QUERY EXECUTE v_sql;
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
