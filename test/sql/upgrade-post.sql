-- Test for https://github.com/linz/postgresql-tableversion/issues/77
SELECT 't77-post.0', table_version.ver_create_revision('t77 r2');
SELECT 't77-post.1', table_version.ver_complete_revision();
SELECT 't77-post.3', table_version.ver_disable_versioning('public', 't77');

-- Cleanup

DELETE FROM table_version.tables_changed where revision in (1001, 1002);
DELETE FROM table_version.revision where id in (1001, 1002);
DROP TABLE t77;
SELECT 't77-pre.0', setval('table_version.revision_id_seq',  1000, true);
