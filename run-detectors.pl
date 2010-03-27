#! /usr/bin/perl -w

# Copyright (c) 2002 Colin Watson <cjwatson@debian.org>.
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

use Binfmt::Lib qw($admindir $procdir quit warning);
use Binfmt::Format;

my @formats;

# Load in all our binary formats.
local *ADMINDIR;
unless (opendir ADMINDIR, $admindir) {
    quit "unable to open $admindir: $!";
}
for my $name (readdir ADMINDIR) {
    if (-f "$admindir/$name" and -e "$procdir/$name") {
	my $format = Binfmt::Format->load ($name, "$admindir/$name");
	$format->{magic} =~ s/\\x(..)/chr hex $1/eg;
	$format->{mask}  =~ s/\\x(..)/chr hex $1/eg;
	$format->{offset} ||= 0;
	push @formats, $format if defined $format;
    }
}
closedir ADMINDIR;

# Find out how much of the file we need to read. The kernel doesn't
# currently let this be more than 128, so we shouldn't need to worry about
# huge memory consumption.
my $toread = 0;
for my $format (@formats) {
    if ($format->{type} eq 'magic') {
	my $size = $format->{offset} + length $format->{magic};
	$toread = $size if $size > $toread;
    }
}

my $buf = '';
if ($toread) {
    local *TARGET;
    open TARGET, $ARGV[0] or quit "unable to open $ARGV[0]: $!";
    read TARGET, $buf, $toread;
    close TARGET;
}

# Now the horrible bit. Since there isn't a real way to plug userspace
# detectors into the kernel (which is why this program exists in the first
# place), we have to redo the kernel's work. Luckily it's a fairly simple
# job ... see linux/fs/binfmt_misc.c:check_file().
#
# There is a small race between the kernel performing this check and us
# performing it. I don't believe that this is a big deal; certainly there
# can be no privilege elevation involved unless somebody deliberately makes
# a set-id binary a binfmt handler, in which case "don't do that, then".

my $extension;
$ARGV[0] =~ /\.([^.]*)/ and $extension = $1;

my @ok_formats;
for my $format (@formats) {
    if ($format->{type} eq 'magic') {
	my $segment = substr $buf, $format->{offset}, length $format->{magic};
	$segment = "$segment" & "$format->{mask}" if length $format->{mask};
	push @ok_formats, $format if $segment eq $format->{magic};
    } else {
	push @ok_formats, $format
	    if defined $extension and $extension eq $format->{magic};
    }
}

# Everything in @ok_formats is now a candidate. Loop through twice, once to
# try everything with a detector and once to try everything without. As soon
# as one succeeds, exec() it.

for my $format (@ok_formats) {
    if (length $format->{detector}) {
	my $status = system $format->{detector}, $ARGV[0];
	$status /= 256;	# actual exit value
	if ($status == 0) {
	    exec $format->{interpreter}, @ARGV
		or warning "unable to exec $format->{interpreter} (@ARGV): $!";
	}
    }
}

for my $format (@ok_formats) {
    unless (length $format->{detector}) {
	exec $format->{interpreter}, @ARGV
	    or warning "unable to exec $format->{interpreter} (@ARGV): $!";
    }
}

quit "unable to find an interpreter for $ARGV[0]";
