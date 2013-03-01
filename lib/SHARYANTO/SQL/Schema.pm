package SHARYANTO::SQL::Schema;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

our $VERSION = '0.02'; # VERSION

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

First you supply the SQL statements in `sqls` to create the database in the form
of array of arrays of statements. The first array element is a series of SQL
statements to create the tables/indexes (recommended to use CREATE TABLE IF NOT
EXISTS instead of CREATE TABLE). This is called version 1. Version will be
created in the special table called `meta` (in the row ('schema_version', 1).
The second array element is a series of SQL statements to update to version 2
(e.g. ALTER TABLE, and so on). The third element to update to version 3, and so
on.

So whenever you want to update your schema, you add a series of SQL statements
to the `sqls` array.

This routine will connect to database and check the current schema version. If
`meta` table does not exist yet, it will be created and the first series of SQL
statements will be executed. The final result is schema at version 1. If `meta`
table exists, schema version will be read from it and one or more series of SQL
statements will be executed to get the schema to the latest version.

Currently only tested on MySQL, Postgres, and SQLite.

_
    args => {
        sqls => {
            schema => ['array*', of => ['array*' => of => 'str*']],
            summary => 'SQL statements to create and update schema',
            req => 1,
        },
        dbh => {
            schema => ['obj*'],
            summary => 'DBI database handle',
            req => 1,
            description => <<'_',

Example:

    [
        [
            # for version 1
            'CREATE TABLE IF NOT EXISTS t1 (...)',
            'CREATE TABLE IF NOT EXISTS t2 (...)',
        ],
        [
            # for version 2
            'ALTER TABLE t1 ADD COLUMN c5 INT NOT NULL',
            'CREATE UNIQUE INDEX i1 ON t2(c1)',
        ],
        [
            # for version 3
            'ALTER TABLE t2 DROP COLUMN c2',
        ],
    ]

_
        },
    },
    "_perinci.sub.wrapper.validate_args" => 0,
};
sub create_or_update_db_schema {
    my %args = @_; if (!exists($args{'dbh'})) { return [400, "Missing argument: dbh"] } require Scalar::Util; my $_sahv_dpath = []; my $arg_err; ((defined($args{'dbh'})) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((Scalar::Util::blessed($args{'dbh'})) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type object"),0)); if ($arg_err) { return [400, "Invalid argument value for dbh: $arg_err"] } if (!exists($args{'sqls'})) { return [400, "Missing argument: sqls"] } require List::Util; ((defined($args{'sqls'})) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($args{'sqls'}) eq 'ARRAY') ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0)) && ((push(@$_sahv_dpath, undef), (!defined(List::Util::first(sub {!( ($_sahv_dpath->[-1] = defined($_sahv_dpath->[-1]) ? $_sahv_dpath->[-1]+1 : 0), ((defined($_)) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($_) eq 'ARRAY') ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0)) && ((push(@$_sahv_dpath, undef), (!defined(List::Util::first(sub {!( ($_sahv_dpath->[-1] = defined($_sahv_dpath->[-1]) ? $_sahv_dpath->[-1]+1 : 0), ((defined($_)) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($_)) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) )}, @{$_})))) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text", pop(@$_sahv_dpath)),0)) )}, @{$args{'sqls'}})))) ? 1 : (($arg_err //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array of texts", pop(@$_sahv_dpath)),0)); if ($arg_err) { return [400, "Invalid argument value for sqls: $arg_err"] } # VALIDATE_ARGS

    my $sqls = $args{sqls};
    my $dbh  = $args{dbh};

    local $dbh->{RaiseError};

    # first, check current schema version
    my $v;
    my @t = $dbh->tables("", undef, "meta");
    if (@t) {
        ($v) = $dbh->selectrow_array(
            "SELECT value FROM meta WHERE name='schema_version'");
    } else {
        $v = 0;
        $dbh->do("CREATE TABLE meta (name VARCHAR(64) NOT NULL PRIMARY KEY, value VARCHAR(255))")
            or return [500, "Can't create table 'meta': " . $dbh->errstr];
        $dbh->do("INSERT INTO meta (name,value) VALUES ('schema_version',0)")
            or return [500, "Can't insert into 'meta': " . $dbh->errstr];
    }

    # perform schema upgrade atomically (at least for db that supports it like
    # postgres)
    my $err;
  UPGRADE:
    for my $i (($v+1) .. @$sqls) {
        undef $err;
        $log->debug("Updating database schema to version $i ...");
        $dbh->begin_work;
        for my $sql (@{ $sqls->[$i-1] }) {
            $dbh->do($sql) or do { $err = $dbh->errstr; last UPGRADE };
        }
        $dbh->do("UPDATE meta SET value=$i WHERE name='schema_version'")
            or do { $err = $dbh->errstr; last UPGRADE };
        $dbh->commit or do { $err = $dbh->errstr; last UPGRADE };
        $v = $i;
    }
    if ($err) {
        $log->error("Can't upgrade schema (from version $v): $err");
        $dbh->rollback;
        return [500, "Can't upgrade schema (from version $v): $err"];
    } else {
        return [200, "OK", {version=>$v}];
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

version 0.02

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head2 create_or_update_db_schema(%args) -> [status, msg, result, meta]

Routine and convention to create/update your application's DB schema.

With this routine (and some convention) you can easily create and update
database schema for your application in a simple (and boring a.k.a. using plain
SQL) way.

First you supply the SQL statements in C<sqls> to create the database in the form
of array of arrays of statements. The first array element is a series of SQL
statements to create the tables/indexes (recommended to use CREATE TABLE IF NOT
EXISTS instead of CREATE TABLE). This is called version 1. Version will be
created in the special table called C<meta> (in the row ('schema_version', 1).
The second array element is a series of SQL statements to update to version 2
(e.g. ALTER TABLE, and so on). The third element to update to version 3, and so
on.

So whenever you want to update your schema, you add a series of SQL statements
to the C<sqls> array.

This routine will connect to database and check the current schema version. If
C<meta> table does not exist yet, it will be created and the first series of SQL
statements will be executed. The final result is schema at version 1. If C<meta>
table exists, schema version will be read from it and one or more series of SQL
statements will be executed to get the schema to the latest version.

Currently only tested on MySQL, Postgres, and SQLite.

Arguments ('*' denotes required arguments):

=over 4

=item * B<dbh>* => I<obj>

DBI database handle.

Example:

    [
        [
            # for version 1
            'CREATE TABLE IF NOT EXISTS t1 (...)',
            'CREATE TABLE IF NOT EXISTS t2 (...)',
        ],
        [
            # for version 2
            'ALTER TABLE t1 ADD COLUMN c5 INT NOT NULL',
            'CREATE UNIQUE INDEX i1 ON t2(c1)',
        ],
        [
            # for version 3
            'ALTER TABLE t2 DROP COLUMN c2',
        ],
    ]

=item * B<sqls>* => I<array>

SQL statements to create and update schema.

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

