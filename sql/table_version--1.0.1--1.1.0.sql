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

-- Provide public select right to metadata tables

GRANT SELECT ON TABLE revision TO public;
GRANT SELECT ON TABLE versioned_tables TO public;
GRANT SELECT ON TABLE tables_changed TO public;

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
        @extschema@.revision
    WHERE
        id = $1
$$ LANGUAGE sql;

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
        @extschema@.revision
    WHERE
        id = ANY($1)
    ORDER BY
        revision DESC;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION ver_enable_versioning(
    p_schema NAME,
    p_table  NAME
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_table_oid       REGCLASS;
    v_key_col         NAME;
    v_revision_table  TEXT;
    v_sql             TEXT;
    v_table_id        @extschema@.versioned_tables.id%TYPE;
    v_revision        @extschema@.revision.id%TYPE;
    v_revision_exists BOOLEAN;
    v_table_has_data  BOOLEAN;
    v_role            TEXT;
    v_privilege       TEXT;
BEGIN
    IF NOT EXISTS (SELECT * FROM pg_tables WHERE tablename = p_table AND schemaname = p_schema) THEN
        RAISE EXCEPTION 'Table %.% does not exists', quote_ident(p_schema), quote_ident(p_table);
    END IF;

    IF @extschema@.ver_is_table_versioned(p_schema, p_table) THEN
        RAISE EXCEPTION 'Table %.% is already versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;

    SELECT
        CLS.oid
    INTO
        v_table_oid
    FROM
        pg_namespace NSP,
        pg_class CLS
    WHERE
        NSP.nspname = p_schema AND
        CLS.relname = p_table AND
        NSP.oid     = CLS.relnamespace;

    SELECT
        ATT.attname as col
    INTO
        v_key_col
    FROM
        pg_index IDX,
        pg_attribute ATT
    WHERE
        IDX.indrelid = v_table_oid AND
        ATT.attrelid = v_table_oid AND
        ATT.attnum = ANY(IDX.indkey) AND
        ATT.attnotnull = TRUE AND
        IDX.indisunique = TRUE AND
        IDX.indexprs IS NULL AND
        IDX.indpred IS NULL AND
        format_type(ATT.atttypid, NULL) IN ('integer', 'bigint', 'text', 'character varying') AND
        array_length(IDX.indkey::INTEGER[], 1) = 1
    ORDER BY
        IDX.indisprimary DESC
    LIMIT 1;

    IF v_key_col IS NULL THEN
        RAISE EXCEPTION 'Table %.% does not have a unique non-compostite integer, bigint, text, or varchar column', quote_ident(p_schema), quote_ident(p_table);
    END IF;

    v_revision_table := @extschema@.ver_get_version_table_full(p_schema, p_table);
    
    v_sql :=
    'CREATE TABLE ' || v_revision_table || '(' ||
        '_revision_created INTEGER NOT NULL REFERENCES @extschema@.revision,' ||
        '_revision_expired INTEGER REFERENCES @extschema@.revision,' ||
        'LIKE ' || quote_ident(p_schema) || '.' || quote_ident(p_table) ||
    ');';
    EXECUTE v_sql;
    
    v_sql := 'ALTER TABLE ' || v_revision_table || ' OWNER TO ' || 
        @extschema@._ver_get_table_owner(v_table_oid);
    EXECUTE v_sql;
    
    -- replicate permissions from source table to revision history table
    FOR v_role, v_privilege IN
        SELECT g.grantee, g.privilege_type
        FROM information_schema.role_table_grants g
        WHERE g.table_name = p_table
        AND   g.table_schema =  p_schema
    LOOP
        EXECUTE 'GRANT ' || v_privilege || ' ON TABLE ' || v_revision_table || 
            ' TO ' || v_role;
    END LOOP;
        
    v_sql := (
        SELECT
            'ALTER TABLE  ' || v_revision_table || ' ALTER COLUMN ' || attname || ' SET STATISTICS ' ||  attstattarget
        FROM
            pg_attribute 
        WHERE
            attrelid = v_table_oid AND
            attname = v_key_col AND
            attisdropped IS FALSE AND
            attnum > 0 AND
            attstattarget > 0
    );
    IF v_sql IS NOT NULL THEN
        EXECUTE v_sql;
    END IF;
    
    -- insert base data into table using a revision that is currently in
    -- progress, or if one does not exist create one.
    
    v_revision_exists := FALSE;
    
    EXECUTE 'SELECT EXISTS (SELECT * FROM ' || CAST(v_table_oid AS TEXT) || ' LIMIT 1)'
    INTO v_table_has_data;
    
    IF v_table_has_data THEN
        IF @extschema@._ver_get_reversion_temp_table('_changeset_revision') THEN
            SELECT
                max(VER.revision)
            INTO
                v_revision
            FROM
                _changeset_revision VER;
            
            v_revision_exists := TRUE;
        ELSE
            SELECT @extschema@.ver_create_revision(
                'Initial revisioning of ' || CAST(v_table_oid AS TEXT)
            )
            INTO  v_revision;
        END IF;
    
        v_sql :=
            'INSERT INTO ' || v_revision_table ||
            ' SELECT ' || v_revision || ', NULL, * FROM ' || CAST(v_table_oid AS TEXT);
        EXECUTE v_sql;
        
        IF NOT v_revision_exists THEN
            PERFORM @extschema@.ver_complete_revision();
        END IF;
    
    END IF;

    v_sql := 'ALTER TABLE  ' || v_revision_table || ' ADD CONSTRAINT ' ||
        quote_ident('pkey_' || v_revision_table) || ' PRIMARY KEY(_revision_created, ' ||
        quote_ident(v_key_col) || ')';
    EXECUTE v_sql;
    
    v_sql := 'CREATE INDEX ' || quote_ident('idx_' || p_table) || '_' || quote_ident(v_key_col) || ' ON ' || v_revision_table ||
        '(' || quote_ident(v_key_col) || ')';
    EXECUTE v_sql;

    v_sql := 'CREATE INDEX ' || quote_ident('fk_' || p_table) || '_expired ON ' || v_revision_table ||
        '(_revision_expired)';
    EXECUTE v_sql;

    v_sql := 'CREATE INDEX ' || quote_ident('fk_' || p_table) || '_created ON ' || v_revision_table ||
        '(_revision_created)';
    EXECUTE v_sql;
    
    EXECUTE 'ANALYSE ' || v_revision_table;

    -- Add dependency of the revision table on the newly versioned table 
    -- to avoid simple drop. Some people might forget that the table is
    -- versioned!
    
    INSERT INTO pg_catalog.pg_depend(
        classid,
        objid,
        objsubid,
        refclassid,
        refobjid,
        refobjsubid,
        deptype
    )
    SELECT
        cat.oid,
        fobj.oid,
        0,
        cat.oid,
        tobj.oid,
        0,
        'n'
    FROM
        pg_class cat, 
        pg_namespace fnsp, 
        pg_class fobj,
        pg_namespace tnsp,
        pg_class tobj
    WHERE
        cat.relname = 'pg_class' AND
        fnsp.nspname = 'table_version' AND
        fnsp.oid = fobj.relnamespace AND
        fobj.relname = @extschema@.ver_get_version_table(p_schema, p_table) AND
        tnsp.nspname = p_schema AND
        tnsp.oid = tobj.relnamespace AND
        tobj.relname   = p_table;

    SELECT
        id
    INTO
        v_table_id
    FROM
        @extschema@.versioned_tables
    WHERE
        schema_name = p_schema AND
        table_name = p_table;
    
    IF v_table_id IS NOT NULL THEN
        UPDATE @extschema@.versioned_tables
        SET    versioned = TRUE
        WHERE  schema_name = p_schema
        AND    table_name = p_table;
    ELSE
        INSERT INTO @extschema@.versioned_tables(schema_name, table_name, key_column, versioned)
        VALUES (p_schema, p_table, v_key_col, TRUE)
        RETURNING id INTO v_table_id;
    END IF;
    
    IF v_table_id IS NOT NULL AND v_table_has_data THEN
        INSERT INTO @extschema@.tables_changed(
            revision,
            table_id
        )
        SELECT
            v_revision,
            v_table_id
        WHERE
            NOT EXISTS (
                SELECT *
                FROM   @extschema@.tables_changed
                WHERE  table_id = v_table_id
                AND    revision = v_revision
        );
    END IF;

    PERFORM @extschema@.ver_create_table_functions(p_schema, p_table, v_key_col);
    PERFORM @extschema@.ver_create_version_trigger(p_schema, p_table, v_key_col);
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ver_create_revision(
    p_comment       TEXT, 
    p_revision_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    p_schema_change BOOLEAN DEFAULT FALSE
) 
RETURNS INTEGER AS
$$
DECLARE
    v_revision @extschema@.revision.id%TYPE;
BEGIN
    IF @extschema@._ver_get_reversion_temp_table('_changeset_revision') THEN
        RAISE EXCEPTION 'A revision changeset is still in progress. Please complete the revision before starting a new one';
    END IF;

    INSERT INTO @extschema@.revision (revision_time, schema_change, comment, user_name)
    VALUES (p_revision_time, p_schema_change, p_comment, SESSION_USER)
    RETURNING id INTO v_revision;
    
    CREATE TEMP TABLE _changeset_revision(
        revision INTEGER NOT NULL PRIMARY KEY
    );
    INSERT INTO _changeset_revision(revision) VALUES (v_revision);
    ANALYSE _changeset_revision;
    
    RETURN v_revision;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- remove security definer from sll functions and functions that create fuunctions

DO $$
DECLARE
   v_pcid    TEXT;
   v_schema  TEXT = '@extschema@';
BEGIN
    FOR v_pcid IN 
        SELECT v_schema || '.' || proname || '(' || pg_get_function_identity_arguments(oid) || ')'
        FROM pg_proc 
        WHERE pronamespace=(SELECT oid FROM pg_namespace WHERE nspname = v_schema)
        AND proname NOT IN ('ver_create_revision', 'ver_complete_revision')
    LOOP
        EXECUTE 'ALTER FUNCTION ' || v_pcid z || ' SECURITY INVOKER';
    END LOOP;
END;
$$;

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
    IF NOT @extschema@.ver_is_table_versioned(p_schema, p_table) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;
    
    v_revision_table := @extschema@.ver_get_version_table_full(p_schema, p_table);
    v_table_columns := '';
    v_select_columns_diff := '';
    v_select_columns_rev := '';
    
    OPEN v_col_cur FOR
    SELECT att_name AS column_name, att_type AS column_type
    FROM unnest(@extschema@._ver_get_table_columns(p_schema || '.' ||  p_table));

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
        IF NOT @extschema@.ver_is_table_versioned(%schema_name%, %table_name%) THEN
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
        
        SELECT @extschema@.ver_get_table_base_revision(%schema_name%, %table_name%)
        INTO   v_base_version;
        IF v_base_version > v_revision2 THEN
            RETURN;
        END IF;
        
        RETURN QUERY EXECUTE
        @extschema@.ver_ExpandTemplate(
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
$FUNC$ LANGUAGE plpgsql;

    $template$;
    
    v_sql := REPLACE(v_sql, '%func_sig%',       @extschema@._ver_get_diff_function(p_schema, p_table));
    v_sql := REPLACE(v_sql, '%table_columns%',  v_table_columns);
    v_sql := REPLACE(v_sql, '%schema_name%',    quote_literal(p_schema));
    v_sql := REPLACE(v_sql, '%table_name%',     quote_literal(p_table));
    v_sql := REPLACE(v_sql, '%full_table_name%', quote_ident(p_schema) || '.' || quote_ident(p_table));
    v_sql := REPLACE(v_sql, '%select_columns%', v_select_columns_diff);
    v_sql := REPLACE(v_sql, '%key_col%',        quote_ident(p_key_col));
    v_sql := REPLACE(v_sql, '%revision_table%', v_revision_table);
    
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@._ver_get_diff_function(p_schema, p_table);
    EXECUTE v_sql;

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
    @extschema@.ver_ExpandTemplate(
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
$FUNC$ LANGUAGE plpgsql;

    $template$;
    
    v_sql := REPLACE(v_sql, '%func_sig%', @extschema@._ver_get_revision_function(p_schema, p_table));
    v_sql := REPLACE(v_sql, '%table_columns%', v_table_columns);
    v_sql := REPLACE(v_sql, '%select_columns%', v_select_columns_rev);
    v_sql := REPLACE(v_sql, '%revision_table%', v_revision_table);
    
    EXECUTE 'DROP FUNCTION IF EXISTS ' || @extschema@._ver_get_revision_function(p_schema, p_table);
    EXECUTE v_sql;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ver_create_version_trigger(
    p_schema  NAME,
    p_table   NAME,
    p_key_col NAME
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_revision_table TEXT;
    v_sql            TEXT;
    v_trigger_name   VARCHAR;
    v_column_name    NAME;
    v_column_update  TEXT;
BEGIN
    IF NOT @extschema@.ver_is_table_versioned(p_schema, p_table) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema), quote_ident(p_table);
    END IF;
    
    v_revision_table := @extschema@.ver_get_version_table_full(p_schema, p_table);
    
    v_column_update := '';
    FOR v_column_name IN
        SELECT att_name AS column_name
        FROM unnest(@extschema@._ver_get_table_columns(p_schema || '.' ||  p_table))
    LOOP
        IF v_column_name = p_key_col THEN
            CONTINUE;
        END IF;
        IF v_column_update != '' THEN
            v_column_update := v_column_update || E',\n                        ';
        END IF;
        
        v_column_update := v_column_update || quote_ident(v_column_name) || ' = NEW.' 
            || quote_ident(v_column_name);
    END LOOP;
    
    v_sql := $template$

CREATE OR REPLACE FUNCTION %revision_table%() RETURNS trigger AS $TRIGGER$
    DECLARE
       v_revision      @extschema@.revision.id%TYPE;
       v_last_revision @extschema@.revision.id%TYPE;
       v_table_id      @extschema@.versioned_tables.id%TYPE;
    BEGIN
        BEGIN
            SELECT
                max(VER.revision)
            INTO
                v_revision
            FROM
                _changeset_revision VER;
                
            IF v_revision IS NULL THEN
                RAISE EXCEPTION 'Versioning system information is missing';
            END IF;
        EXCEPTION
            WHEN undefined_table THEN
                RAISE EXCEPTION 'To begin editing %full_table_name% you need to create a revision';
        END;

        SELECT
            VTB.id
        INTO
            v_table_id
        FROM
            @extschema@.versioned_tables VTB
        WHERE
            VTB.table_name = %table_name% AND
            VTB.schema_name = %schema_name%;
        
        IF v_table_id IS NULL THEN
            RAISE EXCEPTION 'Table versioning system information is missing for %full_table_name%';
        END IF;

        IF NOT EXISTS (
            SELECT TRUE
            FROM   @extschema@.tables_changed
            WHERE  table_id = v_table_id
            AND    revision = v_revision
        )
        THEN
            INSERT INTO @extschema@.tables_changed(revision, table_id)
            VALUES (v_revision, v_table_id);
        END IF;

        
        IF (TG_OP <> 'INSERT') THEN
            SELECT 
                _revision_created INTO v_last_revision
            FROM 
                %revision_table%
            WHERE 
                %key_col% = OLD.%key_col% AND
                _revision_expired IS NULL;

            IF v_last_revision = v_revision THEN
                IF TG_OP = 'UPDATE' AND OLD.%key_col% = NEW.%key_col% THEN
                    UPDATE
                        %revision_table%
                    SET
                        %revision_update_cols%
                    WHERE
                        %key_col% = NEW.%key_col% AND
                        _revision_created = v_revision AND
                        _revision_expired IS NULL;
                    RETURN NEW;
                ELSE
                    DELETE FROM 
                        %revision_table%
                    WHERE
                        %key_col% = OLD.%key_col% AND
                        _revision_created = v_last_revision;
                END IF;
            ELSE
                UPDATE
                    %revision_table%
                SET
                    _revision_expired = v_revision
                WHERE
                    %key_col% = OLD.%key_col% AND
                    _revision_created = v_last_revision;
            END IF;
        END IF;

        IF( TG_OP <> 'DELETE') THEN
            INSERT INTO %revision_table%
            SELECT v_revision, NULL, NEW.*;
            RETURN NEW;
        END IF;
        
        RETURN NULL;
    END;
$TRIGGER$ LANGUAGE plpgsql SECURITY DEFINER;

    $template$;

    v_sql := REPLACE(v_sql, '%schema_name%',    quote_literal(p_schema));
    v_sql := REPLACE(v_sql, '%table_name%',     quote_literal(p_table));
    v_sql := REPLACE(v_sql, '%full_table_name%', quote_ident(p_schema) || '.' || quote_ident(p_table));
    v_sql := REPLACE(v_sql, '%key_col%',        quote_ident(p_key_col));
    v_sql := REPLACE(v_sql, '%revision_table%', v_revision_table);
    v_sql := REPLACE(v_sql, '%revision_update_cols%', v_column_update);
    
    EXECUTE v_sql;

    SELECT @extschema@._ver_get_version_trigger(p_schema, p_table)
    INTO v_trigger_name;
    

    EXECUTE 'DROP TRIGGER IF EXISTS '  || v_trigger_name || ' ON ' ||  
        quote_ident(p_schema) || '.' || quote_ident(p_table);

    EXECUTE 'CREATE TRIGGER '  || v_trigger_name || ' AFTER INSERT OR UPDATE OR DELETE ON ' ||  
        quote_ident(p_schema) || '.' || quote_ident(p_table) ||
        ' FOR EACH ROW EXECUTE PROCEDURE ' || v_revision_table || '()';
    
    EXECUTE 'ALTER FUNCTION ' || v_revision_table || '() ' ||
        'OWNER TO ' || @extschema@._ver_get_table_owner((p_schema || '.' || p_table)::REGCLASS);
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

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

DROP FUNCTION table_version._ver_get_table_cols(NAME, NAME);

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

