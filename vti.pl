#!/usr/bin/env perl
# vti.pl

use strict;
use warnings;
use Getopt::Std;
use Carp;
use File::Basename;

# Include ctkn package.
my $ctkn_path = dirname($0) . "/ctkn.pl";;
require "$ctkn_path";

# globals
my $tool = "vti.pl";
my $usage_str = "$tool [-d] [-h] [<file>...]";

# process options.
use vars qw($opt_h $opt_d);
getopts('dh') || usage();

if (defined($opt_h)) {
	help();
}

# Create ctkn object.
my $ctkn;
if (defined($opt_d)) {
  $ctkn = ctkn_new("cd");
} else {
  $ctkn = ctkn_new("c");
}

my @lines = <>;  # Read whole page in as a single string.
my $page = join(" ", @lines);

$page =~ s/\n//gs;

$page =~ s/^.*root.App.main = //s;
$page =~ s/\(this\).*$//s;

ctkn_input($ctkn, $page, "vti:1");
ctkn_eof($ctkn);

###  print STDERR ctkn_dump($ctkn);

my $i = 0;

my $root = get_hash($ctkn, "root");

my $price = $root->{"context"}->{"dispatcher"}->{"stores"}->{"StreamDataStore"}->{"quoteData"}->{"VTI"}->{"regularMarketPrice"}->{"fmt"};
$price =~ s/\.//;  # remove decimal point (want in pennies).

print "$price\n";

# All done.
exit(0);


# End of main program, start subroutines.

sub get_hash {
  my($ctkn, $name) = @_;
  my $this = {};

  ((ctkn_vals($ctkn)->[$i]) eq '{') || croak("tkn $i=" . (ctkn_vals($ctkn)->[$i]) . ", expected {");
  $i++;

  if (ctkn_vals($ctkn)->[$i] eq '}') {  # empty hash
    $i++;
    return $this;  # Done!
  }

  while (1) {
    my $key = ctkn_vals($ctkn)->[$i];
    $i++;

    (ctkn_vals($ctkn)->[$i] eq ':') || croak("tkn $i=" . ctkn_vals($ctkn)->[$i] . ", expected :; key=$key");
    $i++;

    my $val;
    if (ctkn_vals($ctkn)->[$i] eq '{') {
      $val = get_hash($ctkn, "${name}.$key");
    } elsif (ctkn_vals($ctkn)->[$i] eq '[') {
      $val = get_array($ctkn, "${name}.$key");
    } else {
      $val = ctkn_vals($ctkn)->[$i];
      $i++;
    }

    $this->{$key} = $val;
    ###print STDERR "???${name}{$key}='$val'\n";

    if (ctkn_vals($ctkn)->[$i] eq '}') {
      $i++;
      return $this;  # Done!
    } elsif (ctkn_vals($ctkn)->[$i] eq ',') {
      $i++;
    } else {
      croak("tkn $i=" . ctkn_vals($ctkn)->[$i] . ", expected } or ,");
    }
  }  # while 1
}  # get_hash

sub get_array {
  my($ctkn, $name) = @_;
  my $this = [];
  my $j = 0;

  (ctkn_vals($ctkn)->[$i] eq '[') || croak("tkn $i=" . ctkn_vals($ctkn)->[$i] . ", expected [");
  $i++;

  if (ctkn_vals($ctkn)->[$i] eq ']') {  # empty array
    $i++;
    return $this;
  }

  while (1) {
    my $val;
    if (ctkn_vals($ctkn)->[$i] eq '{') {
      $val = get_hash($ctkn, "${name}[$j]");
    } elsif (ctkn_vals($ctkn)->[$i] eq '[') {
      $val = get_array($ctkn, "${name}[$j]");
    } else {
      $val = ctkn_vals($ctkn)->[$i];
      $i++;
    }

    $this->[$j] = $val;
    ###print STDERR "???${name}[$j]='$val'\n";
    $j++;

    if (ctkn_vals($ctkn)->[$i] eq ']') {
      $i++;
      return $this;
    } elsif (ctkn_vals($ctkn)->[$i] eq ',') {
      $i++;
    } else {
      croak("tkn $i=" . ctkn_vals($ctkn)->[$i] . ", expected ] or ,");
    }
  }  # while 1
}  # get_array

sub usage {
	my($err_str) = @_;

	if (defined $err_str) {
		print STDERR "$tool: $err_str\n\n";
	}
	print STDERR "Usage: $usage_str\n\n";

	exit(1);
}  # usage


sub help {
	my($err_str) = @_;

	if (defined $err_str) {
		print "$tool: $err_str\n\n";
	}
	print <<__EOF__;
Usage: $usage_str
Where:
    -h - help
    -d - debug
    <file>... - zero or more input files.  If omitted, inputs from stdin.

__EOF__

	exit(0);
}  # help
