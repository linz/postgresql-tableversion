
-- {
CREATE OR REPLACE FUNCTION ver_enable_versioning(
    v_table_oid       REGCLASS
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_schema          NAME;
    v_table           NAME;
    v_owner           NAME;
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

    SELECT nspname, relname, rolname
    INTO v_schema, v_table, v_owner
    FROM @extschema@._ver_get_table_info(v_table_oid);

    -- Check that SESSION_USER is the owner of the table, or
    -- refuse to enable versioning on this table
    IF NOT pg_has_role(session_user, v_owner, 'usage') THEN
        RAISE EXCEPTION 'User % cannot enable versioning on table %'
            ' for lack of usage privileges on table owner role %',
            session_user, v_table_oid, v_owner;
    END IF;

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
        RAISE EXCEPTION 'Table % does not have a unique non-compostite integer, bigint, text, or varchar column', v_table_oid::text;
    END IF;

    IF (SELECT count(*) <= 1 FROM information_schema.columns WHERE table_name= v_table AND table_schema = v_schema) THEN
        RAISE EXCEPTION 'Table % must contain at least one other non key column', v_table_oid::text;
    END IF;

    v_revision_table := @extschema@.ver_get_version_table_full(v_schema, v_table);
    
    v_sql :=
    'CREATE TABLE ' || v_revision_table || '(' ||
        '_revision_created INTEGER NOT NULL,' ||
        '_revision_expired INTEGER,' ||
        'LIKE ' || v_table_oid::text ||
    ');';
    BEGIN
      EXECUTE v_sql;
    EXCEPTION
    WHEN duplicate_table THEN
        RAISE EXCEPTION 'Table %.% is already versioned', quote_ident(v_schema), quote_ident(v_table);
    END;
    
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
        WHERE g.table_name = v_table
        AND   g.table_schema =  v_schema
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
        IF coalesce(current_setting('table_version.current_revision', TRUE), '') <> '' THEN
            v_revision := current_setting('table_version.current_revision', TRUE)::INTEGER;
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
    
    v_sql := 'CREATE INDEX ' || quote_ident('idx_' || v_table) || '_' || quote_ident(v_key_col) || ' ON ' || v_revision_table ||
        '(' || quote_ident(v_key_col) || ')';
    EXECUTE v_sql;

    v_sql := 'CREATE INDEX ' || quote_ident('fk_' || v_table) || '_expired ON ' || v_revision_table ||
        '(_revision_expired)';
    EXECUTE v_sql;

    v_sql := 'CREATE INDEX ' || quote_ident('fk_' || v_table) || '_created ON ' || v_revision_table ||
        '(_revision_created)';
    EXECUTE v_sql;
    
    EXECUTE 'ANALYSE ' || v_revision_table;

    SELECT
        id
    INTO
        v_table_id
    FROM
        @extschema@.versioned_tables
    WHERE
        schema_name = v_schema AND
        table_name = v_table;

    IF v_table_id IS NOT NULL THEN
        UPDATE @extschema@.versioned_tables
        SET    versioned = TRUE
        WHERE  schema_name = v_schema
        AND    table_name = v_table;
    ELSE
        INSERT INTO @extschema@.versioned_tables(schema_name, table_name, key_column, versioned)
        VALUES (v_schema, v_table, v_key_col, TRUE)
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

    PERFORM @extschema@.ver_create_table_functions(v_schema, v_table, v_key_col);
    PERFORM @extschema@.ver_create_version_trigger(v_table_oid, v_key_col);
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
--}

CREATE OR REPLACE FUNCTION ver_enable_versioning(p_schema NAME, p_table  NAME)
RETURNS BOOLEAN AS $$
  SELECT @extschema@.ver_enable_versioning(( p_schema || '.' || p_table)::regclass);
$$ LANGUAGE sql;

-- Abort drop of versioned tables.
CREATE OR REPLACE FUNCTION _ver_abort_drop_of_versioned_table()
RETURNS event_trigger AS $$
DECLARE
    obj RECORD;
BEGIN

    FOR obj IN SELECT *
               FROM pg_event_trigger_dropped_objects()
               WHERE object_type = 'table'
    LOOP
        IF @extschema@._ver_is_table_versioned(obj.schema_name, obj.object_name)
        THEN
            RAISE EXCEPTION
                'cannot drop versioned table %, unversion it first',
                obj.object_identity;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- NOTE: we need the DROP EVENT because CREATE OR REPLACE does not
--       exist for events. We _assume_ this script is being loaded
--       within a transaction (as done by table_version-loader)
--       so that the trigger will always be in effect.
DROP EVENT TRIGGER IF EXISTS _ver_abort_drop_of_versioned_table;
CREATE EVENT TRIGGER _ver_abort_drop_of_versioned_table
ON sql_drop EXECUTE PROCEDURE _ver_abort_drop_of_versioned_table();
