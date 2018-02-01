\set ECHO none
--------------------------------------------------------------------------------

-- postgresql-table_version - PostgreSQL table versioning extension
--
-- Copyright 2016 Crown copyright (c)
-- Land Information New Zealand and the New Zealand Government.
-- All rights reserved
--
-- This software is released under the terms of the new BSD license. See the 
-- LICENSE file for more information.
--
--------------------------------------------------------------------------------
-- Provide unit testing for table versioning system using pgTAP
--------------------------------------------------------------------------------

\i test/sql/preparedb

BEGIN;

SELECT plan(94);

SELECT has_schema( 'table_version' );
SELECT has_table( 'table_version', 'revision', 'Should have revision table' );
SELECT has_table( 'table_version', 'tables_changed', 'Should have tables_changed table' );
SELECT has_table( 'table_version', 'versioned_tables', 'Should have versioned_tables table' );
SELECT has_function( 'table_version', 'ver_complete_revision'::name );
SELECT has_function( 'table_version', 'ver_create_revision', ARRAY['text','timestamp without time zone','boolean'] );
SELECT has_function( 'table_version', 'ver_create_table_functions', ARRAY['name','name','name'] );
SELECT has_function( 'table_version', 'ver_create_version_trigger', ARRAY['name','name','name'] );
SELECT has_function( 'table_version', 'ver_delete_revision', ARRAY['integer'] );
SELECT has_function( 'table_version', 'ver_enable_versioning', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_disable_versioning', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_expandtemplate', ARRAY['text','text[]'] );
SELECT has_function( 'table_version', 'ver_get_last_revision'::name );
SELECT has_function( 'table_version', 'ver_get_modified_tables', ARRAY['integer'] );
SELECT has_function( 'table_version', 'ver_get_modified_tables', ARRAY['integer','integer'] );
SELECT has_function( 'table_version', 'ver_get_revision', ARRAY['timestamp without time zone'] );
SELECT has_function( 'table_version', 'ver_get_revision', ARRAY['integer'] );
SELECT has_function( 'table_version', 'ver_get_revisions', ARRAY['integer[]'] );
SELECT has_function( 'table_version', 'ver_get_revisions', ARRAY['timestamp without time zone','timestamp without time zone'] );
SELECT has_function( 'table_version', 'ver_get_table_base_revision', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_get_table_last_revision', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_get_version_table', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_get_version_table_full', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_get_versioned_table_key', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_get_versioned_tables'::name );
SELECT has_function( 'table_version', 'ver_is_table_versioned', ARRAY['name','name'] );
SELECT has_function( 'table_version', 'ver_versioned_table_change_column_type', ARRAY['name','name', 'name', 'text'] );
SELECT has_function( 'table_version', 'ver_versioned_table_add_column', ARRAY['name','name', 'name', 'text'] );
SELECT has_function( 'table_version', 'ver_versioned_table_drop_column', ARRAY['name', 'name', 'name'] );

CREATE SCHEMA foo;

CREATE TABLE foo.bar (
    id INTEGER NOT NULL PRIMARY KEY,
    d1 TEXT
);

INSERT INTO foo.bar (id, d1) VALUES
(1, 'foo bar 1'),
(2, 'foo bar 2'),
(3, 'foo bar 3');

SELECT ok(table_version.ver_enable_versioning('foo', 'bar'), 'Enable versioning on foo.bar');
SELECT ok(table_version.ver_is_table_versioned('foo', 'bar'), 'Check table is revisioned versioning on foo.bar');
SELECT is(table_version.ver_get_versioned_table_key('foo', 'bar'), 'id', 'Check table foo.bar table key');
SELECT is(table_version.ver_get_table_base_revision('foo', 'bar'), 1001, 'Check table base revision');

SELECT has_function( 'table_version', 'ver_get_foo_bar_revision', ARRAY['integer'] );
SELECT has_function( 'table_version', 'ver_get_foo_bar_diff', ARRAY['integer','integer'] );

SELECT set_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_revision(1001)',
    $$VALUES (1, 'foo bar 1'),(2, 'foo bar 2'),(3, 'foo bar 3')$$,
    'Check get table revision function API'
);

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1000, 1001) ORDER BY id',
    $$VALUES ('I'::char, 1, 'foo bar 1'),
             ('I'::char, 2, 'foo bar 2'),
             ('I'::char, 3, 'foo bar 3')$$,
    'Foo bar diff for table creation'
);

-- Edit 1 insert, update and delete
SELECT is(table_version.ver_create_revision('Foo bar edit 1'), 1002, 'Create edit 1 revision');

INSERT INTO foo.bar (id, d1) VALUES (4, 'foo bar 4');

UPDATE foo.bar
SET    d1 = 'foo bar 1 edit'
WHERE  id = 1;

DELETE FROM foo.bar
WHERE id = 3;

SELECT ok(table_version.ver_complete_revision(), 'Complete edit 1 revision');

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002) ORDER BY id',
    $$VALUES ('U'::char, 1, 'foo bar 1 edit'),
             ('D'::char, 3, 'foo bar 3'),
             ('I'::char, 4, 'foo bar 4')$$,
    'Foo bar diff for edit 1'
);

-- Edit 2 insert, update and delete
SELECT is(table_version.ver_create_revision('Foo bar edit 2'), 1003, 'Create edit 2 revision');

INSERT INTO foo.bar (id, d1) VALUES (5, 'foo bar 5');

UPDATE foo.bar
SET    d1 = 'foo bar 2 edit'
WHERE  id = 2;

UPDATE foo.bar
SET    d1 = 'foo bar 4 edit'
WHERE  id = 4;

DELETE FROM foo.bar
WHERE id = 1;

SELECT ok(table_version.ver_complete_revision(), 'Complete edit 2 revision');

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002) ORDER BY id',
    $$VALUES ('U'::char, 1, 'foo bar 1 edit'),
             ('D'::char, 3, 'foo bar 3'),
             ('I'::char, 4, 'foo bar 4')$$,
    'Foo bar diff for edit 1 (recheck)'
);


SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1002, 1003) ORDER BY id',
    $$VALUES ('D'::char, 1, 'foo bar 1 edit'),
             ('U'::char, 2, 'foo bar 2 edit'),
             ('U'::char, 4, 'foo bar 4 edit'),
             ('I'::char, 5, 'foo bar 5')$$,
    'Foo bar diff range for edit 1-2'
);

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1003) ORDER BY id',
    $$VALUES ('D'::char, 1, 'foo bar 1 edit'),
             ('U'::char, 2, 'foo bar 2 edit'),
             ('D'::char, 3, 'foo bar 3'),
             ('I'::char, 4, 'foo bar 4 edit'),
             ('I'::char, 5, 'foo bar 5')$$,
    'Foo bar diff for edit 2'
);

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1010) ORDER BY id',
    $$VALUES ('D'::char, 1, 'foo bar 1 edit'),
             ('U'::char, 2, 'foo bar 2 edit'),
             ('D'::char, 3, 'foo bar 3'),
             ('I'::char, 4, 'foo bar 4 edit'),
             ('I'::char, 5, 'foo bar 5')$$,
    'Foo bar diff for edit 2 (larger range parameter)'
);

-- Edit 3 delete that was added in test edit 2.
SELECT is(table_version.ver_create_revision('Foo bar edit 3'), 1004, 'Create edit 3 revision');

DELETE FROM foo.bar
WHERE id = 4;

SELECT ok(table_version.ver_complete_revision(), 'Complete edit 3 revision');

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1004) ORDER BY id',
    $$VALUES ('D'::char, 1, 'foo bar 1 edit'),
             ('U'::char, 2, 'foo bar 2 edit'),
             ('D'::char, 3, 'foo bar 3'),
             ('I'::char, 5, 'foo bar 5')$$,
    'Foo bar diff check to ensure a row created and deleted in between revisions is not returned'
);

-- Edit 4 add create another revision to check create/delete feature in between revision work
-- the delete is NOT the last revision.
SELECT is(table_version.ver_create_revision('Foo bar edit 4'), 1005, 'Create edit 4 revision');

INSERT INTO foo.bar (id, d1) VALUES (6, 'foo bar 6');

SELECT ok(table_version.ver_complete_revision(), 'Complete edit 4 revision');

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1004, 1005) ORDER BY id',
    $$VALUES ('I'::char, 6, 'foo bar 6')$$,
    'Foo bar diff for edit 4'
);

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1005) ORDER BY id',
    $$VALUES ('D'::char, 1, 'foo bar 1 edit'), 
             ('U'::char, 2, 'foo bar 2 edit'), 
             ('D'::char, 3, 'foo bar 3'), 
             ('I'::char, 5, 'foo bar 5'), 
             ('I'::char, 6, 'foo bar 6')$$,
    'Foo bar diff check to ensure a feature created and delete in between revision does not show (delete does not occur in last revision)'
);

-- Edit 4 re-insert a delete row
SELECT is(table_version.ver_create_revision('Foo bar edit 4'), 1006, 'Create edit 4 revision');

INSERT INTO foo.bar (id, d1) VALUES (1, 'foo bar 1 (re-insert)');

SELECT ok(table_version.ver_complete_revision(), 'Complete edit 4 revision');

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1005, 1006) ORDER BY id',
    $$VALUES ('I'::char, 1, 'foo bar 1 (re-insert)')$$,
    'Foo bar diff check re-insert a prevoiusly deleted row #1'
);

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1006) ORDER BY id',
    $$VALUES ('U'::char, 1, 'foo bar 1 (re-insert)'), 
             ('U'::char, 2, 'foo bar 2 edit'), 
             ('D'::char, 3, 'foo bar 3'), 
             ('I'::char, 5, 'foo bar 5'), 
             ('I'::char, 6, 'foo bar 6')$$,
    'Foo bar diff check re-insert a prevoiusly deleted row #2'
);

SELECT is(table_version.ver_versioned_table_change_column_type('foo', 'bar', 'd1', 'VARCHAR(100)'), TRUE, 'Change column datatype');

SELECT is(table_version.ver_versioned_table_add_column('foo', 'bar', 'baz', 'TEXT'), TRUE, 'Add column datatype');

SELECT is(table_version.ver_versioned_table_drop_column('foo', 'bar', 'baz'), TRUE, 'Drop column');

SELECT ok(table_version.ver_disable_versioning('foo', 'bar'), 'Disable versioning on foo.bar');

-- test versioning of table with text primary key
CREATE TABLE foo.bar2 (
    baz TEXT NOT NULL PRIMARY KEY,
    qux TEXT NOT NULL
);

INSERT INTO foo.bar2 (baz, qux) VALUES
('foo bar 1', 'qux1'),
('foo bar 2', 'qux2'),
('foo bar 3', 'qux3');

SELECT ok(table_version.ver_enable_versioning('foo', 'bar2'), 'Enable versioning of text primary key on foo.bar2');
SELECT ok(table_version.ver_is_table_versioned('foo', 'bar2'), 'Check table is revisioned versioning on foo.bar2');
SELECT is(table_version.ver_get_versioned_table_key('foo', 'bar2'), 'baz', 'Check table foo.bar table key');

-- Edit 1 insert, update and delete for text primary key
SELECT is(table_version.ver_create_revision('Foo bar2 edit'), 1008, 'Create edit text PK');

INSERT INTO foo.bar2 (baz, qux) VALUES ('foo bar 4', 'qux4');

UPDATE foo.bar2
SET    qux = 'qux1 edit'
WHERE  baz = 'foo bar 1';

DELETE FROM foo.bar2
WHERE baz = 'foo bar 3';

SELECT ok(table_version.ver_complete_revision(), 'Complete edit text PK');

SELECT results_eq(
    'SELECT * FROM table_version.ver_get_foo_bar2_diff(1007, 1008) ORDER BY baz',
    $$VALUES ('U'::char, 'foo bar 1', 'qux1 edit'),
             ('D'::char, 'foo bar 3', 'qux3'),
             ('I'::char, 'foo bar 4', 'qux4')$$,
    'Foo bar2 diff for text PK edit'
);

SELECT ok(table_version.ver_disable_versioning('foo', 'bar2'), 'Disable versioning on foo.bar2');

CREATE TABLE foo.bar3 (
    id INTEGER NOT NULL PRIMARY KEY,
    d1 TEXT
);

INSERT INTO foo.bar3 (id, d1) VALUES
(1, 'foo bar 1'),
(2, 'foo bar 2'),
(3, 'foo bar 3');

CREATE TABLE foo.bar4 (
    id INTEGER NOT NULL PRIMARY KEY,
    d1 TEXT
);

INSERT INTO foo.bar4 (id, d1) VALUES
(1, 'foo bar 1a'),
(2, 'foo bar 2a'),
(4, 'foo bar 4'),
(5, 'foo bar 5'),
(6, 'foo bar 6');

SELECT results_eq(
    $$SELECT * FROM
table_version.ver_get_table_differences('foo.bar3', 'foo.bar4', 'id') AS (action CHAR(1), ID INTEGER) ORDER BY 2$$,
    $$VALUES ('U'::CHAR, 1),
             ('U'::CHAR, 2),
             ('D'::CHAR, 3),
             ('I'::CHAR, 4),
             ('I'::CHAR, 5),
             ('I'::CHAR, 6)$$,
    'Diff function between foo3 and foo4'
);

SELECT results_eq(
    $$SELECT number_inserts, number_updates, number_deletes FROM table_version.ver_apply_table_differences('foo.bar3', 'foo.bar4', 'id')$$,
    $$VALUES (3::BIGINT, 2::BIGINT, 1::BIGINT)$$,
    'Apply diff to table function between foo3 and foo4'
);

CREATE ROLE test_owner;
CREATE ROLE test_user;

CREATE TABLE foo.bar5 (
    baz INTEGER NOT NULL PRIMARY KEY,
    qux TEXT
);

ALTER TABLE foo.bar5 OWNER TO test_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON foo.bar5 TO test_user;

SELECT ok(table_version.ver_enable_versioning('foo', 'bar5'), 'Enable versioning on table with permissions');

SELECT table_owner_is(
    'table_version', 'foo_bar5_revision', 'test_owner',
    'Test foo_bar5_revision ownership'
);

SELECT table_privs_are(
    'table_version', 'foo_bar5_revision', 'test_user', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
    'Test foo_bar5_revision permission for test_user'
);

SELECT ok(table_version.ver_disable_versioning('foo', 'bar5'), 'Disable versioning on foo.bar5');

DROP TABLE foo.bar;
DROP TABLE foo.bar2;
DROP TABLE foo.bar3;
DROP TABLE foo.bar4;
DROP TABLE foo.bar5;

-- See
-- https://github.com/linz/postgresql-tableversion/pull/32#issuecomment-319019821

CREATE SCHEMA "fOo";
CREATE SCHEMA "foO";

CREATE TABLE "fOo"."Bar3"("order","B") AS VALUES
(1, 'foo bar 1'),
(2, 'foo bar 2'),
(3, 'foo bar 3');
ALTER TABLE "fOo"."Bar3" ADD PRIMARY KEY("order");

CREATE TABLE "foO"."bAr4" ("order", "B") AS VALUES
(1, 'foo bar 1'),
(2, 'foo bar 2a'),
(4, 'foo bar 4');
ALTER TABLE "foO"."bAr4" ADD PRIMARY KEY("order");

SELECT results_eq(
    $$SELECT * FROM
table_version.ver_get_table_differences('"fOo"."Bar3"', '"foO"."bAr4"', 'order')
AS (action CHAR(1), ID INTEGER)$$,
    $$VALUES ('U'::CHAR, 2),
             ('D'::CHAR, 3),
             ('I'::CHAR, 4)$$,
    'Diff function between fOo.Bar3 and foO.bAr4'
);

ALTER TABLE "fOo"."Bar3" ADD u numeric unique;
ALTER TABLE "foO"."bAr4" ADD u numeric unique;

SELECT results_eq(
    $$SELECT * FROM
table_version.ver_get_table_differences('"fOo"."Bar3"', '"foO"."bAr4"', 'order')
AS (action CHAR(1), ID INTEGER)$$,
    $$VALUES ('U'::CHAR, 2),
             ('D'::CHAR, 3),
             ('I'::CHAR, 4)$$,
    'Diff function between fOo.Bar3 and foO.bAr4 (with unique column)'
);

DROP SCHEMA "fOo" CASCADE;
DROP SCHEMA "foO" CASCADE;

-- Test effects on dropping table

CREATE TABLE foo.dropme (id INTEGER NOT NULL PRIMARY KEY, d1 TEXT);
SELECT ok(table_version.ver_enable_versioning('foo', 'dropme'),
  'enable versioning on foo.dropme');
SELECT ok(table_version.ver_is_table_versioned('foo', 'dropme'),
  'foo.dropme is versioned');
SELECT set_has($$
  SELECT schema_name,table_name
  FROM table_version.ver_get_versioned_tables()
  $$, $$ VALUES ('foo','dropme') $$,
  'foo.dropme is returned by ver_get_versioned_tables'
);
SELECT is(table_version.ver_get_versioned_table_key('foo','dropme'),
  'id', 'foo.dropme versioned table key is "id"');
SELECT throws_like('DROP TABLE foo.dropme',
  'cannot drop%depend on it',
  'foo.dropme can only be drop with CASCADE') ;
DROP TABLE foo.dropme CASCADE;
SELECT ok(NOT table_version.ver_is_table_versioned('foo', 'dropme'),
  'foo.dropme is not versioned after drop cascade');
SELECT set_hasnt($$
  SELECT schema_name,table_name
  FROM table_version.ver_get_versioned_tables()
  $$, $$ VALUES ('foo','dropme') $$,
  'foo.dropme is not returned by ver_get_versioned_tables after drop'
);
SELECT is(table_version.ver_get_versioned_table_key('foo','dropme'),
  NULL, 'foo.dropme versioned table key is null after drop');
CREATE TABLE foo.dropme (id INTEGER NOT NULL PRIMARY KEY, d1 TEXT);
SELECT ok(NOT table_version.ver_is_table_versioned('foo', 'dropme'),
  'foo.dropme is not versioned after re-create');
SELECT set_hasnt($$
  SELECT schema_name,table_name
  FROM table_version.ver_get_versioned_tables()
  $$, $$ VALUES ('foo','dropme') $$,
  'foo.dropme is not returned by ver_get_versioned_tables after re-create'
);
SELECT is(table_version.ver_get_versioned_table_key('foo','dropme'),
  NULL, 'foo.dropme versioned table key is null after re-create');
SELECT ok(table_version.ver_enable_versioning('foo','dropme'),
  'can enable versioning on drop-recreated table foo.dropme');
SELECT ok(table_version.ver_is_table_versioned('foo', 'dropme'),
  'foo.dropme is versioned after re-create and ver_enable_versioning');
SELECT set_has($$
  SELECT schema_name,table_name
  FROM table_version.ver_get_versioned_tables()
  $$, $$ VALUES ('foo','dropme') $$,
  'foo.dropme is returned by ver_get_versioned_tables after re-create and ver_enable_versioning'
);
SELECT is(table_version.ver_get_versioned_table_key('foo','dropme'),
  'id', 'foo.dropme versioned table key is "id" after re-create and ver_enable_versioning');
-- TODO: test changing key !
SELECT throws_like(
  $$ SELECT table_version.ver_enable_versioning('foo','dropme') $$,
  'Table % is already versioned',
  'ver_enable_versioning throws when called on already-versioned table');

-- New in 1.3

SELECT has_function( 'table_version', 'ver_version'::name );

-- New in 1.4

SELECT has_function( 'table_version', 'ver_enable_versioning', ARRAY['regclass'] );

SELECT * FROM finish();

ROLLBACK;

