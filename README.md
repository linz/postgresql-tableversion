[![Build Status](https://travis-ci.org/linz/postgresql-tableversion.svg?branch=master)](https://travis-ci.org/linz/postgresql-tableversion)

postgresql-tableversion
========================

PostgreSQL table versioning extension, recording row modifications and its
history. The extension provides APIs for accessing snapshots of a table at
certain revisions and the difference generated between any two given revisions.
The extension uses a PL/PgSQL trigger based system to record and provide access
to the row revisions.

Easy Installation
-----------------
Install [pgxn-client](http://pgxnclient.projects.pgfoundry.org) which is hosted
on PyPI:

    $ sudo easy_install pgxnclient

Then do:

    $ sudo pgxn install table_version

or
    sudo pgxn load -d my_db table_version

(Run pgxn --help for more info)

Installation via apt-get
------------------------
Add apt repository:

    # Enable fetching packages from packagecloud
    # production repository:
    $ curl -s \
      https://packagecloud.io/install/repositories/linz/prod/script.deb.sh |
      sudo bash

Then install the package (tweak the PGVER line if needed):

    $ PGVER=$(basename `pg_config --sharedir`) \
      sudo apt-get install postgresql-${PGVER}-tableversion


Hard Installation
-----------------

To build it, just do this:

    make
    make installcheck
    make install

If you encounter an error such as:

    "Makefile", line 8: Need an operator

You need to use GNU make, which may well be installed on your system as
`gmake`:

    gmake
    gmake install
    gmake installcheck

If you encounter an error such as:

    make: pg_config: Command not found

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

    env PG_CONFIG=/path/to/pg_config make && make installcheck && make install

And finally, if all that fails (and if you're on PostgreSQL 8.1 or lower, it
likely will), copy the entire distribution directory to the `contrib/`
subdirectory of the PostgreSQL source tree and try it there without
`pg_config`:

    env NO_PGXS=1 make && make installcheck && make install

If you encounter an error such as:

    ERROR:  must be owner of database regression

You need to run the test suite using a super user, such as the default
"postgres" super user:

    make installcheck PGUSER=postgres

Building Debian packaging
--------------------------

Build the Debian packages using the following command:

    make deb

The number of packages built will depend on the number of supported
PostgreSQL versions on your system. Make sure to install the
postgresql-server-dev-all package, and consider adding the
postgresql.org apt repository to get the most versions out
of it (see https://wiki.postgresql.org/wiki/Apt)

Installing the extension
------------------------

Once table_version is installed, you can add it to a database. If you're running
PostgreSQL 9.1.0 or greater, it's a simple as connecting to a database as a
super user and running:

    CREATE EXTENSION table_version;

The extension will install support configuration tables and functions into the
table_version schema.

If you're ugrading from an older version of the extension run:

```
ALTER EXTENSION table_version UPDATE;
```

If you've upgraded your cluster to PostgreSQL 9.1 and already had table_version
installed, you can upgrade it to a properly packaged extension with:

    CREATE EXTENSION table_version FROM unpackaged;


Dependencies
------------

The `table_version` extension has no dependencies other than PL/PgSQL.

License
---------------------
This project is under 3-clause BSD License, except where otherwise specified.
See the LICENSE file for more details.

