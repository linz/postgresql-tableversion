
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
    SELECT @extschema@._ver_create_revision(p_comment, p_revision_time, p_schema_change)
    INTO v_revision;
    PERFORM set_config('table_version.manual_revision', 't', FALSE);
    RETURN v_revision;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;



CREATE OR REPLACE FUNCTION _ver_create_revision(
    p_comment       TEXT, 
    p_revision_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    p_schema_change BOOLEAN DEFAULT FALSE
) 
RETURNS INTEGER AS
$$
DECLARE
    v_revision @extschema@.revision.id%TYPE;
BEGIN
    IF coalesce(current_setting('table_version.manual_revision', TRUE), '') <> '' AND
        coalesce(current_setting('table_version.current_revision', TRUE), '') <> ''
    THEN
        RAISE EXCEPTION 'A revision changeset is still in progress. Please complete the revision before starting a new one';
    END IF;

    INSERT INTO @extschema@.revision (revision_time, schema_change, comment, user_name)
    VALUES (p_revision_time, p_schema_change, p_comment, SESSION_USER)
    RETURNING id INTO v_revision;

    PERFORM set_config('table_version.current_revision', v_revision::VARCHAR, FALSE);
    RETURN v_revision;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
