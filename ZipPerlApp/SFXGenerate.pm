# ZipPerlApp::SFXGenerate: generating pure-Perl SFX archives.
#
# Part of (core of) zipperlapp. (c) 2019-2025 Yutaka OIWA.
# Licensed under Apache License Version 2.0.
# See README.md for details and additional allowances.

package ZipPerlApp::SFXGenerate v2.1.0;

=pod

=head1 NAME

ZipPerlApp::SFXGenerate: a generator for pure-perl SFX archives.

=head1 DESCRIPTION

This module creates a perl script with simple zip archive,
can be used as a self-contained script for several modules.

There are two sets of interfaces: middle level (library level) and
command level.

=cut

use 5.024;
use strict;
use Fcntl; # for sysopen constants
use File::Basename "basename";
use File::Find ();
use Data::Dumper ();
use Hash::Util;

use re '/saa'; # strictly byte-oriented, no middle \n match

use if (__FILE__ eq $0), FindBin => ();
use if (__FILE__ eq $0), lib => "$FindBin::Bin/..";

use ZipPerlApp::ZipTiny;

our $DEBUG = 0;

### Mid-level interfaces

=head1 Middle-level interfaces

The middle-level interfaces has the following methods:

=cut

use fields qw(possible_out main maintype includedir trimlibname
              sizelimit debug interactive diagout_fh progout_fh zip);

sub new {
    my $self = shift;

    $self = fields::new($self) unless ref $self;

    my %options = (sizelimit => 64 * 1048576,
		   progout_fh => undef,
		   diagout_fh => undef,
		   debug => $DEBUG,
		   @_);

    die "ZipPerlApp::SFXGenerate->new: bad keyword arguments" unless
      scalar keys %options == 4;

    my $zip = ZipPerlApp::ZipTiny->new();
    $zip->__setopt($options{sizelimit}, $options{debug}, $options{diagout_fh});

    %$self = (possible_out => undef,
	      main => undef,
	      maintype => 0,
	      includedir => [],
	      trimlibname => 1,
	      interactive => 0,
	      zip => $zip,
	      %options);

    return $self;
}

=head2 SFXGenerate->new([kwd => value, ...])

C<new> creates a new instance for SFX generator.

It has the following keyword arguments:

sizelimit: a file size limit for each zip entry, used for both
generating and running time. (default: 64Mi bytes)

=cut

sub add_entry {
    my $self = shift;
    $self->{zip}->add_entry(@_);
}

=head2 add_entry(entry_name, real_name)

Add a file to the sfx archive.

If two file names are passed, these will be used as a
name for zip entry, and name of the file to read.

See C<ZipTiny::add_entry> for more argument patterns.

=cut

sub generate {
    my $self = shift;
    my $progout_fh = $self->{progout_fh};
    my $diagout_fh = $self->{debug} && $self->{diagout_fh};

    my %options = ( out => undef,
		    main => undef,
		    compression => 0,
		    base64 => 0,
		    textarchive => 0,
		    copy_pod => 0,
		    quote_pod => 0,
		    protect_pod => 2,
		    inhibit_lib => 0, @_);
    die "ZipPerlApp::SFXGenerate::generate: bad keyword argument"
      unless scalar keys %options == 9;

    die "ZipPerlApp::SFXGenerate::generate: no mandatory keyword argument" unless
      defined $options{out} and defined $options{main};

    my $zip = $self->{zip};
    my ($out, $main, $compression, $base64, $textarchive, $copy_pod, $quote_pod, $protect_pod, $inhibit_lib) =
      @options{qw(out main compression base64 textarchive copy_pod quote_pod protect_pod inhibit_lib)};

    if (! $zip->include_q($main)) {
	die "no main file $main will be contained in archive";
    }

    if ($self->{interactive} && $progout_fh) {
	for my $f ($zip->entries) {
	    printf $progout_fh "%s <- %s\n", $f->fname, $f->source;
	}
    }

    my $pod = "";
    my $podsw = 0;

    # consult main script for pod and she-bang

    my ($mainent) = $zip->find_entry($main);

    die unless defined $mainent;
    open MAIN, "<", \($mainent->content) or die "read main: $!";

    my $shebang = '';
    while (($_ = <MAIN>) =~ /^#/) {
	$shebang .= $_;
    }

    if ($copy_pod) {
	while (defined $_) {
	    $podsw = 1 if(/^=[a-z]/);
	    $podsw = 0 if(/^=cut\b/);
	    $pod .= $_ if $podsw;
	    $_ = <MAIN>;
	}
	# more treatment will be later
    }

    $shebang = "#!/usr/bin/perl\n" if $shebang eq '';

    my $mode = ($shebang =~ /\A#!/s ? 0777 : 0666);

    close MAIN;

    # initial try with minimal quotations

    my ($headerdata, $zipdata) = $self->create_sfx($shebang, $main, $pod, $textarchive, $compression, $base64, 0, ($protect_pod == 1), $inhibit_lib);

    if ((($protect_pod == 2) || $quote_pod) && quote_required($zipdata)) {
	# retry with quotations
	print $diagout_fh "detected unquoted pods -- retry with quoting/protection enabled\n" if $self->{debug} && $diagout_fh;
	$protect_pod = !$quote_pod;
	($headerdata, $zipdata) = $self->create_sfx($shebang, $main, $pod, $textarchive, $compression, $base64, $quote_pod, !$quote_pod, $inhibit_lib);
    }

    my ($out_fh, $out_fh_close);

    if (ref $out) {
	$out_fh = $out;
	$out_fh_close = 0;
    } else {
	print $progout_fh "writing to $out\n" if $progout_fh;
	sysopen($out_fh, $out, O_WRONLY | O_CREAT | O_TRUNC, $mode) or die "write: $!";
	$out_fh_close = 1;
    }

    print $out_fh $headerdata or die "$!";
    print $out_fh $zipdata or die "$!";
    close $out_fh or die "$!" if $out_fh_close;
}

=head2 generate(kwd => value, ...)

Generate a sfx archive and write to a file.

The following keyword arguments are accepted:

=over 4

=item out

(mandatory) A file-name or a filehandle for output.

=item main

(mandatory) An entry name for the "main script" in the archive.
The stored "file" of that name will be loaded first.

=item compression

The compression level (0--9 or string 'bzip') for the archive.

=item base64, textarchive, copy_pod, quote_pod, protect_pod, inhibit_lib

These are boolean corresponding to the options of C<zipperlapp>.
See man (or POD) of C<zipperlapp> for details.

=back

=cut

# High-level (command line level) interface

=head1 High-level interfaces

The high-level interface has a single class method called C<zipperlapp>.

=cut

## support routines

sub canonicalize_filename {
    my ($self, $fname, $fixedprefix) = @_;

    # canonicalize input path
    $fname =~ s(\A/+)(/)sg;
    my @fname = split('/', $fname);
    for (my $pos = 0; exists $fname[$pos]; $pos++) {
	next if $pos == -1;
	if ($fname[$pos] eq '.') {
	    splice @fname, $pos, 1;
	    redo;
	} elsif ($pos != 0 &&
		 $fname[$pos] eq '..' &&
		 $fname[$pos-1] ne '' && # not parent-of-root
		 $fname[$pos-1] ne '..' # parent of parent
		) {
	    splice @fname, $pos-1, 2;
	    $pos--;
	    redo;
	}
    }
    $fname = join("/", @fname);

    # trim names with include directory
    my $ename = $fname;
    if ($self->{trimlibname}) {
	my @includedir = @{$self->{includedir}};
	if (defined $fixedprefix) {
	    unshift @includedir, $fixedprefix;
	}
	for my $l (@includedir) {
	    my $libdir = "$l/";
	    my $length = length($libdir);
	    if (substr($ename, 0, length($libdir)) eq $libdir) {
		$ename = substr($ename, $length);
		last;
	    }
	}
    }

    die "$ename: name is absolute\n" if $ename =~ m@\A/@s;
    die "$ename: name contains ..\n" if $ename =~ m@(\A|/)../@s;

    return wantarray ? ($fname, $ename) : $ename;
}

sub cmd_add_file {
    my ($self, $fname, $fixedprefix) = @_;
    my $zip = $self->{zip};
    my $maintype = $self->{maintype};
    # behavior of main mode:
    #  1: add if *.pl, duplication is error
    #  2: add if first
    #  3: noop

    my ($fname, $ename) = $self->canonicalize_filename($fname, $fixedprefix);
    die "cannot find $fname: $!" unless -e $fname;
    die "$fname is not a plain file" unless -f $fname;
    if ($zip->include_q($ename)) {
	my $ent = $zip->find_entry($ename);
	if ($fname ne $ent->source) {
	    die "duplicated files: $fname and ${\ ($ent->source)} will be same name in the archive";
	} else {
	    # skip;
	}
    } else {
	if ($maintype == 1) {
	    if ($ename =~ /\.pl$/s) {
		die "found two .pl files: $self->{main} and $ename\n" if defined $self->{main};
		$self->{main} = $ename;
	    }
	} elsif ($maintype == 2) {
	    $self->{main} = $ename unless defined $self->{main};
	    $self->{possible_out} = $ename unless defined $self->{possible_out};
	}
	$zip->add_entry($ename, $fname);
    }
}

sub cmd_add_dir {
    my ($self, $fname, $prefix) = @_;
    File::Find::find
	({wanted => sub {
	      my $f = $File::Find::name;
	      if ($f =~ /\.p[lm]\z/s && !($f =~ m((\A|\/)\.[^\/])s)) {
		  $self->cmd_add_file($f, $prefix);
	      }
	  },
	  no_chdir => 1
	 }, $fname);
}

=head2 SFXGenerate->zipperlapp(\@files, [kwd => value, ...])

C<zipperlapp> creates a SFX archive.

All arguments are exactly corresponding to the command-line arguments
of C<zipperlapp>.  See man or pod of C<zipperlapp> for details.

The first argument is an array reference for filenames.

The rest is a keyword-style arguments:

=over 4

=item *

Options C<base64>, C<textarchive>, C<copy_pod>,
C<quote_pod>, C<protect_pod>, C<inhibit_lib>, C<searchincludedir>,
C<trimlibname> are booleans corresponding to the command options.

=item *

The option C<out> can contain a file name or a reference to Perl file-handle.
To redirect output to standard output, pass C<\*STDOUT> (the backslash is important),
and also specify C<progout_fh> below.

=item *

C<mainopt> is a string for C<-m> option.

=item *

C<includedir> is an array reference for C<-I> option.

=item *

C<compression> can contain integers 0--9, or a string 'bzip'.

=item *

C<progout_fh> contains a file-handle for progress and informative messages
which C<zipperlapp> generates.

It defaults to STDOUT, and can be C<undef> for suppressing messages.
When C<\*STDOUT> is passed to C<out>, also set this property to C<\*STDERR> or C<undef>.

=back

=cut

sub zipperlapp {
    my $self = shift;

    if (ref $self eq 'ARRAY') { # called as module function
	unshift @_, $self;
	$self = __PACKAGE__;
    }
    my $argv = shift;

    my %poptions = @_;
    my %options = ( out => undef,
		    mainopt => undef,
		    copy_pod => 0,
		    quote_pod => 0,
		    protect_pod => 2,
		    includedir => [],
		    searchincludedir => 1,
		    trimlibname => 0,
		    inhibit_lib => 0,
		  );
    for my $kw (keys %options) {
	if (exists $poptions{$kw}) {
	    $options{$kw} = $poptions{$kw};
	    delete $poptions{$kw};
	}
    }

    if ($self eq __PACKAGE__) { # called as class method
	my $sizelimit = delete $poptions{sizelimit};
	my $debug = delete $poptions{debug} // $DEBUG;
	my $diagout_fh = exists $poptions{diagout_fh} ? delete $poptions{diagout_fh} : *STDERR;
	my $progout_fh = exists $poptions{progout_fh} ? delete $poptions{progout_fh} : *STDOUT;
	$self = ZipPerlApp::SFXGenerate->new
	  (sizelimit => $sizelimit,
	   debug => $debug,
	   diagout_fh => $diagout_fh,
	   progout_fh => $progout_fh
	  );
    }

    $self->{interactive} = 1;

    my $out = $options{out};
    my $mainopt = $options{mainopt};
    my $copy_pod = $options{copy_pod};
    my $quote_pod = $options{quote_pod};
    my $protect_pod = $options{protect_pod};
    my @includedir = @{$options{includedir}};
    my $searchincludedir = $options{searchincludedir};
    $self->{trimlibname} = my $trimlibname = $options{trimlibname};
    my $inhibit_lib = $options{inhibit_lib};

    my $progout_fh = $self->{progout_fh};

    if (!!$quote_pod + !!$poptions{base64} >= 2) {
	die "Error: --quote_pod and --base64 are exclusive\n";
    }
    unless ($poptions{compression} =~ /\A[0-9]|bzip\z/) {
	die "Error: bad --compress=$poptions{compression} (should be 0 to 9)";
	pod2usage(2);
    }

    $self->{possible_out} = undef;
    $self->{main} = undef;
    my $dir = undef;
    $self->{maintype} = 0;

    # determine main file and output name
    # argument types:
    #   type 1: a single directory dir, no main specified
    #     -> include all files in dir, search for the main file (single .pl), output dir.plz
    #   type 2: a set of files
    #     -> specified files included, first argument must be .pl file, output first.plz
    #   type 3: main file specified
    #     -> specified files included, main file must be included, output main.plz

    for (@includedir) {
	$_ =~ s(/+\z)()s;
    }

    if (defined $mainopt) {
	$self->{main} = $mainopt;
	$self->{possible_out} = $self->{main};
	$self->{maintype} = 3;
    }

    if (scalar @ARGV == 1 && -d $ARGV[0]) {
	$dir = $ARGV[0];
	$dir =~ s(/+\z)()s;
	$self->{possible_out} = $dir;
	unshift @includedir, ($dir);
	$searchincludedir = 0;
	$self->{trimlibname} = $trimlibname = 1;
	$self->{maintype} = 1 unless $self->{maintype} == 3;
    } else {
	$self->{maintype} = 2 unless $self->{maintype} == 3;
    }

    if (defined $mainopt) {
	$self->{main} = $self->canonicalize_filename($self->{main}, undef);
    }

    for (@$argv) {
	my $foundprefix = undef;
	unless (-e $_) {
	    if ($searchincludedir) {
		for my $l (@includedir) {
		    my $ff = "$l/$_";
		    if (-e $ff) {
			$foundprefix = $l;
			$_ = $ff;
			last;
		    }
		}
	    }
	}
	if (-f $_) {
	    $self->cmd_add_file($_, $foundprefix);
	} elsif (-d $_) {
	    s(\/+\z)()s;
	    $self->cmd_add_dir($_, $foundprefix);
	} else {
	    die "file not found: $_" unless -e $_;
	    die "unknown type of argument: $_\n";
	}
    }

    if (! defined $out) {
	if (!$self->{possible_out} or $self->{possible_out} eq '.') {
	    die "cannot guess name";
	}
	$out = basename $self->{possible_out}; # for a while
	$out =~ s/(\.pl)?\z/\.plz/;
	say "output is set to: $out";
    }

    die "no main files guessed" unless (defined $self->{main});

    if ($self->{maintype} != 3 || $mainopt ne $self->{main}) {
	say $progout_fh "main file set to: $self->{main}" if $progout_fh;
    }

    $self->generate(out => $out, main => $self->{main}, %poptions);
}

# low-level routines

sub create_sfx {
    my ($self, $shebang, $main, $pod, $textarchive, $compression, $base64, $quote, $protect_pod, $inhibit_lib) = @_;

    my $debug = $self->{debug};
    my $diagout_fh = $self->{diagout_fh};
    my $zip = $self->{zip};

    print $diagout_fh "create_sfx: b64 $base64, quote $quote, protect $protect_pod\n" if ($debug && $diagout_fh);

    my $sfx_embed = (!$textarchive && !$quote && !$base64);

    # prepare launching script
    if ($protect_pod) {
	if ($pod ne "" or $protect_pod == 1) {
	    my $podsig;
	    while () {
		$podsig = sprintf("POD_ESCAPE_ZipPerlApp_%08d", int(rand(100000000)));
		last unless (grep { index($_->content(), $podsig) != -1 or
				      index($_->fname(), $podsig) != -1 } ($zip->entries()));
		print $diagout_fh "protect_pod: signature $podsig is not well... retrying\n" if ($debug >= 2 && $diagout_fh);
	    }
	    print $diagout_fh "protect_pod: signature $podsig\n" if ($debug >= 2 && $diagout_fh);
	    $pod .= "\n=begin $podsig\n\n=cut\n";
	}
    } elsif ($pod ne "") {
	$pod .= "=cut\n";
    }
    if ($base64) {
	$quote = 'base64';
    } elsif ($quote) {
	$quote = 'quote';
    }

    # prepare launching script

    my $sizelimit = $zip->{sizelimit};
    our %config = (main => $main, dequote => $quote, sizelimit => $sizelimit);
    $config{inhibit_lib} = 1 if $inhibit_lib;

    our @features = ("MAIN",
		     ($quote ? ("QUOTE") : ()),
		     ($compression eq 'bzip' ? ("BZIPCOMPRESSION") :
		      ($compression ? ("COMPRESSION") : ())),
		     ($textarchive ? ("TEXTARCHIVE") : ("ZIPARCHIVE")),
		     ($inhibit_lib ? ("INHIBITLIB") : ()),
		    );

    my $config_str =
      Data::Dumper->new([\%config], ['*CONFIG'])
      ->Useqq(1)->Sortkeys(1)->Dump();

    our $script = &script(\@features,
			  CONFIG => $config_str,
			  PKGNAME => 'ZipPerlApp::__ARCHIVED__',
			  POD => $pod);

    my $header = $shebang . "\n" . $script;

    my $zipdata;

    if ($textarchive) {
	$zipdata = $self->create_textarchive();
    } else {
	my $offset = 0;
	if ($sfx_embed) {
	    $offset = length($header);
	}
	print $diagout_fh "offset -> $offset\n" if ($debug && $diagout_fh);
	$zipdata = $zip->make_zip( compress => $compression,
				   offset => $offset,
				   header => "",
				   trailercomment => "");
    }
    if ($quote eq 'quote') {
	$zipdata =~ s/^=/==/mg;
	# quoting breaks archive structure.
	$zipdata =~ s/PK([\000-\037][\000-\037])/PK\000$1/g;
    } elsif ($quote eq 'base64') {
	require MIME::Base64;
	$zipdata = MIME::Base64::encode_base64($zipdata);
    }

    return $header, $zipdata;
}

sub create_textarchive {
    my ($self) = shift;
    my $debug = $self->{debug};
    my $diagout_fh = $self->{diagout_fh};

    my $zipdat = "";
    local $/;
    for my $e ($self->{zip}->entries) {
	my $sep;
	my $fname = $e->fname;
	my $dat = $e->content;
	for(;;) {
	    $sep = sprintf("----TEXTARCHIVE-%08d----------------", int(rand(100000000)));
	    last if index($dat, $sep) == -1 and index($fname, $sep) == -1;
	    print $diagout_fh "create_textarchive: separator $sep is not well... retrying\n" if ($debug >= 2 && $diagout_fh);
	}
	print $diagout_fh "create_textarchive: separator $sep for $fname\n" if ($debug >= 2 && $diagout_fh);
	$zipdat .= "TXD\n$sep\n$fname\n$sep\n$dat\n$sep\n";
    }
    $zipdat .= "TXE\n";
    return $zipdat;
}

sub quote_required {
    my ($zipdat) = @_;
    return (index($zipdat, "\n=") != -1);
}

sub script () {
    my ($features, %replace) = @_;
    my $script = &script_body();

    1 while $script =~ s[^#BEGIN\ ([A-Z0-9_]+)\n(.*?)^#END\ \1\n]
			[grep ($_ eq $1, @$features) ? $2 : ""]mseg;
    $script =~ s[@@([A-Z0-9_]+)@@]
		[%replace{$1} // die "internal error: no replacement"]eg;
    return $script;
}

if (__FILE__ eq $0) {
    my $s = ZipPerlApp::SFXGenerate->new();
    for my $f (["SFXGenerate.pm", "SFXGenerate.pm"],
	       ["ZipTiny.pm", "ZipTiny.pm"]) {
	$s->add_entry(@$f);
    }
    $s->generate(out => "test.plz",
		 main => "ZipTiny.pm",
		 compression => 6, @ARGV);
}

sub script_body () { <<'EOS'; }
# This script is packaged by zipperlapp
use 5.024;
no utf8;
use strict;
package @@PKGNAME@@;

our %source;
our @@CONFIG@@

sub fatal {
    @_ = ("error processing zipped script: @_"); goto &CORE::die; die @_
}

sub read_data {
    my $len = $_[0];
    return '' if $len == 0;
    my $dat;
    read(DATA, $dat, $len);
    fatal "data truncated" if length($dat) != $len;
    return $dat;
}

sub prepare {
    use bytes;
#BEGIN QUOTE
    if (my $quote = $CONFIG{dequote}) {
        local $/;
        my $zipdat = <DATA>;
        close DATA;
        if ($quote eq 'base64') {
            require MIME::Base64;
            $zipdat = MIME::Base64::decode_base64($zipdat);
        } elsif ($quote eq 'quote') {
            $zipdat =~ s/PK\0([\0-\37][\0-\37])/PK$1/g;
            $zipdat =~ s/^==/=/mg;
        }
        open DATA, "<", \$zipdat or fatal "scalar IO failed.";
    }
#END QUOTE

    for(;;) {
	my $hdr = read_data(4);
#BEGIN ZIPARCHIVE
        # This function assumes a "correct" zip archive,
        # using per-file headers instead of the central archive.
	if ($hdr eq "PK\3\4") {
	    # per_file zip header
	    my (undef, $flags, $comp, undef, undef, $crc,
                $csize, $size, $fnamelen, $extlen) =
                unpack("vvvvvVVVvv", read_data(26));
	    my $fname = read_data($fnamelen);
	    my $ext = read_data($extlen);
	    fatal "$fname: unsupported: deferred length" if ($flags & 0x8 != 0);
            fatal "$fname: unsuppprted: 64bit record" if $size == 0xffffffff;
            fatal "$fname: too big data (u:$size)" if $size > $CONFIG{sizelimit};
            fatal "$fname: too big data (c:$csize)" if $csize > $CONFIG{sizelimit};
	    my $dat = read_data($csize);
	    if ($comp == 0) {
		fatal "$fname: malformed data: bad length" if $csize != $size;
#BEGIN COMPRESSION
	    } elsif ($comp == 8) {
                require Compress::Raw::Zlib;
                my $i = new Compress::Raw::Zlib::Inflate(-WindowBits => - &Compress::Raw::Zlib::MAX_WBITS,
                                                         -Bufsize => $size, -LimitOutput => 1, -CRC32 => 1) or die;
		my $buf = '';
                my $r = $i->inflate($dat, $buf, 1);
                fatal "$fname: Inflate failed: error $r" if $r != &Compress::Raw::Zlib::Z_STREAM_END;
		fatal "$fname: Inflate failed: length mismatch" if length($buf) != $size;
		fatal "$fname: Inflate failed: crc mismatch" unless $i->crc32() == $crc;
		$dat = $buf;
#END COMPRESSION
#BEGIN BZIPCOMPRESSION
	    } elsif ($comp == 12) {
                require Compress::Raw::Bzip2;
                my $i = new Compress::Raw::Bunzip2(0, 0, 0, 0, 1);
		my $buf = ''; vec($buf, $size - 1, 8) = 0;
                my $r = $i->bzinflate($dat, $buf);
                fatal "$fname: Bunzip failed: error $r" if $r != &Compress::Raw::Bzip2::BZ_STREAM_END;
		fatal "$fname: Bunzip failed: length mismatch" if length($buf) != $size;
		#fatal "$fname: Bunzip failed: crc mismatch" unless $i->crc32() == $crc;
		$dat = $buf;
#END BZIPCOMPRESSION
	    } else {
		fatal "$fname: unknown compression (type $comp)";
	    }

	    $source{$fname} = $dat;
	    next;
	} elsif ($hdr eq "PK\1\2") {
	    last; # central directory found. exiting.
	} elsif ($hdr eq "PK\5\6") {
	    fatal "malformed or empty archive";
	}
#END ZIPARCHIVE
#BEGIN TEXTARCHIVE
	if ($hdr eq "TXD\n") {
	    (my $bar = <DATA>) ne '' or fatal "malformed archive";
	    my ($fname, $dat);
	    {
		local $/ = "\n" . $bar;
		chomp ($fname = <DATA>);
                chomp ($dat = <DATA>);
	    }
	    $source{$fname} = $dat;
	    next;
	} elsif ($hdr eq "TXE\n") {
	    last;
	}
#END TEXTARCHIVE
	fatal "malformed data";
    }
    close DATA;
}

sub provide {
    my ($self, $fname) = @_;
    if (exists($source{$fname})) {
	my $str = $source{$fname};
	open my $fh, "<", \$str or fatal "string IO failed.";
	return \("#line 1 " . __FILE__  . "/$fname\n"), $fh;
    }
    return undef;
}

prepare();
unshift @INC, \&provide;
#BEGIN INHIBITLIB

$source{'lib.pm'} = "package lib; sub import () { } 1;" if $CONFIG{inhibit_lib};
#END INHIBITLIB

#BEGIN MAIN
package main {
    my $main = $CONFIG{main};
    @@PKGNAME@@::fatal "missing main module in archive" unless exists $@@PKGNAME@@::source{$main};
    do $main;
    die $@ if $@;
}
#END MAIN

@@POD@@

package @@PKGNAME@@;
__DATA__
EOS

1;

=head1 REFERENCE

L<Homepage|https://www.github.com/yoiwa-personal/zipperlapp>

L<Python's "zipapp" implementation|https://docs.python.org/en/3/library/zipapp.html>

=head1 AUTHOR/COPYRIGHT

Copyright 2019-2025 Yutaka OIWA <yutaka@oiwa.jp>.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
L<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

As a special exception to the Apache License, outputs of this
software, which contain a code snippet copied from this software, may
be used and distributed under terms of your choice, so long as the
sole purpose of these works is not redistributing the code snippet,
this software, or modified works of those.  The "AS-IS BASIS" clause
above still applies in these cases.

(In short, you can freely use this software to package YOUR software
and the Apache License will not apply for YOURS.)

=cut
