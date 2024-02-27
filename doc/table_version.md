# table_version

## Synopsis

1. Let's start from scratch and create empty database `table_version`

   ```
   $ createdb table_version
   $ psql table_version
   ```

2. First step we need to do, is to install `table_version` extension to our database

   ```
   table_version=# CREATE EXTENSION table_version;
   CREATE EXTENSION
   ```

3. Next, we create schema `foo` and add it to our search path

   ```
   table_version=# CREATE SCHEMA foo;
   CREATE SCHEMA

   table_version=# SET search_path TO foo,public;
   ```

4. Our table to be versioned will be called `bar` and will be located in `foo` schema

   ```
   table_version=# CREATE TABLE foo.bar (
       id INTEGER NOT NULL PRIMARY KEY,
       baz TEXT
   );
   CREATE TABLE
   ```

5. Enable versioning on created table by calling `ver_enable_versioning` function. The function
   accepts two parameters - schema and table name

   ```
   table_version=# SELECT table_version.ver_enable_versioning('foo', 'bar');
    ver_enable_versioning
   -----------------------
    t
   ```

6. Create first revision of our created table, called `My test edit`

   ```
   table_version=# SELECT table_version.ver_create_revision('My test edit');
    ver_create_revision
   ---------------------
                   1001
   ```

7. Mark revision as done . There is no data in the table or in the history table.

   ```
   table_version=# SELECT table_version.ver_complete_revision();
    ver_complete_revision
   -----------------------
    t
   ```

8. Create next revision of our created table, called `Insert data`

   ```
   table_version=# SELECT table_version.ver_create_revision('Insert data');
    ver_create_revision
   ---------------------
                   1002
   ```

9. Insert some initial set of data

   ```
   table_version=# INSERT INTO foo.bar (id, baz) VALUES
   (1, 'foo bar 1'),
   (2, 'foo bar 2'),
   (3, 'foo bar 3');
   INSERT 0 3
   ```

10. Mark revision as done

    ```
    table_version=# SELECT table_version.ver_complete_revision();
     ver_complete_revision
    -----------------------
     t
    ```

11. And show differences between last revisions
    ```
    table_version=# SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002);
     _diff_action | id |    baz
    --------------+----+-----------
     I            |  3 | foo bar 3
     I            |  1 | foo bar 1
     I            |  2 | foo bar 2
    ```

## Description

PostgreSQL table versioning extension, recording row modifications and its history. The extension
provides APIs for accessing snapshots of a table at certain revisions and the difference generated
between any two given revisions. The extension uses a trigger based system and PL/PgSQL functions to
record and provide access to the row revisions. Note this extension only records changes at the row
level and does revision schema changes or allow for row version branching.

## Purpose

This extension was created to store table data revisions in a data warehouse environment. The
primarily use case was to import bulk difference data from an external system on a daily basis and
record all of those daily revisions. The design decision to maintain the version history data in a
completely separate table from the current data table (instead of just having a view) was driven by
performance reasons. Also note the roots of this extension were developed before syntactic sugar of
materialised views were a real option in PostgreSQL.

## Table Prerequisites

To enable versioning on a table the following conditions must be met:

- The table must have a have a unique non-composite integer, bigint, text or varchar column
- The table must not be temporary

## How it works

When a table is versioned the original table data is left untouched and a new revision table is
created with all the same fields plus a `_revision_created` and `_revision_expired` fields. A row
level trigger is then setup on the original table and whenever an insert, update and delete
statement is run the change is recorded in the table's revision data table. And a statement level
trigger is setup to forbid TRUNCATE.

Revisions are more described in the `table_version.revision` table.

## Security model

- Anyone can create revisions.
- Revisions can only be completed by their creators.
- Only those who have ownership privileges on a table can enable/disable versioning of such table.
- Only empty revisions can be deleted.
- Only the creator of a revision can delete it.

Note that disabling versioning on a table results in all history for that table being deleted.

## Installing the extension

Once `table_version` is installed, you can add it to a database. If you're running PostgreSQL 9.1.0
or greater, it's a simple as connecting to a database as a super user and running:

    CREATE EXTENSION table_version;

The extension will install support configuration tables and functions into the `table_version`
schema.

If you've upgraded your cluster to PostgreSQL 9.1 and already had `table_version` installed, you can
upgrade it to a properly packaged extension with:

    CREATE EXTENSION table_version FROM unpackaged;

## General Usage

Take the following example. We have a table `bar` in schema `foo` and insert some data:

    CREATE EXTENSION table_version;

    CREATE SCHEMA foo;

    CREATE TABLE foo.bar (
        id INTEGER NOT NULL PRIMARY KEY,
        baz TEXT
    );

    INSERT INTO foo.bar (id, baz) VALUES
    (1, 'foo bar 1'),
    (2, 'foo bar 2'),
    (3, 'foo bar 3');

Then to enable versioning on a table you need to run the following command:

    SELECT table_version.ver_enable_versioning('foo', 'bar');

After you have run this command, triggers `foo_bar_revision_trg` and `foo_bar_truncate_trg` should
have been created on the `foo.bar` table. Also the `table_version.foo_bar_revision` table is created
to store the revision data. If you execute a select from the table you can see the base revision
data:

    SELECT * FROM table_version.foo_bar_revision;

     _revision_created | _revision_expired | id |    baz
    -------------------+-------------------+----+-----------
                  1001 |                   |  1 | foo bar 1
                  1001 |                   |  2 | foo bar 2
                  1001 |                   |  3 | foo bar 3
    (3 rows)

After the table has been versioned and you want to edit some data you _must first start a revision_,
do the edits and then complete the revision. i.e:

    SELECT table_version.ver_create_revision('My test edit');

    -- now do some edits
    INSERT INTO foo.bar (id, baz) VALUES (4, 'foo bar 4');

    UPDATE foo.bar
    SET    baz = 'foo bar 1 edit'
    WHERE  id = 1;

    DELETE FROM foo.bar
    WHERE id = 3;

    SELECT table_version.ver_complete_revision();

Now you should have some more edits in `table_version.foo_bar_revision` table:

    SELECT * FROM table_version.foo_bar_revision;

     _revision_created | _revision_expired | id |       baz
    -------------------+-------------------+----+----------------
                  1001 |                   |  2 | foo bar 2
                  1002 |                   |  4 | foo bar 4
                  1001 |              1002 |  1 | foo bar 1
                  1002 |                   |  1 | foo bar 1 edit
                  1001 |              1002 |  3 | foo bar 3
    (5 rows)

If we want to get the changed data from one revision to another (in this case from 1001 to 1002) we
run:

    SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002);

     _diff_action | id |       baz
    --------------+----+----------------
     U            |  1 | foo bar 1 edit
     D            |  3 | foo bar 3
     I            |  4 | foo bar 4
    (3 rows)

As you can see the updates are recorded below. The `_diff_action` column indicates the type of
modification:

- 'U' = Update
- 'D' = Delete
- 'I' = Insert

If you would like to gain access to a snapshot of the data at a given time then call the following
function:

    SELECT * FROM table_version.ver_get_foo_bar_revision(1001);

     id |    baz
    ----+-----------
      2 | foo bar 2
      1 | foo bar 1
      3 | foo bar 3
    (3 rows)

Finally if you would like to remove versioning for the table call:

    SELECT table_version.ver_disable_versioning('foo', 'bar');

## Auto revisions

You can if you don't want to call the API functions of `ver_create_revision` and
`ver_complete_revision` explicitly. This can be useful if your application can't use the call the
API functions before editing. e.g. ongoing logical replication.

Under this auto-revision mode, revision edits are grouped by transactions.

    CREATE EXTENSION table_version;

    CREATE SCHEMA foo;

    CREATE TABLE foo.bar (
        id INTEGER NOT NULL PRIMARY KEY,
        baz TEXT
    );

    SELECT table_version.ver_enable_versioning('foo', 'bar');

    BEGIN;
    INSERT INTO foo.bar (id, baz) VALUES (1, 'foo bar 1');
    INSERT INTO foo.bar (id, baz) VALUES (2, 'foo bar 2');
    INSERT INTO foo.bar (id, baz) VALUES (3, 'foo bar 3');
    COMMIT;

    BEGIN;
    UPDATE foo.bar
    SET    baz = 'foo bar 1 edit'
    WHERE  id = 1;
    COMMIT;


    SELECT * FROM table_version.foo_bar_revision;

     _revision_created | _revision_expired | id |       baz
    -------------------+-------------------+----+----------------
                  1001 |                   |  2 | foo bar 2
                  1001 |                   |  3 | foo bar 3
                  1001 |              1002 |  1 | foo bar 1
                  1002 |                   |  1 | foo bar 1 edit

    (3 row)

The revision message will be automatically created for you based on the transaction ID.

      id  |       revision_time        |         start_time         | user_name | schema_change |    comment
    ------+----------------------------+----------------------------+-----------+---------------+---------------
     1001 | 2024-02-26 22:10:30.751895 | 2024-02-26 22:10:30.758708 | postgres  | f             | Auto Txn 4859
     1002 | 2024-02-27 08:38:44.548215 | 2024-02-27 08:38:44.556542 | root      | f             | Auto Txn 4860
    (2 rows)

## Replicate data using table differences

If you would like to maintain a copy of table data on a remote system this is easily done with this
revision system. Here the steps:

1.  First you need to determine which tables are versioned:

        SELECT * FROM table_version.ver_get_versioned_tables();

         schema_name | table_name | key_column
        -------------+------------+------------
         foo         | bar        | id
        (1 row)

2.  Next you need to determine which revisions you what to replicate to your system:

            SELECT table_version.ver_get_table_base_revision('foo', 'bar');

             ver_get_table_base_revision
            -----------------------------
                                     1001
            (1 row)

3.  Now determine all of the revisions have been applied to the table.

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

4.  The first data copy operation is to create a base snapshot of the table data:

        CREATE TABLE foo_bar_copy AS
        SELECT * FROM table_version.ver_get_foo_bar_revision(
            table_version.ver_get_table_base_revision('foo', 'bar')
        );

5.  Now to maintain your base copy you can select an difference change set and then apply that to
    your base copy: -- Where 'my_last_revision' is the last revision that your dataset has on --
    your remote system SELECT \* FROM table_version.ver_get_foo_bar_diff( my_last_revision,
    table_version.ver_get_table_last_revision('foo', 'bar') );

## Configuration tables

The extension creates the following configuration tables:

- `table_version.revision`
- `table_version.tables_changed`
- `table_version.versioned_tables`

Whenever a new table is setup for versioning or an versioned table is edited the metadata of that
transaction is recorded in these tables. When databases using the `table_version` extension are
dumped that data from these configuration tables are also dumped to ensure the patch history data is
persisted.

**WARNING**: If the extension is dropped by the user using the `CASCADE` option:

    DROP EXTENSION table_version CASCADE;

Then the configuration tables and their data will be lost. Only drop the extension if you are sure
the versioning metadata is no longer required.

## Migrate existing `table_version` installation

If you already have the `table_version` functions and config tables installed in your database not
using the PostgreSQL extension, you can upgrade it using the following command:

    CREATE EXTENSION table_version FROM unpackaged;

## Support Functions

### `ver_apply_table_differences()`

Generates a difference between any a source original table and a new table and then applies those
differences to the original table. Both table must have a single column primary key. Comparisons are
only done between common table columns

    FUNCTION table_version.ver_apply_table_differences(
        p_original_table REGCLASS,
        p_new_table REGCLASS,
        p_key_column NAME,
        OUT number_inserts BIGINT,
        OUT number_deletes BIGINT,
        OUT number_updates BIGINT
    )

**Parameters**

`p_original_table` : The original source table to compare against and then apply the changes to

`p_new_table` : The table containing the new data to compare against the original

`p_key_column` : The common key column used for comparing rows between tables

**Returns**

Returns a record of 3 values for the changed applied to the original table.:

- `number_inserts` = The number of row inserted into the original table
- `number_deletes` = The number of row deleted from the original table
- `number_updates` = The number of row updated in the original table

**Exceptions**

throws an exception if the source table:

- either tables's key column is not a unique non-composite integer, bigint, text, or varchar column
- no common columns between tables were found

**Example**

    SELECT * FROM table_version.ver_apply_table_differences('foo.bar1', 'foo.bar2', 'id');

### `ver_get_table_differences()`

Generates a difference between two tables. Both table must have a single column primary key.
Comparisons are only done between common table columns

    FUNCTION table_version.ver_get_table_differences(
        p_table1 regclass,
        p_table2 regclass,
        p_compare_key name)
    RETURNS SETOF record

**Parameters**

`p_table1` : The first table

`p_table2` : The second table

`p_key_column` : The common key column used for comparing rows between tables

**Returns**

Returns a generic set of records. Each row contains the following columns:

- action CHAR(1)
- id {key's datatype}

Because the function returns a generic set of records the schema type for the the returned record
needs to be defined. This definition will be dependent on the key column's datatype.

**Exceptions**

throws an exception if the source table:

- either tables's key column is not a unique non-composite integer, bigint, text, or varchar column
- no common columns between tables were found

**Example**

    SELECT * FROM table_version.ver_get_table_differences('foo.bar1', 'foo.bar2', 'id') AS
    (action CHAR(1), ID INTEGER)

### `ver_table_key_datatype()`

Returns the table's key column datatype

    FUNCTION table_version.ver_table_key_datatype(
        p_table REGCLASS,
        p_key_column NAME)
    RETURNS TEXT

**Parameters**

` p_table` : The table

`p_key_column` : The table's key column

**Returns**

Returns the PostgreSQL datatype for the key column

**Example**

    SELECT table_version.ver_table_key_datatype('foo.bar', 'id');

## Table Versioning Functions

These functions get created once an table has been versioned

### `ver_get_{schema_name}_{table_name}_diff()`

Generates a difference between any two given revisions for versioned table

    FUNCTION ver_get_{schema_name}_{table_name}_diff(
       p_revision1 INTEGER,
       p_revision2 INTEGER
    )
    RETURNS TABLE(_diff_action CHAR(1), [table_column1, table_column2 ...])

**Parameters**

`p_revision1` : The start revision to generate the difference

`p_revision2` : The end revision to generate the difference

**Returns**

A tableset of changed rows containing the each row that has been inserted, updated or deleted
between the start and end revisions. The `_diff_action` column contains the type of modification for
each row. The `_diff_action` value can be one of:

- 'U' = Update
- 'D' = Delete
- 'I' = Insert

**Exceptions**

throws an exception if the source table:

- is not versioned
- revision 1 is greater than revision 2

**Example**

    SELECT * FROM table_version.ver_get_foo_bar_diff(1001, 1002);

### `ver_get_{schema_name}_{table_name}_revision()`

Generates tableset for versioned table at a given revision ID.

    FUNCTION ver_get_{schema_name}_{table_name}_revision(p_revision INTEGER)
    RETURNS TABLE([table_column1, table_column2 ...])

**Parameters**

`p_revision` : The revision to generate the tableset for

**Returns**

A tableset for the table at a given revision ID.

**Example**

    SELECT * FROM table_version.ver_get_foo_bar_revision(1001);

## General Functions

### `ver_enable_versioning()`

This function enable versioning for a table.

    FUNCTION ver_enable_versioning(p_schema NAME, p_table NAME)
    RETURNS BOOLEAN

**Parameters**

`p_schema` : The table schema

`p_table` : The table name

**Returns**

`true` or `false` if versioning the table was successful

**Exceptions**

Throws an exception if the source table:

- does not exist
- is already versioned
- does not have a unique non-composite integer, bigint, text or varchar column

**Notes**

Versioning a table will do the following things:

1. A revision table with the `schema_name_revision` naming convention will be created in the
   `table_version` schema.
2. Any data in the table will be inserted into the `revision` data table. If SQL session is not
   currently in an active revision, a revision will be will be automatically created, then completed
   once the data has been inserted.
3. Triggers will be created on the versioned table to maintain the changes in the revision table and
   forbid TRUNCATE.
4. A function will be created with the `ver_schema_name_revision_diff` naming convention in the
   `table_version` schema that allow you to get changeset data for a range of revisions.
5. A function will be created with the `ver_schema_name_revision_revision` naming convention in the
   `table_version` schema that allow you to get a specific revision of the table.

**Example**

    SELECT table_version.ver_enable_versioning('foo', 'bar');

### `ver_disable_versioning()`

Disables versioning on a table

    FUNCTION ver_disable_versioning( p_schema NAME, p_table NAME)
    RETURNS BOOLEAN

**Parameters**

`p_schema` : The table schema

`p_table` : The table name

**Returns**

`true` or `false` if disabling versioning on the table was successful

**Exceptions**

throws an exception if the source table:

- is not versioned

**Notes**

All associated objects created for the versioning will be dropped.

**Example**

    SELECT table_version.ver_disable_versioning('foo', 'bar');

### `ver_create_revision()`

Create a new revision within the current SQL session.

    FUNCTION ver_create_revision(
        p_comment TEXT,
        p_revision_time
        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        p_schema_change BOOLEAN DEFAULT FALSE
    )
    RETURN INTEGER

**Parameters**

`p_comment` : A comment for revision

`p_revision_time` : The the datetime of the revision in terms of a business context. Defaults to
current date time.

`p_schema_change` : The the datetime of the revision in terms of a business context. Defaults to
false

**Returns**

The identifier for the new revision.

**Exceptions**

throws an exception if:

- a revision is still in progress within the current SQL session

**Notes**

This function must be called before INSERTS, UPDATES OR DELETES can occur on a table versioned
table. The first revision ID starts at 1000.

**Example**

    SELECT table_version.ver_create_revision('My edit');

### `ver_complete_revision()`

Completed a revision within the current SQL session.

    FUNCTION ver_complete_revision()
    RETURNS BOOLEAN

**Returns**

`true` or `false` if the revision was successfully completed. Will return `false` if an revision has
not been created.

**Notes**

This must be called after a revision is created within the SQL session.

**Example**

    SELECT table_version.ver_complete_revision()

### `ver_delete_revision()`

Delete an empty revision.

    FUNCTION ver_delete_revision(p_revision INTEGER)
    RETURNS BOOLEAN

**Parameters**

`p_revision` : The revision ID

**Returns**

Returns `true` if the revision was successfully deleted.

**Notes**

This is useful if the revision was allocated, but was not used for any table updates.

**Example**

    SELECT table_version.ver_delete_revision(1000)

### `ver_get_revision()`

Get the revision information for the given revision ID.

    FUNCTION ver_get_revision(
        p_revision        INTEGER,
        OUT id            INTEGER,
        OUT revision_time TIMESTAMP,
        OUT start_time    TIMESTAMP,
        OUT schema_change BOOLEAN,
        OUT comment       TEXT,
        OUT user_name     TEXT
    );

**Parameters**

`p_revision` : The revision ID

**Returns**

The function has the following out parameters:

`id` : The returned revision id

`revision_time` : The returned revision datetime

`start_time` : The returned start time of when revision record was created

`schema_change` : The returned flag if the revision had a schema change

`comment` : The returned revision comment

`user_name` : The returned user who created the revision

**Example**

    SELECT * FROM table_version.ver_get_revision(1000)

### `ver_get_revision()`

Get the last revision for the given datetime. If no revision is recorded at the datetime, then the
next oldest revision is returned.

    FUNCTION ver_get_revision(p_date_time TIMESTAMP);
    RETURNS INTEGER

**Parameters**

`p_revision` : The revision ID

**Returns**

The revision id

**Example**

    SELECT table_version.ver_get_revision('2016-01-16 00:00:00'::TIMESTAMP)

### `ver_get_revisions()`

Get multiple revisions

    FUNCTION ver_get_revisions(p_revisions INTEGER[])
    RETURNS TABLE(
        id             INTEGER,
        revision_time  TIMESTAMP,
        start_time     TIMESTAMP,
        schema_change  BOOLEAN,
        comment        TEXT,
        user_name      TEXT
    )

**Parameters**

`p_revisions` : An array of revision ids

**Returns**

A tableset of revisions records.

**Example**

    SELECT * FROM table_version.ver_get_revisions(ARRAY[1000,1001,1002])

### `ver_get_revisions()`

Get revisions for a given date range

    REPLACE FUNCTION ver_get_revisions(p_start_date TIMESTAMP, p_end_date TIMESTAMP)
    RETURNS TABLE(id INTEGER)

**Parameters**

`p_start_date` : The start datetime for the range of revisions

`p_end_date` : The end datetime for the range of revisions

**Returns**

    A tableset of revision records

**Example**

    SELECT * FROM table_version.ver_get_revisions('2016-01-16 00:00:00', '2016-01-18 00:00:00')

### `ver_get_last_revision()`

Get the last revision

    FUNCTION ver_get_last_revision()
    RETURNS INTEGER

**Returns**

The revision id

**Example**

    SELECT ver_get_last_revision()

### `ver_get_table_base_revision()`

Get the base revision for a given table.

    FUNCTION ver_get_table_base_revision(p_schema NAME, p_table NAME)
    RETURNS INTEGER

**Parameters**

`p_schema` : The table schema

`p_table` : The table name

**Returns**

The revision id

**Exceptions**

throws an exception if:

- the table is not versioned

**Example**

    SELECT table_version.ver_get_table_base_revision('foo', 'bar')

### `ver_get_table_last_revision()`

Get the last revision for a given table.

    FUNCTION ver_get_table_last_revision(p_schema NAME, p_table NAME)
    RETURNS INTEGER

**Parameters**

`p_schema` : The table schema

`p_table` : The table name

**Returns**

The revision id

**Exceptions**

throws an exception if:

- the table is not versioned

**Example**

    SELECT table_version.ver_get_table_last_revision('foo', 'bar')

### `ver_get_versioned_tables()`

Get all versioned tables

    FUNCTION ver_get_versioned_tables()
    RETURNS TABLE(schema_name NAME, table_name NAME, key_column VARCHAR(64))

**Returns**

A tableset of modified table records.

**Example**

    SELECT * FROM table_version.ver_get_versioned_tables()

### `ver_get_versioned_table_key()`

Get the versioned table key

    FUNCTION ver_get_versioned_table_key(p_schema_name NAME, p_table_name NAME)
    RETURNS VARCHAR(64)

**Parameters**

`p_schema_name` : The table schema

`p_table_name` : The table name

**Returns**

The versioned table key.

**Example**

    SELECT table_version.ver_get_versioned_table_key('foo', 'bar')

### `ver_get_modified_tables()`

Get all tables that are modified by a revision.

    FUNCTION ver_get_modified_tables(p_revision  INTEGER)
    RETURNS TABLE(schema_name NAME, table_name NAME)

**Parameters**

`p_revision` : The revision

**Returns**

A tableset of modified table records including the schema and table name.

**Exceptions**

throws an exception if:

- the revision does not exist

**Example**

    SELECT * FROM table_version.ver_get_table_last_revision(1000)

### `ver_get_modified_tables()`

Get tables that are modified for a given revision range.

    FUNCTION ver_get_modified_tables(p_revision1 INTEGER, p_revision2 INTEGER)
    RETURNS TABLE(revision INTEGER, schema_name NAME, table_name NAME)

**Parameters**

`p_revision1` : The start revision for the range

`p_revision2` : The end revision for the range

**Returns**

A tableset of records modified tables and revision when the change occurred.

**Example**

    SELECT * FROM table_version.ver_get_modified_tables(1000, 1001)

### `ver_is_table_versioned()`

Check if table is versioned.

    FUNCTION ver_is_table_versioned(p_schema NAME, p_table NAME)
    RETURNS BOOLEAN

**Parameters**

`p_schema` : The table schema

`p_table` : If the table is versioned

**Returns**

`true` or `false`if the table is versioned

**Example**

    SELECT table_version.ver_is_table_versioned('foo', 'bar')

### `ver_versioned_table_change_column_type()`

Modify a column datatype for a versioned table.

    FUNCTION ver_versioned_table_change_column_type(
        p_schema_name NAME,
        p_table_name NAME,
        p_column_name NAME,
        p_column_datatype TEXT
    )
    RETURNS BOOLEAN

**Parameters**

`p_schema_name` : The table schema

`p_table_name` : The table name

`p_column_name` : The name of the column to modify

`p_column_datatype` : The datatype of column to modify

**Returns**

`true` or `false` if the column was successfully modified

**Exceptions**

throws an exception if:

- the table is not versioned

**Example**

    SELECT table_version.ver_versioned_table_change_column_type('foo', 'bar', 'baz', 'VARCHAR(100)')

### `ver_versioned_table_add_column()`

Add a column to a versioned table.

    FUNCTION ver_versioned_table_add_column(
        p_schema_name NAME,
        p_table_name  NAME,
        p_column_name NAME,
        p_column_datatype TEXT
    )
    RETURNS BOOLEAN

**Parameters**

`p_schema_name` : The table schema

`p_table_name` : The table name

`p_column_name` : The name of the column to add

`p_column_datatype` : The datatype of column to add

**Returns**

`true` or `false` if the column was added successful

**Exceptions**

throws an exception if:

- the table is not versioned

**Notes**

Column can not have a default values.

**Example**

    SELECT table_version.ver_versioned_table_add_column('foo', 'bar', 'baz', 'VARCHAR(100)')

### `ver_versioned_table_drop_column()`

Delete a column from a versioned table.

    FUNCTION ver_versioned_table_drop_column(
        p_schema_name NAME,
        p_table_name  NAME,
        p_column_name NAME
    )
    RETURNS BOOLEAN

**Parameters**

`p_schema_name` : The table schema

`p_table_name` : The table name

`p_column_name` : The name of the column to delete

**Returns**

`true` or `false` if the column was successfully deleted

**Exceptions**

throws an exception if:

- the table is not versioned

**Example**

    SELECT table_version.ver_versioned_table_drop_column('foo', 'bar', 'baz')

### `ver_fix_revision_disorder()`

Reorder revisions created out of time order. This could happen if the revision sequence was
accidentally reset either manually or by upgrading to versions 1.3.0, 1.3.1 or 1.4.0 which were
affected by a [bug](https://github.com/linz/postgresql-tableversion/issues/77) triggering such reset

The function takes no parameters and returns the number of revisions which were renamed to obtain an
ordered sequence. You can safely call this function multiple times, expecting 0 to be returned after
the first call (in case of uncommitted transactions there could be additional revisions to reorder
after the first run).

### `ver_log_modified_tables()`

Regenerate the metadata table `table_version.tables_changed` from the data in
`table_version.versioned_tables` and associated revision tables.

This may be useful if the table data gets corrupted for any reason. Data in that table is a
redundancy used to speed up some queries.

The function takes no parameters and returns void. You can safely call this function multiple times.

## Support

This library is stored in an open
[GitHub repository](http://github.com/linz/postgresql-tableversion). Feel free to fork and
contribute! Please file bug reports via
[GitHub Issues](http://github.com/linz/postgresql-tableversion/issues/).

## Author

[Jeremy Palmer](http://www.linz.govt.nz)

## Copyright and License

Copyright 2016 Crown copyright (c) Land Information New Zealand and the New Zealand Government. All
rights reserved

This software is provided as a free download under the 3-clause BSD License. See the LICENSE file
for more details.
