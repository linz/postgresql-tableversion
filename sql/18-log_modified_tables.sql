
CREATE OR REPLACE FUNCTION ver_log_modified_tables()
RETURNS VOID
AS $$
DECLARE
    v_version_table VARCHAR;
    v_rec RECORD;
BEGIN

    TRUNCATE table_version.tables_changed;
    FOR v_rec IN SELECT id, schema_name, table_name
                 FROM table_version.versioned_tables
                 WHERE versioned
    LOOP
        v_version_table := @extschema@.ver_get_version_table(
                                v_rec.schema_name,
                                v_rec.table_name);
        EXECUTE format('INSERT INTO "@extschema@"."tables_changed"'
            '(table_id, revision) '
            'SELECT %1$L::int, rev FROM ( '
            '  SELECT _revision_created rev '
            '    FROM "@extschema@".%2$I UNION'
            '  SELECT _revision_expired rev '
            '    FROM "@extschema@".%2$I '
            ') foo '
            '  WHERE rev IS NOT NULL',
            v_rec.id, v_version_table
            );
    END LOOP;

END;
$$ LANGUAGE plpgsql;

