
CREATE OR REPLACE FUNCTION _ver_is_table_versioned(
    p_schema NAME,
    p_table  NAME
)
RETURNS BOOLEAN AS
$$
    SELECT EXISTS (
      SELECT
          versioned
      FROM
          @extschema@.versioned_tables
      WHERE
          schema_name = p_schema AND
          table_name = p_table
    )
$$ LANGUAGE sql STABLE;

-- {
CREATE OR REPLACE FUNCTION ver_is_table_versioned(
    p_schema NAME,
    p_table  NAME
)
RETURNS BOOLEAN AS
$$
DECLARE
    v_is_versioned BOOLEAN;
BEGIN
    v_is_versioned := @extschema@._ver_is_table_versioned(p_schema, p_table);

    IF v_is_versioned IS FALSE THEN
        RETURN FALSE;
    END IF;

    -- Check that table exists and triggers are in place;
    -- warn otherwise, see:
    -- https://github.com/linz/postgresql-tableversion/issues/57
    BEGIN
      v_is_versioned := EXISTS (
        SELECT *
      FROM pg_trigger t
      WHERE t.tgrelid = (quote_ident(p_schema) || '.' || quote_ident(p_table) )::regclass
        AND t.tgname = p_schema || '_' || p_table || '_revision_trg'
      );
    EXCEPTION
      WHEN UNDEFINED_TABLE THEN
        RAISE WARNING 'Table %.% does not exist', p_schema, p_table;
        RETURN FALSE;
      WHEN OTHERS THEN
        RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
    END;

    IF NOT v_is_versioned THEN
        RAISE WARNING 'Table %.% is known as versioned but lacks versioning triggers',
          p_schema, p_table
        USING HINT = 'use ver_create_version_trigger to recover';
    END IF;

    RETURN v_is_versioned;
END;
$$ LANGUAGE plpgsql STABLE;
-- }

