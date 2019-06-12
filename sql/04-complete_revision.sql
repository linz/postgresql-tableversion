
CREATE OR REPLACE FUNCTION ver_complete_revision() RETURNS BOOLEAN AS
$$
DECLARE
    v_user_name TEXT;

BEGIN
    IF NOT @extschema@._ver_get_reversion_temp_table('_changeset_revision') THEN
        RETURN FALSE;
    END IF;

    SELECT user_name
        FROM @extschema@.revision r, _changeset_revision t
        WHERE r.id = t.revision
        INTO v_user_name;

    IF NOT pg_has_role(session_user, v_user_name, 'usage') THEN
        RAISE EXCEPTION 'In-progress revision can only be completed '
                        'by its creator user %', v_user_name;
    END IF;
    
    DROP TABLE _changeset_revision;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

