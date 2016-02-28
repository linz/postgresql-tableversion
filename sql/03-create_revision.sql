
CREATE OR REPLACE FUNCTION ver_create_revision(
    p_comment       TEXT, 
    p_revision_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    p_schema_change BOOLEAN DEFAULT FALSE
) 
RETURNS INTEGER AS
$$
DECLARE
    v_revision table_version.revision.id%TYPE;
BEGIN
    IF table_version._ver_get_reversion_temp_table('_changeset_revision') THEN
        RAISE EXCEPTION 'A revision changeset is still in progress. Please complete the revision before starting a new one';
    END IF;

    INSERT INTO table_version.revision (revision_time, schema_change, comment, user_name)
    VALUES (p_revision_time, p_schema_change, p_comment, CURRENT_USER)
    RETURNING id INTO v_revision;
    
    CREATE TEMP TABLE _changeset_revision(
        revision INTEGER NOT NULL PRIMARY KEY
    );
    INSERT INTO _changeset_revision(revision) VALUES (v_revision);
    ANALYSE _changeset_revision;
    
    RETURN v_revision;
END;
$$ LANGUAGE plpgsql;
