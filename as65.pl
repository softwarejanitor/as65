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
my $listing1 = 0;  # Listing for pass 1.
my $listing2 = 0;  # Listing for pass 2.
my $code_listing = 1;  # Generated code listing.
my $symbol_table = 1;  # Output symbol table.

my %symbols = ();  # Hash of symbol table values.

my $base = 0x800;  # Default base address.  Overide with -a (decimal) or -x (hex) from command line or .org or ORG directives in code.

my $output_file = '';  # Output file, required to be set with -o command line flag.

sub usage {
  print "Usage:\n";
  print "$0 [-a addr] [-x \$addr] [-v] [-q] [-d] [-s] [-l] [-l1] [-l2] [-c] [-h] <input_file>\n";
  print " -a addr : Start address in decimal (default 2048)\n";
  print " -x \$addr : Start address in hex (default $800)\n";
  print " -o <output file> : Output file name (required).\n";
  print " -v : Verbose (default on)\n";
  print " -q : Quiet (default off)\n";
  print " -d : Debug (default off)\n";
  print " -s : Symbol Table\n";
  print " -l : Listing (both passes) (default off)\n";
  print " -l1 : Listing (Pass 1) (default off)\n";
  print " -l2 : Listing (Pass 2) (default off)\n";
  print " -c : Generated code listing (default on)\n";
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
  # Listing (both passes).
  } elsif ($ARGV[0] eq '-l') {
    $listing1 = 1;
    $listing2 = 1;
    shift;
  # Pass 1 listing.
  } elsif ($ARGV[0] eq '-l1') {
    $listing1 = 1;
    shift;
  # Pass 2 listing.
  } elsif ($ARGV[0] eq '-l2') {
    $listing2 = 1;
    shift;
  # Code listing.
  } elsif ($ARGV[0] eq '-c') {
    $code_listing = 0;
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
  'BCS' => {
    # BCS	Relative	BCS Oper	B0	2	2
    'Relative' => 0xb0,
  },
  'BEQ' => {
    # BEQ	Relative	BEQ Oper	F0	2	2
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
    'Relative' => 0x0f,
  },
  'BNE' => {
    # BNE	Relative	BNE Oper	D0	2	2
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
    'Absolute_X' => 0xd0,
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
    # 		Zero Page,Y	LDY Zpg,X	B4	2	4
    'Zero_Page_Y' => 0xb4,
    # 		Absolute	LDY Abs		AC	3	4
    'Absolute' => 0xac,
    # 		Absolute,Y	LDY Abs,X	BC	3	4
    'Absolute_Y' => 0xbc,
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

# Generate code for one byte instructions.
sub generate_8 {
  my ($ofh, $addr, $opcode, $opval) = @_;

  print sprintf(">>>> GENERATING %04x  %02x\n", $addr, $opcode) if $code_listing;
  print $ofh pack("C", $opcode);
}

# Generate code for two byte instructions.
sub generate_16 {
  my ($ofh, $addr, $opcode, $opval) = @_;

  print sprintf(">>>> GENERATING %04x  %02x %02x\n", $addr, $opcode, $opval) if $code_listing;
  print $ofh pack("C", $opcode);
  print $ofh pack("C", $opval);
}

# Generate code for three byte instructions.
sub generate_24 {
  my ($ofh, $addr, $opcode, $opval1, $opval2) = @_;

  print sprintf(">>>> GENERATING %04x  %02x %02x %02x\n", $addr, $opcode, $opval1, $opval2) if $code_listing;
  print $ofh pack("C", $opcode);
  print $ofh pack("C", $opval1);
  print $ofh pack("C", $opval2);
}

sub sym_add {
  my ($symval, $offset) = @_;

  if ($symval =~ /\$([0-9a-fA-F]+)/) {
    return hex(lc($1)) + $offset;
  }
  return $symval + $offset;
}

sub sym_sub {
  my ($symval, $offset) = @_;

  if ($symval =~ /\$([0-9a-fA-F]+])/) {
    return hex(lc($1)) + $offset;
  }
  return $symval - $offset;
}

sub handle_8_bit_symbol {
  my ($ofh, $lineno, $addr, $opcode, $symbol) = @_;

  my $symval = $symbols{$symbol};
  if (defined $symval) {
    my $opval = $symval;
    if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])/) {
      $opval = hex(lc($1));
    }
    generate_16($ofh, $addr, $opcode, $opval);
  } else {
    print "**** $lineno - Unknown symbol '$symbol'\n";
    generate_16($ofh, $addr, $opcode, 0x00);
  }
}

sub handle_8_bit_symbol_add {
  my ($ofh, $lineno, $addr, $opcode, $symbol, $val) = @_;

  my $symval = $symbols{$symbol};
  if (defined $symval) {
    my $opval = sym_add($symval, $val);
    generate_16($ofh, $addr, $opcode, $opval);
  } else {
    print "**** $lineno - Unknown symbol '$symbol'\n";
    generate_16($ofh, $addr, $opcode, 0x00);
  }
}

sub handle_8_bit_symbol_sub {
  my ($ofh, $lineno, $addr, $opcode, $symbol, $val) = @_;

  my $symval = $symbols{$symbol};
  if (defined $symval) {
    my $opval = sym_sub($symval, $val);
    generate_16($ofh, $addr, $opcode, $opval);
  } else {
    print "**** $lineno - Unknown symbol '$symbol'\n";
    generate_16($ofh, $addr, $opcode, 0x00);
  }
}

sub handle_16_bit_symbol {
  my ($ofh, $lineno, $addr, $opcode, $symbol) = @_;

  my $symval = $symbols{$symbol};
  if (defined $symval) {
    my $opval1 = 0;
    my $opval2 = 0;
    if ($symval =~ /\$([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])/) {
      $opval1 = hex(lc($1));
      $opval2 = hex(lc($2));
    } else {
      my $opval = sprintf("%04x", $symval);
      $opval1 = hex(substr($opval, 0, 2));
      $opval2 = hex(substr($opval, 2, 2));
    }
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  } else {
    print "**** $lineno - Unknown symbol '$symbol'\n";
    generate_24($ofh, $addr, $opcode, 0x00, 0x00);
  }
}

sub handle_16_bit_symbol_add {
  my ($ofh, $lineno, $addr, $opcode, $symbol, $val) = @_;

  my $symval = $symbols{$symbol};
  if (defined $symval) {
    my $opval = sym_add($symval, $val);
    my $opv = sprintf("%04x", $opval);
    my $opval1 = hex(substr($opv, 0, 2));
    my $opval2 = hex(substr($opv, 2, 2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  } else {
    print "**** $lineno - Unknown symbol '$symbol'\n";
    generate_24($ofh, $addr, $opcode, 0x00, 0x00);
  }
}

sub handle_16_bit_symbol_sub {
  my ($ofh, $lineno, $addr, $opcode, $symbol, $val) = @_;

  my $symval = $symbols{$symbol};
  if (defined $symval) {
    my $opval = sym_sub($symval, $val);
    my $opv = sprintf("%04x", $opval);
    my $opval1 = hex(substr($opv, 0, 2));
    my $opval2 = hex(substr($opv, 2, 2));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  } else {
    print "**** $lineno - Unknown symbol '$symbol'\n";
    generate_24($ofh, $addr, $opcode, 0x00, 0x00);
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
  if ($operand =~ /^#\$[0-9a-fA-f][0-9a-fA-F]$/) {
    return 2;
  } elsif ($operand =~ /^#(\d)+$/) {
    return 0 if ($1 > 255);
    return 2;
  # Handle symbols.
  } elsif ($operand =~ /^#([A-Za-z\.][A-Za-z0-9_\.]+)$/) {
    # Not Immediate if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^#([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*(\d+)$/) {
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  }

  return 0;
}

sub generate_Immediate {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^#\$([0-9a-fA-F][0-9a-fA-F])$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^#(\d+)$/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^#([A-Za-z\.][A-Za-z0-9_\.]+)/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^#([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)$/) {
    # Add
    handle_8_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^#([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)$/) {
    # Subtract
    handle_8_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Immediate Bad Operand : '$operand'\n";
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
  if ($operand =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/) {
    return 2;
  } elsif ($operand =~ /^(\d+)$/) {
    return 0 if $1 > 255;
    return 2;
  # Handle symbols
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)$/) {
    # Not Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  # Allow symbol arithmetic
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*\d+$/) {
    # Not Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  }

  return 0;
}

sub generate_Zero_Page {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F])/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^(\d+)$/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)$/) {
    # Add
    handle_8_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)$/) {
    # Subtract
    handle_8_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Zero_Page Bad Operand : '$operand'\n";
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
  if ($operand =~ /^\$[0-9a-fA-F][0-9a-fA-F],[Xx]$/) {
    return 2;
  } elsif ($operand =~ /^(\d+),[Xx]$/) {
    return 0 if $1 > 255;
    return 2;
  # Handle symbols
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Xx]$/) {
    # Not Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*\d+,[Xx]$/) {
    # Not Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  }

  return 0;
}

sub generate_Zero_Page_X {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F]),[Xx]$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Xx]$/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Xx]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Handle symbol arithmetic
  } elsif ($operand =~ /^([A-Za-z\.][0-9a-zA-Z_\.]+)\s*[+]\s*(\d+),[Xx]$/) {
    # Add
    handle_8_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^([A-Za-z\.][0-9a-zA-Z_\.]+)\s*[-]\s*(\d+),[Xx]$/) {
    # Subtract
    handle_8_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Zero_Page_X Bad Operand : '$operand'\n";
  }
  $_[0] += 2;
}

# LDX Zpg,Y	B6
# STX Zpg,Y	96
sub is_Zero_Page_Y {
  my ($operand, $lineno) = @_;
  if ($operand =~ /^\$[0-9a-fA-F][0-9a-fA-F],[Yy]$/) {
    return 2;
  } elsif ($operand =~ /^(\d+),[Yy]$/) {
    return 0 if $1 > 255;
    return 2;
  # Handle symbols
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Yy]$/) {
    # Not Zero Page,Y if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*\d+,[Yy]$/) {
    # Not Zero Page,Y if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  }

  return 0;
}

sub generate_Zero_Page_Y {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F]),[Yy]$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Yy]$/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Yy]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+),[Yy]$/) {
    # Add
    handle_8_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+),[Yy]$/) {
    # Subtract
    handle_8_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Zero_Page_Y Bad Operand : '$operand'\n";
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
  if ($operand =~ /^\$[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/) {
    return 2;
  } elsif ($operand =~ /^\d+$/) {
    return 2;
  # handle symbols
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)$/) {
    # Not Ansolute if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
    }
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*\d+$/) {
    # Not Ansolute if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
    }
    return 2;
  }

  return 0;
}

sub generate_Absolute {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F][0-9A-Fa-f][0-9A-Fa-f]$)/) {
    my $opval1 = hex(lc(substr($1, 0, 2)));
    my $opval2 = hex(lc(substr($1, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Parse decimal
  } elsif ($operand =~ /^(\d+)$/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Return symbol value
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $operand);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)$/) {
    # Add
    handle_16_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)$/) {
    # Subtract
    handle_16_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Absolute Bad Operand '$operand'\n";
  }
  $_[0] += 3;
}

# JMP (Abs)	6C
sub is_Indirect_Absolute {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]+)\)$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)$/) {
    return 2;
  # Handle symbol
  } elsif ($operand =~ /^\([A-Za-z\.][A-Za-z0-9_\.]+\)$/) {
    return 2;
  # Allow symbol arithmetic
  } elsif ($operand =~ /^\([A-Za-z\.][A-Za-z0-9_\.]+\s*[+-]\s*\d+\)/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Absolute {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F][0-9a-fA-F][0-9A-Fa-f][0-9A-Fa-f])\)/) {
    my $opval1 = hex(lc(substr($1, 0, 2)));
    my $opval2 = hex(lc(substr($1, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Return symbol value
  } elsif ($operand =~ /^\(([A-Za-z\.][0-9a-zA-Z]+)\)/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)\)/) {
    # Add
    handle_16_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)\)/) {
    # Subtract
    handle_16_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Indirect_Absolute Bad Operand '$operand'\n";
  }
  $_[0] += 3;
}

# JMP (Abs,X)	7C
sub is_Indirect_Absolute_X {
  my ($operand, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F]+),[Xx]\)$/) {
    return 2;
  # Parse decimal
  } elsif ($operand =~ /^\((\d+),[Xx]\)$/) {
    return 2;
  # Handle symbol
  } elsif ($operand =~ /^\([A-Za-z\.][A-Za-z0-9_\.]+,[Xx]\)$/) {
    return 2;
  # Allow symbol arithmetic
  } elsif ($operand =~ /^\(\S+\s*[+-]\s*\d+,[Xx]\)/) {
    return 2;
  }

  return 0;
}

sub generate_Indirect_Absolute_X {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F][0-9a-fA-F][0-9A-Fa-f][0-9A-Fa-f])\),[Xx]/) {
    my $opval1 = hex(lc(substr($1, 0, 2)));
    my $opval2 = hex(lc(substr($1, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\),[Xx]/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Return symbol value
  } elsif ($operand =~ /^\(([A-Za-z\.][0-9a-zA-Z_]+)\),[Xx]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)\),[Xx]$/) {
    # Add
    handle_16_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)\),[Xx]$/) {
    # Subtract
    handle_16_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Indirect_Absolute_X Bad Operand '$operand'\n";
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
  if ($operand =~ /^\$[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F],[Xx]$/) {
    return 2;
  } elsif ($operand =~ /^(\d{1,3}),[Xx]$/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Xx]$/) {
    # Not Ansolute,X if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
    }
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*(\d+),[Xx]$/) {
    # Not Ansolute,X if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
    }
    return 2;
  }

  return 0;
}

sub generate_Absolute_X {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F][0-9A-Fa-f][0-9A-Fa-f]),[Xx]/) {
    my $opval1 = hex(lc(substr($1, 0, 2)));
    my $opval2 = hex(lc(substr($1, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Xx]/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Return symbol value
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Xx]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+),[Xx]$/) {
    # Add
    handle_16_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+),[Xx]$/) {
    # Subtract
    handle_16_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Indirect_Absolute_X Bad Operand '$operand'\n";
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
  if ($operand =~ /^\$[0-9a-fA-F]{4},[Yy]$/) {
    return 2;
  } elsif ($operand =~ /^\d+,[Yy]$/) {
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Yy]$/) {
    # Not Ansolute,Y if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
    }
    return 2;
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*(\d+),[Yy]/) {
    # Not Ansolute,Y if the symbol is not 16 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      return 0 if $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
    }
    return 2;
  }

  return 0;
}

sub generate_Absolute_Y {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\$([0-9a-fA-F][0-9a-fA-F][0-9A-Fa-f][0-9A-Fa-f]),[Yy]/) {
    my $opval1 = hex(lc(substr($1, 0, 2)));
    my $opval2 = hex(lc(substr($1, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Parse decimal
  } elsif ($operand =~ /^(\d+),[Yy]/) {
    my $opval = sprintf("%04x", $1);
    my $opval1 = hex(lc(substr($opval, 0, 2)));
    my $opval2 = hex(lc(substr($opval, 2, 2)));
    generate_24($ofh, $addr, $opcode, $opval2, $opval1);
  # Return symbol value
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+),[Yy]$/) {
    handle_16_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+),[Yy]$/) {
    # Add
    handle_16_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+),[Yy]$/) {
    # Subtract
    handle_16_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Absolute_Y Bad Operand '$operand'\n";
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
  if ($operand =~ /^\(\$[0-9a-fA-F][0-9a-fA-F],[Xx]\)$/) {
    return 2;
  } elsif ($operand =~ /^\((\d+),[Xx]\)$/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+),[Xx]\)$/) {
    # Not Indirect Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*(\d+),[Xx]\)/) {
    # Not Indirect Zero Page,X if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  }

  return 0;
}

sub generate_Indirect_Zero_Page_X {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-f][0-9a-fA-f]),[Xx]\)$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\),[Xx]/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+),[Xx]\)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+),[Xx]\)$/) {
    # Add
    handle_8_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+),[Xx]\)$/) {
    # Subtract
    handle_8_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Indirect_Zero_Page_X Bad Operand : '$operand'\n";
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
  if ($operand =~ /^\(\$([0-9a-fA-F][0-9a-fA-F])\),[Yy]$/) {
    return 2;
  } elsif ($operand =~ /^\((\d+)\),[Yy]/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\),[Yy]$/) {
    # Not Indirect Zero Page,Y if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*(\d+)\),[Yy]/) {
    # Not Indirect Zero Page,Y if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
      return 0;
    }
    return 2;
  }

  return 0;
}

sub generate_Indirect_Zero_Page_Y {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F][0-9a-fA-F])\),[Yy]$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\),[Yy]$/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\),[Yy]$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)\),[Yy]$/) {
    # Add
    handle_8_bit_symbol_add($ofh, $lineno, $addr, $opcode, $1, $2);
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)\),[Yy]$/) {
    # Subtract
    handle_8_bit_symbol_sub($ofh, $lineno, $addr, $opcode, $1, $2);
  } else {
    print ">>>> $lineno - Indirect_Zero_Page_Y Bad Operand : '$operand'\n";
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
  if ($operand =~ /^\(\$[0-9a-fA-F][0-9a-fA-F]\)$/) {
    return 2;
  } elsif ($operand =~ /^\((\d+)\)$/) {
    return 0 if $1 > 255;
    return 2;
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\)$/) {
    # Not Indirect Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    }
    return 2;
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+-]\s*(\d+)\)$/) {
    # Not Indirect Zero Page if the symbol is not 8 bits.
    my $symval = $symbols{$1};
    if (defined $symval) {
      if ($symval =~ /^\d+$/) {
        return 0 if ($symval > 255);
      } else {
        return 0 unless $symval =~ /^\$[0-9a-fA-F][0-9a-fA-F]$/;
      }
    }
    return 2;
  }

  return 0;
}

sub generate_Indirect_Zero_Page {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;
  # Parse hex
  if ($operand =~ /^\(\$([0-9a-fA-F][0-9a-fA-F])\)$/) {
    my $opval = hex(lc($1));
    generate_16($ofh, $addr, $opcode, $opval);
  # Parse decimal
  } elsif ($operand =~ /^\((\d+)\)/) {
    generate_16($ofh, $addr, $opcode, $1);
  # Return symbol value
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\)$/) {
    handle_8_bit_symbol($ofh, $lineno, $addr, $opcode, $1);
  # Allow arithmetic on symbol
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[+]\s*(\d+)\)$/) {
    # Add
    my $symval = $symbols{$1};
    if (defined $symval) {
      my $opval = sym_add($symval, $2);
      generate_16($ofh, $addr, $opcode, $opval);
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
    }
  } elsif ($operand =~ /^\(([A-Za-z\.][A-Za-z0-9_\.]+)\s*[-]\s*(\d+)\)$/) {
    # Subtract
    my $symval = $symbols{$1};
    if (defined $symval) {
      my $opval = sym_sub($symval, $2);
      generate_16($ofh, $addr, $opcode, $opval);
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
    }
  } else {
    print ">>>> $lineno - Indirect_Zero_Page Bad Operand '$operand'\n";
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
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;

  # Decode hex
  if ($operand =~ /^\$([0-9a-fA-F]{1,4}$)/) {
    my $opval = hex(lc($1));
    my $rel = (0 - ($addr - $opval)) + 254;
    if ($rel < 0) {
      $rel += 256;
    }
    if ($rel > 255) {
      $rel -= 256;
    }
    generate_16($ofh, $addr, $opcode, $rel);
  # Decode decimal
  } elsif ($operand =~ /^(\d+)$/) {
    my $rel = (0 - ($addr - $1)) + 254;
    if ($rel < 0) {
      $rel += 256;
    }
    if ($rel > 255) {
      $rel -= 256;
    }
    generate_16($ofh, $addr, $opcode, $rel);
  # Handle symbols
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)$/) {
    my $symval = $symbols{$1};
    if (defined $symval) {
      my $opval = lc($symval);
      if ($symval =~ /^\$([0-9a-fA-F]{1,4})/) {
        $opval = hex($1);
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
      generate_16($ofh, $addr, $opcode, $rel);
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
    }
  # Handle symbol arithmetic
  } elsif ($operand =~ /^([A-Za-z\.][A-Za-z0-9_\.]+)\s*([+-])\s*(\d+)$/) {
    my $symval = $symbols{$1};
    if (defined $symval) {
      my $opval = lc($symval);
      if ($symval =~ /^\$([0-9a-fA-F]{1,4})/) {
        $opval = hex($1);
      } else {
        $opval = $symval;
      }

      if ($2 eq '+') {
        $opval += $3;
      } elsif ($2 eq '-') {
        $opval -= $3;
      }

      my $rel = (0 - ($addr - $opval)) + 254;
      if ($rel < 0) {
        $rel += 256;
      }
      if ($rel > 255) {
        $rel -= 256;
      }
      generate_16($ofh, $addr, $opcode, $rel);
    } else {
      print "**** $lineno - Unknown symbol '$1'\n";
    }
  } else {
    print ">>>> $lineno - Relative Bad Operand '$operand'\n";
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
# PHX		DA
# PHY		5A
# PLA		68
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
  }

  return 0;
}

sub generate_Implied {
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;

  generate_8($ofh, $addr, $opcode);

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
  my ($addr, $operand, $opcode, $ofh, $lineno) = @_;

  generate_8($ofh, $addr, $opcode);

  $_[0]++;
}

sub parse_line {
  my ($line, $lineno) = @_;

  my ($label, $mnemonic, $operand, $comment) = ('', '', '', '');
  if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(;.+)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = $4;
  } elsif ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s*$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = $3;
    $comment = '';
  } elsif ($line =~ /^\s+(\S+)\s+(\S+)\s+(;.+)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = $3;
  } elsif ($line =~ /^\s+(\S+)\s+(\S+)\s*$/) {
    $label = '';
    $mnemonic = $1;
    $operand = $2;
    $comment = '';
  } elsif ($line =~ /^\s+(\S+)\s+;\s*$/) {
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
  } elsif ($line =~ /^(\S+)\s+(\S+)$/) {
    $label = $1;
    $mnemonic = $2;
    $operand = '';
    $comment = '';
  } elsif ($line =~ /^\s+(\S+)\s+(;.+)$/) {
    $label = '';
    $mnemonic = $1;
    $operand = '';
    $comment = $2;
  } else {
    print "SYNTAX ERROR!  $lineno : $line\n";
  }

  $label = '' unless defined $label;
  $comment = '' unless defined $comment;
  $mnemonic = '' unless defined $mnemonic;
  $operand = '' unless defined $operand;

  return ($label, $mnemonic, $operand, $comment);
}

my $addr = $base;

my $ifh;

my $lineno = 0;

# Open the input file.
if (open($ifh, "<$input_file")) {

  print "**** Starting 1st pass ****\n" if $verbose;

  print "\n" if $verbose;

  # Pass 1, build symbol table.
  while (my $line = readline $ifh) {
    chomp $line;

    $lineno++;

    print sprintf("%4d %5d \$%04x |  %s\n", $lineno, $addr, $addr, $line) if $listing1;

    # Skip blank lines.
    next if $line =~ /^\s*$/;

    # Skip comment lines.
    next if $line =~ /^\s*;/;
    next if $line =~ /\*/;

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
    if (defined $label && $label ne '' && $label ne ';' && $mnemonic !~ /EQU|\.EQ/i) {
      my $symbol = $label;
      $symbol =~ s/:$//;
      print sprintf("%%%%%%%% Saving symbol $label %s \$%04x\n", $addr, $addr) if $verbose;
      $symbols{$symbol} = sprintf("\$%04x", $addr);
    }

    next unless defined $mnemonic;
    next if $mnemonic eq '';

    my $ucmnemonic = uc($mnemonic);

    # We only need to look for ORG and EQU on pass 1.
    if ($ucmnemonic eq 'ORG') {
      # Set base
      $operand =~ s/^\$//;
      $base = hex(lc($operand));
      $addr = $base;
      print "%%%% Setting base to $base\n" if $verbose;
    } elsif ($ucmnemonic =~ /EQU|\.EQ/i) {
      # define constant
      my $symbol = $label;
      $symbol =~ s/:$//;
      print "%%%% Saving Symbol $symbol $operand\n" if $verbose;
      $symbols{$symbol} = $operand;
    # Mnemonic	Addressing mode	Form		Opcode	Size	Timing
    } elsif (defined $mnemonics{$ucmnemonic}) {
      my $foundit = 0;
      foreach my $opmode (keys $mnemonics{$ucmnemonic}) {
        my $checkfunc = $modefuncs{$opmode}{'check'};
        if ($checkfunc->($operand, $lineno)) {
          $addr += $modefuncs{$opmode}{'size'};
          $foundit = 1;
          last;
        }
      }
      if (! $foundit) {
        print "!!!! Unrecognized operating mode $line!\n";
      }
    } else {
      print "SYNTAX ERROR 1! $mnemonic\n";
    }
  }

  print "\n" if $verbose;

  if ($symbol_table) {
    print "---- Symbol table ----\n";

    foreach my $ky (keys %symbols) {
      print "$ky :  $symbols{$ky}\n";
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

  # Pass two, generate output
  open($ofh, ">$output_file") or die "Can't write $output_file\n";

  binmode $ofh;

  while (my $line = readline $ifh) {
    chomp $line;

    $lineno++;

    print sprintf("%4d %5d \$%04x |  %s\n", $lineno, $addr, $addr, $line) if $listing1;

    # Skip blank lines.
    next if $line =~ /^\s*$/;

    # Skip comment lines.
    next if $line =~ /^\s*;/;
    next if $line =~ /\*/;

    # Skip .org lines.
    next if $line =~ /^\.org\s+.+/;
    # Skip .alias lines.
    next if $line =~ /^\.alias\s+\S+\s+.+/;

    # Parse input lines.
    my ($label, $mnemonic, $operand, $comment) = parse_line($line, $lineno);

    next unless defined $mnemonic;
    next if $mnemonic eq '';

    my $ucmnemonic = uc($mnemonic);

    # Skip ORG and EQU on pass 2.
    next if $ucmnemonic eq 'ORG';
    next if $ucmnemonic eq 'EQU';

    if (defined $mnemonics{$ucmnemonic}) {
      my $foundit = 0;
      foreach my $opmode (keys $mnemonics{$ucmnemonic}) {
        my $checkfunc = $modefuncs{$opmode}{'check'};
        my $genfunc = $modefuncs{$opmode}{'gen'};
        if ($checkfunc->($operand, $lineno)) {
            $genfunc->($addr, $operand, $mnemonics{$ucmnemonic}{$opmode}, $ofh, $lineno);
            $foundit = 1;
            last;
        }
      }
      if (! $foundit) {
        print "!!!! Unrecognized operating mode $line!\n";
      }
    } else {
      print "SYNTAX ERROR 2! $mnemonic\n";
    }
  }

  close $ofh;

  close $ifh;
} else {
  die "Can't open $input_file\n";
}

1;

