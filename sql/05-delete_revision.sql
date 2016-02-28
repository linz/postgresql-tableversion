
CREATE OR REPLACE FUNCTION ver_delete_revision(
    p_revision INTEGER
) 
RETURNS BOOLEAN AS
$$
DECLARE
    v_status BOOLEAN;
BEGIN
    BEGIN
        DELETE FROM table_version.revision
        WHERE id = p_revision;
        v_status := FOUND;
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE WARNING 'Can not delete revision % as it is referenced by other tables', p_revision;
            v_status := FALSE;
    END;
    RETURN v_status;
END;
$$ LANGUAGE plpgsql;

