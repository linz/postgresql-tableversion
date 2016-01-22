/**
* Completed a revision. This must be called after a revision is created.
*
* @return                 Return if the revision was sucessfully completed.
*/
CREATE OR REPLACE FUNCTION ver_complete_revision() RETURNS BOOLEAN AS
$$
BEGIN
    IF NOT table_version._ver_get_reversion_temp_table('_changeset_revision') THEN
        RETURN FALSE;
    END IF;

    DROP TABLE _changeset_revision;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

