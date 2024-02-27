
CREATE OR REPLACE FUNCTION ver_delete_revision(
    p_revision INTEGER
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_user_name TEXT;
BEGIN
    SELECT user_name
        FROM @extschema@.revision
        WHERE id = p_revision
        INTO v_user_name;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF NOT pg_has_role(session_user, v_user_name, 'usage') THEN
        RAISE WARNING 'Can not delete revision % created by user %',
                       p_revision, v_user_name;
        RETURN FALSE;
    END IF;

    IF coalesce(current_setting('table_version.current_revision', TRUE), '') <> ''
    THEN
        IF current_setting('table_version.current_revision', TRUE)::INTEGER = p_revision THEN
            RAISE WARNING 'Revision % is in progress, please complete it'
                          ' before attempting to delete it.', p_revision;
            RETURN FALSE;
        END IF;
    END IF;

    BEGIN
        DELETE FROM @extschema@.revision
        WHERE id = p_revision;
        return TRUE;
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE WARNING 'Can not delete revision % as it is referenced by other tables: %', p_revision, SQLERRM;
            RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

