#! /usr/bin/perl -w

# Copyright (c) 2000, 2001, 2002 Colin Watson <cjwatson@debian.org>.
# See update-binfmts(8) for documentation.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

use strict;

use POSIX qw(uname);
use Text::Wrap;
use Binfmt::Lib qw($admindir $importdir $procdir $auxdir $cachedir quit warning);
use Binfmt::Format;

my $VERSION = '@VERSION@';

$Text::Wrap::columns = 79;

use vars qw($test);

my $register = "$procdir/register";
my $status = "$procdir/status";
my $run_detectors = "$auxdir/run-detectors";

my %formats;

# Various "print something and exit" routines.

sub version ()
{
    print "update-binfmts $VERSION.\n"
	or die "unable to write version message: $!";
}

sub usage ()
{
    version;
    print <<EOF
Copyright (c) 2000, 2001, 2002 Colin Watson. This is free software; see
the GNU General Public License version 2 or later for copying conditions.

Usage:

  update-binfmts [options] --install <name> <path> <spec>
  update-binfmts [options] --remove <name> <path>
  update-binfmts [options] --import [<name>]
  update-binfmts [options] --display [<name>]
  update-binfmts [options] --enable [<name>]
  update-binfmts [options] --disable [<name>]

  where <spec> is one of:

    --magic <byte-sequence> [--mask <byte-sequence>] [--offset <offset>]
    --extension <extension>

  The following argument may be added to any <spec> to have a userspace
  process determine whether the file should be handled:

    --detector <path>

Options:

    --package <package-name>    for --install and --remove, specify the
                                current package name
    --admindir <directory>      use <directory> instead of /var/lib/binfmts
                                as administration directory
    --importdir <directory>     use <directory> instead of /usr/share/binfmts
                                as import directory
    --cachedir <directory>      use <directory> instead of /var/cache/binfmts
                                as cache directory
    --test                      don't do anything, just demonstrate
    --help                      print this help screen and exit
    --version                   output version and exit

EOF
	or die "unable to write usage message: $!";
}

sub usage_quit ($;@)
{
    my $me = $0;
    $me =~ s#.*/##;
    print STDERR wrap '', '', "$me:", @_, "\n";
    usage;
    exit 2;
}

sub check_supported_os ()
{
    my $sysname = (uname)[0];
    return if $sysname eq 'Linux';
    print <<EOF;
Sorry, update-binfmts currently only works on Linux.
EOF
    if ($sysname eq 'GNU') {
	print <<EOF;
Patches for Hurd support are welcomed; they should not be difficult.
EOF
    }
    exit 0;
}

# Make sure options are unambiguous.

sub check_modes ($$)
{
    return unless $_[0];
    usage_quit "two modes given: --$_[0] and $_[1]";
}

sub check_types ($$)
{
    return unless $_[0];
    usage_quit "two binary format specifications given: --$_[0] and $_[1]";
}

sub rename_mv ($$)
{
    my ($source, $dest) = @_;
    return (rename($source, $dest) || (system('mv', $source, $dest) == 0));
}

sub get_import ($)
{
    my $name = shift;
    my %import;
    local *IMPORT;
    unless (open IMPORT, "< $name") {
	warning "unable to open $name: $!";
	return;
    }
    local $_;
    while (<IMPORT>) {
	chomp;
	my ($name, $value) = split ' ', $_, 2;
	$import{lc $name} = $value;
    }
    close IMPORT;
    return %import;
}

# Loading and unloading logic, which should cope with the various ways this
# has been implemented.

sub get_binfmt_style ()
{
    my $style;
    local *FS;
    unless (open FS, '/proc/filesystems') {
	# Weird. Assume procfs.
	warning "unable to open /proc/filesystems: $!";
	return 'procfs';
    }
    if (grep m/\bbinfmt_misc\b/, <FS>) {
	# As of 2.4.3, the official Linux kernel still uses the original
	# interface, but Alan Cox's patches add a binfmt_misc filesystem
	# type which needs to be mounted separately. This may get into the
	# official kernel in the future, so support both.
	$style = 'filesystem';
    } else {
	# The traditional interface.
	$style = 'procfs';
    }
    close FS;
    return $style;
}

sub load_binfmt_misc ()
{
    if ($test) {
	print "load binfmt_misc\n";
	return 1;
    }

    my $style = get_binfmt_style;
    # If the style is 'filesystem', then we must already have the module
    # loaded, as binfmt_misc wouldn't show up in /proc/filesystems
    # otherwise.
    if ($style eq 'procfs' and not -f $register) {
	if (not -x '/sbin/modprobe' or
	    system qw(/sbin/modprobe -q binfmt_misc)) {
	    warning "Couldn't load the binfmt_misc module.";
	    return 0;
	}
    }

    unless (-d $procdir) {
	warning "binfmt_misc module seemed to be loaded, but no $procdir",
		"directory! Giving up.";
	return 0;
    }

    # Find out what the style looks like now.
    $style = get_binfmt_style;
    if ($style eq 'filesystem' and not -f $register) {
	if (system ('/bin/mount', '-t', 'binfmt_misc',
		    '-o', 'nodev,noexec,nosuid', 'binfmt_misc', $procdir)) {
	    warning "Couldn't mount the binfmt_misc filesystem on $procdir.";
	    return 0;
	}
    }

    if (-f $register) {
	local *STATUS;
	if (open STATUS, "> $status") {
	    print STATUS "1\n";
	    close STATUS;
	} else {
	    warning "unable to open $status for writing: $!";
	}
	return 1;
    } else {
	warning "binfmt_misc initialized, but $register missing! Giving up.";
	return 0;
    }
}

sub unload_binfmt_misc ()
{
    my $style = get_binfmt_style;

    if ($test) {
	print "unload binfmt_misc ($style)\n";
	return 1;
    }

    if ($style eq 'filesystem') {
	if (system '/bin/umount', $procdir) {
	    warning "Couldn't unmount the binfmt_misc filesystem from",
		    "$procdir.";
	    return 0;
	}
    }
    # We used to try to unload the kernel module as well, but it seems that
    # it doesn't always unload properly (http://bugs.debian.org/155570) and
    # in any case it means that strictly speaking we have to remember if the
    # module was loaded when we started. Since it's not actually important,
    # we now just don't bother.
    return 1;
}

# Reading the administrative directory.
sub load_format ($;$)
{
    my $name = shift;
    my $quiet = shift;
    if (-f "$admindir/$name") {
	my $format = Binfmt::Format->load ($name, "$admindir/$name", $quiet);
	$formats{$name} = $format if defined $format;
    }
}

sub load_all_formats (;$)
{
    my $quiet = shift;
    local *ADMINDIR;
    unless (opendir ADMINDIR, $admindir) {
	quit "unable to open $admindir: $!";
    }
    for my $name (readdir ADMINDIR) {
	load_format $name, $quiet;
    }
    closedir ADMINDIR;
}

# Actions.

# Enable a binary format in the kernel.
sub act_enable (;$);
sub act_enable (;$)
{
    my $name = shift;
    if (defined $name) {
	my $cacheonly = 0;
	$cacheonly = 1 unless load_binfmt_misc;
	$cacheonly = 1 if -e "$procdir/$name";
	load_format $name;
	unless ($test or exists $formats{$name}) {
	    warning "$name not in database of installed binary formats.";
	    return 0;
	}
	my $binfmt = $formats{$name};
	my $type = ($binfmt->{type} eq 'magic') ? 'M' : 'E';

	my $need_detector = (defined $binfmt->{detector} and
			     length $binfmt->{detector}) ? 1 : 0;
	unless ($need_detector) {
	    # Scan the format database to see if anything else uses the same
	    # spec as us. If so, assume that we need a detector, effectively
	    # /bin/true. Don't actually set $binfmt->{detector} though,
	    # since run-detectors optimizes the case of empty detectors and
	    # "runs" them last.
	    load_all_formats 'quiet';
	    for my $id (keys %formats) {
		next if $id eq $name;
		if ($binfmt->equals ($formats{$id})) {
		    $need_detector = 1;
		    last;
		}
	    }
	}
	# Fake the interpreter if we need a userspace detector program.
	my $interpreter = $need_detector ? $run_detectors
					 : $binfmt->{interpreter};

	my $flags = (defined $binfmt->{credentials} and
		     $binfmt->{credentials} eq 'yes') ? 'C' : '';

	my $regstring = ":$name:$type:$binfmt->{offset}:$binfmt->{magic}" .
			":$binfmt->{mask}:$interpreter:$flags\n";
	if ($test) {
	    print "enable $name with the following format string:\n",
		  " $regstring";
	} else {
	    local *CACHE;
	    if (open CACHE, ">$cachedir/$name") {
	        print CACHE $regstring;
		close CACHE or warning "unable to close $cachedir/$name: $!";
	    } else {
		warning "unable to open $cachedir/$name for writing: $!";
	    }
	    unless ($cacheonly) {
	        local *REGISTER;
	        unless (open REGISTER, ">$register") {
		    warning "unable to open $register for writing: $!";
		    return 0;
	        }
	        print REGISTER $regstring;
	        unless (close REGISTER) {
	 	    warning "unable to close $register: $!";
		    return 0;
	        }
	    }
	}
	return 1;
    } else {
	my $worked = 1;
	load_all_formats;
	for my $id (keys %formats) {
	    $worked &= act_enable $id;
	}
	return $worked;
    }
}

# Disable a binary format in the kernel.
sub act_disable (;$);
sub act_disable (;$)
{
    my $name = shift;
    return 1 unless -d $procdir;    # We're disabling anyway, so we don't mind
    if (defined $name) {
	unless (-e "$procdir/$name") {
	    # Don't warn in this circumstance, as it could happen e.g. when
	    # binfmt-support and a package depending on it are upgraded at
	    # the same time, so we get called when stopped. Just pretend
	    # that the disable operation succeeded.
	    return 1;
	}

	# We used to check the entry in $procdir to make sure we were
	# removing an entry with the same interpreter, but this is bad; it
	# makes things really difficult for packages that want to change
	# their interpreter, for instance. Now we unconditionally remove and
	# rely on the calling logic to check that the entry in $admindir
	# belongs to the same package.
	# 
	# In other words, $admindir becomes the canonical reference, not
	# $procdir. This is in line with similar update-* tools in Debian.

	if ($test) {
	    print "disable $name\n";
	} else {
	    local *PROCENTRY;
	    unless (open PROCENTRY, ">$procdir/$name") {
		warning "unable to open $procdir/$name for writing: $!";
		return 0;
	    }
	    print PROCENTRY -1;
	    unless (close PROCENTRY) {
		warning "unable to close $procdir/$name: $!";
		return 0;
	    }
	    if (-e "$procdir/$name") {
		warning "removal of $procdir/$name ignored by kernel!";
		return 0;
	    }
	}
	return 1;
    }
    else
    {
	my $worked = 1;
	load_all_formats;
	for my $id (keys %formats) {
	    if (-e "$procdir/$id") {
		$worked &= act_disable $id;
	    }
	}
	unload_binfmt_misc;	# ignore errors here
	return $worked;
    }
}

# Install a binary format into binfmt-support's database. Attempt to enable
# the new format in the kernel as well.
sub act_install ($$)
{
    my $name = shift;
    my $binfmt = shift;
    load_format $name, 'quiet';
    if (exists $formats{$name}) {
	# For now we just silently zap any old versions with the same
	# package name (has to be silent or upgrades are annoying). Maybe we
	# should be more careful in the future.
	my $package = $binfmt->{package};
	my $old_package = $formats{$name}{package};
	unless ($package eq $old_package) {
	    $package     = '<local>' if $package eq ':';
	    $old_package = '<local>' if $old_package eq ':';
	    warning "current package is $package, but binary format already",
		    "installed by $old_package";
	    return 0;
	}
    }
    # Separate test just in case the administrative file exists but is
    # corrupt.
    if (-f "$admindir/$name") {
	unless (act_disable $name) {
	    warning "unable to disable binary format $name";
	    return 0;
	}
    }
    if (-e "$procdir/$name" and not $test) {
	# This is a bit tricky. If we get here, then the kernel knows about
	# a format we don't. Either somebody has used binfmt_misc directly,
	# or update-binfmts did something wrong. For now we do nothing;
	# disabling and re-enabling all binary formats will fix this anyway.
	# There may be a --force option in the future to help with problems
	# like this.
	# 
	# Disabled for --test, because otherwise it never works; the
	# vagaries of binfmt_misc mean that it isn't really possible to find
	# out from userspace exactly what's going to happen if people have
	# been bypassing update-binfmts.
	warning "found manually created entry for $name in $procdir;",
		"leaving it alone";
	return 1;
    }

    if ($test) {
	print "install the following binary format description:\n";
	$binfmt->dump_stdout;
    } else {
	$binfmt->write ("$admindir/$name.tmp") or return 0;
	unless (rename_mv "$admindir/$name.tmp", "$admindir/$name") {
	    warning "unable to install $admindir/$name.tmp as",
		    "$admindir/$name: $!";
	    return 0;
	}
    }
    $formats{$name} = $binfmt;
    unless (act_enable $name) {
	warning "unable to enable binary format $name";
	return 0;
    }
    return 1;
}

# Remove a binary format from binfmt-support's database. Attempt to disable
# the format in the kernel first.
sub act_remove ($$)
{
    my $name = shift;
    my $package = shift;
    unless (-f "$admindir/$name") {
	# There may be a --force option in the future to allow entries like
	# this to be removed; either they were created manually or
	# update-binfmts was broken.
	warning "$admindir/$name does not exist; nothing to do!";
	return 1;
    }
    load_format $name, 'quiet';
    if (exists $formats{$name}) {
	my $old_package = $formats{$name}{package};
	unless ($package eq $old_package) {
	    $package     = '<local>' if $package eq ':';
	    $old_package = '<local>' if $old_package eq ':';
	    warning "current package is $package, but binary format already",
		    "installed by $old_package; not removing.";
	    # I don't think this should be fatal.
	    return 1;
	}
    }
    unless (act_disable $name) {
	warning "unable to disable binary format $name";
	return 0;
    }
    if ($test) {
	print "remove $admindir/$name\n";
    } else {
	unless (unlink "$admindir/$name") {
	    warning "unable to remove $admindir/$name: $!";
	    return 0;
	}
	delete $formats{$name};
	unlink "$cachedir/$name";
    }
    return 1;
}

# Import a new format file into binfmt-support's database. This is intended
# for use by packaging systems.
sub act_import (;$);
sub act_import (;$)
{
    my $name = shift;
    if (defined $name) {
	my $id;
	if ($name =~ m!.*/(.*)!) {
	    $id = $1;
	} else {
	    $id = $name;
	    $name = "$importdir/$name";
	}

	if ($id =~ /^(\.\.?|register|status)$/) {
	    warning "binary format name '$id' is reserved";
	    return 0;
	}

	my %import = get_import $name;
	unless (scalar keys %import) {
	    warning "couldn't find information about '$id' to import";
	    return 0;
	}

	load_format $id, 'quiet';
	if (exists $formats{$id}) {
	    if ($formats{$id}{package} eq ':') {
		# Installed version was installed manually, so don't import
		# over it.
		warning "preserving local changes to $id";
		return 1;
	    } else {
		# Installed version was installed by a package, so it should
		# be OK to replace it.
	    }
	}

	# TODO: This duplicates the verification code below slightly.
	unless (defined $import{package}) {
	    warning "$name: required 'package' line missing";
	    return 0;
	}

	unless (-x $import{interpreter}) {
	    warning "$name: no executable $import{interpreter} found, but",
		    "continuing anyway as you request";
	}

	act_install $id, Binfmt::Format->new ($name, %import);
	return 1;
    } else {
	local *IMPORTDIR;
	unless (opendir IMPORTDIR, $importdir) {
	    warning "unable to open $importdir: $!";
	    return 0;
	}
	my $worked = 1;
	for (readdir IMPORTDIR) {
	    next unless -f "$importdir/$_";
	    if (-f "$importdir/$_") {
		$worked &= act_import $_;
	    }
	}
	closedir IMPORTDIR;
	return $worked;
    }
}

# Display a format stored in binfmt-support's database.
sub act_display (;$);
sub act_display (;$)
{
    my $name = shift;
    if (defined $name) {
	print "$name (", (-e "$procdir/$name" ? 'enabled' : 'disabled'),
	      "):\n";
	load_format $name;
	my $binfmt = $formats{$name};
	my $package = $binfmt->{package} eq ':' ? '<local>'
						: $binfmt->{package};
	print <<EOF;
     package = $package
        type = $binfmt->{type}
      offset = $binfmt->{offset}
       magic = $binfmt->{magic}
        mask = $binfmt->{mask}
 interpreter = $binfmt->{interpreter}
    detector = $binfmt->{detector}
EOF
    } else {
	load_all_formats;
	for my $id (keys %formats) {
	    act_display $id;
	}
    }
    return 1;
}

# Now go.

check_supported_os;

my @modes = qw(install remove import display enable disable);
my @types = qw(magic extension);

my ($package, $name);
my ($mode, $type);
my %spec;

my %unique_options = (
    'package'	=> \$package,
    'mask'	=> \$spec{mask},
    'offset'	=> \$spec{offset},
    'detector'  => \$spec{detector},
);

my %arguments = (
    'admindir'	=> ['path' => \$admindir],
    'importdir'	=> ['path' => \$importdir],
    'cachedir'	=> ['path' => \$cachedir],
    'install'	=> ['name' => \$name, 'path' => \$spec{interpreter}],
    'remove'	=> ['name' => \$name, 'path' => \$spec{interpreter}],
    'package'	=> ['package-name' => \$package],
    'magic'	=> ['byte-sequence' => \$spec{magic}],
    'extension'	=> ['extension' => \$spec{extension}],
    'mask'	=> ['byte-sequence' => \$spec{mask}],
    'offset'	=> ['offset' => \$spec{offset}],
    'detector'  => ['path' => \$spec{detector}],
);

my %parser = (
    'help'	=> sub { usage; exit 0; },
    'version'	=> sub { version; exit 0; },
    'test'	=> sub { $test = 1; },
    'install'	=> sub {
	-x $spec{interpreter}
	    or warning "no executable $spec{interpreter} found, but",
		       "continuing anyway as you request";
    },
    'remove'	=> sub {
	-x $spec{interpreter}
	    or warning "no executable $spec{interpreter} found, but",
		       "continuing anyway as you request";
    },
    'import'	=> sub { $name = (@ARGV >= 1) ? shift @ARGV : undef; },
    'display'	=> sub { $name = (@ARGV >= 1) ? shift @ARGV : undef; },
    'enable'	=> sub { $name = (@ARGV >= 1) ? shift @ARGV : undef; },
    'disable'	=> sub { $name = (@ARGV >= 1) ? shift @ARGV : undef; },
    'offset'	=> sub {
	$spec{offset} =~ /^\d+$/
	    or usage_quit 'offset must be a whole number';
    },
    'detector'  => sub {
	-x $spec{detector}
	    or warning "no executable $spec{detector} found, but",
		       "continuing anyway as you request";
    },
);

while (defined($_ = shift))
{
    last if /^--$/;
    if (!/^--(.+)$/) {
	usage_quit "unknown argument '$_'";
    }
    my $option = $1;
    my $is_mode = grep { $_ eq $option } @modes;
    my $is_type = grep { $_ eq $option } @types;
    my $has_args = exists $arguments{$option};

    unless ($is_mode or $is_type or $has_args or exists $parser{$option}) {
	usage_quit "unknown argument '$_'";
    }

    check_modes $mode, $option if $is_mode;
    check_types $type, $option if $is_type;

    if (exists $unique_options{$option} and
	defined ${$unique_options{$option}}) {
	usage_quit "more than one --$option option given";
    }

    if ($has_args) {
	my (@descs, @varrefs);
	# Split into descriptions and variable references.
	my $alt = 0;
	foreach my $arg (@{$arguments{$option}}) {
	    if (($alt = !$alt))	{ push @descs, "<$arg>"; }
	    else		{ push @varrefs, $arg; }
	}
	usage_quit "--$option needs @descs" unless @ARGV >= @descs;
	foreach my $varref (@varrefs) { $$varref = shift @ARGV; }
    }

    &{$parser{$option}} if defined $parser{$option};

    $mode = $option if $is_mode;
    $type = $option if $is_type;
}

$package = ':' unless defined $package;

unless (defined $mode) {
    usage_quit 'you must use one of --install, --remove, --import, --display,',
	       '--enable, --disable';
}

my $binfmt;
if ($mode eq 'install') {
    defined $type or usage_quit '--install requires a <spec> option';
    if ($name =~ /^(\.\.?|register|status)$/) {
	usage_quit "binary format name '$name' is reserved";
    }
    $binfmt = Binfmt::Format->new ($name, package => $package, type => $type,
				   %spec);
}

my %actions = (
    'install'	=> [\&act_install, $binfmt],
    'remove'	=> [\&act_remove, $package],
    'import'	=> [\&act_import],
    'display'	=> [\&act_display],
    'enable'	=> [\&act_enable],
    'disable'	=> [\&act_disable],
);

unless (exists $actions{$mode}) {
    usage_quit "unknown mode: $mode";
}

my @actargs = @{$actions{$mode}};
my $actsub = shift @actargs;
if ($actsub->($name, @actargs)) {
    exit 0;
} else {
    quit 'exiting due to previous errors';
}
