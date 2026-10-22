#!/usr/bin/perl

#
# PostGIS - Spatial Types for PostgreSQL
# http://postgis.net
#
# Copyright (C) 2020-2022 Sandro Santilli <strk@kbt.io>
#
# This is free software; you can redistribute and/or modify it under
# the terms of the GNU General Public Licence. See the COPYING file.
#

use File::Basename;
use POSIX ();


sub usage
{
	print qq{Usage: $0 <command> [<args>]
Commands:
  help               print this message and exits
  list-all           list all databases
  list-enabled       list PostGIS-enabled databases
  enable <db>...     enable PostGIS in given databases
  upgrade [<db>...]  upgrade PostGIS in given databases (or all)
  status [<db>...]   print PostGIS status in given databases (or all)
  install-extension-upgrades [--pg_sharedir <dir>] [--extension <name>] [<from>...]
		Ensure files required to upgrade PostGIS from
		the given version are installed on the system.
		The <from> arguments may be either version numbers
		or PostgreSQL share directories to scan to find available
		ones.
};

}

my %SUPPORTED_EXTENSIONS = (
	'address_standardizer' => 1,
	'address_standardizer_data_us' => 1,
	'postgis' => 1,
	'postgis_raster' => 1,
	'postgis_sfcgal' => 1,
	'postgis_tiger_geocoder' => 1,
	'postgis_topology' => 1
);


sub install_upgrade_from
{
	my ( $SHAREDIR, $EXTENSION, $from ) = @_;

	#print "SHAREDIR: $SHAREDIR\n";
	#print "FROM: $from\n";
	die "Please specify a sharedir and a version to install upgrade support for.\n"
		unless $from;

	# sanify ${from}
	die "'${from}': invalid version, only 3 dot-separated numbers optionally followed by alphanumeric string are allowed\n"
		unless $from =~ /^[0-9]+\.[0-9]+\.[0-9]+[a-z0-9]*$/;

	# extension to process
	my %extensions = %SUPPORTED_EXTENSIONS;
	my $glob = "postgis*.control";

	if ( defined($EXTENSION) ) {
		%extensions = (
			$EXTENSION => 1
		);
		$glob = $EXTENSION;
	}

	my $EXTDIR = ${SHAREDIR} . '/extension';

	while (my $cfile = glob("${EXTDIR}/${glob}")) {
		# Do stuff
		#print " CFILE: ${cfile}\n";
		my $extname = basename($cfile, '.control');

		unless ( exists( $extensions{$extname} ) )
		{
			if ( defined($EXTENSION) )  {
				print STDERR "ERROR: glob [${glob}] matched unrequested extension [${extname}]\n";
			} else {
				print STDERR "NOTICE: extension [${extname}] is not a core PostGIS extension\n";
			}
			next;
		}

		#print " EXTENSION: [${extname}]\n";

		die "File ${EXTDIR}/${extname}--TEMPLATED--TO--ANY.sql is missing"
			unless -f "${EXTDIR}/${extname}--TEMPLATED--TO--ANY.sql";

		# List form of system(): no shell is involved, so ${from} can never
		# be interpreted as shell syntax.
		my @lncmd = ('ln', '-fs', "${extname}--TEMPLATED--TO--ANY.sql", "${EXTDIR}/${extname}--${from}--ANY.sql");
		#print " CMD: @lncmd\n";
		my $rv = system(@lncmd);
		if ( $rv ) {
			die "Error encountered running: @lncmd: $!";
		}

	}

	return 0; # success
}

sub install_upgrade_from_available
{
	my ($SHAREDIR, $EXTENSION) = @_;
	my $EXTDIR = ${SHAREDIR} . '/extension';

	#print "EXTDIR: ${EXTDIR}\n";

	opendir(my $d, $EXTDIR) || die "Cannot read ${EXTDIR} directory\n";
	my @files = grep { /^postgis--/ && ! /--.*--/ } readdir($d);
	foreach ( @files )
	{
		m/^postgis--(.*)\.sql/;
		my $ver = $1;
		next if $ver eq 'unpackaged'; # we don't want to install upgrade from unpackaged
		print "Found version $ver\n";
		return $rv if my $rv = install_upgrade_from $SHAREDIR, $EXTENSION, $ver;
		#return $rv if $rv; # first failure aborts all
	}
	closedir($d);

	exit 0; # success
}

sub install_extension_upgrades
{
	my $DEFSHAREDIR = `pg_config --sharedir`;
	chop($DEFSHAREDIR);
	my $SHAREDIR = ${DEFSHAREDIR};
	my $EXTENSION;

	my @ver;

	for ( my $i=0; $i<@_; $i++ )
	{
		if ( $_[$i] eq '--pg_sharedir' )
		{
			$i++ < @_ - 1 || die '--pg_sharedir requires an argument';
			$SHAREDIR = $_[$i];
			die "$SHAREDIR is not a directory" unless -d ${SHAREDIR};
			next;
		}
		elsif ( $_[$i] eq '--extension' )
		{
			$i++ < @_ - 1 || die '--extension requires an argument';
			$EXTENSION = $_[$i];
			die "$EXTENSION is not a supported extension"
				unless ( exists( $SUPPORTED_EXTENSIONS{$EXTENSION} ) );
			next;
		}

		push @ver, $_[$i];
	}

	print "Installation target: ${SHAREDIR} ${EXTENSION}\n";

	if ( 0 == @ver )
	{
		print "No versions given, will scan ${SHAREDIR}\n";
		push @ver, ${SHAREDIR};
	}


	foreach ( @ver )
	{
		my $v = $_;
		if ( -d $v ) {
			install_upgrade_from_available($SHAREDIR, ${EXTENSION}, $v);
		} else {
			install_upgrade_from($SHAREDIR, ${EXTENSION}, $v);
		}
	}

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

sub get_all_databases
{
  my $ALL = run_psql(0, '-qXtAc', 'select datname from pg_database where datallowconn', 'template1');
  return split("\n", $ALL);
}

sub list_all_databases
{
  my @ALL = get_all_databases();
  foreach (@ALL)
  {
    print $_ . "\n";
  }
}

sub list_enabled_databases
{
  my @ALL = get_all_databases();
  my $sql = "
    SELECT proname
    FROM pg_proc
    WHERE proname = 'postgis_full_version'
  ";
  foreach my $db (@ALL)
  {
    my $enabled = run_psql(0, '-qXtAc', $sql, $db);
    print $db . "\n" if $enabled ne '';
  }
}

sub enable
{
	print "Enable called with args: @_\n";
  my $db = shift;
  die "Please specify a database name" unless "$db";
  die "Enable is not implemented yet";
}

sub upgrade
{
  my @DB = @_;

  #die "Please specify at least a database name" unless @DB;
  @DB = get_all_databases() unless @DB;

  foreach my $db (@DB)
  {
    print "upgrading PostGIS in db $db if needed\n";
    open(my $SESSION, '|-', 'psql', '-qXtA', $db) || die "Could not connect to database ${db}";
    print $SESSION <<'EOF';
DO $BODY$
BEGIN
  IF EXISTS ( SELECT * FROM pg_proc where proname = 'postgis_extensions_upgrade' )
  THEN
    UPDATE pg_catalog.pg_extension SET extversion = 'ANY'
    WHERE extname IN (
      'postgis',
      'postgis_raster',
      'postgis_sfcgal',
      'postgis_topology',
      'postgis_tiger_geocoder'
    );
    PERFORM postgis_extensions_upgrade();
  END IF;
END;
$BODY$ LANGUAGE 'plpgsql';
EOF
    @out = <$SESSION>;
    print @out;
    close($SESSION);
  }
}

sub status
{
  my @DB = @_;

  @DB = get_all_databases() unless @DB;

  foreach my $db (@DB)
  {
    my $sql = "
SELECT quote_ident(n.nspname)
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

    $sql="SELECT ${SCHEMA}.postgis_full_version()";
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
		elsif ( $FULL_VERSION =~ /deprecated functions/ )
		{
			$NEED_UPGRADE=" - NEEDS UPGRADE (HAS DEPRECATED FUNCTIONS)";
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
elsif ( $cmd eq "list-all" ) {
	exit list_all_databases(@ARGV);
}
elsif ( $cmd eq "list-enabled" ) {
	exit list_enabled_databases(@ARGV);
}
elsif ( $cmd eq "upgrade" ) {
	exit upgrade(@ARGV);
}
elsif ( $cmd eq "status" ) {
	exit status(@ARGV);
}
elsif ( $cmd eq "install-extension-upgrades" ) {
	exit install_extension_upgrades(@ARGV);
}
else {
	print STDERR "Unrecognized command: $cmd\n";
  usage(STDERR);
  exit 1
}
