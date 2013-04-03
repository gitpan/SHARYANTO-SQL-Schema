package SHARYANTO::SQL::Schema;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

our $VERSION = '0.05'; # VERSION

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(create_or_update_db_schema);

our %SPEC;

$SPEC{create_or_update_db_schema} = {
    v => 1.1,
    summary => 'Routine and convention to create/update '.
        'your application\'s DB schema',
    description => <<'_',

With this routine (and some convention) you can easily create and update
database schema for your application in a simple (and boring a.k.a. using plain
SQL) way.

*Version*: version is an integer and starts from 1. Each software release with
schema change will bump the version number to 1. Version information is stored
in a special table called `meta` (SELECT value FROM meta WHERE
name='schema_version').

You supply the SQL statements in `spec`. `spec` is a hash which contains the key
`install` (the value of which is a series of SQL statements to create the schema
from nothing). It should be the SQL statements to create the latest version of
the schema.

There should also be zero or more `upgrade_to_v$VERSION` keys, the value of each
is a series of SQL statements to upgrade from ($VERSION-1) to $VERSION. So there
could be `upgrade_to_v2`, `upgrade_to_v3`, and so on up the latest version.

This routine will connect to database and check the current schema version. If
`meta` table does not exist yet, the SQL statements in `install` will be
executed. The `meta` table will also be created and a row ('schema_version', 1)
is added.

If `meta` table already exists, schema version will be read from it and one or
more series of SQL statements from `upgrade_to_v$VERSION` will be executed to
bring the schema to the latest version.

Currently only tested on MySQL, Postgres, and SQLite. Postgres is recommended
because it can do transactional DDL (a failed upgrade in the middle will not
cause the database schema state to be inconsistent, e.g. in-between two
versions).

_
    args => {
        spec => {
            schema => ['hash*'], # XXX require 'install' & 'latest_v' keys
            summary => 'SQL statements to create and update schema',
            req => 1,
            description => <<'_',

Example:

    {
        install => [
            'CREATE TABLE IF NOT EXISTS t1 (...)',
            'CREATE TABLE IF NOT EXISTS t2 (...)',
        ],

        upgrade_to_v2 => [
            'ALTER TABLE t1 ADD COLUMN c5 INT NOT NULL',
            'CREATE UNIQUE INDEX i1 ON t2(c1)',
        ],

        upgrade_to_v3 => [
            'ALTER TABLE t2 DROP COLUMN c2',
        ],
    }

_
        },
        dbh => {
            schema => ['obj*'],
            summary => 'DBI database handle',
            req => 1,
        },
    },
    "_perinci.sub.wrapper.validate_args" => 0,
};
sub create_or_update_db_schema {
    my %args = @_; if (!exists($args{'spec'})) { return [400, "Missing argument: spec"] } my $_sahv_dpath = []; my $arg_err; ((defined($args{'spec'})) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($args{'spec'}) eq 'HASH') ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type hash"),0)); if ($arg_err) { return [400, "Invalid argument value for spec: $arg_err"] } if (!exists($args{'dbh'})) { return [400, "Missing argument: dbh"] } require Scalar::Util; ((defined($args{'dbh'})) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((Scalar::Util::blessed($args{'dbh'})) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type object"),0)); if ($arg_err) { return [400, "Invalid argument value for dbh: $arg_err"] } # VALIDATE_ARGS

    my $spec = $args{spec};
    my $dbh  = $args{dbh};

    local $dbh->{RaiseError};

    # first, check current schema version

    # XXX check spec: latest_v and upgrade_to_v$V must synchronize

    my $v;
    my @t = $dbh->tables("", undef, "meta");
    if (@t) {
        ($v) = $dbh->selectrow_array(
            "SELECT value FROM meta WHERE name='schema_version'");
    }
    $v //= 0;

    my $orig_v = $v;

    # perform schema upgrade atomically per version (at least for db that
    # supports it like postgres)
    my $err;

  STEP:
    for my $i (($v+1) .. $spec->{latest_v}) {
        undef $err;
        my $last;

        $dbh->begin_work;

        if ($v == 0 && !@t) {
            $dbh->do("CREATE TABLE meta (name VARCHAR(64) NOT NULL PRIMARY KEY, value VARCHAR(255))")
                or do { $err = $dbh->errstr; last STEP };
            $dbh->do("INSERT INTO meta (name,value) VALUES ('schema_version',0)")
                or do { $err = $dbh->errstr; last STEP };
        }

        if ($v == 0 && $spec->{install}) {
            $log->debug("Updating database schema from version $v to $i ...");
            my $j = 0;
            for my $sql (@{ $spec->{install} }) {
                $dbh->do($sql) or do { $err = $dbh->errstr; last STEP };
                $i++;
            }
            $dbh->do("UPDATE meta SET value=$spec->{latest_v} WHERE name='schema_version'")
                or do { $err = $dbh->errstr; last STEP };
            $last++;
        } else {
            $log->debug("Updating database schema from version $v to $i ...");
            $spec->{"upgrade_to_v$i"}
                or do { $err = "Error in spec: upgrade_to_v$i not specified"; last STEP };
            for my $sql (@{ $spec->{"upgrade_to_v$i"} }) {
                $dbh->do($sql) or do { $err = $dbh->errstr; last STEP };
            }
            $dbh->do("UPDATE meta SET value=$i WHERE name='schema_version'")
                or do { $err = $dbh->errstr; last STEP };
        }

        $dbh->commit or do { $err = $dbh->errstr; last STEP };

        $v = $i;
    }
    if ($err) {
        $log->error("Can't upgrade schema (from version $v): $err");
        $dbh->rollback;
        return [500, "Can't upgrade schema (from version $v): $err"];
    } else {
        return [200, "OK (upgraded from v=$orig_v)", {version=>$v}];
    }

    [200];
}

1;
# ABSTRACT: Routine and convention to create/update your application's DB schema


__END__
=pod

=head1 NAME

SHARYANTO::SQL::Schema - Routine and convention to create/update your application's DB schema

=head1 VERSION

version 0.05

=head1 DESCRIPTION

This module uses L<Log::Any> for logging.

To use this module, you typically run the create_or_update_db_schema() routine
at the start of your program/script, e.g.:

 use DBI;
 use SHARYANTO::SQL::Schema qw(create_or_update_db_schema);
 my $spec = {...}; # the schema specification
 my $dbh = DBI->connect(...);
 my $res = create_or_update_db_schema(dbh=>$dbh, spec=>$spec);

This way, your program automatically creates/updates database schema when run.
Users need not know anything.

=head1 SEE ALSO

Some other database migration tools that directly uses SQL:

=over

=item * L<Database::Migrator>

Pretty much similar, albeit more fully-fledged/involved. You have to use OO
style. You put each version's SQL in a separate file and subdirectory. Perl
scripts can also be executed for each version upgrade. Meta table is
configurable (default recommended is 'AppliedMigrations').

=back

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head2 create_or_update_db_schema(%args) -> [status, msg, result, meta]

Routine and convention to create/update your application's DB schema.

With this routine (and some convention) you can easily create and update
database schema for your application in a simple (and boring a.k.a. using plain
SQL) way.

I<Version>: version is an integer and starts from 1. Each software release with
schema change will bump the version number to 1. Version information is stored
in a special table called C<meta> (SELECT value FROM meta WHERE
name='schema_version').

You supply the SQL statements in C<spec>. C<spec> is a hash which contains the key
C<install> (the value of which is a series of SQL statements to create the schema
from nothing). It should be the SQL statements to create the latest version of
the schema.

There should also be zero or more C<upgrade_to_v$VERSION> keys, the value of each
is a series of SQL statements to upgrade from ($VERSION-1) to $VERSION. So there
could be C<upgrade_to_v2>, C<upgrade_to_v3>, and so on up the latest version.

This routine will connect to database and check the current schema version. If
C<meta> table does not exist yet, the SQL statements in C<install> will be
executed. The C<meta> table will also be created and a row ('schema_version', 1)
is added.

If C<meta> table already exists, schema version will be read from it and one or
more series of SQL statements from C<upgrade_to_v$VERSION> will be executed to
bring the schema to the latest version.

Currently only tested on MySQL, Postgres, and SQLite. Postgres is recommended
because it can do transactional DDL (a failed upgrade in the middle will not
cause the database schema state to be inconsistent, e.g. in-between two
versions).

Arguments ('*' denotes required arguments):

=over 4

=item * B<dbh>* => I<obj>

DBI database handle.

=item * B<spec>* => I<hash>

SQL statements to create and update schema.

Example:

    {
        install => [
            'CREATE TABLE IF NOT EXISTS t1 (...)',
            'CREATE TABLE IF NOT EXISTS t2 (...)',
        ],
    
        upgrade_to_v2 => [
            'ALTER TABLE t1 ADD COLUMN c5 INT NOT NULL',
            'CREATE UNIQUE INDEX i1 ON t2(c1)',
        ],
    
        upgrade_to_v3 => [
            'ALTER TABLE t2 DROP COLUMN c2',
        ],
    }

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

