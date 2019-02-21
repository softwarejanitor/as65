#!/usr/bin/perl -w

#
# as65.pl
#
# Simple 65C02 mini-assembler.
#
# 20181211 LSH
#

use strict;

my $verbose = 1;  # Print messages, default to on.
my $debug = 0;  # Debug mode, default to off.  Very chatty if on.
my $listing = 0;  # Listing for pass 1.
my $code_listing = 1;  # Generated code listing.
my $symbol_table = 1;  # Output symbol table.
my $error_summary = 1;  # Output error summary, default to on.

my %symbols = ();  # Hash of symbol table values.
my %macros = ();  # Hash of macros.

my @errors = ();

my $in_macro = 0;
my $cur_macro = '';

my $in_conditional = 0;
my $skip = 0;

my $edasm = 0;

my $base = 0x800;  # Default base address.  Overide with -a (decimal) or -x (hex) from command line or .org or ORG directives in code.

my $output_file = '';  # Output file, required to be set with -o command line flag.

my $checksum = 0;

my $COUT_BOLD = "\e[1m";
my $COUT_YELLOW = "\e[1;33m";
my $COUT_NORMAL = "\e[1;37m";
my $COUT_DIM = "\e[0;37m";
my $COUT_BROWN = "\e[0;33m";
my $COUT_RED = "\e[1;31m";
my $COUT_GREEN = "\e[1;32m";
my $COUT_VIOLET = "\e[1;35m";
my $COUT_AQUA = "\e[1;36m";

sub usage {
  print "Usage:\n";
  print "$0 [-a addr] [-x \$addr] [-v] [-q] [-d] [-s] [-l] [-c] [-h] <input_file>\n";
  print " -a addr : Start address in decimal (default 2048)\n";
  print " -x \$addr : Start address in hex (default $800)\n";
  print " -o <output file> : Output file name (required).\n";
  print " -v : Verbose (default on)\n";
  print " -q : Quiet (default off)\n";
  print " -d : Debug (default off)\n";
  print " -s : Symbol Table\n";
  print " -l : Listing (source pass 1) (default off)\n";
  print " -c : Generated code listing (default on)\n";
  print " -e : Generated error summary (default on)\n";
  print " -C : Toggle color output (default on)\n";
  print " -edasm : Toggle EDASM mode (default ooff)\n";
  print " -h : This help\n";
}

# Process command line arguments.
while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
  # Set base address in decimal.
  if ($ARGV[0] eq '-a' && defined $ARGV[1] && $ARGV[1] =~ /^\d+$/) {
    $base = $ARGV[1];
    shift;
    shift;
  # Set base address in hex.
  } elsif ($ARGV[0] eq '-x' && defined $ARGV[1] && $ARGV[1] =~ /^[a-f0-9A-F]+$/) {
    $base = hex(lc($ARGV[1]));
    shift;
    shift;
  # Get output filename
  } elsif ($ARGV[0] eq '-o' && defined $ARGV[1] && $ARGV[1] ne '') {
    $output_file = $ARGV[1];
    shift;
    shift;
  # Verbose.
  } elsif ($ARGV[0] eq '-v') {
    $verbose = 1;
    shift;
  # Quiet (opposite of verbose).
  } elsif ($ARGV[0] eq '-q') {
    $verbose = 0;
    shift;
  # Debug.
  } elsif ($ARGV[0] eq '-d') {
    $debug = 1;
    shift;
  # Symbol table.
  } elsif ($ARGV[0] eq '-s') {
    $symbol_table = 0;
    shift;
  # Listing (pass 1).
  } elsif ($ARGV[0] eq '-l') {
    $listing = 1;
    shift;
  # Code listing.
  } elsif ($ARGV[0] eq '-c') {
    $code_listing = 0;
    shift;
  # Error summary.
  } elsif ($ARGV[0] eq '-e') {
    $error_summary = 0;
    shift;
  # Toggle color output (default on).
  } elsif ($ARGV[0] eq '-C') {
    $COUT_BOLD = "";
    $COUT_YELLOW = "";
    $COUT_NORMAL = "";
    $COUT_DIM = "";
    $COUT_BROWN = "";
    $COUT_RED = "";
    $COUT_GREEN = "";
    $COUT_VIOLET = "";
    $COUT_AQUA = "";
    shift;
  # Toggle EDASM mode (default ooff).
  } elsif ($ARGV[0] eq '-edasm') {
    $edasm = 1;
    shift;
  # Help.
  } elsif ($ARGV[0] eq '-h') {
    usage();
    exit;
  } else {
    die "Invalid argument $ARGV[0]\n";
  }
}

my $input_file = shift;

die "Must supply input filename\n" unless defined $input_file && $input_file;
die "Must supply output filename with -o flag\n" unless defined $output_file && $output_file;

# Functions to check and generate code for each 65C02 addressing mode plus the size for each.
my %modefuncs = (
  'Immediate' => {
    'check' => \&is_Immediate,
    'gen' => \&generate_Immediate,
    'size' => 2,
  },
  'Zero_Page' => {
    'check' => \&is_Zero_Page,
    'gen' => \&generate_Zero_Page,
    'size' => 2,
  },
  'Zero_Page_X' => {
    'check' => \&is_Zero_Page_X,
    'gen' => \&generate_Zero_Page_X,
    'size' => 2,
  },
  'Zero_Page_Y' => {
    'check' => \&is_Zero_Page_Y,
    'gen' => \&generate_Zero_Page_Y,
    'size' => 2,
  },
  'Absolute' => {
    'check' => \&is_Absolute,
    'gen' => \&generate_Absolute,
    'size' => 3,
  },
  'Indirect_Absolute' => {
    'check' => \&is_Indirect_Absolute,
    'gen' => \&generate_Indirect_Absolute,
    'size' => 3,
  },
  'Indirect_Absolute_X' => {
    'check' => \&is_Indirect_Absolute_X,
    'gen' => \&generate_Indirect_Absolute_X,
    'size' => 3,
  },
  'Absolute_X' => {
    'check' => \&is_Absolute_X,
    'gen' => \&generate_Absolute_X,
    'size' => 3,
  },
  'Absolute_Y' => {
    'check' => \&is_Absolute_Y,
    'gen' => \&generate_Absolute_Y,
    'size' => 3,
  },
  'Indirect_Zero_Page_X' => {
    'check' => \&is_Indirect_Zero_Page_X,
    'gen' => \&generate_Indirect_Zero_Page_X,
    'size' => 2,
  },
  'Indirect_Zero_Page_Y' => {
    'check' => \&is_Indirect_Zero_Page_Y,
    'gen' => \&generate_Indirect_Zero_Page_Y,
    'size' => 2,
  },
  'Indirect_Zero_Page' => {
    'check' => \&is_Indirect_Zero_Page,
    'gen' => \&generate_Indirect_Zero_Page,
    'size' => 2,
  },
  'Relative' => {
    'check' => \&is_Relative,
    'gen' => \&generate_Relative,
    'size' => 2,
  },
  'Implied' => {
    'check' => \&is_Implied,
    'gen' => \&generate_Implied,
    'size' => 1,
  },
  'Accumulator' => {
    'check' => \&is_Accumulator,
    'gen' => \&generate_Accumulator,
    'size' => 1,
  },
);

# The opcodes for each 65C02 instruction mnemonic.
my %mnemonics = (
  'ADC' => {
    # ADC	Immediate	ADC #Oper	69	2	2
    'Immediate' => 0x69,
    # 		Zero Page	ADC Zpg		65	2	3
    'Zero_Page' => 0x65,
    # 		Zero Page,X	ADC Zpg,X	75	2	4
    'Zero_Page_X' => 0x75,
    # 		Absolute	ADC Abs		6D	3	4
    'Absolute' => 0x6d,
    # 		Absolute,X	ADC Abs,X	7D	3	4
    'Absolute_X' => 0x7d,
    # 		Absolute,Y	ADC Abs,Y	79	3	4
    'Absolute_Y' => 0x79,
    # 		(Zero Page,X)	ADC (Zpg,X)	61	2	6
    'Indirect_Zero_Page_X' => 0x61,
    # 		(Zero Page),Y	ADC (Zpg),Y	71	2	5
    'Indirect_Zero_Page_Y' => 0x71,
    # 		(Zero Page)	ADC (Zpg)	72	2	5
    'Indirect_Zero_Page' => 0x72,
  },
  'AND' => {
    # AND	Immediate	AND #Oper	29	2	2
    'Immediate' => 0x29,
    # 		Zero Page	AND Zpg		25	2	3
    'Zero_Page' => 0x25,
    # 		Zero Page,X	AND Zpg,X	35	2	4
    'Zero_Page_X' => 0x35,
    # 		Absolute	AND Abs		2D	3	4
    'Absolute' => 0x2d,
    # 		Absolute,X	AND Abs,X	3D	3	4
    'Absolute_X' => 0x3d,
    # 		Absolute,Y	AND Abs,Y	39	3	4
    'Absolute_Y' => 0x39,
    # 		(Zero Page,X)	AND (Zpg,X)	21	2	6
    'Indirect_Zero_Page_X' => 0x21,
    # 		(Zero Page),Y	AND (Zpg),Y	31	2	5
    'Indirect_Zero_Page_Y' => 0x31,
    # 		(Zero Page)	AND (Zpg)	32	2	5
    'Indirect_Zero_Page' => 0x32,
  },
  'ASL' => {
    # AS	Accumulator	ASL A		0A	1	2
    'Accumulator' => 0x0a,
    # 		Zero Page	ASL Zpg		06	2	5
    'Zero_Page' => 0x06,
    # 		Zero Page,X	ASL Zpg,X	16	2	6
    'Zero_Page_X' => 0x16,
    # 		Absolute	ASL Abs		0E	3	6
    'Absolute' => 0x0e,
    # 		Absolute,X	ASL Abs,X	1E	3	7
    'Absolute_X' => 0x1e,
  },
  'BBR0' => {
    # BBR0	Relative	BBR0 Oper	0F	2	2
    'Relative' => 0x0f,
  },
  'BBR1' => {
    # BBR1	Relative	BBR1 Oper	1F	2	2
    'Relative' => 0x1f,
  },
  'BBR2' => {
    # BBR2	Relative	BBR2 Oper	2F	2	2
    'Relative' => 0x2f,
  },
  'BBR3' => {
    # BBR3	Relative	BBR3 Oper	3F	2	2
    'Relative' => 0x3f,
  },
  'BBR4' => {
    # BBR4	Relative	BBR4 Oper	4F	2	2
    'Relative' => 0x4f,
  },
  'BBR5' => {
    # BBR5	Relative	BBR5 Oper	5F	2	2
    'Relative' => 0x5f,
  },
  'BBR6' => {
    # BBR6	Relative	BBR6 Oper	6F	2	2
    'Relative' => 0x6f,
  },
  'BBR7' => {
    # BBR7	Relative	BBR7 Oper	7F	2	2
    'Relative' => 0x7f,
  },
  'BBS0' => {
    # BBS0	Relative	BBS0 Oper	8F	2	2
    'Relative' => 0x8f,
  },
  'BBS1' => {
    # BBS1	Relative	BBS1 Oper	9F	2	2
    'Relative' => 0x9f,
  },
  'BBS2' => {
    # BBS2	Relative	BBS2 Oper	AF	2	2
    'Relative' => 0xaf,
  },
  'BBS3' => {
    # BBS3	Relative	BBS3 Oper	BF	2	2
    'Relative' => 0xbf,
  },
  'BBS4' => {
    # BBS4	Relative	BBS4 Oper	CF	2	2
    'Relative' => 0xcf,
  },
  'BBS5' => {
    # BBS5	Relative	BBS5 Oper	DF	2	2
    'Relative' => 0xdf,
  },
  'BBS6' => {
    # BBS6	Relative	BBS6 Oper	EF	2	2
    'Relative' => 0xef,
  },
  'BBS7' => {
    # BBS7	Relative	BBS7 Oper	FF	2	2
    'Relative' => 0xff,
  },
  'BCC' => {
    # BCC	Relative	BCC Oper	90	2	2
    'Relative' => 0x90,
  },
  'BLT' => {  # Pseudo-op same as BCC
    # BLT	Relative	BLT Oper	90	2	2
    'Relative' => 0x90,
  },
  'BCS' => {
    # BCS	Relative	BCS Oper	B0	2	2
    'Relative' => 0xb0,
  },
  'BGE' => {  # Pseudo-op same as BCS
    # BGE	Relative	BGE Oper	B0	2	2
    'Relative' => 0xb0,
  },
  'BEQ' => {
    # BEQ	Relative	BEQ Oper	F0	2	2
    'Relative' => 0xf0,
  },
  'BFL' => {  # Pseudo-op same as BEQ
    # BFL	Relative	BFL Oper	F0	2	2
    'Relative' => 0xf0,
  },
  'BIT' => {
    # BIT	Immediate	BIT #Oper	89	2	2
    'Immediate' => 0x89,
    #	 	Zero Page	BIT Zpg		24	2	3
    'Zero_Page' => 0x24,
    # 		Zero Page,X	BIT Zpg,X	34	2	4
    'Zero_Page_X' => 0x34,
    # 		Absolute	BIT Abs		2C	3	4
    'Absolute' => 0x2c,
    # 		Absolute,X	BIT Abs,X	3C	3	4
    'Absolute_X' => 0x3c,
  },
  'BMI' => {
    # BMI	Relative	BMI Oper	30	2	2
    'Relative' => 0x30,
  },
  'BNE' => {
    # BNE	Relative	BNE Oper	D0	2	2
    'Relative' => 0xd0,
  },
  'BTR' => {  # Pseudo-op same as BNE
    # BTR	Relative	BTR Oper	D0	2	2
    'Relative' => 0xd0,
  },
  'BPL' => {
    # BPL	Relative	BPL Oper	10	2	2
    'Relative' => 0x10,
  },
  'BRA' => {
    # BRA	Relative	BRA Oper	80	2	3
    'Relative' => 0x80,
  },
  'BRK' => {
    # BRK	Implied		BRK		00	1	7
    'Implied' => 0x00,
  },
  'BVC' => {
    # BVC	Relative	BVC Oper	50	2	2
    'Relative' => 0x50,
  },
  'BVS' => {
    # BVS	Relative	BVS Oper	70	2	2
    'Relative' => 0x70,
  },
  'CLC' => {
    # CLC	Implied		CLC		18	1	2
    'Implied' => 0x18,
  },
  'CLD' => {
    # CLD	Implied		CLD		D8	1	2
    'Implied' => 0xd8,
  },
  'CLI' => {
    # CLI	Implied		CLI		58	1	2
    'Implied' => 0x58,
  },
  'CLV' => {
    # CLV	Implied		CLV		B8	1	2
    'Implied' => 0xb8,
  },
  'CMP' => {
    # CMP	Immediate	CMP #Oper	C9	2	2
    'Immediate' => 0xc9,
    # 		Zero Page	CMP Zpg		C5	2	3
    'Zero_Page' => 0xc5,
    # 		Zero Page,X	CMP Zpg,X	D5	2	4
    'Zero_Page_X' => 0xd5,
    # 		Absolute	CMP Abs		CD	3	4
    'Absolute' => 0xcd,
    # 		Absolute,X	CMP Abs,X	DD	3	4
    'Absolute_X' => 0xdd,
    # 		Absolute,Y	CMP Abs,Y	D9	3	4
    'Absolute_Y' => 0xd9,
    # 		(Zero Page,X)	CMP (Zpg,X)	C1	2	6
    'Indirect_Zero_Page_X' => 0xc1,
    # 		(Zero Page),Y	CMP (Zpg),Y	D1	2	5
    'Indirect_Zero_Page_Y' => 0xd1,
    # 		(Zero Page)	CMP (Zpg)	D2	2	5
    'Indirect_Zero_Page' => 0xd2,
  },
  'CPX' => {
    # CPX	Immediate	CPX #Oper	E0	2	2
    'Immediate' => 0xe0,
    # 		Zero Page	CPX Zpg		E4	2	3
    'Zero_Page' => 0xe4,
    # 		Absolute	CPX Abs		EC	3	4
    'Absolute' => 0xec,
  },
  'CPY' => {
    # CPY	Immediate	CPY #Oper	C0	2	2
    'Immediate' => 0xc0,
    # 		Zero Page	CPY Zpg		C4	2	3
    'Zero_Page' => 0xc4,
    # 		Absolute	CPY Abs		CC	3	4
    'Absolute' => 0xcc,
  },
  'DEA' => {
    # DEA	Accumulator	DEA		3A	1	2
    'Accumulator' => 0x3a,
  },
  'DEC' => {
    # DEC	Zero Page	DEC Zpg		C6	2	5
    'Zero_Page' => 0xc6,
    # 		Zero Page,X	DEC Zpg,X	D6	2	6
    'Zero_Page_X' => 0xd6,
    # 		Absolute	DEC Abs		CE	3	6
    'Absolute' => 0xce,
    # 		Absolute,X	DEC Abs,X	DE	3	7
    'Absolute_X' => 0xde,
  },
  'DEX' => {
    # DEX	Implied		DEX		CA	1	2
    'Implied' => 0xca,
  },
  'DEY' => {
      # DEY	Implied		DEY		88	1	2
    'Implied' => 0x88,
  },
  'EOR' => {
    # EOR	Immediate	EOR #Oper	49	2	2
    'Immediate' => 0x49,
    # 		Zero Page	EOR Zpg		45	2	3
    'Zero_Page' => 0x45,
    # 		Zero Page,X	EOR Zpg,X	55	2	4
    'Zero_Page_X' => 0x55,
    # 		Absolute	EOR Abs		4D	3	4
    'Absolute' => 0x4d,
    # 		Absolute,X	EOR Abs,X	5D	3	4
    'Absolute_X' => 0x5d,
    # 		Absolute,Y	EOR Abs,Y	59	3	4
    'Absolute_Y' => 0x59,
    # 		(Zero Page,X)	EOR (Zpg,X)	41	2	6
    'Indirect_Zero_Page_X' => 0x41,
    # 		(Zero Page),Y	EOR (Zpg),Y	51	2	5
    'Indirect_Zero_Page_Y' => 0x51,
    # 		(Zero Page)	EOR (Zpg)	52	2	5
    'Indirect_Zero_Page' => 0x52,
  },
  'XOR' => {  # Pseudo-op same as EOR
    # XOR	Immediate	XOR #Oper	49	2	2
    'Immediate' => 0x49,
    # 		Zero Page	XOR Zpg		45	2	3
    'Zero_Page' => 0x45,
    # 		Zero Page,X	XOR Zpg,X	55	2	4
    'Zero_Page_X' => 0x55,
    # 		Absolute	XOR Abs		4D	3	4
    'Absolute' => 0x4d,
    # 		Absolute,X	XOR Abs,X	5D	3	4
    'Absolute_X' => 0x5d,
    # 		Absolute,Y	XOR Abs,Y	59	3	4
    'Absolute_Y' => 0x59,
    # 		(Zero Page,X)	XOR (Zpg,X)	41	2	6
    'Indirect_Zero_Page_X' => 0x41,
    # 		(Zero Page),Y	XOR (Zpg),Y	51	2	5
    'Indirect_Zero_Page_Y' => 0x51,
    # 		(Zero Page)	XOR (Zpg)	52	2	5
    'Indirect_Zero_Page' => 0x52,
  },
  'INA' => {
    # INA	Accumulator	INA		1A	1	2
    'Accumulator' => 0x1a,
  },
  'INC' => {
    # INC	Zero Page	INC Zpg		E6	2	5
    'Zero_Page' => 0xe6,
    # 		Zero Page,X	INC Zpg,X	F6	2	6
    'Zero_Page_X' => 0xf6,
    # 		Absolute	INC Abs		EE	3	6
    'Absolute' => 0xee,
    # 		Absolute,X	INC Abs,X	FE	3	7
    'Absolute_X' => 0xfe,
  },
  'INX' => {
    # INX	Implied		INX		E8	1	2
    'Implied' => 0xe8,
  },
  'INY' => {
    # INY	Implied		INY		C8	1	2
    'Implied' => 0xc8,
  },
  'JMP' => {
    # JMP	Absolute	JMP Abs		4C	3	3
    'Absolute' => 0x4c,
    # 		(Absolute)	JMP (Abs)	6C	3	5
    'Indirect_Absolute' => 0x6c,
    # 		(Absolute,X)	JMP (Abs,X)	7C	3	6
    'Indirect_Absolute_X' => 0x7c,
  },
  'JSR' => {
    # JSR	Absolute	JSR Abs		20	3	6
    'Absolute' => 0x20,
  },
  'LDA' => {
    # LDA	Immediate	LDA #Oper	A9	2	2
    'Immediate' => 0xa9,
    # 		Zero Page	LDA Zpg		A5	2	3
    'Zero_Page' => 0xa5,
    # 		Zero Page,X	LDA Zpg,X	B5	2	4
    'Zero_Page_X' => 0xb5,
    # 		Absolute	LDA Abs		AD	3	4
    'Absolute' => 0xad,
    # 		Absolute,X	LDA Abs,X	BD	3	4
    'Absolute_X' => 0xbd,
    # 		Absolute,Y	LDA Abs,Y	B9	3	4
    'Absolute_Y' => 0xb9,
    # 		(Zero Page,X)	LDA (Zpg,X)	A1	2	6
    'Indirect_Zero_Page_X' => 0xa1,
    # 		(Zero Page),Y	LDA (Zpg),Y	B1	2	5
    'Indirect_Zero_Page_Y' => 0xb1,
    # 		(Zero Page)	LDA (Zpg)	B2	2	5
    'Indirect_Zero_Page' => 0xb2,
  },
  'LDX' => {
    # LDX	Immediate	LDX #Oper	A2	2	2
    'Immediate' => 0xa2,
    # 		Zero Page	LDX Zpg		A6	2	3
    'Zero_Page' => 0xa6,
    # 		Zero Page,Y	LDX Zpg,Y	B6	2	4
    'Zero_Page_Y' => 0xb6,
    # 		Absolute	LDX Abs		AE	3	4
    'Absolute' => 0xae,
    # 		Absolute,Y	LDX Abs,Y	BE	3	4
    'Absolute_Y' => 0xbe,
  },
  'LDY' => {
    # LDY	Immediate	LDY #Oper	A0	2	2
    'Immediate' => 0xa0,
    # 		Zero Page	LDY Zpg		A4	2	3
    'Zero_Page' => 0xa4,
    # 		Zero Page,X	LDY Zpg,X	B4	2	4
    'Zero_Page_X' => 0xb4,
    # 		Absolute	LDY Abs		AC	3	4
    'Absolute' => 0xac,
    # 		Absolute,X	LDY Abs,X	BC	3	4
    'Absolute_X' => 0xbc,
  },
  'LSR' => {
    # LSR	Accumulator	LSR A		4A	1	2
    'Accumulator' => 0x4a,
    # 		Zero Page	LSR Zpg		46	2	5
    'Zero_Page' => 0x46,
    # 		Zero Page,X	LSR Zpg,X	56	2	6
    'Zero_Page_X' => 0x56,
    # 		Absolute	LSR Abs		4E	3	6
    'Absolute' => 0x4e,
    # 		Absolute,X	LSR Abs,X	5E	3	7
    'Absolute_X' => 0x5e,
  },
  'NOP' => {
    # NOP	Implied		NOP		EA	1	2
    'Implied' => 0xea,
  },
  'ORA' => {
    # ORA	Immediate	ORA #Oper	09	2	2
    'Immediate' => 0x09,
    # 		Zero Page	ORA Zpg		05	2	3
    'Zero_Page' => 0x05,
    # 		Zero Page,X	ORA Zpg,X	15	2	4
    'Zero_Page_X' => 0x15,
    # 		Absolute	ORA Abs		0D	3	4
    'Absolute' => 0x0d,
    # 		Absolute,X	ORA Abs,X	1D	3	4
    'Absolute_X' => 0x1d,
    # 		Absolute,Y	ORA Abs,Y	19	3	4
    'Absolute_Y' => 0x19,
    # 		(Zero Page,X)	ORA (Zpg,X)	01	2	6
    'Indirect_Zero_Page_X' => 0x01,
    # 		(Zero Page),Y	ORA (Zpg),Y	11	2	5
    'Indirect_Zero_Page_Y' => 0x11,
    # 		(Zero Page)	ORA (Zpg)	12	2	5
    'Indirect_Zero_Page' => 0x12,
  },
  'PHA' => {
    # PHA	Implied		PHA		48	1	3
    'Implied' => 0x48,
  },
  'PHP' => {
    # PHP	Implied		PHP		08	1	3
    'Implied' => 0x08,
  },
  'PHX' => {
    # PHX	Implied		PHX		DA	1	3
    'Implied' => 0xda,
  },
  'PHY' => {
    # PHY	Implied		PHY		5A	1	3
    'Implied' => 0x5a,
  },
  'PLA' => {
    # PLA	Implied		PLA		68	1	4
    'Implied' => 0x68,
  },
  'PLP' => {
    # PLP	Implied		PLP		68	1	4
    'Implied' => 0x28,
  },
  'PLX' => {
    # PLX	Implied		PLX		FA	1	4
    'Implied' => 0xfa,
  },
  'PLY' => {
    # PLY	Implied		PLY		7A	1	4
    'Implied' => 0x7a,
  },
  'ROL' => {
    # ROL	Accumulator	ROL A		2A	1	2
    'Accumulator' => 0x2a,
    # 		Zero Page	ROL Zpg		26	2	5
    'Zero_Page' => 0x26,
    # 		Zero Page,X	ROL Zpg,X	36	2	6
    'Zero_Page_X' => 0x36,
    # 		Absolute	ROL Abs		2E	3	6
    'Absolute' => 0x2e,
    # 		Absolute,X	ROL Abs,X	3E	3	7
    'Absolute_X' => 0x3e,
  },
  'ROR' => {
    # ROR	Accumulator	ROR A		6A	1	2
    'Accumulator' => 0x6a,
    # 		Zero Page	ROR Zpg		66	2	5
    'Zero_Page' => 0x66,
    # 		Zero Page,X	ROR Zpg,X	76	2	6
    'Zero_Page_X' => 0x76,
    # 		Absolute	ROR Abs		6E	3	6
    'Absolute' => 0x6e,
    # 		Absolute,X	ROR Abs,X	7E	3	7
    'Absolute_X' => 0x7e,
  },
  'RTI' => {
    # RTI	Implied		RTI		40	1	6
    'Implied' => 0x40,
  },
  'RTS' => {
    # RTS	Implied		RTS		60	1	6
    'Implied' => 0x60,
  },
  'SBC' => {
    # SBC	Immediate	SBC #Oper	E9	2	2
    'Immediate' => 0xe9,
    # 		Zero Page	SBC Zpg		E5	2	3
    'Zero_Page' => 0xe5,
    # 		Zero Page,X	SBC Zpg,X	F5	2	4
    'Zero_Page_X' => 0xf5,
    # 		Absolute	SBC Abs		ED	3	4
    'Absolute' => 0xed,
    # 		Absolute,X	SBC Abs,X	FD	3	4
    'Absolute_X' => 0xfd,
    # 		Absolute,Y	SBC Abs,Y	F9	3	4
    'Absolute_Y' => 0xf9,
    # 		(Zero Page,X)	SBC (Zpg,X)	E1	2	6
    'Indirect_Zero_Page_X' => 0xe1,
    # 		(Zero Page),Y	SBC (Zpg),Y	F1	2	5
    'Indirect_Zero_Page_Y' => 0xf1,
    # 		(Zero Page)	SBC (Zpg)	F2	2	5
    'Indirect_Zero_Page' => 0xf2,
  },
  'SEC' => {
    # SEC	Implied		SEC		38	1	2
    'Implied' => 0x38,
  },
  'SED' => {
    # SED	Implied		SED		F8	1	2
    'Implied' => 0xf8,
  },
  'SEI' => {
    # SEI	Implied		SEI		78	1	2
    'Implied' => 0x78,
  },
  'STA' => {
    # STA	Zero Page	STA Zpg		85	2	3
    'Zero_Page' => 0x85,
    # 		Zero Page,X	STA Zpg,X	95	2	4
    'Zero_Page_X' => 0x95,
    # 		Absolute	STA Abs		8D	3	4
    'Absolute' => 0x8d,
    # 		Absolute,X	STA Abs,X	9D	3	5
    'Absolute_X' => 0x9d,
    # 		Absolute,Y	STA Abs,Y	99	3	5
    'Absolute_Y' => 0x99,
    # 		(Zero Page,X)	STA (Zpg,X)	81	2	6
    'Indirect_Zero_Page_X' => 0x81,
    # 		(Zero Page),Y	STA (Zpg),Y	91	2	6
    'Indirect_Zero_Page_Y' => 0x91,
    # 		(Zero Page)	STA (Zpg)	92	2	5
    'Indirect_Zero_Page' => 0x92,
  },
  'STX' => {
    # STX	Zero Page	STX Zpg		86	2	3
    'Zero_Page' => 0x86,
    # 		Zero Page,Y	STX Zpg,Y	96	2	4
    'Zero_Page_Y' => 0x96,
    # 		Absolute	STX Abs		8E	3	4
    'Absolute' => 0x8e,
  },
  'STY' => {
    # STY	Zero Page	STY Zpg		84	2	3
    'Zero_Page' => 0x84,
    # 		Zero Page,X	STY Zpg,X	94	2	4
    'Zero_Page_X' => 0x94,
    # 		Absolute	STY Abs		8C	3	4
    'Absolute' => 0x8c,
  },
  'STZ' => {
    # STZ	Zero Page	STZ Zpg		64	2	3
    'Zero_Page' => 0x64,
    # 		Zero Page,X	STZ Zpg,X	74	2	4
    'Zero_Page_X' => 0x74,
    # 		Absolute	STZ Abs		9C	3	4
    'Absolute' => 0x9c,
    # 		Absolute,X	STZ Abs,X	9E	3	5
    'Absolute_X' => 0x9e,
  },
  'TAX' => {
    # TAX	Implied		TAX		AA	1	2
    'Implied' => 0xaa,
  },
  'TAY' => {
    # TAY	Implied		TAY		A8	1	2
    'Implied' => 0xa8,
  },
  'TRB' => {
    # TRB	Zero Page	TRB Zpg		14	2	5
    'Zero_Page' => 0x14,
    # 		Absolute	TRB Abs		1C	3	6
    'Absolute' => 0x1c,
  },
  'TSB' => {
    # TSB	Zero Page	TSB Zpg		04	2	5
    'Zero_Page' => 0x04,
    # 		Absolute	TSB Abs		0C	3	6
    'Absolute' => 0x0c,
  },
  'TSX' => {
    # TSX	Implied		TSX		BA	1	2
    'Implied' => 0xba,
  },
  'TXA' => {
    # TXA	Implied		TXA		8A	1	2
    'Implied' => 0x8a,
  },
  'TXS' => {
    # TXS	Implied		TXS		9A	1	2
    'Implied' => 0x9a,
  },
  'TYA' => {
    # TYA	Implied		TYA		98	1	2
    'Implied' => 0x98,
  },
);

sub print_err {
  my ($line) = @_;

  push @errors, $line;

  print $COUT_RED . $line . $COUT_NORMAL;
}

sub calc_checksum {
  my ($byte) = @_;

  # Checksum is exclusive or of all output bytes.  This is a Merlin thing.
  $checksum ^= $byte;
}

# Generate code for one byte instructions.
sub generate_8 {
  my ($ofh, $addr, $opcode, $lineno, $line) = @_;

  print sprintf("%04x:  %02x        %-4d  %s\n", $addr, $opcode, $lineno, $line) if $code_listing;
  print $ofh pack("C", $opcode);

  calc_checksum($opcode);
}

# Generate code for two byte instructions.
sub generate_16 {
  my ($ofh, $addr, $opcode, $opval, $lineno, $line) = @_;

  $opval = 0x00 unless defined $opval;

  if ($opval =~ /^\$([0-9a-fA-F]{1,2})$/) {
    $opval = hex(lc($1));
  }
  print sprintf("%04x:  %02x %02x     %-4d  %s\n", $addr, $opcode, $opval, $lineno, $line) if $code_listing;
  print $ofh pack("C", $opcode);
  print $ofh pack("C", $opval);

  calc_checksum($opcode);
  calc_checksum($opval);
}

# Generate code for three byte instructions.
sub generate_24 {
  my ($ofh, $addr, $opcode, $opval1, $opval2, $lineno, $line) = @_;

  $opval1 = 0x00 unless defined $opval1;
  $opval2 = 0x00 unless defined $opval2;

  print sprintf("%04x:  %02x %02x %02x  %-4d  %s\n", $addr, $opcode, $opval1, $opval2, $lineno, $line) if $code_listing;
  print $ofh pack("C", $opcode);
  print $ofh pack("C", $opval1);
  print $ofh pack("C", $opval2);

  calc_checksum($opcode);
  calc_checksum($opval1);
  calc_checksum($opval2);
}

# Generate output for strings, defined storage, etc.
sub generate_bytes {
  my ($ofh, $addr, $bytes, $lineno, $line) = @_;
  my $firstflag = 1;
  foreach my $byte (@{$bytes}) {
    if ($firstflag) {
      print sprintf("%04x:  %02x        %-4d  %s\n", $addr, ord($byte), $lineno, $line) if $code_listing;
      $firstflag = 0;
    } else {
      print sprintf("%04x:  %02x\n", $addr, ord($byte)) if $code_listing;
    }
    print $ofh pack("C", ord($byte));

    calc_checksum(ord($byte));

    $addr++;
  }
  $_[1] = $addr;
}

sub get_symval {
  my ($prt, $sym) = @_;

  my $val = $symbols{$sym};
  $val = $symbols{$sym . ':'} unless defined $val;
  $val = $symbols{':' . $sym} unless defined $val;
  if (defined $val) {
    # Get high byte.
    if (defined $prt && $prt eq '<') {
      # Hex
      if ($val =~ /\$([0-9a-fA-F]{1,2})/) {
        $val = '$' . $1;
      # Binary
      } elsif ($val =~ /%([01]{8})/) {
        $val = '$'. sprintf("%02x", unpack('C', pack("B8", $1)));
      # Decimal
      } elsif ($val =~ /^(\d+)$/) {
        $val = '$' . substr(sprintf("%04x", $1), 0, 2);
      }
    # Get low byte.
    } elsif (defined $prt && $prt eq '>') {
      # 16 bit Hex
      if ($val =~ /\$[0-9a-fA-F]*([0-9a-fA-F][0-9a-fA-F])/) {
        $val = '$' . $1;
      # 8 bit Hex
      } elsif ($val =~ /\$([0-9a-fA-F][0-9a-fA-F])/) {
        $val = '$' . $1;
      # 4 bit Hex
      } elsif ($val =~ /\$([0-9a-fA-F])/) {
        $val = '$' . $1;
      # Binary
      } elsif ($val =~ /%[01]{8}([01]{8})/) {
        $val = '$'. sprintf("%02x", unpack('C', pack("B8", $1)));
      # Decimal
      } elsif ($val =~ /^(\d+)$/) {
        $val = '$' . substr(sprintf("%04x", $1), 2, 2);
      }
    # Binary
    } elsif ($val =~ /%([01]{8})([01]{8})/) {
      $val = '$'. sprintf("%02x%02x", unpack('C', pack("B8", $1)), unpack('C', pack("B8", $2)));
    # Decimal
    }
  }
  return $val;
}

sub is_symbol {
  my ($operand) = @_;

  return 1 if $operand =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*$/;

  return 0;
}

sub parse_symbol {
  my ($operand) = @_;

  my $prt = '';
  my $sym = '';
  if ($operand =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*$/) {
    $prt = $1;
    $sym = $2;
  }
  $prt = '' unless defined $prt;
  return get_symval($prt, $sym);
}

sub parse_symval {
  my ($symval) = @_;

  if ($symval =~ /\$([0-9a-fA-F]+)/) {
    return hex(lc($1));
  } elsif ($symval =~ /%([01]{8})/) {
    my $byte = unpack('C', pack("B8", $1));
    return $byte;
  } elsif ($symval =~ /^(\d+)$/) {
    return $1;
  }

  return $symval;
}

sub sym_op {
  my ($symval, $op, $offset) = @_;

  $symval = 0 unless defined $symval;

  $offset = 0 unless defined $offset;

  my $roff = $offset;
  if ($offset =~ /\$([0-9a-fA-F]*)/) {
    $roff = hex(lc($1));
  }

  my $val = parse_symval($symval);

  if (defined $op) {
    if ($op eq '+') {
      $val += $roff;
    } elsif ($op eq '-') {
      $val -= $roff;
    } elsif ($op eq '*') {
      $val *= $roff;
    } elsif ($op eq '/') {
      $val /= $roff;
    }
  }

  return $val;
}

sub handle_8_bit_symbol {
  my ($ofh, $lineno, $addr, $opcode, $prt, $symbol, $op, $val, $line) = @_;

  my $symval = $symbols{$symbol};
  $symval = $symbols{$symbol . ':'} unless defined $symval;
  $symval = $symbols{':' . $symbol} unless defined $symval;
  if (defined $symval) {
    my $opval = $symval;
    # $prt is used to specify the 1st or 2nd byte.
    if (defined $prt && (($prt eq '>' && $edasm) || ($prt eq '<' && !$edasm))) {
      if ($symval =~ /^\$[0-9a-fA-F]{1,2}([0-9a-fA-F][0-9a-fA-F])$/) {
        $opval = hex(lc($1));
      } elsif ($symval =~ /^\$([0-9a-fA-F])$|^\$([0-9a-fA-F])$/) {
        $opval = hex(lc($1));
      }
    } elsif (defined $prt && (($prt eq '<' && $edasm) || ($prt = '>' && !$edasm))) {
      if ($symval =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        $opval = hex(lc($1));
      } elsif ($symval =~ /^\$([0-9a-fA-F])$/) {
        $opval = hex(lc($1));
      }
    } else {
      if ($symval =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        $opval = hex(lc($1));
      } elsif ($symval =~ /^\$([0-9a-fA-F])$/) {
        $opval = hex(lc($1));
      } elsif ($symval =~ /%([01]{8})$/) {
        $opval = unpack('C', pack("B8", $1));
      } else {
      }
    }
    if ($opval =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
      $opval = hex(lc($1));
    }
    if ($opval > 255) {
      $opval -= 256;
    }
    my $opval2 = sym_op($opval, $op, $val);
    if ($opval2 > 255) {
      $opval2 -= 256;
    }
    generate_16($ofh, $addr, $opcode, $opval2, $lineno, $line);
  } else {
    print_err("**** $lineno - Unknown symbol '$symbol' in '$line'\n");
    generate_16($ofh, $addr, $opcode, 0x00, $lineno, $line);
  }
}

sub handle_16_bit_symbol {
  my ($ofh, $lineno, $addr, $opcode, $symbol, $op, $val, $line) = @_;

  my $symval = $symbols{$symbol};
  $symval = $symbols{$symbol . ':'} unless defined $symval;
  $symval = $symbols{':' . $symbol} unless defined $symval;
  if (defined $symval) {
    my $opval1 = 0;
    my $opval2 = 0;
    if ($symval =~ /^\$([0-9a-fA-F]+)$/) {
      my $opval = sprintf("%04x", sym_op($symval, $op, $val));
      $opval1 = hex(lc(substr($opval, 0, 2)));
      $opval2 = hex(lc(substr($opval, 2, 2)));
    }
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  } else {
    print_err("**** $lineno - Unknown symbol '$symbol' in '$line'\n");
    generate_24($ofh, $addr, $opcode, 0x00, 0x00, $lineno, $line);
  }
}

# ADC #Oper	69
# AND #Oper	29
# BIT #Oper	89
# CMP #Oper	C9
# CPX #Oper	E0
# CPY #Oper	C0
# EOR #Oper	49
# LDA #Oper	A9
# LDX #Oper	A2
# LDY #Oper	A0
# ORA #Oper	09
# SBC #Oper	E9
sub is_Immediate {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^#\$[0-9a-fA-f]{0,1}[0-9a-fA-F]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^#%([01]{8})$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^#(\d)+$/) {
    #return 0 if ($1 > 255);
    return 2;
  # Parse ASCII
  } elsif ($operand =~ /^#"(.)["]*$/) {
    return 2;
  # Handle symbols.
  } elsif ($operand =~ /^#[<>]*([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
    return 2;
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^#[<>]*([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*(\$*[0-9a-fA-F]+)$/) {
    return 2;
  # For macros
  } elsif ($operand =~ /^#\](\d+)$/) {
    return 2;
  } elsif ($operand =~ /^#\[(\d+)$/) {
    return 2;
  #} else {
    #print "NOT IMMEDIATE! '$operand'\n";
  }

  return 0;
}

sub generate_Immediate {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^#\$([0-9a-fA-F]{0,1}[0-9a-fA-F])$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^#%([01]{8})$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^#(\d+)$/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Parse ASCII
  } elsif ($operand =~ /^#"(.)["]*$/) {
    generate_16($ofh, $addr, $opcode, ord($1), $lineno, $line);
  # Handle symbol
  } elsif ($operand =~ /^#([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^#([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\](\d+)$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Immediate Bad Operand : '$operand' in '$line'\n");
  }

  $_[0] += 2;
}

# ADC Zpg	65
# AND Zpg	25
# ASL Zpg	06
# BIT Zpg	24
# CMP Zpg	C5
# CPX Zpg	E4
# CPY Zpg	C4
# DEC Zpg	C6
# EOR Zpg	45
# INC Zpg	E6
# LDA Zpg	A5
# LDX Zpg	A6
# LDY Zpg	A4
# LSR Zpg	46
# ORA Zpg	05
# ROL Zpg	26
# ROR Zpg	66
# SBC Zpg	E5
# STA Zpg	85
# STX Zpg	86
# STY Zpg	84
# STZ Zpg	64
# TRB Zpg	14
# TSB Zpg	04
sub is_Zero_Page {
  my ($operand, $lineno) = @_;

  # Don't mistake Accumulator mode for instructions like LSR.
  return 0 if $operand =~ /^[Aa]$/;

  # Parse hex
  if ($operand =~ /^\$[0-9a-fA-F]{0,1}[0-9a-fA-F]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^#%([01]{8})$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^(\d+)$/) {
    return 0 if $1 > 255;
    return 2;
  # Handle symbols
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
    # Not Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  # Allow symbol arithmetic
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*\$*[0-9a-fA-F]+$/) {
    # Not Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\](\d+)$/) {
    return 2;
  }

  return 0;
}

sub generate_Zero_Page {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^%([01]{8})$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^(\d+)$/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\](\d+)$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Zero_Page Bad Operand : '$operand' in '$line'\n");
  }
  $_[0] += 2;
}

# ADC Zpg,X	75
# AND Zpg,X	35
# ASL Zpg,X	16
# BIT Zpg,X	34
# DEC Zpg,X	D6
# EOR Zpg,X	55
# INC Zpg,X	F6
# LDA Zpg,X	B5
# LDY Zpg,X	B4
# LSR Zpg,X	56
# ORA Zpg,X	15
# ROL Zpg,X	36
# ROR Zpg,X	76
# SBC Zpg,X	F5
# STA Zpg,X	95
# STY Zpg,X	94
# STZ Zpg,X	74
sub is_Zero_Page_X {
  my ($operand, $lineno) = @_;

  # Don't mistake Accumulator mode for instructions like LSR.
  return 0 if $operand =~ /^[Aa]$/;

  # Parse hex
  if ($operand =~ /^\$[0-9a-fA-F]{0,1}[0-9a-fA-F],[Xx]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^%([01]{8}),[Xx]$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Xx]$/) {
    return 0 if $1 > 255;
    return 2;
  # Handle symbols
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]$/) {
    # Not Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*\$*[0-9a-fA-F]+,[Xx]$/) {
    # Not Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\](\d+),[Xx]$/) {
    return 2;
  }

  return 0;
}

sub generate_Zero_Page_X {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F]),[Xx]$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^%([01]{8}),[Xx]$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Xx]$/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Handle symbol arithmetic
  } elsif ($operand =~ /^([<>]*)([0-9A-Za-z\.\?:][0-9a-zA-Z_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+),[Xx]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\](\d+),[Xx]$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Zero_Page_X Bad Operand : '$operand' in '$line'\n");
  }
  $_[0] += 2;
}

# LDX Zpg,Y	B6
# STX Zpg,Y	96
sub is_Zero_Page_Y {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$[0-9a-fA-F]{0,1}[0-9a-fA-F],[Yy]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^%([01]{8}),[Yy]$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Yy]$/) {
    return 0 if $1 > 255;
    return 2;
  # Handle symbols
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Yy]$/) {
    # Not Zero Page,Y if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*\$*[0-9a-fA-F]+,[Yy]$/) {
    # Not Zero Page,Y if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\](\d+),[Yy]$/) {
    return 2;
  }

  return 0;
}

sub generate_Zero_Page_Y {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F]),[Yy]$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^%([01]{8}),[Yy]$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Yy]$/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Yy]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^({<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+),[Yy]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\](\d+),[Yy]$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Zero_Page_Y Bad Operand : '$operand' in '$line'\n");
  }
  $_[0] += 2;
}

# ADC Abs	6D
# AND Abs	2D
# ASL Abs	0E
# BIT Abs	2C
# CMP Abs	CD
# CPX Abs	EC
# CPY Abs	CC
# DEC Abs	CE
# EOR Abs	4D
# INC Abs	EE
# JMP Abs	4C
# JSR Abs	20
# LDA Abs	AD
# LDX Abs	AE
# LDY Abs	AC
# LSR Abs	4E
# ORA Abs	0D
# ROL Abs	2E
# ROR Abs	6E
# SBC Abs	ED
# STA Abs	8D
# STX Abs	8E
# STY Abs	8C
# STZ Abs	9C
# TRB Abs	1C
# TSB Abs	0C
sub is_Absolute {
  my ($operand, $lineno) = @_;

  # Don't mistake Accumulator mode for instructions like LSR.
  return 0 if $operand =~ /^[Aa]$/;

  # Parse hex
  if ($operand =~ /^\$[0-9a-fA-F]{0,1}[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^%([01]{16})$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\d+$/) {
    return 2;
  # handle symbols
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
    # Not Ansolute if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
    }
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*\$*[0-9a-fA-F]+$/) {
    # Not Ansolute if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\](\d+)$/) {
    return 2;
  }

  return 0;
}

sub generate_Absolute {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9A-Fa-f][0-9A-Fa-f])$/) {
    my $opval1 = hex(lc($1));
    my $opval2 = hex(lc($2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^%([01]{8})([0-1]{8})$/) {
    my $opval1 = unpack('C', pack("B8", $1));
    my $opval2 = unpack('C', pack("B8", $2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^(\d+)$/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $operand, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $line);
  # For macros
  } elsif ($operand =~ /^\](\d+)$/) {
    generate_24($ofh, $addr, $opcode, $mac2, $mac1, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Absolute Bad Operand '$operand' in '$line'\n");
  }
  $_[0] += 3;
}

# JMP (Abs)	6C
sub is_Indirect_Absolute {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]+)\)$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{16})\)$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)$/) {
    return 2;
  # Handle symbol
  } elsif ($operand =~ /^\([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*\)$/) {
    return 2;
  # Allow symbol arithmetic
  } elsif ($operand =~ /^\([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*\s*[+-\\*\/]\s*[#]*\$*[0-9a-fA-F]+\)/) {
    return 2;
  # For macros
  } elsif ($operand =~ /^\(\](\d+)\)$/) {
    return 2;
  } elsif ($operand =~ /^\(\[(\d+)\)$/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Absolute {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9A-Fa-f][0-9A-Fa-f])\)/) {
    my $opval1 = hex(lc($1));
    my $opval2 = hex(lc($2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8})([01]{8})\)$/) {
    my $opval1 = unpack('C', pack("B8", $1));
    my $opval2 = unpack('C', pack("B8", $2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\)/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)\)/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $line);
  # For macros
  } elsif ($operand =~ /^\(\](\d+)\)$/) {
    generate_24($ofh, $addr, $opcode, $mac2, $mac1, $lineno, $line);
  } elsif ($operand =~ /^\(\[(\d+)\)$/) {
    generate_24($ofh, $addr, $opcode, $mac2, $mac1, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Indirect_Absolute Bad Operand '$operand' in '$line'\n");
  }
  $_[0] += 3;
}

# JMP (Abs,X)	7C
sub is_Indirect_Absolute_X {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]+),[Xx]\)$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{16}),[Xx]\)$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+),[Xx]\)$/) {
    return 2;
  # Handle symbol
  } elsif ($operand =~ /^\([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*,[Xx]\)$/) {
    return 2;
  # Allow symbol arithmetic
  } elsif ($operand =~ /^\([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*\s*[+-\\*\/]\s*[#]*\$*[0-9a-fA-F]+,[Xx]\)/) {
    return 2;
  # For macros
  } elsif ($operand =~ /^\(\](\d+),[Xx]\)$/) {
    return 2;
  } elsif ($operand =~ /^\(\[(\d+),[Xx]\)$/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Absolute_X {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9A-Fa-f][0-9A-Fa-f]),[Xx]\)/) {
    my $opval1 = hex(lc($1));
    my $opval2 = hex(lc($2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8})([01]{8}),[Xx]\)$/) {
    my $opval1 = unpack('C', pack("B8", $1));
    my $opval2 = unpack('C', pack("B8", $2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+),[Xx]\)/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]\)$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+),[Xx]\)$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $line);
  # For macros
  } elsif ($operand =~ /^\(\](\d+),[Xx]\)$/) {
    generate_24($ofh, $addr, $opcode, $mac2, $mac1, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Indirect_Absolute_X Bad Operand '$operand' in '$line'\n");
  }
  $_[0] += 3;
}

# ADC Abs,X	7D
# AND Abs,X	3D
# ASL Abs,X	1E
# BIT Abs,X	3C
# CMP Abs,X	DD
# DEC Abs,X	DE
# EOR Abs,X	5D
# INC Abs,X	FE
# LDA Abs,X	BD
# LSR Abs,X	5E
# ORA Abs,X	1D
# ROL Abs,X	3E
# ROR Abs,X	7E
# SBC Abs,X	FD
# STA Abs,X	9D
# STZ Abs,X	9E
sub is_Absolute_X {
  my ($operand, $lineno) = @_;

  # Don't mistake Accumulator mode for instructions like LSR.
  return 0 if $operand =~ /^[Aa]$/;

  # Parse hex
  if ($operand =~ /^\$[0-9a-fA-F]{0,1}[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F],[Xx]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^%([01]{16}),[Xx]$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^(\d{1,3}),[Xx]$/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]$/) {
    # Not Ansolute,X if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
    }
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*(\$*[0-9a-fA-F]+),[Xx]$/) {
    # Not Ansolute,X if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\](\d+),[Xx]$/) {
    return 2;
  }

  return 0;
}

sub generate_Absolute_X {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9A-Fa-f][0-9A-Fa-f]),[Xx]/) {
    my $opval1 = hex(lc($1));
    my $opval2 = hex(lc($2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^%([01]{8})([01]{8}),[Xx]$/) {
    my $opval1 = unpack('C', pack("B8", $1));
    my $opval2 = unpack('C', pack("B8", $2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Xx]/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+),[Xx]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $line);
  # For macros
  } elsif ($operand =~ /^\](\d+),[Xx]$/) {
    generate_24($ofh, $addr, $opcode, $mac2, $mac1, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Indirect_Absolute_X Bad Operand '$operand' in '$line'\n");
  }
  $_[0] += 3;
}

# ADC Abs,Y	79
# AND Abs,Y	39
# CMP Abs,Y	D9
# EOR Abs,Y	59
# LDA Abs,Y	B9
# LDX Abs,Y	BE
# LDY Abs,X	BC
# ORA Abs,Y	19
# SBC Abs,Y	F9
# STA Abs,Y	99
sub is_Absolute_Y {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$[0-9a-fA-F]{0,1}[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F],[Yy]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^%([01]{16}),[Yy]$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\d+,[Yy]$/) {
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Yy]$/) {
    # Not Ansolute,Y if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
    }
    return 2;
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*(\$*[0-9a-fA-F]+),[Yy]/) {
    # Not Ansolute,Y if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\(\](\d+),[Yy]\)$/) {
    return 2;
  } elsif ($operand =~ /^\(\[(\d+),[Yy]\)$/) {
    return 2;
  }

  return 0;
}

sub generate_Absolute_Y {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9A-Fa-f][0-9A-Fa-f]),[Yy]/) {
    my $opval1 = hex(lc($1));
    my $opval2 = hex(lc($2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^%([01]{8})([01]{8}),[Yy]$/) {
    my $opval1 = unpack('C', pack("B8", $1));
    my $opval2 = unpack('C', pack("B8", $2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Yy]/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Yy]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+),[Yy]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $line);
  # For macros
  } elsif ($operand =~ /^\(\](\d+),[Yy]\)$/) {
    generate_24($ofh, $addr, $opcode, $mac2, $mac1, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Absolute_Y Bad Operand '$operand' in '$line'\n");
  }
  $_[0] += 3;
}

# ADC (Zpg,X)	61
# AND (Zpg,X)	21
# CMP (Zpg,X)	C1
# EOR (Zpg,X)	41
# LDA (Zpg,X)	A1
# ORA (Zpg,X)	01
# SBC (Zpg,X)	E1
# STA (Zpg,X)	81
sub is_Indirect_Zero_Page_X {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$[0-9a-fA-F]{0,1}[0-9a-fA-F],[Xx]\)$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8}),[Xx]\)$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+),[Xx]\)$/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]\)$/) {
    # Not Indirect Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*(\$*[0-9a-fA-F]+),[Xx]\)/) {
    # Not Indirect Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\(\](\d+),[Xx]\)$/) {
    return 2;
  } elsif ($operand =~ /^\(\[(\d+),[Xx]\)$/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Zero_Page_X {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-f]{0,1}[0-9a-fA-f]),[Xx]\)$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8}),[Xx]\)$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\),[Xx]/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^\(([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*),[Xx]\)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+),[Xx]\)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\(\](\d+),[Xx]\)$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Indirect_Zero_Page_X Bad Operand : '$operand' in '$line'\n");
  }
  $_[0] += 2;
}

# ADC (Zpg),Y	71
# AND (Zpg),Y	31
# CMP (Zpg),Y	D1
# EOR (Zpg),Y	51
# LDA (Zpg),Y	B1
# ORA (Zpg),Y	11
# SBC (Zpg),Y	F1
# STA (Zpg),Y	91
sub is_Indirect_Zero_Page_Y {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]{0,1}[0-9a-fA-F])\),[Yy]$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8})\),[Yy]$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\),[Yy]/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\),[Yy]$/) {
    # Not Indirect Zero Page,Y if the symbol is not 8 bits.
    return 2;
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*(\$*[0-9a-fA-F]+)\),[Yy]/) {
    # Not Indirect Zero Page,Y if the symbol is not 8 bits.
    return 2;
  # For macros
  } elsif ($operand =~ /^\(\](\d+)\),[Yy]$/) {
    return 2;
  } elsif ($operand =~ /^\(\[(\d+)\),[Yy]$/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Zero_Page_Y {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]{0,1}[0-9a-fA-F])\),[Yy]$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8})\),[Yy]$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\),[Yy]$/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^\(([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\),[Yy]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\([<>]*([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)\),[Yy]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\(\](\d+)\),[Yy]$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Indirect_Zero_Page_Y Bad Operand : '$operand' in '$line'\n");
  }
  $_[0] += 2;
}

# ADC (Zpg)	72
# AND (Zpg)	32
# CMP (Zpg)	D2
# EOR (Zpg)	52
# LDA (Zpg)	B2
# ORA (Zpg)	12
# SBC (Zpg)	F2
# STA (Zpg)	92
sub is_Indirect_Zero_Page {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$[0-9a-fA-F]{0,1}[0-9a-fA-F]\)$/) {
    return 2;
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8})\)$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)$/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\)$/) {
    # Not Indirect Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^\(([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+-\\*\/]\s*[#]*(\$*[0-9a-fA-F]+)\)$/) {
    # Not Indirect Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    $symval = $symbols{$1 . ':'} unless defined $symval;
    $symval = $symbols{':' . $1} unless defined $symval;
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$|^%[01]{8}$/;
      }
    } else {
      # Assume that forward declared symbols are addresses.
      return 0;
    }
    return 2;
  # For macros
  } elsif ($operand =~ /^\(\](\d+)\)$/) {
    return 2;
  } elsif ($operand =~ /^\(\](\d+)\)$/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Zero_Page {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line, $mac1, $mac2) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]{0,1}[0-9a-fA-F])\)$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse binary
  } elsif ($operand =~ /^\(%([01]{8})\)$/) {
    my $opval = unpack('C', pack("B8", $1));
    generate_16($ofh, $addr, $opcode, $opval, $lineno, $line);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)/) {
    generate_16($ofh, $addr, $opcode, $1, $lineno, $line);
  # Return symbol value
  } elsif ($operand =~ /^\(([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, undef, undef, $line);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)\)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1, $2, $3, $4, $line);
  # For macros
  } elsif ($operand =~ /^\(\](\d+)\)$/) {
    my $val = $mac1;
    if ($1 == 2) {
      $val = $mac2;
    }
    generate_16($ofh, $addr, $opcode, $val, $lineno, $line);
  } else {
    print_err(">>>> $lineno - Indirect_Zero_Page Bad Operand '$operand' in '$line'\n");
  }
  $_[0] += 2;
}

# BBR0 Oper	0F
# BBR1 Oper	1F
# BBR2 Oper	2F
# BBR3 Oper	3F
# BBR4 Oper	4F
# BBR5 Oper	5F
# BBR6 Oper	6F
# BBR7 Oper	7F
# BBS0 Oper	8F
# BBS1 Oper	9F
# BBS2 Oper	AF
# BBS3 Oper	BF
# BBS4 Oper	CF
# BBS5 Oper	DF
# BBS6 Oper	EF
# BBS7 Oper	FF
# BCC Oper	90
# BCS Oper	B0
# BEQ Oper	F0
# BMI Oper	30
# BNE Oper	D0
# BPL Oper	10
# BRA Oper	80
# BVC Oper	50
# BVS Oper	70
sub is_Relative {
  my ($operand, $lineno) = @_;
  # Just needs to have an operand, we'll figure it out
  if ($operand =~ /^(\S+)/) {
    return 2;
  }

  return 0;
}

sub generate_Relative {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line) = @_;

  # Decode hex
  if ($operand =~ /^\$([0-9a-fA-F]+$)/) {
    my $opval = hex(lc($1));
    my $rel = (0 - ($addr - $opval)) + 254;
    if ($rel < 0) {
      $rel += 256;
    }
    if ($rel > 255) {
      $rel -= 256;
    }
    if ($rel < 0 || $rel > 255) {
      print_err("^^^^ $lineno - Illegal Branch in '$line'\n");
      generate_16($ofh, $addr, $opcode, 0x00, $lineno, $line);
    } else {
      generate_16($ofh, $addr, $opcode, $rel, $lineno, $line);
    }
  # Decode decimal
  } elsif ($operand =~ /^(\d+)$/) {
    my $rel = (0 - ($addr - $1)) + 254;
    if ($rel < 0) {
      $rel += 256;
    }
    if ($rel > 255) {
      $rel -= 256;
    }
    if ($rel < 0 || $rel > 255) {
      print_err("^^^^ $lineno - Illegal Branch in '$line'\n");
      generate_16($ofh, $addr, $opcode, 0x00, $lineno, $line);
    } else {
      generate_16($ofh, $addr, $opcode, $rel, $lineno, $line);
    }
  # Handle symbols
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
    my $symbol = $1;
    my $symval = $symbols{$symbol};
    $symval = $symbols{$symbol . ':'} unless defined $symval;
    $symval = $symbols{':' . $symbol} unless defined $symval;
    if (defined $symval) {
      my $opval = lc($symval);
      if ($symval =~ /^\$([0-9a-fA-F]+)$/) {
        $opval = hex(lc($1));
      } else {
        $opval = $symval;
      }

      my $rel = (0 - ($addr - $opval)) + 254;
      if ($rel < 0) {
        $rel += 256;
      }
      if ($rel > 255) {
        $rel -= 256;
      }
      if ($rel < 0 || $rel > 255) {
        print_err("^^^^ $lineno - Illegal Branch in '$line'\n");
        generate_16($ofh, $addr, $opcode, 0x00, $lineno, $line);
      } else {
        generate_16($ofh, $addr, $opcode, $rel, $lineno, $line);
      }
    } else {
      print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
    }
  # Handle symbol arithmetic
  } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
    my $sym = $1;
    my $op = $2;
    my $val = $3;
    my $symval = $symbols{$sym};
    $symval = $symbols{$sym . ':'} unless defined $symval;
    $symval = $symbols{':' . $sym} unless defined $symval;
    if (defined $symval) {
      my $opval = lc($symval);
      if ($symval =~ /^\$([0-9a-fA-F]+)$/) {
        $opval = hex(lc($1));
      } else {
        $opval = $symval;
      }

      if ($op eq '+') {
        $opval += $val;
      } elsif ($op eq '-') {
        $opval -= $val;
      }

      my $rel = (0 - ($addr - $opval)) + 254;
      if ($rel < 0) {
        $rel += 256;
      }
      if ($rel > 255) {
        $rel -= 256;
      }
      generate_16($ofh, $addr, $opcode, $rel, $lineno, $line);
    } else {
      print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
    }
  } else {
    print_err(">>>> $lineno - Relative Bad Operand '$operand' in '$line'\n");
  }

  $_[0] += 2;
}

# BRK		00
# CLC		18
# CLD		D8
# CLI		58
# CLV		B8
# DEX		CA
# DEY		88
# INX		E8
# INY		C8
# NOP		EA
# PHA		48
# PHP		08
# PHX		DA
# PHY		5A
# PLA		68
# PLP		28
# PLX		FA
# PLY		7A
# RTI		40
# RTS		60
# SEC		38
# SED		F8
# SEI		78
# TAX		AA
# TAY		A8
# TSX		BA
# TXA		8A
# TXS		9A
# TYA		98
sub is_Implied {
  my ($operand, $lineno) = @_;

  # No operand on implied instructions
  if ($operand eq '') {
    return 1;
  } elsif ($operand =~ /^\s*;/) {
    return 1;
  }

  return 0;
}

sub generate_Implied {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line) = @_;

  generate_8($ofh, $addr, $opcode, $lineno, $line);

  $_[0]++;
}

# ASL A		0A
# DEA		3A
# INA		1A
# LSR A		4A
# ROL A		2A
# ROR A		6A
sub is_Accumulator {
  my ($operand, $lineno) = @_;

  if ($operand =~ /^[Aa]$/ || $operand eq '') {
    return 1;
  }

  return 0;
}

sub generate_Accumulator {
  my ($addr, $operand, $opcode, $ofh, $lineno, $line) = @_;

  generate_8($ofh, $addr, $opcode, $lineno, $line);

  $_[0]++;
}

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
    print_err(sprintf("SYNTAX ERROR!    %-4d  %s\n", $lineno, $line));
  }

  $label = '' unless defined $label;
  $comment = '' unless defined $comment;
  $mnemonic = '' unless defined $mnemonic;
  $operand = '' unless defined $operand;

  print "label=$label mnemonic=$mnemonic operand=$operand comment=$comment\n" if $debug;

  return ($label, $mnemonic, $operand, $comment);
}

my $addr = $base;

my $ifh;

my $lineno = 0;

my $in_include = 0;

my $ififh;

my $ilineno = 0;

# Open the input file.
if (open($ifh, "<$input_file")) {

  print "**** Starting 1st pass ****\n" if $verbose;

  print "\n" if $verbose;

  # Pass 1, build symbol table.
  #while (my $line = readline $ifh) {
  while (!eof($ifh)) {
    my $line = '';
    if ($in_include) {
      $line = readline $ififh;

      chomp $line;

      $ilineno++;

      print $COUT_YELLOW . sprintf("%04x:  %-4d  %s\n", $addr, $ilineno, $line) . $COUT_NORMAL if $listing;

#print $COUT_GREEN . "line=$line\n" . $COUT_NORMAL;

      if (eof($ififh)) {
        $in_include = 0;
        print $COUT_GREEN . "---- END INCLUDE ----\n" . $COUT_NORMAL if $debug;
      }
    } else {
      $line = readline $ifh;

      $lineno++;

      chomp $line;

      print sprintf("%04x:  %-4d  %s\n", $addr, $lineno, $line) if $listing;
    }

    # Handle include files.
    if ($line =~ /^#include\s+"([^"]+)"\s*\;*.*/ || $line =~ /^\.include\s+"([^"]+)"\s*\;*.*/) {
      if (open($ififh, "<$1")) {
        print $COUT_GREEN . "---- INCLUDING $1 ----\n" . $COUT_NORMAL if $debug;
        $in_include = 1;
        $ilineno = 0;
      } else {
        print_err("**** Unable to open $1 - '$line'\n");
      }
      next;
    }

    # Skip blank lines.
    next if $line =~ /^\s*$/;

    # Skip comment lines.
    next if $line =~ /^\s*;/;
    next if $line =~ /^\s*\*/;

    # Process .org lines.
    if ($line =~ /^\.org\s+(.+)/) {
      my $operand = $1;
      $operand =~ s/^\$//;
      $base = hex(lc($operand));
      $addr = $base;
      print sprintf("%%%%%%%% base=%s \$%02x\n", $base, $base) if $verbose;
      next;
    }
    # Parse .alias lines.
    if ($line =~ /^\.alias\s+(\S+)\s+(.+)/) {
      my $alias = $1;
      my $val = $2;
      $val =~ s/\s*;(.+)$//;
      $symbols{$alias} = $val;
      print "%%%% alias $alias $val\n" if $verbose;
      next;
    }

    # Parse input lines.
    my ($label, $mnemonic, $operand, $comment) = parse_line($line, $lineno);

    my $rv;

    # Look for symbols.
    if (defined $label && $label ne '' && $label ne ';' && $mnemonic !~ /EQU|\.EQ|^=$/i) {
      my $symbol = $label;
      print $COUT_AQUA . sprintf("%%%%%%%% Saving symbol $label %s \$%04x\n", $addr, $addr) . $COUT_NORMAL if $verbose;
      $symbols{$symbol} = sprintf("\$%04x", $addr);
    }

    next unless defined $mnemonic;
    next if $mnemonic eq '';

    my $ucmnemonic = uc($mnemonic);

    if ($in_macro) {
      if ($ucmnemonic ne '<<<') {
        print $COUT_AQUA . "%%%% Saving $line to macro $cur_macro\n" . $COUT_NORMAL;
        push @{$macros{$cur_macro}}, $line;
      }
    }

    if ($in_conditional) {
print ">>>> IN CONDITIONAL\n";
      if ($skip) {
        print "******** SKIPPING!!!!! ********\n";
        next;
      }
    }

    # We only need to look for ORG and EQU on pass 1.
    if ($ucmnemonic =~ /ORG|\.OR/) {
      # Set base
      $operand =~ s/^\$//;
      $base = hex(lc($operand));
      $addr = $base;
      print sprintf("%%%%%%%% Setting base to \$%04x\n", $base) if $verbose;
    } elsif ($ucmnemonic =~ /EQU|\.EQ|^=$/i) {
      # define constant
      my $symbol = $label;
      #print $COUT_AQUA . "%%%% Saving Symbol $symbol $operand\n" . $COUT_NORMAL if $verbose;
      # Hex
      if ($operand =~ /^\$([0-9a-fA-F]+)$/) {
        $symbols{$symbol} = lc($operand);
      # Decimal
      } elsif ($operand =~ /^(\d+)$/) {
        $symbols{$symbol} = '$' . sprintf("%x", $operand);
      # 8 bit binary
      } elsif ($operand =~ /^%([01]{8})$/) {
        $symbols{$symbol} = '$' . sprintf("%02x", unpack('C', pack("B8", $1)));
        print $COUT_AQUA . "%%%% Saving Symbol $symbol $symbols{$symbol}\n" . $COUT_NORMAL if $verbose;
      # 16 bit binary
      } elsif ($operand =~ /^%([01]{8})([01]{8})$/) {
        $symbols{$symbol} = '$' . sprintf("%02x", unpack('C', pack("B8", $1))) . sprintf("%02x", unpack('C', pack("B8", $2)));
        print $COUT_AQUA . "%%%% Saving Symbol $symbol $symbols{$symbol}\n" . $COUT_NORMAL if $verbose;
      } elsif ($operand eq '*') {
        $symbols{$symbol} = sprintf("\$%x", $addr);
      # Handle symbol
      } elsif ($operand =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
        my $prt = $1;
        my $sym = $2;
        my $symval = $symbols{$sym};
        $symval = $symbols{$sym . ':'} unless defined $symval;
        $symval = $symbols{':' . $sym} unless defined $symval;
        if (defined $symval) {
          # Handle < and >.
          if (defined $prt && $prt eq '<') {
            if ($symval =~ /\$([0-9a-fA-F]{1,2})/) {
              $symbols{$symbol} = $1;
              print $COUT_AQUA . "%%%% Saving Symbol $symbol $1\n" . $COUT_NORMAL if $verbose;
            }
          } elsif (defined $prt && $prt eq '>') {
            if ($symval =~ /\$[0-9a-fA-F]*([0-9a-fA-F]{1,2})/) {
              $symbols{$symbol} = $1;
              print $COUT_AQUA . "%%%% Saving Symbol $symbol $1\n" . $COUT_NORMAL if $verbose;
            }
          } else {
            $symbols{$symbol} = $symval;
            print $COUT_AQUA . "%%%% Saving Symbol $symbol $symval\n" . $COUT_NORMAL if $verbose;
          }
        } else {
          print_err("**** $lineno - Unknown symbol '$2' in '$line'\n");
        }
      # Allow arithmetic on symbol
      } elsif ($operand =~ /^([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
        ##FIXME -- need to handle < and > here.
        my $sym = $2;
        my $op = $3;
        my $opv = $4;
        if (defined $sym) {
          my $symv = $symbols{$sym};
          $symv = $symbols{$sym . ':'} unless defined $symv;
          $symv = $symbols{':' . $sym} unless defined $symv;
          if (defined $symv) {
            $symbols{$symbol} = sprintf("\$%x", sym_op($symv, $op, $opv));
            print $COUT_AQUA . "%%%% Saving Symbol $symbol $symbols{$symbol}\n" . $COUT_NORMAL if $verbose;
          } else {
            print_err("**** $lineno - Unknown symbol '$sym' in '$line'\n");
          }
        }
      } else {
        print $COUT_AQUA . "%%%% Saving Symbol $symbol $operand\n" . $COUT_NORMAL if $verbose;
        $symbols{$symbol} = $operand;
      }
    } elsif ($ucmnemonic =~ /HEX/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      if ($operand =~ /([0-9a-fA-F]+)/) {
         $addr += (length($1) / 2);
      }
    } elsif ($ucmnemonic =~ /^DS$/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      if ($operand =~ /\$([0-9a-fA-F]+)/) {
         $addr += hex(lc($1));
      } elsif ($operand =~ /^(\d+)/) {
         $addr += $1;
      }
    } elsif ($ucmnemonic =~ /^DB$|^TYP$/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      $addr++;
    } elsif ($ucmnemonic =~ /^DA$|^\.DA$|^DW$/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      $addr += 2;
    } elsif ($ucmnemonic =~ /DFB/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      if ($operand =~ /^%([01]{8})/) {
        $addr++;
      } elsif ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        $addr++;
      } elsif ($operand =~ /^#<(.+)/) {
        $addr++;
      } elsif ($operand =~ /^#>(.+)/) {
        $addr++;
      } elsif ($operand =~ /^#(.+)/) {
        my @args = split /,/, $1;
        $addr += scalar @args * 2;
      # Allow symbol arithmetic.
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr++;
          } elsif ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr += 2;
          }
        #} else {
        #  print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
        }
      # Allow symbols.
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*$/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr++;
          } elsif ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr += 2;
          }
        #} else {
        #  print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
        }
      } else {
        my @symbols = split(',', $operand);
        my @bytes;
        foreach my $sym (@symbols) {
          my $prt = '';
          my $symbol = $sym;
          if ($sym =~ /^([\<\>]*)([A-Za-z\.\?:][A-Za-z0-9_\.\?:]+)/) {
            $prt = $1;
            $symbol = $2;
          }
          my $symval = get_symval($prt, $symbol);
          if (defined $symval) {
            push @bytes, sprintf("%02x", parse_symval($symval));
          #} else {
          #  print_err("**** $lineno - Unknown symbol '$sym' in '$line'\n");
          }
        }
        $addr += scalar(@bytes);
      }
    } elsif ($ucmnemonic =~ /ASC|DCI|INV|FLS|BLK|REV|STR/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      my $str = '';
      my $trl;
      if ($operand =~ /^\"(.+)\"([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      } elsif ($operand =~ /^'(.+)'([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      }
      $addr += (length($str) - 1);
      $addr++ if defined $trl;
##FIXME -- need to test this
    } elsif ($ucmnemonic =~ /HBY/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      ##FIXME -- implement this
    } elsif ($ucmnemonic =~ /^BYT$/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      ##FIXME -- implement this
    } elsif ($ucmnemonic =~ /DFS/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      ##FIXME -- implement this
    } elsif ($ucmnemonic =~ /BYTE/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      my @args = split /,/, $operand;
      $addr += scalar @args;
    } elsif ($ucmnemonic =~ /WORD/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      my @args = split /,/, $operand;
      $addr += scalar @args * 2;
    } elsif ($ucmnemonic =~ /OBJ|CHK|LST|END|SAV|\.TF|XC/) {
      # Just ignore this
    } elsif ($ucmnemonic =~ /MAC/) {
      print "**** MACRO START **** '$line'\n" if $debug;
      $macros{$label} = ();
      $in_macro = 1;
      $cur_macro = $label;
    } elsif ($ucmnemonic =~ /\<\<\</) {
      print "**** MACRO END **** '$line'\n" if $debug;
      $in_macro = 0;
      $cur_macro = '';
    # Conditional assembly
    } elsif ($ucmnemonic =~ /^DO$/) {
print ">>>>  DO  $operand\n";
      $in_conditional = 1;
      if ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          if ($symval =~ /\$([0-9a-fA-F]+)$/) {
            if (hex($1) > 0) {
              $skip = 1;
            }
          }
        } else {
          print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
        }
      } else {
        print_err("**** $lineno - ERROR PARSING CONDITIONAL '$operand' in '$line'\n");
      }
    } elsif ($ucmnemonic =~ /^FIN$/) {
      $in_conditional = 0;
      $skip = 0;
    # Mnemonic	Addressing mode	Form		Opcode	Size	Timing
    } elsif (defined $mnemonics{$ucmnemonic}) {
      my $foundit = 0;
      foreach my $opmode (keys %{$mnemonics{$ucmnemonic}}) {
        my $checkfunc = $modefuncs{$opmode}{'check'};
        if ($checkfunc->($operand, $lineno)) {
          $addr += $modefuncs{$opmode}{'size'};
          $foundit = 1;
          last;
        }
      }
      if (! $foundit) {
        print_err("!!!! $lineno - Unrecognized addressing mode '$line'!\n");
      }
    } elsif (defined $macros{$ucmnemonic}) {
      print "#### MACRO $ucmnemonic ####\n" if $debug;

      # Add length for the macro.
      my $maclnno = 0;
      foreach my $macln (@{$macros{$ucmnemonic}}) {
        $maclnno++;
        my ($maclabel, $macmnemonic, $macoperand, $maccomment) = parse_line($macln, $maclnno);
        my $ucmacmnemonic = uc($macmnemonic);

        my $foundit = 0;
        foreach my $opmode (keys %{$mnemonics{$ucmacmnemonic}}) {
          my $checkfunc = $modefuncs{$opmode}{'check'};
          if ($checkfunc->($macoperand, $maclnno)) {
            $addr += $modefuncs{$opmode}{'size'};
            $foundit = 1;
            last;
          }
        }
        if (! $foundit) {
          print_err("!!!! $maclnno - Unrecognized addressing mode in macro '$macln'!\n");
        }
      }
    } else {
      print_err("$lineno - Unknown mnemonic '$mnemonic' in '$line'\n");
    }
  }

  print "**** Starting 1st pass again ****\n" if $verbose;

  print "\n" if $verbose;

  # Rewind to the beginning of the input file.
  seek($ifh, 0, 0);

  $addr = $base;
  $lineno = 0;
  $checksum = 0;
  $in_macro = 0;
  $in_conditional = 0;
  $in_include = 0;

  # Pass 1.5, build symbol table.
  #while (my $line = readline $ifh) {
  while (!eof($ifh)) {
    my $line = '';
    if ($in_include) {
      $line = readline $ififh;

      $ilineno++;

      $in_include = 0 if eof($ififh);
    } else {
      $line = readline $ifh;

      $lineno++;
    }

    chomp $line;

    #print sprintf("%04x:  %-4d  %s\n", $addr, $lineno, $line) if $listing;

    # Handle include files.
    if ($line =~ /^#include\s+"([^"]+)"\s*\;*.*/ || $line =~ /^\.include\s+"([^"]+)"\s*\;*.*/) {
      if (open($ififh, "<$1")) {
        $in_include = 1;
        $ilineno = 0;
      } else {
        print_err("**** Unable to open $1 - '$line'\n");
      }
      next;
    }

    # Skip blank lines.
    next if $line =~ /^\s*$/;

    # Skip comment lines.
    next if $line =~ /^\s*;/;
    next if $line =~ /^\s*\*/;

    # Process .org lines.
    #if ($line =~ /^\.org\s+(.+)/) {
    #  my $operand = $1;
    #  $operand =~ s/^\$//;
    #  $base = hex(lc($operand));
    #  $addr = $base;
    #  print sprintf("%%%%%%%% base=%s \$%02x\n", $base, $base) if $verbose;
    #  next;
    #}
    # Parse .alias lines.
    #if ($line =~ /^\.alias\s+(\S+)\s+(.+)/) {
    #  my $alias = $1;
    #  my $val = $2;
    #  $val =~ s/\s*;(.+)$//;
    #  $symbols{$alias} = $val;
    #  print "%%%% alias $alias $val\n" if $verbose;
    #  next;
    #}

    # Parse input lines.
    my ($label, $mnemonic, $operand, $comment) = parse_line($line, $lineno);

    my $rv;

    # Look for symbols.
    if (defined $label && $label ne '' && $label ne ';' && $mnemonic !~ /EQU|\.EQ|^=$/i) {
      my $symbol = $label;
      if (! defined $symbols{$symbol}) {
        print $COUT_AQUA . sprintf("%%%%%%%% Saving symbol $label %s \$%04x\n", $addr, $addr) . $COUT_NORMAL if $verbose;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
    }

    next unless defined $mnemonic;
    next if $mnemonic eq '';

    my $ucmnemonic = uc($mnemonic);

    #if ($in_macro) {
    #  if ($ucmnemonic ne '<<<') {
    #    print $COUT_AQUA . "%%%% Saving $line to macro $cur_macro\n" . $COUT_NORMAL;
    #    push @{$macros{$cur_macro}}, $line;
    #  }
    #}

    # We only need to look for ORG and EQU on pass 1.
    if ($ucmnemonic =~ /ORG|\.OR/) {
      # Set base
      #$operand =~ s/^\$//;
      #$base = hex(lc($operand));
      #$addr = $base;
      #print sprintf("%%%%%%%% Setting base to \$%04x\n", $base) if $verbose;
    } elsif ($ucmnemonic =~ /EQU|\.EQ|^=$/i) {
      # define constant
      my $symbol = $label;
      if (! defined $symbols{$symbol}) {
        #print $COUT_AQUA . "%%%% Saving Symbol $symbol $operand\n" . $COUT_NORMAL if $verbose;
        #if ($operand =~ /^\$([0-9a-fA-F]+)$/) {
        #  $symbols{$symbol} = lc($operand);
        ## 8 bit binary
        #} elsif ($operand =~ /^%([01]{8})$/) {
        #  $symbols{$symbol} = '$' . sprintf("%02x", unpack('C', pack("B8", $1)));
        ## 16 bit binary
        #} elsif ($operand =~ /^%([01]{8})([01]{8})$/) {
        #  $symbols{$symbol} = '$' . sprintf("%02x", unpack('C', pack("B8", $1))) . sprintf("%02x", unpack('C', pack("B8", $2)));

        # Handle symbol
        #} elsif ($operand =~ /^([<>]*)([A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
        if ($operand =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
          my $prt = $1;
          my $symval = $symbols{$2};
          $symval = $symbols{$2 . ':'} unless defined $symval;
          $symval = $symbols{':' . $2} unless defined $symval;
          if (defined $symval) {
            # Handle < and >.
            if (defined $prt && (($prt eq '>' && $edasm) || ($prt eq '<' && !$edasm))) {
              if ($symval =~ /\$([0-9a-fA-F]{1,2})/) {
                $symbols{$symbol} = $1;
                print $COUT_AQUA . "%%%% Saving Symbol $symbol $1\n" . $COUT_NORMAL if $verbose;
              }
            } elsif (defined $prt && (($prt eq '<' && $edasm) || ($prt = '>' && !$edasm))) {
              if ($symval =~ /\$[0-9a-fA-F]*([0-9a-fA-F]{1,2})/) {
                $symbols{$symbol} = $1;
                print $COUT_AQUA . "%%%% Saving Symbol $symbol $1\n" . $COUT_NORMAL if $verbose;
              }
            } else {
              $symbols{$symbol} = $symval;
              print $COUT_AQUA . "%%%% Saving Symbol $symbol $symval\n" . $COUT_NORMAL if $verbose;
            }
          } else {
            print_err("**** $lineno - Unknown symbol '$2' in '$line'\n");
          }
        # Allow arithmetic on symbol
        } elsif ($operand =~ /^([<>]*)([A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+]\s*[#]*(\$*[0-9a-fA-F]+)$/) {
          # Add
          $symbols{$symbol} = sprintf("\$%x", sym_op($symbols{$2}, '+', $3));
          print $COUT_AQUA . "%%%% Saving Symbol $symbol $symbols{$symbol}\n" . $COUT_NORMAL if $verbose;
        } elsif ($operand =~ /^([<>]*)([A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[-]\s*[#]*(\$*[0-9a-fA-F]+)$/) {
          # Subtract
          $symbols{$symbol} = sprintf("\$%x", sym_op($symbols{$2}, '-', $3));
          print $COUT_AQUA . "%%%% Saving Symbol $symbol $symbols{$symbol}\n" . $COUT_NORMAL if $verbose;
        } else {
          $symbols{$symbol} = $operand;
          print $COUT_AQUA . "%%%% Saving Symbol $symbol $operand\n" . $COUT_NORMAL if $verbose;
        }
      }
    } elsif ($ucmnemonic =~ /HEX/) {
      if ($label ne '') {
        my $symbol = $label;
        if (! defined $symbols{$symbol}) {
          $symbols{$symbol} = sprintf("\$%04x", $addr);
        }
      }
      if ($operand =~ /([0-9a-fA-F]+)/) {
         $addr += (length($1) / 2);
      ##FIXME -- need to handle symbols here.
      }
    } elsif ($ucmnemonic =~ /^DS$/) {
      if ($label ne '') {
        my $symbol = $label;
        if (! defined $symbols{$symbol}) {
          $symbols{$symbol} = sprintf("\$%04x", $addr);
        }
      }
      if ($operand =~ /\$([0-9a-fA-F]+)/) {
         $addr += hex(lc($1));
      } elsif ($operand =~ /^(\d+)/) {
         $addr += $1;
      ##FIXME -- need to handle symbols here.
      }
    } elsif ($ucmnemonic =~ /^DB$|^TYP$/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      $addr++;
    } elsif ($ucmnemonic =~ /^DA$|^\.DA$|^DW$/) {
      if ($label ne '') {
        my $symbol = $label;
        if (! defined $symbols{$symbol}) {
          $symbols{$symbol} = sprintf("\$%04x", $addr);
        }
      }
      $addr += 2;
    } elsif ($ucmnemonic =~ /DFB/) {
      if ($label ne '') {
        my $symbol = $label;
        if (! defined $symbols{$symbol}) {
          $symbols{$symbol} = sprintf("\$%04x", $addr);
        }
      }
      if ($operand =~ /^%([01]{8})/) {
        $addr++;
      } elsif ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        $addr++;
      } elsif ($operand =~ /^#<(.+)/) {
        $addr++;
      } elsif ($operand =~ /^#>(.+)/) {
        $addr++;
      } elsif ($operand =~ /^#(.+)/) {
        my @args = split /,/, $1;
        $addr += scalar @args * 2;
      # Allow symbol arithmetic.
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr++;
          } elsif ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr += 2;
          }
        } else {
          print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
        }
      # Allow symbols.
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*$/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr++;
          } elsif ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
            $addr += 2;
          }
        } else {
          print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
        }
      } else {
        my @symbols = split(',', $operand);
        my @bytes;
        foreach my $sym (@symbols) {
          my $prt = '';
          my $symbol = $sym;
          if ($sym =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]+)/) {
            $prt = $1;
            $symbol = $2;
          }
          my $symval = get_symval($prt, $symbol);
          if (defined $symval) {
            if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])/) {
              push @bytes, pack('C', hex(sprintf("%02x", hex(lc($1)))));
              push @bytes, pack('C', hex(sprintf("%02x", hex(lc($2)))));
            } else {
              push @bytes, sprintf("%02x", parse_symval($symval));
            }
          } else {
            print_err("**** $lineno - Unknown symbol '$sym' in '$line'\n");
          }
        }
        $addr += scalar(@bytes);
      }
    } elsif ($ucmnemonic =~ /ASC|DCI|INV|FLS|BLK|REV|STR/) {
      if ($label ne '') {
        my $symbol = $label;
        if (! defined $symbols{$symbol}) {
          $symbols{$symbol} = sprintf("\$%04x", $addr);
        }
      }
      my $str = '';
      my $trl;
      if ($operand =~ /^\"(.+)\"([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      } elsif ($operand =~ /^'(.+)'([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      }
      $addr += (length($str) - 1);
      $addr++ if defined $trl;
##FIXME -- need to test this
    } elsif ($ucmnemonic =~ /HBY/) {
      if ($label ne '') {
        my $symbol = $label;
        if (! defined $symbols{$symbol}) {
          $symbols{$symbol} = sprintf("\$%04x", $addr);
        }
      }
      ##FIXME -- implement this
    } elsif ($ucmnemonic =~ /^BYT$/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      ##FIXME -- implement this
    } elsif ($ucmnemonic =~ /DFS/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      ##FIXME -- implement this
    } elsif ($ucmnemonic =~ /BYTE/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      my @args = split /,/, $operand;
      $addr += scalar @args;
    } elsif ($ucmnemonic =~ /WORD/) {
      if ($label ne '') {
        my $symbol = $label;
        $symbols{$symbol} = sprintf("\$%04x", $addr);
      }
      my @args = split /,/, $operand;
      $addr += scalar @args * 2;
    } elsif ($ucmnemonic =~ /OBJ|CHK|LST|END|SAV|\.TF|XC/) {
      # Just ignore this
    } elsif ($ucmnemonic =~ /MAC/) {
    #  print "**** MACRO START **** '$line'\n" if $debug;
    #  $macros{$label} = ();
    #  $in_macro = 1;
    #  $cur_macro = $label;
    } elsif ($ucmnemonic =~ /\<\<\</) {
    #  print "**** MACRO END **** '$line'\n" if $debug;
    #  $in_macro = 0;
    #  $cur_macro = '';
    # Conditional assembly
    } elsif ($ucmnemonic =~ /^DO$/) {
print ">>>>  DO  $operand\n";
      $in_conditional = 1;
    } elsif ($ucmnemonic =~ /^FIN$/) {
print ">>>> END CONDITIONAL\n";
      $in_conditional = 0;
    # Mnemonic	Addressing mode	Form		Opcode	Size	Timing
    } elsif (defined $mnemonics{$ucmnemonic}) {
      my $foundit = 0;
      foreach my $opmode (keys %{$mnemonics{$ucmnemonic}}) {
        my $checkfunc = $modefuncs{$opmode}{'check'};
        if ($checkfunc->($operand, $lineno)) {
          $addr += $modefuncs{$opmode}{'size'};
          $foundit = 1;
          last;
        }
      }
      if (! $foundit) {
        print_err("!!!! $lineno - Unrecognized addressing mode '$line'!\n");
      }
    } elsif (defined $macros{$ucmnemonic}) {
      print "#### MACRO $ucmnemonic ####\n" if $debug;

      # Add length for the macro.
      my $maclnno = 0;
      foreach my $macln (@{$macros{$ucmnemonic}}) {
        $maclnno++;
        my ($maclabel, $macmnemonic, $macoperand, $maccomment) = parse_line($macln, $maclnno);
        my $ucmacmnemonic = uc($macmnemonic);

        my $foundit = 0;
        foreach my $opmode (keys %{$mnemonics{$ucmacmnemonic}}) {
          my $checkfunc = $modefuncs{$opmode}{'check'};
          if ($checkfunc->($macoperand, $maclnno)) {
            $addr += $modefuncs{$opmode}{'size'};
            $foundit = 1;
            last;
          }
        }
        if (! $foundit) {
          print_err("!!!! $maclnno - Unrecognized addressing mode in macro '$macln'!\n");
        }
      }
    } else {
      print_err("$lineno - Unknown mnemonic '$mnemonic' in '$line'\n");
    }
  }

  print "\n" if $verbose;

  if ($symbol_table) {
    print "---- Symbol table ----\n\n";

    foreach my $ky (keys %symbols) {
      print sprintf("%-13s :  %s\n", $ky, $symbols{$ky});
    }

    print "\n";
  }

  print "**** Starting 2nd pass ****\n" if $verbose;

  print "\n" if $verbose;

  # Rewind to the beginning of the input file.
  seek($ifh, 0, 0);

  my $ofh;

  $addr = $base;
  $lineno = 0;
  $checksum = 0;
  $in_macro = 0;
  $in_conditional = 0;

  $in_include = 0;

  # Pass two, generate output
  open($ofh, ">$output_file") or die "Can't write $output_file\n";

  binmode $ofh;

  #while (my $line = readline $ifh) {
  while (!eof($ifh)) {
    my $line = '';
    if ($in_include) {
      $line = readline $ififh;

      $ilineno++;

      $in_include = 0 if eof($ififh);
    } else {
      $line = readline $ifh;

      $lineno++;
    }

    chomp $line;

    # Handle include files.
    if ($line =~ /^#include\s+"([^"]+)"\s*\;*.*/ || $line =~ /^\.include\s+"([^"]+)"\s*\;*.*/) {
      if (open($ififh, "<$1")) {
        $in_include = 1;
        $ilineno = 0;
      } else {
        print_err("**** Unable to open $1 - '$line'\n");
      }
      next;
    }

    # Skip blank lines, comment lines, .org .alias.
    if ($line =~ /^\s*$|^\s*;|^\s*\*|^\.org\s+.+|^\.alias\s+\S+\s+.+/) {
      print sprintf("                 %-4d  %s\n", $lineno, $line) if $code_listing;
      next;
    }

    # Parse input lines.
    my ($label, $mnemonic, $operand, $comment) = parse_line($line, $lineno);

    #next unless defined $mnemonic;
    #next if $mnemonic eq '';
    if (!defined $mnemonic || $mnemonic eq '') {
      print sprintf("                 %-4d  %s\n", $lineno, $line) if $code_listing;
      next;
    }

    my $ucmnemonic = uc($mnemonic);

    # Skip ORG, EQU and OBJ on pass 2.
    if ($ucmnemonic =~ /ORG|\.OR|EQU|\.EQ|OBJ|LST|^=$|END|SAV|\.TF|XC/) {
      print sprintf("                 %-4d  %s\n", $lineno, $line) if $code_listing;
      next;
    }

    if (defined $mnemonics{$ucmnemonic}) {
      my $foundit = 0;
      foreach my $opmode (keys %{$mnemonics{$ucmnemonic}}) {
        my $checkfunc = $modefuncs{$opmode}{'check'};
        my $genfunc = $modefuncs{$opmode}{'gen'};
        if ($checkfunc->($operand, $lineno)) {
          $genfunc->($addr, $operand, $mnemonics{$ucmnemonic}{$opmode}, $ofh, $lineno, $line);
          $foundit = 1;
          last;
        }
      }
      if (! $foundit) {
        print_err("!!!! $lineno - Unrecognized addressing mode '$line'!\n");
      }
    } elsif ($ucmnemonic eq 'HEX') {
      # Unpack hex data.
      #my @bytes  = map { pack('C', hex(lc($_))) } ($operand =~ /(..)/g);
      my @bytes  = map { pack('C', hex(lc($_))) } ($operand =~ /(..)/g);
      generate_bytes($ofh, $addr, \@bytes, $lineno, $line);
    } elsif ($ucmnemonic =~ /ASC|DCI|INV|FLS|BLK|REV|STR/) {
      # Unpack string dats.
      my ($str, $trl);
      if ($operand =~ /^\"(.+)\"([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      } elsif ($operand =~ /^'(.+)'([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      } elsif ($operand =~ /^\"(.+)\",([0-9a-fA-F]*)$/) {
        $str = $1;
        $trl = $2;
      } else {
        print_err(">>>> $lineno - Macro Bad Operand '$operand' in '$line'\n");
      }
      $str = '' unless defined $str;
      my @bytes  = map { pack('C', ord($_) | 0x80) } ($str =~ /(.)/g);
      if ($ucmnemonic eq 'REV') {
        @bytes = reverse @bytes;
      }
      if ($ucmnemonic eq 'STR') {
        # Add byte for size.
        generate_8($ofh, $addr, scalar(@bytes), $lineno, $line);
        $addr++;
      }
      ##FIXME -- need to implement bit setting for INV, FLS, etc.
      generate_bytes($ofh, $addr, \@bytes, $lineno, $line);
      if (defined $trl && $trl ne '') {
        my @trlbytes  = map { pack('C', hex(lc($_))) } ($trl =~ /(..)/g);
        generate_bytes($ofh, $addr, \@trlbytes, $lineno, '');
      }
    } elsif ($ucmnemonic =~ /DFB/i) {
      if ($operand =~ /^%([01]{8})/) {
        my $byte = unpack('C', pack("B8", $1));
        generate_8($ofh, $addr, $byte, $lineno, $line);
        $addr++;
      } elsif ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        generate_8($ofh, $addr, hex(lc($1)), $lineno, $line);
        $addr++;
      } elsif ($operand =~ /^#<(.+)/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          my $opval = $symval;
          if ($symval =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
            $opval = hex(lc($1));
          }
          generate_8($ofh, $addr, $opval, $lineno, $line);
        } else {
          print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
          generate_8($ofh, $addr, 0x00, $lineno, $line);
        }
        $addr++;
      } elsif ($operand =~ /^#>(.+)/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if (defined $symval) {
          my $opval = $symval;
          if ($symval =~ /\$[0-9a-fA-F]*([0-9a-fA-F][0-9a-fA-F])$/) {
            $opval = hex(lc($1));
          }
          generate_8($ofh, $addr, $opval, $lineno, $line);
        } else {
          print_err("**** $lineno - Unknown symbol '$1' in '$line'\n");
          generate_8($ofh, $addr, 0x00, $lineno, $line);
        }
        $addr++;
      } elsif ($operand =~ /^#(.+)/) {
        my @args = split /,/, $1;
        foreach my $arg (@args) {
          $arg =~ s/#//g;
          my $opval = sprintf("%04x", $arg);
          my $opval1 = hex(substr($opval, 0, 2));
          my $opval2 = hex(substr($opval, 2, 2));
          generate_16($ofh, $addr, $opval2, $opval1, $lineno, $line);
          $addr++;
        }
      # Allow symbol arithmetic.
      } elsif ($operand =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*([+-\\*\/])\s*[#]*(\$*[0-9a-fA-F]+)$/) {
        my $prt = $1;
        my $sym = $2;
        my $op = $3;
        my $val = $4;
        if ($val =~ /^\$([0-9a-fA-F]+)/) {
          $val = hex(lc($1));
        }
        my $symval = get_symval($prt, $sym);
        if (defined $symval) {
          if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])$/) {
            my $opval = hex(lc($1));
            if ($op eq '+') {
              $opval += $val;
            } elsif ($op eq '-') {
              $opval -= $val;
            }
            generate_8($ofh, $addr, $opval, $lineno, $line);
            $addr++;
          } elsif ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])/) {
            my $opval = hex(lc($1));
            if ($op eq '+') {
              $opval += $val;
            } elsif ($op eq '-') {
              $opval -= $val;
            }
            my $opv = sprintf("%04x", $opval);
            my $opval1 = hex(lc(substr($opv, 0, 2)));
            my $opval2 = hex(lc(substr($opv, 2, 2)));
            generate_16($ofh, $addr, $opval1, $opval2, $lineno, $line);
            $addr += 2;
          }
        } else {
          print_err("**** $lineno - Unknown symbol '$sym' in '$line'\n");
          generate_8($ofh, $addr, 0x00, $lineno, $line);
          $addr++;
        }
      # Allow symbols
      } elsif ($operand =~ /^[\<\>]*[0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]+,*/) {
        my @symbols = split(',', $operand);
        my @bytes;
        foreach my $sym (@symbols) {
          my $prt = '';
          my $symbol = $sym;
          if ($sym =~ /^([<>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]+)/) {
            $prt = $1;
            $symbol = $2;
          }
          my $symval = get_symval($prt, $symbol);
          if (defined $symval) {
            # Split into two bytes if necessary
            if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])/) {
              push @bytes, pack('C', hex(sprintf("%02x", hex(lc($1)))));
              push @bytes, pack('C', hex(sprintf("%02x", hex(lc($2)))));
            } else {
              push @bytes, pack('C', hex(sprintf("%02x", parse_symval($symval))));
            }
          } else {
            print_err("**** $lineno - Unknown symbol '$sym' in '$line'\n");
          }
        }
        generate_bytes($ofh, $addr, \@bytes, $lineno, $line);
      } else {
        print_err("$line - Bad byte definition '$operand'\n");
      }
    } elsif ($ucmnemonic =~ /^DS$/) {
      # Decimal
      my $strlen = 0;
      my $val = 0x00;
      if ($operand =~ /^(\d+)$/) {
        $strlen = $1;
      } elsif ($operand =~ /^(\d+),"(.)["]*/) {
        $strlen = $1;
        $val = ord($2);
      } elsif ($operand =~ /^(\d+),'(.)[']*/) {
        $strlen = $1;
        $val = ord($2);
      } elsif ($operand =~ /^(\d+),\$([0-9a-fA-F][0-9a-fA-F])/) {
        $strlen = $1;
        $val = hex(lc($2));
      # Hex
      } elsif ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        $strlen = 1;
        $val = hex(lc($1));
        ##FIXME -- probably need to add ," " support here, etc.
      }
      my @bytes;
      for (my $loopc = 0; $loopc < $strlen; $loopc++) {
        push @bytes, pack('C', $val);
      }
      generate_bytes($ofh, $addr, \@bytes, $lineno, $line);
    } elsif ($ucmnemonic =~ /^DB$|^TYP$/) {
        # GPH ADDED 201902016
        my $prt = '';
        if ($operand =~ /^([<>]*)/) {
          $prt = $1;
        }
        #END GPH
      if ($operand =~ /^%([01]{8})/) {
        my $opval = unpack('C', pack("B8", $1));
        generate_8($ofh, $addr, $opval, $lineno, $line);
        $addr++;
      } elsif ($operand =~ /^(\d+)/) {
        generate_8($ofh, $addr, $1, $lineno, $line);
        $addr++;
      } elsif ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
        my $opval = hex(lc($1));
        generate_8($ofh, $addr, $opval, $lineno, $line);
        $addr++;
        # GPH ADDED 20190216 support for db {symbol}
      } elsif ($operand =~ /^([\<\>]*)([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
        my $rawsym = $2;
        my $opval1 = '';
        my $opval2 = '';
        my $symval = $symbols{$rawsym};
        if ($prt =~ /^\>/) {       # LSB case
          $symval =~ s/^\$//;
          my $opval = sprintf("%04x", hex(lc($symval)));
          $opval1 = hex(lc(substr($opval, 0, 2)));
          generate_8($ofh, $addr, $opval1, $lineno, $line);
          $addr++;
        } else {
          $symval =~ s/^\$//;
          my $opval = sprintf("%04x", hex(lc($symval)));
          $opval1 = hex(lc(substr($opval, 2, 2)));
          generate_8($ofh, $addr, $opval1, $lineno, $line);
          $addr++;
        }
      }
      # END GPH
    } elsif ($ucmnemonic =~ /^DA$|^\.DA$|^DW$/) {
      # Handle binary.
      if ($operand =~ /^%([01]{16})/) {
        my $opval1 = unpack('C', pack("B8", substr($1, 0, 8)));
        my $opval2 = unpack('C', pack("B8", substr($1, 8, 8)));
        generate_16($ofh, $addr, $opval2, $opval1, $lineno, $line);
        $addr += 2;
      # Handle decimal.
      } elsif ($operand =~ /^(\d+)$/) {
        my $opval = sprintf("%04x", $1);
        my $opval1 = hex(lc(substr($opval, 0, 2)));
        my $opval2 = hex(lc(substr($opval, 2, 2)));
        generate_16($ofh, $addr, $opval2, $opval1, $lineno, $line);
        $addr += 2;
      # Handle address arithmetic.
      } elsif ($operand =~ /^\$([0-9a-fA-F]+)\s*([+-\\*\/])\s*(\$*.+)$/) {
        my $opval = hex(lc($1));
        my $op = $2;
        my $val = $3;
        if ($val =~ /^\$([0-9a-fA-F]+)/) {
          $val = hex(lc($1));
        }
        if ($op eq '+') {
          $opval += $val;
        } elsif ($op eq '-') {
          $opval -= $val;
        }
        my $opv = sprintf("%04x", $opval);
        my $opval1 = hex(lc(substr($opv, 0, 2)));
        my $opval2 = hex(lc(substr($opv, 2, 2)));
        generate_16($ofh, $addr, $opval2, $opval1, $lineno, $line);
        $addr += 2;
      # Handle hex.
      } elsif ($operand =~ /^\$([0-9a-fA-F]+)([0-9a-fA-F][0-9a-fA-F])$/) {
        my $opval1 = hex(lc($1));
        my $opval2 = hex(lc($2));
        generate_16($ofh, $addr, $opval2, $opval1, $lineno, $line);
        $addr += 2;
      } elsif ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])$/) {
        my $opval = hex(lc($1));
        generate_16($ofh, $addr, $opval, 0x00, $lineno, $line);
      # GPH ADDED 20190216 symbol support
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
        my $rawsym = $1;
        my $opval1 = '';
        my $opval2 = '';
        my $symval = $symbols{$rawsym};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        $symval =~ s/^\$//;
        my $opval = sprintf("%04x", hex(lc($symval)));
        $opval1 = hex(lc(substr($opval, 0, 2)));
        $opval2 = hex(lc(substr($opval, 2, 2)));
        generate_16($ofh, $addr, $opval2, $opval1, $lineno, $line);
        $addr += 2;
      }
      #END GPH
    } elsif ($ucmnemonic =~ /HBY/) {
      ##FIXME -- implement this
      print "NOT YET IMPLEMENTED!\n";
    } elsif ($ucmnemonic =~ /^BYT$/) {
      ##FIXME -- implement this
      print "NOT YET IMPLEMENTED!\n";
    } elsif ($ucmnemonic =~ /DFS/) {
      ##FIXME -- implement this
      print "NOT YET IMPLEMENTED!\n";
    } elsif ($ucmnemonic =~ /BYTE/) {
      my @args = split /,/, $operand;
      my @bytes = ();
      foreach my $opval (@args) {
        # Binary
        if ($opval =~ /^%([01]{8})/) {
          push @bytes, unpack('C', pack("B8", $1));
          $addr++;
        # Decimal
        } elsif ($opval =~ /^\d+$/) {
          push @bytes, $opval;
          $addr++;
        # Hex
        } elsif ($opval =~ /^\$([0-9a-fA-F]+)$/) {
          my $ov = sprintf("%02x", hex(lc($1)));
          push @bytes, hex(lc($ov));
          $addr++;
        ##FIXME -- probably should handle symbols here too.
        }
      }
      generate_bytes($ofh, $addr, \@bytes, $lineno, $line);
    } elsif ($ucmnemonic =~ /WORD/) {
      my @args = split /,/, $operand;
      my @bytes = ();
      foreach my $opval (@args) {
        # Binary
        if ($opval =~ /^%([01]{16})/) {
          my $ov1 = unpack('C', pack("B8", substr($1, 0, 8)));
          my $ov2 = unpack('C', pack("B8", substr($1, 8, 8)));
          push @bytes, $ov1;
          push @bytes, $ov2;
          $addr += 2;
        # Decimal
        } elsif ($opval =~ /^(\d+)$/) {
          my $ov = sprintf("%04x", $1);
          my $ov1 = hex(lc(substr($ov, 0, 2)));
          my $ov2 = hex(lc(substr($ov, 2, 2)));
          push @bytes, $ov1;
          push @bytes, $ov2;
          $addr += 2;
        # Hex
        } elsif ($opval =~ /^\$([0-9a-fA-F]+)$/) {
          my $ov = sprintf("%04x", hex(lc($1)));
          my $ov1 = hex(lc(substr($ov, 0, 2)));
          my $ov2 = hex(lc(substr($ov, 2, 2)));
          push @bytes, $ov1;
          push @bytes, $ov2;
        # Symbol
        } elsif ($opval =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
          my $rawsym = $1;
          my $ov1 = '';
          my $ov2 = '';
          my $symval = $symbols{$rawsym};
          $symval = $symbols{$1 . ':'} unless defined $symval;
          $symval = $symbols{':' . $1} unless defined $symval;
          $symval =~ s/^\$//;
          my $ov = sprintf("%04x", hex(lc($symval)));
          $ov1 = hex(lc(substr($ov, 0, 2)));
          $ov2 = hex(lc(substr($ov, 2, 2)));
          push @bytes, $ov1;
          push @bytes, $ov2;
        }
      }
      generate_bytes($ofh, $addr, \@bytes, $lineno, $line);
    } elsif ($ucmnemonic =~ /MAC/) {
      # Ignore on subsequent passes.
    } elsif ($ucmnemonic =~ /\<\<\</) {
      # Ignore on subsequent passes.
    # Conditional assembly
    } elsif ($ucmnemonic =~ /^DO$/) {
print ">>>>  DO  $operand\n";
      $in_conditional = 1;
    } elsif ($ucmnemonic =~ /^FIN$/) {
print ">>>>  END CONDITIONAL\n";
      $in_conditional = 0;
    } elsif ($ucmnemonic eq 'CHK') {
      generate_8($ofh, $addr, $checksum, $lineno, $line);
    } elsif (defined $macros{$ucmnemonic}) {
      #print "#### MACRO $ucmnemonic ####\n" if $debug;
      print sprintf("                 %-4d  %s\n", $lineno, $line) if $code_listing;

      my $opval1 = '';
      my $opval2 = '';

      # Parse hex
      if ($operand =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9A-Fa-f][0-9A-Fa-f])$/) {
        $opval1 = hex(lc($1));
        $opval2 = hex(lc($2));
      # Parse binary
      } elsif ($operand =~ /^%([01]{8})([0-1]{8})$/) {
        $opval1 = unpack('C', pack("B8", $1));
        $opval2 = unpack('C', pack("B8", $2));
      # Parse decimal
      } elsif ($operand =~ /^(\d+)$/) {
        my $opval = sprintf("%04x", $1);
        $opval1 = hex(lc(substr($opval, 0, 2)));
        $opval2 = hex(lc(substr($opval, 2, 2)));
      # Return symbol value
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)$/) {
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if ($symval =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
          $opval1 = hex(lc($1));
          $opval2 = hex(lc($2));
        } elsif ($symval =~ /^\$([0-9a-fA-F][0-9a-fA-F])$/) {
          $opval1 = hex(lc($1));
          $opval2 = 0x00;
        } else {
          $symval =~ s/^\$//;
          my $opval = sprintf("%04x", $symval);
          $opval1 = hex(lc(substr($opval, 0, 2)));
          $opval2 = hex(lc(substr($opval, 2, 2)));
        }
      # Allow arithmetic on symbol
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[+]\s*[#]*(\$*[0-9a-fA-F]+)$/) {
        # Add
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if ($symval =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
          $opval1 = hex(lc($1));
          $opval2 = hex(lc($2));
        } elsif ($symval =~ /^\$([0-9a-fA-F][0-9a-fA-F])$/) {
          $opval1 = hex(lc($1));
          $opval2 = 0x00;
        } else {
          $symval =~ s/^\$//;
          my $opval = sprintf("%04x", $symval);
          $opval1 = hex(lc(substr($opval, 0, 2)));
          $opval2 = hex(lc(substr($opval, 2, 2)));
        }
        ##FIXME -- need to do add here
      } elsif ($operand =~ /^([0-9A-Za-z\.\?:][A-Za-z0-9_\.\?:]*)\s*[-]\s*[#]*(\$*[0-9a-fA-F]+)$/) {
        # Subtract
        my $symval = $symbols{$1};
        $symval = $symbols{$1 . ':'} unless defined $symval;
        $symval = $symbols{':' . $1} unless defined $symval;
        if ($symval =~ /^\$([0-9a-fA-F]{0,1}[0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])$/) {
          $opval1 = hex(lc($1));
          $opval2 = hex(lc($2));
        } elsif ($symval =~ /^\$([0-9a-fA-F][0-9a-fA-F])$/) {
          $opval1 = hex(lc($1));
          $opval2 = 0x00;
        } else {
          $symval =~ s/^\$//;
          my $opval = sprintf("%04x", $symval);
          $opval1 = hex(lc(substr($opval, 0, 2)));
          $opval2 = hex(lc(substr($opval, 2, 2)));
        }
        ##FIXME -- need to do sub here
      #} else {
      #  print_err(">>>> $lineno - Macro Bad Operand '$operand' in '$line'\n");
      }

      my $maclnno = 0;
      foreach my $macln (@{$macros{$ucmnemonic}}) {
        $maclnno++;
        my ($maclabel, $macmnemonic, $macoperand, $maccomment) = parse_line($macln, $maclnno);
        #print sprintf("                 %-4d  %s\n", $maclnno, $macln) if $code_listing;
        my $ucmacmnemonic = uc($macmnemonic);
        if (defined $mnemonics{$ucmacmnemonic}) {
          my $foundit = 0;
          foreach my $opmode (keys %{$mnemonics{$ucmacmnemonic}}) {
            my $checkfunc = $modefuncs{$opmode}{'check'};
            my $genfunc = $modefuncs{$opmode}{'gen'};
            if ($checkfunc->($macoperand, $maclnno)) {
              $genfunc->($addr, $macoperand, $mnemonics{$ucmacmnemonic}{$opmode}, $ofh, $maclnno, $macln, $opval1, $opval2);
              $foundit = 1;
              last;
            }
          }
          if (! $foundit) {
            print_err("!!!! $maclnno - Unrecognized addressing mode '$macln'!\n");
          }
        } else {
          print_err("$maclnno - Unknown mnemonic '$mnemonic' in macro '$macln'\n");
        }
      }
    } else {
      print_err("$lineno - Unknown mnemonic '$mnemonic' in '$line'\n");
    }
  }

  close $ofh;

  close $ifh;

  # Output error summary.
  if ($error_summary) {
    print "\n";
    if (scalar @errors) {
      print "**** Summary of errors:\n";
      print "\n";
      foreach my $line (@errors) {
        print $line;
      }
      print "\n";
    } else {
      print "**** No errors. ****\n";
    }
  }
} else {
  die "Can't open $input_file\n";
}

1;

