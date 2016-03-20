
CREATE OR REPLACE FUNCTION ver_complete_revision() RETURNS BOOLEAN AS
$$
BEGIN
    IF NOT @extschema@._ver_get_reversion_temp_table('_changeset_revision') THEN
        RETURN FALSE;
    END IF;
    
    DROP TABLE _changeset_revision;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

