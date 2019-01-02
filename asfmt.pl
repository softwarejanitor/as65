#!/usr/bin/perl -w

#
# asfmt.pl
#
# Simple 65C02 assembler source formatter.
#
# 20181219 LSH
#

use strict;

my $debug = 0;

sub usage {
  print "Usage:\n";
  print "$0 [-h] <input_file>\n";
  print " -h : This help\n";
}

# Process command line arguments.
while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  # Help.
  if ($ARGV[0] eq '-h') {
    usage();
    exit;
  } else {
    die "Invalid argument $ARGV[0]\n";
  }
}

my $input_file = shift;

die "Must supply input filename\n" unless defined $input_file && $input_file;

sub parse_line {
  my ($line, $lineno) = @_;

  my ($label, $mnemonic, $operand, $comment) = ('', '', '', '');
  if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s*(;.*)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = $4;
  } elsif ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s*$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = '';
  } elsif ($line =~ /^\s+(\S+)\s+(\S+)\s*(;.*)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = $3;
  } elsif ($line =~ /^\s+(\S+)\s+(\S+)\s*$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = '';
    if ($operand =~ /^;/) {
      $comment = $operand;
      $operand = '';
    }
  } elsif ($line =~ /^\s+(\S+)\s*(;.*)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = '';
    $comment = $2;
  } elsif ($line =~ /^\s+(\S+)\s*$/) {
    $label = '';
    $mnemonic = $1;
    $operand = '';
    $comment = '';
  } elsif ($line =~ /^(\S+)\s*$/) {
    $label = $1;
    $mnemonic = '';
    $operand = '';
    $comment = '';
  } elsif ($line =~ /^(\S+)\s+(\S+)\s*$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = '';
    $comment = '';
  } elsif ($line =~ /^\s+(\S+)\s*(;.*)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = '';
    $comment = $2;
  } elsif ($line =~ /^(\S+)\s+(\S+)\s*(;.*)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = '';
    $comment = $3;
  } elsif ($line =~ /^(\S+)\s*(;.*)$/) {
    $label = $1;
    $mnemonic = '';
    $operand = '';
    $comment = $2;
  } elsif ($line =~ /^(\S+)\s+([Aa][Ss][Cc])\s+(".+"[,]*[0-9a-fA-F]*)\s+(;.*)$|^(\S+)\s+([Ddl[Cc][Ii])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^(\S+)\s+([Ii][Nn][Vv])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^(\S+)\s+([Ff][Ll][Ss])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^(\S+)\s+([Rr][Ee][Vv])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^(\S+)\s+([Ss][Tt][Rr])\s+(".+"[0-9a-fA-F]*)\s*(;.*)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = $4;
  } elsif ($line =~ /^\s+([Aa][Ss][Cc])\s+(".+"[,]*[0-9a-fA-F]*)\s+(;.*)$|^\s+([Dd][Cc][Ii])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^\s+([Ii][Nn][Vv])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^\s+([Ff][Ll][Ss])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^\s+([Rr][Ee][Vv])\s+(".+"[0-9a-fA-F]*)\s+(;.*)$|^\s+([Ss][Tt][Rr])\s+(".+"[0-9a-fA-F]*)\s*(;.*)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = $3;
  } elsif ($line =~ /^(\S+)\s+([Aa][Ss][Cc])\s+(".+"[,]*[0-9a-fA-F]*)\s*$|^(\S+)\s+([Dd][Cc][Ii])\s+(".+"[0-9a-fA-F]*)\s*$|^(\S+)\s+([Ii][Nn][Vv])\s+(".+"[0-9a-fA-F]*)\s*$|^(\S+)\s+([Ff][Ll][Ss])\s+(".+"[0-9a-fA-F]*)\s*$|^(\S+)\s+([Rr][Ee][Vv])\s+(".+"[0-9a-fA-F]*)\s*$|^(\S+)\s+([Ss][Tt][Rr])\s+(".+"[0-9a-fA-F]*)\s*$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = '';
  } elsif ($line =~ /^\s+([Aa][Ss][Cc])\s+(".+"[,]*[0-9a-fA-F]*)\s*$|^\s+([Dd][Cc][Ii])\s+(".+"[0-9a-fA-F]*)\s*$|^\s+([Ii][Nn][Vv])\s+(".+"[0-9a-fA-F]*)\s*$|^\s+([Ff][Ll][Ss])\s+(".+"[0-9a-fA-F]*)\s*$|^\s+([Rr][Ee][Vv])\s+(".+"[0-9a-fA-F]*)\s*$|^\s+([Ss][Tt][Rr])\s+(".+"[0-9a-fA-F]*)\s*$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = '';
  # Next 4 for things like LDA #" "
  } elsif ($line =~ /^\s+(\S+)\s+(#\".\")\s*(;.*)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = $3;
  } elsif ($line =~ /^\s+(\S+)\s+(#\".\")\s*$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = '';
  } elsif ($line =~ /^(\S+)\s+(\S+)\s+(#\".\")\s*(;.*)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = $3;
  } elsif ($line =~ /^(\S+)\s+(\S+)\s+(#\".\")\s*$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = '';
  # Next 4 for things like DS 255," "
  } elsif ($line =~ /^\s+([Dd][Ss])\s+(\d+,\".\")\s*(;.*)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = $3;
  } elsif ($line =~ /^\s+([Dd][Ss])\s+(\d+,\".\")\s*$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = '';
  } elsif ($line =~ /^(\S+)\s+([Dd][Ss])\s+(\d+,\".\")\s*(;.*)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = $3;
  } elsif ($line =~ /^(\S+)\s+([Dd][Ss])\s+(\d+,\".\")\s*$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = '';
  # Handle comments w/o ; -- S-C assembler
  } elsif ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(.+)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = $4;
  } elsif ($line =~ /^\s+(\S+)\s+(\S+)\s+(.+)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = $3;
  } else {
    print sprintf("SYNTAX ERROR!    %-4d  %s\n", $lineno, $line);
  }

  $label = '' unless defined $label;
  $comment = '' unless defined $comment;
  $mnemonic = '' unless defined $mnemonic;
  $operand = '' unless defined $operand;

  print "label=$label mnemonic=$mnemonic operand=$operand comment=$comment\n" if $debug;

  return ($label, $mnemonic, $operand, $comment);
}

my $ifh;

# Open the input file.
if (open($ifh, "<$input_file")) {
  my $lineno = 0;

  while (my $line = readline $ifh) {
    chomp $line;

    $lineno++;

    if ($line =~ /^\s*\*|^\s*;/ || $line eq '') {
      print "$line\n";
      next;
    }

    # Parse input lines.
    my ($label, $mnemonic, $operand, $comment) = parse_line($line, $lineno);

    print sprintf("%-12s %-4s %-12s %s\n", $label, $mnemonic, $operand, $comment);
  }

  close $ifh;
} else {
  die "Can't open $input_file\n";
}

1;

