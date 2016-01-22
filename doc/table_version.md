table_version
=============

Synopsis
--------

    #= CREATE EXTENSION table_version;
    CREATE EXTENSION
    
    #= CREATE TABLE foo.bar (
        id INTEGER NOT NULL PRIMARY KEY,
        d1 TEXT
    );
    CREATE TABLE
    
    #= SELECT table_version.ver_enable_versioning('foo', 'bar');
     ver_enable_versioning 
    -----------------------
     t

    SELECT table_version.ver_create_revision('My test edit');
     ver_create_revision 
    ---------------------
                    1001

    #= INSERT INTO foo.bar (id, d1) VALUES
    (1, 'foo bar 1'),
    (2, 'foo bar 2'),
    (3, 'foo bar 3');
    INSERT 0 3

    #= SELECT table_version.ver_complete_revision(); 
     ver_complete_revision 
    -----------------------
     t
    
    #= SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002);
     _diff_action | id |    d1
    --------------+----+-----------
     I            |  3 | foo bar 3
     I            |  1 | foo bar 1
     I            |  2 | foo bar 2
    
Description
-----------

PostgreSQL table versioning extension, recording row modifications and its history.
The extension provides APIs for accessing snapshots of a table at certain revisions
and the difference generated between any two given revisions. The extension uses
a trigger based system and PL/PgSQL functions to record and provide access to the
row revisions. Note this extension only records changes at the row level and does
revision schema changes or allow for row version branching. 

Purpose
-------

This extension was created to store table data revisions in a data warehouse
environment. The primarly use case was to import bulk difference data from an
external system on a daily basis and record all of those daily revisions.
The design decision to maintain the version history data in a completely separate
table from the current data table (instead of just having a view) was driven by
performance reasons. Also note the roots of this extension were developed before
materialised view were a real option in PostgreSQL. In any case 

Table Prerequisites
-------------------

To enable versioning on a table the following conditions must be met:

- The table must have a have a unique non-composite integer column
- The table must not be temporary

How it works
------------

When a table is versioned the original table data is left untouched and a new
revision table is created with all the same fields plus a "_revsion_created"
and "_revision_expired" field. A row level trigger is then setup on the original
table and whenever an insert, update and delete statement is run the change
is recorded in the table's revision data table. 

Usage
-----

Take the following example. We have a table 'bar' in schema 'foo' and insert
some data:

    CREATE EXTENSION table_version;
    
    CREATE SCHEMA foo;

    CREATE TABLE foo.bar (
        id INTEGER NOT NULL PRIMARY KEY,
        d1 TEXT
    );

    INSERT INTO foo.bar (id, d1) VALUES
    (1, 'foo bar 1'),
    (2, 'foo bar 2'),
    (3, 'foo bar 3');

Then to enable versioning on a table you need to run the following command:

    SELECT table_version.ver_enable_versioning('foo', 'bar');

After you have run this command a trigger 'table_version.foo_bar_revision()'
should have been created on the foo.bar table. Also the
"table_version.foo_bar_revision" table is created to store the revision
data. If you execute a select from the table you can see the base revision
data:

    SELECT * FROM table_version.foo_bar_revision;
    
     _revision_created | _revision_expired | id |    d1
    -------------------+-------------------+----+-----------
                  1001 |                   |  1 | foo bar 1
                  1001 |                   |  2 | foo bar 2
                  1001 |                   |  3 | foo bar 3
    (3 rows)
    

After the table has been versioned and you want to edit some data you
must first start a revision, do the edits and then complete the revision. i.e:

    SELECT table_version.ver_create_revision('My test edit');

    -- now do some edits
    INSERT INTO foo.bar (id, d1) VALUES (4, 'foo bar 4');
    
    UPDATE foo.bar
    SET    d1 = 'foo bar 1 edit'
    WHERE  id = 1;
    
    DELETE FROM foo.bar
    WHERE id = 3;

    SELECT table_version.ver_complete_revision(); 


Now you should have some more edits in table_version.foo_bar_revision table:

    SELECT * FROM table_version.foo_bar_revision;

     _revision_created | _revision_expired | id |       d1
    -------------------+-------------------+----+----------------
                  1001 |                   |  2 | foo bar 2
                  1002 |                   |  4 | foo bar 4
                  1001 |              1002 |  1 | foo bar 1
                  1002 |                   |  1 | foo bar 1 edit
                  1001 |              1002 |  3 | foo bar 3
    (5 rows)

If we want to get the changed data from one revision to another (in this case
from 1001 to 1002) we run:

    SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002);

     _diff_action | id |       d1
    --------------+----+----------------
     U            |  1 | foo bar 1 edit
     D            |  3 | foo bar 3
     I            |  4 | foo bar 4
    (3 rows)

As you can see the updates are recorded below. The '_diff_action' column
indicates the type of modification:

- 'U' = Update
- 'D' = Delete
- 'I' = Insert

If you would like to gain access to a snapshot of the data at a given time
then call the following function:

    SELECT * FROM table_version.ver_get_foo_bar_revision(1001);
    
     id |    d1
    ----+-----------
      2 | foo bar 2
      1 | foo bar 1
      3 | foo bar 3
    (3 rows)

Finally if you would like to remove versioning for the table call:

    SELECT table_version.ver_disable_versioning('foo', 'bar');

Replicate data using table differences
--------------------------------------

If you would like to maintain a copy of table data on a remote system this is
easily done with this revision system. Here the steps:

1. First you need to determine which tables are versioned:

    SELECT * FROM table_version.ver_get_versioned_tables();

     schema_name | table_name | key_column
    -------------+------------+------------
     foo         | bar        | id
    (1 row)
    
2. Next you need to determine which revisions you what to replicate to your
system:

    SELECT table_version.ver_get_table_base_revision('foo', 'bar');

     ver_get_table_base_revision
    -----------------------------
                             1001
    (1 row)

3. Now determine all of the revisions have been applied to the table.

    SELECT
        id,
        revision_time
    FROM
        table_version.ver_get_revisions(
            ARRAY(
                SELECT generate_series(
                    table_version.ver_get_table_base_revision('foo', 'bar'),
                    table_version.ver_get_last_revision()
                )
            )
        )
    ORDER BY
       id ASC;

      id  |      revision_time
    ------+-------------------------
     1001 | 2011-03-11 16:14:49.062
     1002 | 2011-03-11 16:15:22.578
    (2 rows)

5. The first data copy operation is to create a base snapshot of the table data:

    CREATE TABLE foo_bar_copy AS
    SELECT * FROM table_version.ver_get_foo_bar_revision(
        table_version.ver_get_table_base_revision('foo', 'bar')
    );


4. Now to maintain your base copy you can select an difference change set and
then apply that to your base copy:
    
    -- Where 'my_last_revision' is the last revision that your dataset has on
    -- your remote system
    SELECT * FROM table_version.ver_get_foo_bar_diff(
        my_last_revision,
        table_version.ver_get_table_last_revision('foo', 'bar')
    );


Configuration tables
--------------------

The extension creates the following configuration tables:

- table_version.revision
- table_version.tables_changed
- table_version.versioned_tables

Whenever a new table is setup for versioning or an versioned table is edited the
metadata of that transacation is recorded in these tables. When databases using
the table_version extension are dumped that data from these configuration tables
are also dumped to ensure the patch history data is persisted.

**WARNING**: If the extension is dropped by the user using the CASCADE option:

    DROP EXTENSION table_version CASCADE;

Then the configuration tables and their data will be lost. Only drop the
extension if you are sure the versioning metadata is no longer required.

Migrate existing table_version installation
-------------------------------------------

If you already have the table_version functions and config tables installed in
your database not using the PostgreSQL extension, you can upgrade it using the
following command:

    CREATE EXTENSION table_version FROM unpackaged;

Functions
---------

### `ver_enable_versioning()` ###

    FUNCTION ver_enable_versioning(p_schema NAME, p_table NAME) 
    RETURNS BOOLEAN

**Parameters**

`p_schema`
: The table schema

`p_table`
: The table name

**Exceptions**

* throws RAISE_EXCEPTION if the table does not exist
* throws RAISE_EXCEPTION if the table is already versioned
* throws RAISE_EXCEPTION if the table does not have a unique non-compostite integer column

This function enable versioning for a table. Versioning a table will do the
following things:

1. A revision table with the schema_name_revision naming convention will be
   created in the table_version schema.
2. Any data in the table will be inserted into the revision data table. If
   SQL session is not currently in an active revision, a revision will be
   will be automatically created, then completed once the data has been
   inserted.
3. A trigger will be created on the versioned table that will maintain the changes
   in the revision table.
4. A function will be created with the ver_schema_name_revision_diff naming 
   convention in the table_version schema that allow you to get changeset data
   for a range of revisions.
5. A function will be created with the ver_schema_name_revision_revision naming 
   convention in the table_version schema that allow you to get a specific revision
   of the table.

For example:

    SELECT table_version.ver_enable_versioning('foo', 'bar');

### `ver_enable_versioning()` ###

    FUNCTION ver_enable_versioning(p_schema NAME, p_table NAME) 
    RETURNS BOOLEAN
    
Support
-------

This library is stored in an open [GitHub
repository](http://github.com/linz/postgresql-tableversion). Feel free to fork
and contribute! Please file bug reports via [GitHub
Issues](http://github.com/linz/postgresql-tableversion/issues/).

Author
------

[Jeremy Palmer](http://www.linz.govt.nz)

Copyright and License
---------------------

Copyright 2016 Crown copyright (c) Land Information New Zealand and the New
Zealand Government. All rights reserved

This software is provided as a free download under the 3-clause BSD License. See
the LICENSE file for more details.

