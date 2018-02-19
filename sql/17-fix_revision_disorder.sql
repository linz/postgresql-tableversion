--
-- Change ID of any revision having start_time at a later time than
-- any other revision with higher ID
--
-- New IDs for revisions to be moved will be assigned in
-- start_time order and start after the highest existing
-- revision ID.
--
-- The number of moved revisions is returned.
--
-- {
CREATE OR REPLACE FUNCTION ver_fix_revision_disorder()
RETURNS bigint AS
$FIX$
DECLARE

  v_rec RECORD;
  v_newid bigint;
  v_numversionedtables int;
  v_totdisordered bigint;
  v_numdisordered bigint;

BEGIN

-- 1. Make sure sequence is set to stop filling gaps

  PERFORM setval('@extschema@.revision_id_seq',
    greatest(
      (select max(id) FROM @extschema@.revision),
      (select last_value from @extschema@.revision_id_seq)
    ), true);

-- 2. Prepare update queries
  v_numversionedtables := 0;
  FOR v_rec IN SELECT schema_name, table_name
               FROM table_version.versioned_tables
  LOOP
    BEGIN
      EXECUTE format('PREPARE "p_uc%s" AS '
          'UPDATE table_version.%s_%s_revision '
          'SET _revision_created = $1 WHERE _revision_created = $2',
          v_numversionedtables, v_rec.schema_name, v_rec.table_name);
      EXECUTE format('PREPARE "p_ue%s" AS '
          'UPDATE table_version.%s_%s_revision '
          'SET _revision_created = $1 WHERE _revision_created = $2',
          v_numversionedtables, v_rec.schema_name, v_rec.table_name);
      v_numversionedtables := v_numversionedtables + 1;
    EXCEPTION WHEN UNDEFINED_TABLE THEN

      RAISE WARNING 'Spurious record in table_version.versioned_tables '
                    'for table % in schema %: % does not exist)',
                    v_rec.table_name, v_rec.schema_name,
                    format('table_version.%s_%s_revision',
                      v_rec.schema_name, v_rec.table_name);
    END;
  END LOOP;

-- 3. For each misplaced revision, move to correct place

  v_totdisordered := 0;

  LOOP

    v_numdisordered := 0;

    FOR v_rec IN
      WITH revs_by_id AS (
        SELECT
          row_number() OVER (ORDER BY id) seq,
          id,
          start_time
        FROM
          table_version.revision
      ),
      revs_by_time AS (
        SELECT
          row_number() OVER (ORDER BY start_time) seq,
          id,
          start_time
        FROM
          table_version.revision
      )
      SELECT
          a.id,
          a.start_time atm,
          b.id as bi,
          b.start_time btm
        FROM revs_by_id a, revs_by_time b
       WHERE a.seq = b.seq
         AND a.id < b.id
         AND a.start_time > b.start_time
       ORDER by a.start_time

    LOOP

      -- Revision v_rec.id has to be moved to nextval('@extschema@.revision_id_seq');

      v_numdisordered := v_numdisordered + 1;

      -- Create new revision v_record

      INSERT INTO @extschema@.revision
        (id, revision_time, start_time, user_name, schema_change, comment)
      SELECT
        nextval('@extschema@.revision_id_seq'::regclass),
        revision_time, start_time, user_name, schema_change,
        comment
      FROM @extschema@.revision
        WHERE id = v_rec.id
      RETURNING id
      INTO v_newid;

      RAISE NOTICE 'Revision % has start_time %, while % has start_time %: renamed % to %',
        v_rec.id, v_rec.atm, v_rec.bi, v_rec.btm, v_rec.id, v_newid;

      -- Update @extschema@.tables_changed

      UPDATE @extschema@.tables_changed
        SET revision = v_newid
        WHERE revision = v_rec.id;
        
      -- Update all revisions of all revisioned tables


      FOR v_i IN 0..v_numversionedtables-1
      LOOP
        EXECUTE format('EXECUTE "p_uc%s"(%s, %s)', v_i, v_newid, v_rec.id);
        EXECUTE format('EXECUTE "p_ue%s"(%s, %s)', v_i, v_newid, v_rec.id);
      END LOOP;

      -- Delete now hopefully unreferenced old revision

      DELETE FROM @extschema@.revision WHERE id = v_rec.id;

    END LOOP;

    v_totdisordered := v_totdisordered + v_numdisordered;

    IF v_numdisordered = 0 THEN
      EXIT;
    END IF;

  END LOOP;

-- 4. Deallocate prepared update queries
  FOR i IN 0..v_numversionedtables-1
  LOOP
    EXECUTE format('DEALLOCATE "p_uc%s"', i);
    EXECUTE format('DEALLOCATE "p_ue%s"', i);
  END LOOP;

  RETURN v_totdisordered;

END;
$FIX$
LANGUAGE 'plpgsql' VOLATILE;
--}
