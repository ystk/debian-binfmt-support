package Binfmt::Format;

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

use Errno qw(ENOENT);
use Binfmt::Lib qw(quit warning);

my @fields = qw(package type offset magic mask interpreter);
my @optional_fields = qw(detector credentials);

sub load ($$$;$)
{
    my $class = shift;
    my $name = shift;
    my $filename = shift;
    my $quiet = shift;
    my $self = {name => $name};
    local *BINFMT;
    open BINFMT, "< $filename" or quit "unable to open $filename: $!";
    for my $field (@fields) {
	$self->{$field} = <BINFMT>;
	unless (defined $self->{$field}) {
	    if ($quiet) {
		return;
	    } else {
		quit "$filename corrupt: out of binfmt data reading $field";
	    }
	}
    }
    for my $field (@optional_fields) {
	$self->{$field} = <BINFMT>;
	$self->{$field} = '' unless defined $self->{$field};
    }
    close BINFMT;
    chomp $self->{$_} for keys %$self;
    return bless $self, $class;
}

sub new ($$%)
{
    my $class = shift;
    my $name = shift;
    my $self = {name => $name};
    while (@_) {    # odd number of arguments => last value undef
	my $key = shift;
	my $value = shift;
	# $value may be undef, as update-binfmts' parser is simpler that way.
	if (defined $value and $value =~ /\n/) {
	    quit "newlines prohibited in binfmt files ($value)";
	}
	$self->{$key} = $value;
    }

    unless (defined $self->{type}) {
	if (defined $self->{magic}) {
	    if (defined $self->{extension}) {
		warning "$name: can't use both --magic and --extension";
		return undef;
	    } else {
		$self->{type} = 'magic';
	    }
	} else {
	    if (defined $self->{extension}) {
		$self->{type} = 'extension';
	    } else {
		warning "$name: either --magic or --extension is required";
		return undef;
	    }
	}
    }

    if ($self->{type} eq 'extension') {
	$self->{magic} = $self->{extension};
	if (defined $self->{mask}) {
	    warning "$name: can't use --mask with --extension";
	    return undef;
	}
	if (defined $self->{offset}) {
	    warning "$name: can't use --offset with --extension";
	    return undef;
	}
    }
    delete $self->{extension};

    $self->{mask} = '' unless defined $self->{mask};
    $self->{offset} ||= 0;

    return bless $self, $class;
}

sub write ($;$)
{
    my $self = shift;
    my $filename = shift;

    unless (unlink $filename) {
	if ($! != ENOENT) {
	    warning "unable to ensure $filename nonexistent: $!";
	    return 0;
	}
    }
    local *BINFMT;
    unless (open BINFMT, "> $filename") {
	warning "unable to open $filename for writing: $!";
	return 0;
    }

    for my $field (@fields, @optional_fields) {
	print BINFMT (defined ($self->{$field}) ? $self->{$field} : ''), "\n";
    }

    unless (close BINFMT) {
	warning "unable to close $filename: $!";
	return 0;
    }

    return 1;
}

sub dump_stdout ($)
{
    my $self = shift;
    for my $field (@fields, @optional_fields) {
	printf "%12s = %s\n", $field,
	    (defined $self->{$field}) ? $self->{$field} : '';
    }
}

sub equals ($$)
{
    my $self = shift;
    my $other = shift;
    for my $field (qw(type offset magic mask)) {
	return 0 if $self->{$field} ne $other->{$field};
    }
    return 1;
}

1;
