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

-- Remove any existing FKs.

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

    IF (SELECT count(*) <= 1 FROM information_schema.columns WHERE table_name= p_table AND table_schema = p_schema) THEN
        RAISE EXCEPTION 'Table %.% must contain at least one other non key column', quote_ident(p_schema), quote_ident(p_table);
    END IF;

    v_revision_table := @extschema@.ver_get_version_table_full(p_schema, p_table);
    
    v_sql :=
    'CREATE TABLE ' || v_revision_table || '(' ||
        '_revision_created INTEGER NOT NULL,' ||
        '_revision_expired INTEGER,' ||
        'LIKE ' || quote_ident(p_schema) || '.' || quote_ident(p_table) ||
    ');';
    EXECUTE v_sql;
    
    v_sql := 'ALTER TABLE ' || v_revision_table || ' OWNER TO ' || 
        @extschema@._ver_get_table_owner(v_table_oid);
    EXECUTE v_sql;
    
    -- replicate permissions from source table to revision history table
    FOR v_role, v_privilege IN
        SELECT CASE WHEN g.grantee = 'PUBLIC'
                   THEN 'public'
                   ELSE g.grantee
               END as grantee,
               g.privilege_type
        FROM information_schema.role_table_grants g
        WHERE g.table_name = p_table
        AND   g.table_schema =  p_schema
    LOOP
        EXECUTE 'GRANT ' || v_privilege || ' ON TABLE ' || v_revision_table || 
            ' TO ' || quote_ident(v_role);
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


CREATE OR REPLACE FUNCTION ver_versioned_table_drop_column(
    p_schema_name NAME,
    p_table_name  NAME,
    p_column_name NAME
)
RETURNS BOOLEAN AS
$$
DECLARE
    v_key_col NAME;
    v_trigger_name TEXT;
    v_revision_table TEXT;
BEGIN
    IF NOT @extschema@.ver_is_table_versioned(p_schema_name, p_table_name) THEN
        RAISE EXCEPTION 'Table %.% is not versioned', quote_ident(p_schema_name), quote_ident(p_table_name);
    END IF;

    v_revision_table := @extschema@.ver_get_version_table_full(p_schema_name, p_table_name);
    v_trigger_name := @extschema@._ver_get_version_trigger(p_schema_name, p_table_name);

    EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' || quote_ident(p_table_name) ||      ' DISABLE TRIGGER ' || v_trigger_name;
    EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' || quote_ident(p_table_name) ||      ' DROP COLUMN ' || quote_ident(p_column_name);
    EXECUTE 'ALTER TABLE ' || v_revision_table      || ' DROP COLUMN ' || quote_ident(p_column_name);
    EXECUTE 'ALTER TABLE ' || quote_ident(p_schema_name) || '.' || quote_ident(p_table_name) ||      ' ENABLE TRIGGER ' || v_trigger_name;
    
    SELECT
        key_column
    INTO
        v_key_col
    FROM 
        @extschema@.versioned_tables
    WHERE
        schema_name = p_schema_name AND
        table_name = p_table_name;
    
    PERFORM @extschema@.ver_create_table_functions(p_schema_name, p_table_name, v_key_col);
    PERFORM @extschema@.ver_create_version_trigger(p_schema_name, p_table_name, v_key_col);
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
