
CREATE OR REPLACE FUNCTION ver_complete_revision() RETURNS BOOLEAN AS
$$
DECLARE
    v_user_name TEXT;

BEGIN
    IF coalesce(current_setting('table_version.current_revision', TRUE), '') = '' THEN
        RAISE EXCEPTION 'No in-progress revision';
        RETURN FALSE;
    END IF;

    SELECT user_name
    FROM @extschema@.revision r
    WHERE r.id = current_setting('table_version.current_revision', TRUE)::INTEGER
    INTO v_user_name;

    IF NOT pg_has_role(session_user, v_user_name, 'usage') THEN
        RAISE EXCEPTION 'In-progress revision can only be completed '
                        'by its creator user %', v_user_name;
    END IF;
    
    PERFORM set_config('table_version.current_revision', '', FALSE);
    PERFORM set_config('table_version.manual_revision', '', FALSE);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

