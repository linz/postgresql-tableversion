/**
* Create a new revision within the curernt SQL session. This must be called before INSERTS, UPDATES OR DELETES
* can occur on a versioned table.
*
* @param p_comment        A comment for revision.
* @param p_revision_time  The the datetime of the revision in terms of a business context.
* @param p_schema_change  Does this revision implement a schema change.
* @return                 The identifier for the new revision.
* @throws RAISE_EXCEPTION If a revision is still in progress within the current SQL session.
*/
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
        RAISE EXCEPTION 'A revision changeset is still in progress. Please complete the changeset before starting a new one';
    END IF;

    INSERT INTO table_version.revision (revision_time, schema_change, comment)
    VALUES (p_revision_time, p_schema_change, p_comment)
    RETURNING id INTO v_revision;
    
    CREATE TEMP TABLE _changeset_revision(
        revision INTEGER NOT NULL PRIMARY KEY
    );
    INSERT INTO _changeset_revision(revision) VALUES (v_revision);
    ANALYSE _changeset_revision;
    
    RETURN v_revision;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
