package ExtUtils::MakeMaker;

# Authors: Andy Dougherty	<doughera@lafcol.lafayette.edu>
#	   Andreas Koenig	<k@franz.ww.TU-Berlin.DE>
#	   Tim Bunce		<Tim.Bunce@ig.co.uk>

# Last Revision: 12 Oct 1994

# This utility is designed to write a Makefile for an extension 
# module from a Makefile.PL. It is based on the excellent Makefile.SH
# model provided by Andy Dougherty and the perl5-porters. 

# It splits the task of generating the Makefile into several
# subroutines that can be individually overridden.
# Each subroutine returns the text it wishes to have written to
# the Makefile.

use Config;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(writeMakefile mkbootstrap $Verbose);
@EXPORT_OK = qw(%att @recognized_att_keys);

use strict qw(refs);

# Setup dummy package:
# MY exists for overriding methods to be defined within
unshift(@MY::ISA, qw(MM));

$Verbose = 0;
$Subdirs = 0;	# set to 1 to have this .PL run all below
$^W=1;


# For most extensions it will do to call
#
#   use ExtUtils::MakeMaker
#   &writeMakefile("potential_libs" => "-L/usr/alpha -lfoo -lbar");
#
# from Makefile.PL in the extension directory
# It is also handy to include some of the following attributes:
#
@recognized_att_keys=qw(
    TOP INC DISTNAME VERSION DEFINE OBJECT LDTARGET ARMAYBE
    BACKUP_LIBS  AUTOSPLITMAXLEN LINKTYPE
    potential_libs otherldflags perl fullperl
    distclean_tarflags
    clean_files realclean_files
);

#
# TOP      is the directory above lib/ and ext/ (normally ../..)
#          (MakeMaker will normally work this out for itself)
# INC      is something like "-I/usr/local/Minerva/include"
# DISTNAME is a name of your choice for distributing the package
# VERSION  is your version number
# DEFINE   is something like "-DHAVE_UNISTD_H"
# OBJECT   defaults to '$(BASEEXT).o', but can be a long string containing 
#          all object files, e.g. "tkpBind.o tkpButton.o tkpCanvas.o"
# LDTARGET defaults to $(OBJECT) and is used in the ld command
#          (some machines need additional switches for bigger projects)
# ARMAYBE  defaults to ":", but can be used to run ar before ld
# BACKUP_LIBS is an anonymous array of libraries to be searched for
#          until we get at least some output from ext/util/extliblist
#          'potential_libs' => "-lgdbm",
#          'BACKUP_LIBS' => [ "-ldbm -lfoo", "-ldbm.nfs" ]
# AUTOSPLITMAXLEN defaults to 8 and is used when autosplit is done
#          (can be set higher on a case-by-case basis)
# defaults to `dynamic', can be set to `static'

#
# `make distclean'  builds $(DISTNAME)-$(VERSION).tar.Z after a clean

# Be aware, that you can also pass attributes into the %att hash table
# by calling Makefile.PL with an argument of the form TOP=/some/where.

# If the Makefile generated by default does not fit your purpose,
# you may specify private subroutines in the Makefile.PL as there are:
#
# MY->initialize        =>   sub MY::initialize{ ... }
# MY->post_initialize   =>   sub MY::post_initialize{ ... }
# MY->constants         =>   etc
# MY->dynamic
# etc. (see function writeMakefile, for the current breakpoints)
#
# Each subroutines returns the text it wishes to have written to
# the Makefile. To override a section of the Makefile you can
# either say: 	sub MY::co { "new literal text" }
# or you can edit the default by saying something like:
#	sub MY::co { $_=MM->co; s/old text/new text/; $_ }
#
# If you still need a different solution, try to develop another 
# subroutine, that fits your needs and submit the diffs to 
# perl5-porters or comp.lang.perl as appropriate.

sub writeMakefile {
    %att = @_;
    local($\)="\n";

    foreach (@ARGV){
	$att{$1}=$2 if m/(.*)=(.*)/;
    }
    print STDOUT "MakeMaker" if $Verbose;
    print STDOUT map("	$_ = '$att{$_}'\n", sort keys %att) if ($Verbose && %att);

    MY->initialize();

    print STDOUT "Writing ext/$att{FULLEXT}/Makefile (with variable substitutions)";

    open MAKE, ">Makefile" or die "Unable to open Makefile: $!";

    MY->mkbootstrap(split(" ", $att{'dynaloadlibs'}));
    print MAKE MY->post_initialize;

    print MAKE MY->constants;
    print MAKE MY->post_constants;

    print MAKE MY->subdir if $Subdirs;
    print MAKE MY->dynamic;
    print MAKE MY->force;
    print MAKE MY->static;
    print MAKE MY->co;
    print MAKE MY->c;
    print MAKE MY->installpm;
    print MAKE MY->clean;
    print MAKE MY->realclean;
    print MAKE MY->test;
    print MAKE MY->install;
    print MAKE MY->perldepend;
    print MAKE MY->distclean;
    print MAKE MY->postamble;

    MY->finish;

    close MAKE;

    1;
}


sub mkbootstrap{
    MY->mkbootstrap(@_)
}


sub avoid_typo_warnings{
    local($t) = "$t
	$main::writeMakefile
	$main::mkbootstrap
	$main::Verbose
	$DynaLoader::dl_resolve_using
	$ExtUtils::MakeMaker::Config
	$DynaLoader::Config
    ";
}


# --- Supply the MakeMaker default methods ---

package MM;

use Config;
require Exporter;

Exporter::import('ExtUtils::MakeMaker', qw(%att @recognized_att_keys));

# These attributes cannot be overridden
@other_att_keys=qw(extralibs dynaloadlibs statloadlibs bootdep);


sub find_perl{
    my($self, $ver, $names, $dirs, $trace) = @_;
    my($name, $dir);
    print "Looking for perl $ver by these names: @$names, in these dirs: @$dirs\n"
	if ($trace);
    foreach $dir (@$dirs){
	foreach $name (@$names){
	    print "checking $dir/$name\n" if ($trace >= 2);
	    next unless -x "$dir/$name";
	    print "executing $dir/$name\n" if ($trace);
	    my($out) = `$dir/$name -e 'require $ver; print "5OK\n" ' 2>&1`;
	    return "$dir/$name" if $out =~ /5OK/;
	}
    }
    warn "Unable to find a perl $ver (by these names: @$names, in these dirs: @$dirs)\n";
    0; # false and not empty
}


sub initialize {
    # Find out directory name.  This is also the extension name.
    chop($pwd=`pwd`);

    unless ( $top = $att{TOP} ){
	foreach(qw(../.. ../../.. ../../../..)){
	    ($top=$_, last) if -f "$_/config.sh";
	}
	die "Can't find config.sh" unless -f "$top/config.sh";
    }
    chdir $top or die "Couldn't chdir $top: $!";
    chop($abstop=`pwd`);
    chdir $pwd;

    # EXTMODNAME = The perl module name for this extension.
    # FULLEXT = Full pathname to extension directory.
    # BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
    # ROOTEXT = Directory part of FULLEXT. May be empty.
    my($p) = $pwd; $p =~ s:^\Q$abstop/ext/\E::;
    ($att{EXTMODNAME}=$p) =~ s#/#::#g ;		#eg. BSD::Foo::Socket
    ($att{FULLEXT}   =$p);			#eg. BSD/Foo/Socket
    ($att{BASEEXT}   =$p) =~ s:.*/:: ;		#eg. Socket
    ($att{ROOTEXT}   =$p) =~ s:/?\Q$att{BASEEXT}\E$:: ; #eg. BSD/Foo

    # Find Perl 5. The only contract here is that both 'perl' and 'fullperl'
    # will be working versions of perl 5.
    $att{'perl'} = MY->find_perl(5.0, [ qw(perl5 perl miniperl) ],
			    [ $abstop, split(":", $ENV{PATH}) ], 0 )
	    unless ($att{'perl'} && -x $att{'perl'});

    # Define 'fullperl' to be a non-miniperl (used in test: target)
    ($att{'fullperl'} = $att{'perl'}) =~ s/miniperl$/perl/
	unless ($att{'fullperl'} && -x $att{'fullperl'});

    for $key (@recognized_att_keys, @other_att_keys){
	# avoid warnings for uninitialized vars
	$att{$key} = "" unless defined $att{$key};
    }

    # compute extralibs, dynaloadlibs and statloadlibs from
    # $att{'potential_libs'}

    unless ( &run_extliblist($att{'potential_libs'}) ){
       foreach ( @{$att{'BACKUP_LIBS'} || []} ){
           #  Try again.  Maybe they have specified some other libraries
           last if  &run_extliblist($_);
       }
    }
}


sub run_extliblist {
    my($potential_libs)=@_;
    # Now run ext/util/extliblist to discover what *libs definitions
    # are required for the needs of $potential_libs
    $ENV{'potential_libs'} = $potential_libs;
    $_=`. $abstop/ext/util/extliblist;
	echo extralibs=\$extralibs
	echo dynaloadlibs=\$dynaloadlibs
	echo statloadlibs=\$statloadlibs
	echo bootdep=\$bootdep
	`;
    my(@w);
    foreach $line (split "\n", $_){
	chomp $line;
	if ($line =~ /(.*)\s*=\s*(.*)$/){
	    $att{$1} = $2;
	    print STDERR "	$1 = $2" if $Verbose;
	}else{
	    push(@w, $line);
	}
    }
    print STDERR "Messages from extliblist:\n", join("\n",@w,'')
       if @w ;
    join '', @att{qw(extralibs dynaloadlibs statloadlibs)};
}


sub post_initialize{
    "";
}
 

sub constants {
    my(@m);

    $att{BOOTDEP}  = (-f "$att{BASEEXT}_BS") ? "$att{BASEEXT}_BS" : "";
    $att{OBJECT}   = '$(BASEEXT).o' unless $att{OBJECT};
    $att{LDTARGET} = '$(OBJECT)'    unless $att{LDTARGET};
    $att{ARMAYBE}  = ":"            unless $att{ARMAYBE};
    $att{AUTOSPLITMAXLEN} = 8       unless $att{AUTOSPLITMAXLEN};
    $att{LINKTYPE} = ($Config{'usedl'}) ? 'dynamic' : 'static'
	unless $att{LINKTYPE};


    push @m, "
#
# This Makefile is for the $att{FULLEXT} extension to perl.
# It was written by Makefile.PL, so don't edit it, edit
# Makefile.PL instead. ANY CHANGES MADE HERE WILL BE LOST!
# 

DISTNAME = $att{DISTNAME}
VERSION = $att{VERSION}

TOP = $top
ABSTOP = $abstop
PERL = $att{'perl'}
FULLPERL = $att{'fullperl'}
INC = $att{INC}
DEFINE = $att{DEFINE}
OBJECT = $att{OBJECT}
LDTARGET = $att{LDTARGET}
";

    push @m, "
CC = $Config{'cc'}
LIBC = $Config{'libc'}
LDFLAGS = $Config{'ldflags'}
CLDFLAGS = $Config{'ldflags'}
LINKTYPE = $att{LINKTYPE}
ARMAYBE = $att{ARMAYBE}
RANLIB = $Config{'ranlib'}

SMALL = $Config{'small'}
LARGE = $Config{'large'} $Config{'split'}
# The following are used to build and install shared libraries for
# dynamic loading.
LDDLFLAGS = $Config{'lddlflags'}
CCDLFLAGS = $Config{'ccdlflags'}
CCCDLFLAGS = $Config{'cccdlflags'}
SO = $Config{'so'}
DLEXT = $Config{'dlext'}
DLSRC = $Config{'dlsrc'}
";

    push @m, "
# $att{FULLEXT} might need to be linked with some extra libraries.
# EXTRALIBS =  full list of libraries needed for static linking.
#		Only those libraries that actually exist are included.
# DYNALOADLIBS = list of those libraries that are needed but can be
#		linked in dynamically on this platform.  On SunOS, for
#		example, this would be .so* libraries, but not archive
#		libraries.  The bootstrap file is installed only if
#		this list is not empty.
# STATLOADLIBS = list of those libraries which must be statically
#		linked into the shared library.  On SunOS 4.1.3, 
#		for example,  I have only an archive version of
#		-lm, and it must be linked in statically.
EXTRALIBS = $att{'extralibs'}
DYNALOADLIBS = $att{'dynaloadlibs'}
STATLOADLIBS = $att{'statloadlibs'}

";

    push @m, "
# EXTMODNAME = The perl module name for this extension.
# FULLEXT = Full pathname to extension directory.
# BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
# ROOTEXT = Directory part of FULLEXT. May be empty.
EXTMODNAME = $att{EXTMODNAME}
FULLEXT = $att{FULLEXT}
BASEEXT = $att{BASEEXT}
ROOTEXT = $att{ROOTEXT}
# and for backward compatibility and for AIX support (due to change!)
EXT = $att{BASEEXT}

# $att{FULLEXT} might have its own typemap
EXTTYPEMAP = ".(-f "typemap" ? "typemap" : "")."
# $att{FULLEXT} might have its own bootstrap support
BOOTSTRAP = $att{BASEEXT}.bs
BOOTDEP = $att{BOOTDEP}
";

    push @m, '
# Where to put things:
AUTO = $(TOP)/lib/auto
AUTOEXT = $(TOP)/lib/auto/$(FULLEXT)
INST_BOOT = $(AUTOEXT)/$(BASEEXT).bs
INST_DYNAMIC = $(AUTOEXT)/$(BASEEXT).$(DLEXT)
INST_STATIC = $(BASEEXT).a
INST_PM = $(TOP)/lib/$(FULLEXT).pm
'."
# These two are only used by install: targets
INSTALLPRIVLIB = $Config{'installprivlib'}
INSTALLARCHLIB = $Config{'installarchlib'}
";

    push @m, "\nshellflags = $Config{'shellflags'}" if $Config{'shellflags'};

    push @m, q{
# Tools
SHELL = /bin/sh
CCCMD = `sh $(shellflags) $(ABSTOP)/cflags $@`
XSUBPP = $(TOP)/ext/xsubpp
# the following is a portable way to say mkdir -p
MKPATH = $(PERL) -we '$$"="/"; foreach(split(/\//,$$ARGV[0])){ push(@p, $$_); next if -d "@p"; print "mkdir @p\n"; mkdir("@p",0777)||die "mkdir @p: $$!" } exit 0;'
AUTOSPLITLIB = cd $(TOP); \
	$(PERL) -Ilib -e 'use AutoSplit; $$AutoSplit::Maxlen=}.$att{AUTOSPLITMAXLEN}.q{; autosplit_lib_modules(@ARGV) ;'
};

    push @m, '

all :: 

config :: Makefile
	@$(MKPATH) $(AUTOEXT)

install ::

';

    join('',@m);
}


sub post_constants{
    "";
}


sub subdir {
    my(@m);
    foreach $MakefilePL (<*/Makefile.PL>){
	($subdir=$MakefilePL) =~ s:/Makefile\.PL$:: ;
	push @m, "
config ::
	\@cd $subdir ; \\
	if test ! -f Makefile; then \\
	test -f Makefile.PL  && \$(PERL) -I\$(ABSTOP)/lib Makefile.PL TOP=\$(ABSTOP) ; \\
	fi

all ::
	cd $subdir ; \$(MAKE) config
	cd $subdir ; \$(MAKE) all
";

    }
    join('',@m);
}


sub co {
    '
.c.o:
	$(CCCMD) $(CCCDLFLAGS) $(DEFINE) -I$(TOP) $(INC) $*.c
';
}


sub force {
    '
# Phony target to force checking subdirectories.
FORCE:
';
}


sub dynamic {
    '
all::	$(LINKTYPE)

# Target for Dynamic Loading:
dynamic::	$(INST_DYNAMIC) $(INST_PM) $(INST_BOOT)

$(INST_DYNAMIC): $(OBJECT)
	@$(MKPATH) $(AUTOEXT)
	$(ARMAYBE) cr $(EXTMODNAME).a $(OBJECT) 
	ld $(LDDLFLAGS) -o $@ $(LDTARGET) '.$att{'otherldflags'}.' $(STATLOADLIBS)

$(BOOTSTRAP): $(BOOTDEP)
	$(PERL) -I$(TOP)/lib -e \'use ExtUtils::MakeMaker; &mkbootstrap("$(DYNALOADLIBS)");\'
	touch $(BOOTSTRAP)

$(INST_BOOT): $(BOOTSTRAP)
	@test ! -s $(BOOTSTRAP) || cp $(BOOTSTRAP) $@
';
}


sub static {
    '
# Target for Static Loading:
static:: $(INST_STATIC) $(INST_PM)

$(INST_STATIC): $(OBJECT)
	ar cr $@ $(OBJECT)
	$(RANLIB) $@
	echo $(EXTRALIBS) >> $(TOP)/ext.libs
';
}


sub c {
    '
$(BASEEXT).c:	$(BASEEXT).xs $(XSUBPP) $(TOP)/ext/typemap $(EXTTYPEMAP) $(TOP)/cflags
	$(PERL) $(XSUBPP) $(BASEEXT).xs >tmp
	mv tmp $@
';
}


sub installpm {
    '
$(INST_PM):	$(BASEEXT).pm
	@$(MKPATH) $(TOP)/lib/$(ROOTEXT)
	rm -f $@
	cp $(BASEEXT).pm $@
	@$(AUTOSPLITLIB) $(EXTMODNAME)
';
}


sub clean {
    '
clean::
	rm -f *.o *.a mon.out core $(BASEEXT).c so_locations
	rm -f makefile Makefile $(BOOTSTRAP) $(BASEEXT).bso '.$att{'clean_files'}.'
';
}


sub realclean {
    '
realclean:: 	clean
	rm -f $(INST_DYNAMIC) $(INST_STATIC) $(INST_BOOT)
	rm -rf $(INST_PM) $(AUTOEXT) '.$att{'realclean_files'}.'

purge:	realclean
';
}


sub test {
    '
test: all
	$(FULLPERL) -I$(TOP)/lib -e \'use Test::Harness; runtests @ARGV;\' t/*.t
';
}


sub install {
    '
# used if installperl will not be installing it for you
install:: all
	# not yet defined
';
}


sub distclean {
    my($tarflags) = $att{'distclean_tarflags'} || 'cvf';
    '
distclean:     clean
	rm -f Makefile *~ t/*~
	cd ..; tar '.$tarflags.' "$(DISTNAME)-$(VERSION).tar" $(BASEEXT)
	cd ..; compress "$(DISTNAME)-$(VERSION).tar"
';
}


sub perldepend {
    '
$(OBJECT) : Makefile
$(OBJECT) : $(TOP)/EXTERN.h
$(OBJECT) : $(TOP)/INTERN.h
$(OBJECT) : $(TOP)/XSUB.h
$(OBJECT) : $(TOP)/av.h
$(OBJECT) : $(TOP)/cop.h
$(OBJECT) : $(TOP)/cv.h
$(OBJECT) : $(TOP)/dosish.h
$(OBJECT) : $(TOP)/embed.h
$(OBJECT) : $(TOP)/form.h
$(OBJECT) : $(TOP)/gv.h
$(OBJECT) : $(TOP)/handy.h
$(OBJECT) : $(TOP)/hv.h
$(OBJECT) : $(TOP)/keywords.h
$(OBJECT) : $(TOP)/mg.h
$(OBJECT) : $(TOP)/op.h
$(OBJECT) : $(TOP)/opcode.h
$(OBJECT) : $(TOP)/patchlevel.h
$(OBJECT) : $(TOP)/perl.h
$(OBJECT) : $(TOP)/perly.h
$(OBJECT) : $(TOP)/pp.h
$(OBJECT) : $(TOP)/proto.h
$(OBJECT) : $(TOP)/regcomp.h
$(OBJECT) : $(TOP)/regexp.h
$(OBJECT) : $(TOP)/scope.h
$(OBJECT) : $(TOP)/sv.h
$(OBJECT) : $(TOP)/unixish.h
$(OBJECT) : $(TOP)/util.h
$(TOP)/config.h:        $(TOP)/config.sh; cd $(TOP); /bin/sh config_h.SH
$(TOP)/embed.h: $(TOP)/config.sh; cd $(TOP); /bin/sh embed_h.SH
$(TOP)/cflags:  $(TOP)/config.sh; cd $(TOP); /bin/sh cflags.SH

Makefile:	Makefile.PL
	$(PERL) -I$(TOP)/lib Makefile.PL
';
}


sub postamble{
    "";
}


sub finish {
    chmod 0644, "Makefile";
    system("$Config{'eunicefix'} Makefile") unless $Config{'eunicefix'} eq ":";
}



sub mkbootstrap {
#
# mkbootstrap, by:
#
#	Andreas Koenig <k@otto.ww.TU-Berlin.DE>
#	Tim Bunce <Tim.Bunce@ig.co.uk>
#	Andy Dougherty <doughera@lafcol.lafayette.edu>
#
#  This perl script attempts to make a bootstrap file for use by this
#  system's DynaLoader. It typically gets called from an extension
#  Makefile.
#
# There is no .bs file supplied with the extension. Instead a _BS
# file which has code for the special cases, like posix for berkeley db
# on the NeXT.
# 
# This file will get parsed, and produce a maybe empty
# @DynaLoader::dl_resolve_using array for the current architecture.
# That will be extended by $dynaloadlibs, which was computed by Andy's
# extliblist script. If this array still is empty, we do nothing, else
# we write a .bs file with an @DynaLoader::dl_resolve_using array, but
# without any `if's, because there is no longer a need to deal with
# special cases.
# 
# The _BS file can put some code into the generated .bs file by placing
# it in $bscode. This is a handy 'escape' mechanism that may prove
# useful in complex situations.
# 
# If @DynaLoader::dl_resolve_using contains -L* or -l* entries then
# mkbootstrap will automatically add a dl_findfile() call to the
# generated .bs file.
#
    my($self, @dynaloadlibs)=@_;
    print STDERR "	dynaloadlibs=@dynaloadlibs" if $Verbose;
    require DynaLoader; # we need DynaLoader, if the *_BS gets interpreted
    import DynaLoader;  # we don't say `use', so if DynaLoader is not 
	          # yet built MakeMaker works nonetheless except here

    &initialize unless defined $att{'perl'};

    rename "$att{BASEEXT}.bs", "$att{BASEEXT}.bso";

    if (-f "$att{BASEEXT}_BS"){
	$_ = "$att{BASEEXT}_BS";
	package DynaLoader; # execute code as if in DynaLoader
	local($osname, $dlsrc) = (); # avoid warnings
	($osname, $dlsrc) = @Config{qw(osname dlsrc)};
	$bscode = "";
	unshift @INC, ".";
	require $_;
    }

    if ($Config{'dlsrc'} =~ /^dl_dld/){
	package DynaLoader;
	push(@dl_resolve_using, dl_findfile('-lc'));
    }

    my(@all) = (@dynaloadlibs, @DynaLoader::dl_resolve_using);
    my($method) = '';
    if (@all){
	open BS, ">$att{BASEEXT}.bs"
		or die "Unable to open $att{BASEEXT}.bs: $!";
	print STDOUT "Writing $att{BASEEXT}.bs\n";
	print STDOUT "	containing: @all" if $Verbose;
	print BS "# $att{BASEEXT} DynaLoader bootstrap file for $Config{'osname'} architecture.\n";
	print BS "# Do not edit this file, changes will be lost.\n";
	print BS "# This file was automatically generated by the\n";
	print BS "# mkbootstrap routine in ExtUtils/MakeMaker.pm.\n";
	print BS "\@DynaLoader::dl_resolve_using = ";
	if (" @all" =~ m/ -[lL]/){
	    print BS "  dl_findfile(qw(\n  @all\n  ));\n";
	}else{
	    print BS "  qw(@all);\n";
	}
	# write extra code if *_BS says so
	print BS $DynaLoader::bscode if $DynaLoader::bscode;
	print BS "1;\n";
	close BS;
    }

    if ($Config{'dlsrc'} =~ /^dl_aix/){
       open AIX, ">$att{BASEEXT}.exp";
       print AIX "#!\nboot_$att{BASEEXT}\n";
       close AIX;
    }
}

# the following makes AutoSplit happy (bug in perl5b3e)
package ExtUtils::MakeMaker;
1;

__END__
