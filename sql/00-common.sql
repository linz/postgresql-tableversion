-- {
CREATE OR REPLACE FUNCTION _ver_get_table_info(regclass)
RETURNS TABLE (nspname name, relname name, rolname name) AS $$
    SELECT
      n.nspname, c.relname, r.rolname
    FROM
      pg_namespace n, pg_class c, pg_roles r
    WHERE
      c.oid = $1
    AND
      r.oid = c.relowner
    AND
      n.oid = c.relnamespace;
$$ LANGUAGE 'sql';
--}
