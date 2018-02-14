-- Test for https://github.com/linz/postgresql-tableversion/issues/77
CREATE TABLE t77 (k int primary key, v text);
SELECT 't77-pre.1', table_version.ver_enable_versioning('public', 't77');
SELECT 't77-pre.2', table_version.ver_create_revision('t77 r1');
SELECT 't77-pre.3', table_version.ver_complete_revision();

