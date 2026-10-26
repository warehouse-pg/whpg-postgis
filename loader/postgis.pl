#!/usr/bin/perl

#
# PostGIS - Spatial Types for PostgreSQL
# http://postgis.net
#
# Copyright (C) 2020 Sandro Santilli <strk@kbt.io>
#
# This is free software; you can redistribute and/or modify it under
# the terms of the GNU General Public Licence. See the COPYING file.
#

use POSIX ();

sub usage
{
	print qq{Usage: $0 <command> [<args>]
Commands:
  help               print this message and exits
  enable <database>  enable PostGIS in given database
  upgrade <database> upgrade PostGIS in given database
  status <database>  print PostGIS status in given database
};

}


sub enable
{
	print "Enable called with args: @_\n";
  my $db = shift;
  die "Please specify a database name" unless "$db";
  die "Enable is not implemented yet";
}

# Run psql with the given arguments, bypassing the shell so that database
# and schema names can never be interpreted as shell syntax. Returns the
# output as a single string; $? holds the exit status as with backticks.
# When $merge_stderr is true, stderr is captured together with stdout.
sub run_psql
{
  my ($merge_stderr, @args) = @_;
  my $pid = open(my $fh, '-|');
  die "Could not fork to run psql: $!" unless defined $pid;
  if ( ! $pid )
  {
    open(STDERR, '>&', \*STDOUT) if $merge_stderr;
    exec('psql', @args);
    # exec failed: report and leave the child immediately, without running
    # the parent's END blocks or destructors.
    print STDERR "Could not run psql: $!\n";
    POSIX::_exit(127);
  }
  my $out = join('', <$fh>);
  close($fh);
  return $out;
}

sub upgrade
{
  die "Please specify at least a database name" unless @_;

  foreach my $db (@_)
  {
    print "upgrading db $db\n";
    # List form of open(): the database name is passed as an argument,
    # never interpolated into a shell command line.
    open(my $SESSION, '|-', 'psql', '-qXtA', $db) || die "Could not connect to database ${db}";
    print $SESSION <<'EOF';
BEGIN;
UPDATE pg_catalog.pg_extension SET extversion = 'ANY'
 WHERE extname IN (
			'postgis',
			'postgis_raster',
			'postgis_sfcgal',
			'postgis_topology',
			'postgis_tiger_geocoder'
  );
SELECT postgis_extensions_upgrade();
COMMIT;
EOF
    close($SESSION);
  }
}

sub status
{
  die "Please specify at least a database name" unless @_;

  foreach my $db (@_)
  {
    my $sql = "
SELECT n.nspname
  FROM pg_namespace n, pg_proc p
  WHERE n.oid = p.pronamespace
    AND p.proname = 'postgis_full_version'
";

		my $SCHEMA = run_psql(1, '-qXtA', $db, '-c', $sql);
		chop($SCHEMA);
		if ( $? ne 0 )
		{
			$SCHEMA =~ s/^.*FATAL: *//;
			print "db $db cannot be inspected: $SCHEMA\n";
			next;
		}

    if ( ! "$SCHEMA" )
		{
      print "db $db does not have postgis enabled\n";
      next;
    }

    # The schema name comes from the catalog and may contain any
    # character, so quote it as an identifier instead of pasting it in.
    $sql="SELECT quote_ident(n.nspname)
  FROM pg_namespace n, pg_proc p
  WHERE n.oid = p.pronamespace
    AND p.proname = 'postgis_full_version'";
    my $QSCHEMA = run_psql(0, '-qXtA', $db, '-c', $sql);
    chop($QSCHEMA);
    $sql="SELECT ${QSCHEMA}.postgis_full_version()";
    my $FULL_VERSION = run_psql(0, '-qXtA', $db, '-c', $sql);
		#print "FULL_VERSION: ${FULL_VERSION}\n";

    #POSTGIS="3.1.0dev r3.1.0alpha1-3-gfc5392de7"
    my $VERSION="unknown";
    if ( $FULL_VERSION =~ /POSTGIS="([^ ]*).*/ )
		{
			$VERSION=$1;
		}

    my $EXTENSION='';
    if ( $FULL_VERSION =~ /\[EXTENSION\]/ )
		{
      $EXTENSION=" as extension";
    }
    my $NEED_UPGRADE='';
    if ( $FULL_VERSION =~ /need upgrade/ )
		{
      $NEED_UPGRADE=" - NEEDS UPGRADE";
    }

    print "db $db has postgis ${VERSION}${EXTENSION} in schema ${SCHEMA}${NEED_UPGRADE}\n";
  }
}

# Avoid NOTICE messages
$ENV{'PGOPTIONS'} = $ENV{'PGOPTIONS'} . ' --client-min-messages=warning';

my $cmd = shift;
if ( $cmd eq "help" ) {
	usage(STDOUT);
	exit 0;
}
elsif ( $cmd eq "enable" ) {
	exit enable(@ARGV);
}
elsif ( $cmd eq "upgrade" ) {
	exit upgrade(@ARGV);
}
elsif ( $cmd eq "status" ) {
	exit status(@ARGV);
}
else {
	print STDERR "Unrecognized command: $cmd\n";
  usage(STDERR);
  exit 1
}
