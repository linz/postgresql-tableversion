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
\set ECHO none
\set QUIET true
\set VERBOSITY verbose
\pset format unaligned
\pset tuples_only true

SET client_min_messages TO WARNING;

BEGIN;

CREATE EXTENSION table_version;
CREATE EXTENSION pgtap;

SELECT plan(55);

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
SELECT ok(table_version.ver_disable_versioning('foo', 'bar'), 'Disable versioning on foo.bar');

SELECT * FROM finish();

ROLLBACK;

