package Binfmt::Lib;

# Copyright (c) 2000, 2001, 2002 Colin Watson <cjwatson@debian.org>.
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

# There are no published interfaces here. If you base code outside
# binfmt-support on this package, it may be broken at any time.

use strict;
use vars qw(@ISA @EXPORT_OK $admindir $importdir $procdir $auxdir $cachedir);

use Text::Wrap;

use Exporter ();
@ISA = qw(Exporter);
@EXPORT_OK = qw($admindir $importdir $procdir $auxdir $cachedir quit warning);

$admindir  = '/var/lib/binfmts';
$importdir = '/usr/share/binfmts';
$procdir   = '/proc/sys/fs/binfmt_misc';
$auxdir    = '/usr/share/binfmt-support';
$cachedir  = '/var/cache/binfmts';

sub quit ($;@)
{
    my $me = $0;
    $me =~ s#.*/##;
    print STDERR wrap '', '', "$me:", @_, "\n";
    exit 2;
}

# Something has gone wrong, but not badly enough for us to give up.
sub warning ($;@) {
    my $me = $0;
    $me =~ s#.*/##;
    print STDERR wrap '', '', "$me: warning:", @_, "\n";
}

1;
