#!/usr/bin/perl
#
#  mms2make.pl - convert Descrip.MMS file to Makefile
#  Version 2.0 29-Sep-1994
#  David Denholm <denholm@conmat.phys.soton.ac.uk>
#
#  1.0  06-Aug-1994  Charles Bailey  bailey@genetics.upenn.edu
#    - original version
#  2.0  29-Sep-1994  David Denholm <denholm@conmat.phys.soton.ac.uk>
#    - take action based on MMS .if / .else / .endif
#      any command line options after filenames are set in an assoc array %macros
#      maintain "@condition as a stack of current conditions
#      we unshift a 0 or 1 to front of @conditions at an .ifdef
#      we invert top of stack at a .else
#      we pop at a .endif
#      we deselect any other line if $conditions[0] is 0
#      I'm being very lazy - push a 1 at start, then dont need to check for
#      an empty @conditions [assume nesting in descrip.mms is correct] 

if ($#ARGV > -1 && $ARGV[0] =~ /^[\-\/]trim/i) {
  $do_trim = 1;
  shift @ARGV;
}
$infile  = $#ARGV > -1 ? shift(@ARGV) : "Descrip.MMS";
$outfile = $#ARGV > -1 ? shift(@ARGV) : "Makefile.";

# set any other args in %macros - set VAXC by default
foreach (@ARGV) { $macros{"\U$_"}=1 }

# consistency check
$macros{"DECC"} = 1 if $macros{"__AXP__"};

# set conditions as if there was a .if 1  around whole file
# [lazy - saves having to check for empty array - just test [0]==1]
@conditions = (1);

open(INFIL,$infile) || die "Can't open $infile: $!\n"; 
open(OUTFIL,">$outfile") || die "Can't open $outfile: $!\n"; 

print OUTFIL "#> This file produced from $infile by $0\n";
print OUTFIL "#> Lines beginning with \"#>\" were commented out during the\n";
print OUTFIL "#> conversion process.  For more information, see $0\n";
print OUTFIL "#>\n";

while (<INFIL>) {
  s/$infile/$outfile/eoi;
  if (/^\#/) { 
    if (!/^\#\:/) {print OUTFIL;}
    next;
  }

# look for ".ifdef macro" and push 1 or 0 to head of @conditions
# push 0 if we are in false branch of another if
  if (/^\.ifdef\s*(.+)/i)
  {
     print OUTFIL "#> ",$_ unless $do_trim;
     unshift @conditions, ($macros{"\U$1"} ? $conditions[0] : 0);
     next;
  }

# reverse $conditions[0] for .else provided surrounding if is active
  if (/^\.else/i)
  {
      print OUTFIL "#> ",$_ unless $do_trim;
      $conditions[0] = $conditions[1] && !$conditions[0];
      next;
  }

# pop top condition for .endif
  if (/^\.endif/i)
  {
     print OUTFIL "#> ",$_ unless $do_trim;
     shift @conditions;
     next;
  }

  next if ($do_trim && !$conditions[0]);

# spot new rule and pick up first source file, since some versions of
# Make don't provide a macro for this
  if (/[^#!]*:\s+/) {
    if (/:\s+([^\s,]+)/) { $firstsrc = $1 }
    else { $firstsrc = "\$<" }
  }

  s/^ +/\t/;
  s/^\.first/\.first:/i;
  s/^\.suffixes/\.suffixes:/i;
  s/\@\[\.vms\]/\$\$\@\[\.vms\]/;
  s/f\$/f\$\$/goi;
  s/\$\(mms\$source\)/$firstsrc/i;
  s/\$\(mms\$target\)/\$\@/i;
  s/\$\(mms\$target_name\)\$\(O\)/\$\@/i;
  s/\$\(mms\$target_name\)/\$\*/i;
  s/sys\$([^\(])/sys\$\$$1/gi;
  print OUTFIL "#> " unless $conditions[0];
  print OUTFIL $_;
}

close INFIL;
close OUTFIL;

