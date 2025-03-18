#!/usr/bin/perl
# zipperlapp - Make an executable perl script bundle using zip archive
#
# https://github.com/yoiwa-personal/zipperlapp/
#
# Copyright 2019-2025 Yutaka OIWA <yutaka@oiwa.jp>.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# As a special exception to the Apache License, outputs of this
# software, which contain a code snippet copied from this software, may
# be used and distributed under terms of your choice, so long as the
# sole purpose of these works is not redistributing the code snippet,
# this software, or modified works of those.  The "AS-IS BASIS" clause
# above still applies in these cases.

use 5.024;
use strict;
use Fcntl; # for sysopen constants
use File::Basename "basename";
use File::Find ();
use Data::Dumper ();
use Getopt::Long qw(:config posix_default bundling permute);

#use Pod::Usage;
sub pod2usage {
    require Pod::Usage;
    goto &Pod::Usage::pod2usage;
}

use re '/saa'; # strictly byte-oriented, no middle \n match

use FindBin;
use if (! scalar %ZipPerlApp::), lib => $FindBin::Bin;
use ZipTiny;

our $VERSION = "2.0.0";

our $debug = 0;

my $compression = 0;
my $bzipcompression = 0;
my $out = undef;
my $mainopt = undef;
my $copy_pod = 0;
my $quote_pod = 0;
my $protect_pod = 2;
my $textarchive = 0;
my $base64 = 0;
my $trimlibname = 1;
my $searchincludedir = 1;
my @includedir = ();
my $inhibit_lib = 0;
our $sizelimit = 1048576 * 64;

GetOptions(
	   'compress|C:9' => \$compression,
	   'bzip' => \$bzipcompression,
	   'output|o=s' => \$out,
	   'main|m=s' => \$mainopt,
	   'copy-pod|p!' => \$copy_pod,
	   'quote-pod!' => \$quote_pod,
	   'protect-pod!' => \$protect_pod,
	   'base64|B' => \$base64,
	   'text-archive|T' => \$textarchive,

	   'includedir|I:s' => \@includedir,
	   'search-includedir!' => \$searchincludedir,
	   'trim-includedir!' => \$trimlibname,

	   'inhibit-use-lib' => \$inhibit_lib,

	   "sizelimit=i" => \$sizelimit,

	   'debug:+' => \$debug,

	   'help' => sub { pod2usage(1) }) or do { pod2usage(2); exit 1 };

if (!!$quote_pod + !!$base64 >= 2) {
    print STDERR "Error: --quote_pod and --base64 are exclusive\n";
    pod2usage(2);
}
if (!!$compression + !!$bzipcompression >= 2) {
    print STDERR "Error: --compression and --bzip are exclusive\n";
    pod2usage(2);
}
unless ($compression =~ /\A[0-9]|Zb\z/) {
    print STDERR "Error: bad --compress=$compression (should be 0 to 9)";
    pod2usage(2);
}

if ($compression eq 'Zb' || $bzipcompression) {
    $compression = 'bzip';
}

if (@ARGV == 0) {
    if (defined $mainopt) {
	unshift @ARGV, ($mainopt);
    } else {
	pod2usage(2);
    }
}

$ZipTiny::DEBUG = $debug;
$ZipTiny::SIZELIMIT = $sizelimit;

my $possible_out = undef;
my $main = undef;
my $dir = undef;
my $maintype = 0;

# determine main file and output name
# argument types:
#   type 1: a single directory dir, no main specified
#     -> include all files in dir, search for the main file (single .pl), output dir.plz
#   type 2: a set of files
#     -> specified files included, first argument must be .pl file, output first.plz
#   type 3: main file specified
#     -> specified files included, main file must be included, output main.plz

my @files = ();
my %enames = {};

sub canonicalize_filename {
    my ($fname, $fixedprefix) = @_;

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
    if ($trimlibname) {
	my @includedir = @includedir;
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

sub add_file {
    my ($fname, $fixedprefix) = @_;
    # behavior of main mode:
    #  1: add if *.pl, duplication is error
    #  2: add if first
    #  3: noop

    my ($fname, $ename) = canonicalize_filename($fname, $fixedprefix);
    die "cannot find $fname: $!" unless -e $fname;
    die "$fname is not a plain file" unless -f $fname;
    if (exists $enames{$ename}) {
	if ($fname ne $enames{$ename}) {
	    die "duplicated files: $fname and $enames{$ename} will be same name in the archive";
	} else {
	    # skip;
	}
    } else {
	if ($maintype == 1) {
	    if ($ename =~ /\.pl$/s) {
		die "found two .pl files: $main and $ename\n" if defined $main;
		$main = $ename;
	    }
	} elsif ($maintype == 2) {
	    $main = $ename unless defined $main;
	    $possible_out = $ename unless defined $possible_out;
	}
	$enames{$ename} = $fname;
	push @files, [$ename, $fname];
    }
}

sub add_dir {
    my ($fname, $prefix) = @_;
    File::Find::find
	({wanted => sub {
	      my $f = $File::Find::name;
	      if ($f =~ /\.p[lm]\z/s && !($f =~ m((\A|\/)\.[^\/])s)) {
		  add_file($f, $prefix);
	      }
	  },
	  no_chdir => 1
	 }, $fname);
}

for (@includedir) {
    $_ =~ s(/+\z)()s;
}

if (defined $mainopt) {
    $main = $mainopt;
    $possible_out = $main;
    $maintype = 3;
}

if (-d $ARGV[0]) {
    die "if the first file is a directory, it must be the only argument" unless (scalar @ARGV == 1);
    $dir = $ARGV[0];
    $dir =~ s(/+\z)()s;
    $possible_out = $dir;
    unshift @includedir, ($dir);
    $searchincludedir = 0;
    $trimlibname = 1;
    $maintype = 1 unless $maintype == 3;
} else {
    $maintype = 2 unless $maintype == 3;
}

if (defined $mainopt) {
    $main = canonicalize_filename($main);
}

for (@ARGV) {
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
	add_file($_, $foundprefix);
    } elsif (-d $_) {
	s(\/+\z)()s;
	add_dir($_, $foundprefix);
    } else {
	die "file not found: $_" unless -e $_;
	die "unknown type of argument: $_\n";
    }
}

if (! defined $out) {
    if (!$possible_out or $possible_out eq '.') {
	die "cannot guess name";
    }
    $out = basename $possible_out; # for a while
    $out =~ s/(\.pl)?\z/\.plz/;
    say "output is set to: $out";
}

die "no main files guessed" unless (defined $main);

if ($maintype != 3 || $mainopt ne $main) {
    say "main file set to: $main";
}

if (! exists $enames{$main}) {
    die "no main file $main will be contained in archive";
}

for my $f (@files) {
    printf "%s <- %s\n", $f->[0], $f->[1];
}

my $pod = "";
my $podsw = 0;

# if ($inhibit_lib) { push @files, (['lib.pm', \'1;']);

@files = ZipTiny::prepare_zip(@files);

# consult main script for pod and she-bang

# this depends on internal data structure of ZipTiny
my ($mainent) = grep { $_->{FNAME} eq $main } @files;

die unless defined $mainent;
open MAIN, "<", \($mainent->{CONTENT}) or die "read main: $!";
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

# initial try with minimal quotations

my ($headerdata, $zipdata) = create_sfx(\@files, $shebang, $pod, $textarchive, $compression, $base64, 0, ($protect_pod == 1));

if ((($protect_pod == 2) || $quote_pod) && quote_required($zipdata)) {
    # retry with quotations
    print STDERR "detected unquoted pods -- retry with quoting/protection enabled\n" if $debug;
    $protect_pod = !$quote_pod;
    ($headerdata, $zipdata) = create_sfx(\@files, $shebang, $pod, $textarchive, $compression, $base64, $quote_pod, !$quote_pod);
}

print "writing to $out\n";

sysopen(O, $out, O_WRONLY | O_CREAT | O_TRUNC, $mode) or die "write: $!";

print O $headerdata or die "$!";
print O $zipdata or die "$!";
close O or die "$!";
exit(0);

sub create_sfx {
    my ($files, $shebang, $pod, $textarchive, $compression, $base64, $quote, $protect_pod) = @_;
    my (@files) = @$files;

    my $sfx_embed = (!$textarchive && !$quote && !$base64);

    # prepare launching script

    print STDERR "create_sfx: b64 $base64, quote $quote, protect $protect_pod\n" if $debug;
    if ($protect_pod) {
	if ($pod ne "" or $protect_pod == 1) {
	    my $podsig;
	    while () {
		$podsig = sprintf("POD_ESCAPE_ZipPerlApp_%08d", int(rand(100000000)));
		last unless (grep { index($_->{CONTENT}, $podsig) != -1 or
				      index($_->{FNAME}, $podsig) != -1 } @files);
		print "protect_pod: signature $podsig is not well... retrying\n" if $debug >= 2;
	    }
	    print "protect_pod: signature $podsig\n" if $debug >= 2;
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

    our %config = (main => $main, dequote => $quote, sizelimit => $sizelimit);
    $config{inhibit_lib} = 1 if $inhibit_lib;

    our @features = ("MAIN",
		     ($quote ? ("QUOTE") : ()),
		     ($compression ? ("COMPRESSION") : ()),
		     ($bzipcompression ? ("BZIPCOMPRESSION") : ()),
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
	$zipdata = create_textarchive(@files);
    } else {
	my $offset = 0;
	if ($sfx_embed) {
	    $offset = length($header);
	}
	print STDERR "offset -> $offset\n" if $debug;
	$zipdata = ZipTiny::make_zip(\@files,
			  COMPRESS => $compression,
			  OFFSET => $offset,
			  HEADER => "",
			  TRAILERCOMMENT => "");
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

sub create_textarchive() {
    my $zipdat = "";
    local $/;
    for my $e (@_) {
	# this depends on internal data structure of ZipTiny
	my $sep;
	my $fname = $e->{FNAME};
	my $dat = $e->{CONTENT};
	for(;;) {
	    $sep = sprintf("----TEXTARCHIVE-%08d----------------", int(rand(100000000)));
	    last if index($dat, $sep) == -1 and index($fname, $sep) == -1;
	    print STDERR "create_textarchive: separator $sep is not well... retrying\n" if $debug >= 2;
	}
	print STDERR "create_textarchive: separator $sep for $fname\n" if $debug >= 2;
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

$source{'lib.pm'} = "package lib; sub import () { } 1;";
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

=head1 NAME

zipperlapp - Make an executable perl script bundle using zip archive

=head1 SYNOPSIS

  zipperlapp [options] {directory | file ...}

  Options:
    --main              -m module    specify main entry module
    --output=file       -o file      output file
    --compress[={0-9}]  -C[{0-9}]    apply compression
    --base64            -B           encode with BASE64
    --text-archive      -T           use text-based archive format
    --copy-pod          -p           copy pod from main module
    --includedir        -I           locations to find input files
    --protect-pod
    --quote-pod
    --help                           show help

=head1 DESCRIPTION

This program bundles several Perl module files and wraps them as an
"executable" zip archive.  An output file can be invoked as a Perl
script, or (if a source file contains a C<"#!"> line) as a directly
executable command.  Also, it can be handled by (almost every) zip
archiver as an "sfx" file.

Inside Perl scripts, all files contained in the archive is put in the
top of the searched library set.  The program can simply use C<use> or
C<require> statements to load the contained modules, without modifying
the C<@INC> variable.

=head1 ARGUMENTS

=over 8

=item B<directory>

If there are only one argument and it is a name of directory, All
C<*.pl>/C<*.pm> files under that directory (recursively) are included.
The directory name itself is truncated.

=item B<files>

Otherwise, all files specified in the argument are included.

=back

=head1 OPTIONS

=head2 INPUT/OUTPUT OPTIONS

=over 8

=item B<--main, -m>

Specify the main module which is automatically "require"-d.  Also, a
"she-bang" line and continuous comment lines at the top of main module
are copied to the output.

If one and only one script with extension C<'.pl'> is contained in the
input set of modules, it is automatically detected.  Otherwise, the
main module must be explicitly specified.

=item B<--includedir, -I>

Specify the locations to search input files, in addition to the current
directory.
If this option is specified multiple times, the files will be searched
in order of the specifications.

This option will have two kinds of separate effect; if C<'-Ilib File.pm'>
is speficied in the command line, as an example:

=over 2

=item *

the command will include C<'lib/File.pm'> to the archive, if C<'File.pm'>
does not exist.  This behavior can be disabled by specifing
C<'--no-search-includedir'>.

=item *

the file C<'lib/File.pm'> will be included to the archive as C<'File.pm'>,
triming the library part of the name. This happens either when the file is
speficied explicitly or through C<-I> option.
This behavior can be disabled by specifing
C<'--no-trim-includedir'>.

If two or more files will share the same name after this triming,
it will be an error and rejected.

=back

=item B<--output, -o>

Specify the name of the output file.

If omitted, either the name of the source directory or the base name
of the main module is taken, with a postfix C<'.plz'> is appended.

It is always safe to specify the output file.

=back

=head2 ARCHIVE OPTIONS

=over 8

=item B<--compress>, B<-C>

Specify the compression level for the Deflate algorithm.

If C<-C> is specified without a digit, the highest level 9 is set.

If not specified at all, the files are not compressed.
It makes the content of the script almost transparently visible.
Also, the script will not load zlib and other libraries run-time.

Outputs generated without C<-C> options will not contain decompression
functionality, that means you need to add C<-0> or similar options
when you modify the contents with zip archivers.

=item B<--bzip>

Use BZIP2 algorithm for compression.

This compression method is not common, but it was implemented around
2003 (PKzip 4.6) to 2006 (Infozip 3.0f18), and most current
implementation of zip archive supports bzip2 compression.

=item B<--base64, -B>

It will encode the embedded ZIP archive with Base64 encoding.  It
makes the script about 40% larger and also loses zip-transparent
behavior as an sfx file, in trade for making the output script
completely ASCII-clean.

=item B<--text-archive, -T>

It will use its own plaintext archive format for storing modules.
The output will not be compatible with zip archivers.

Output scripts generated with this option will be plaintext, if all
input modules are plaintext in ASCII or some specific ASCII-compatible
encoding.  In addition to that, it is easier to modify its content by
hand, because the format uses no byte-oriented structure.

This format will be useful when (1) you need to edit module sources
embedded in outputs by text editors, or (2) when the whole source code
must be transparently visible for auditing or inspections (if even
C<-C0> is unsatisfactory).

The option combination with C<-B> is possible, but it is not very
meaningful.

=back

=head2 POD HANDLING OPTIONS

=over 8

=item B<--copy-pod, -p>

If specified, it will copy all pod (Perl's plain old document format)
sections in the main module to the output script.

Alternatively, when compression (-C) is not used, it is likely that
any pod-using modules may see pod sections from all of embedded
modules within the zip file structure.  If only your main module
contains a pod, you may be possibly depend on that "behavior" and not
using this option, although it is not a guaranteed behavior.

=item B<--protect-pod>

Unless either compression (-C) or Base64 encoding (-B) is used, pod
processors may see pod sections embedded in the original source
scripts, within the zip archive; It may either be a good or not a good
thing.

If C<--protect-pod> is specified, the command will insert a small
snippet of Pod to the output so that most pod processors will skip
such "ghost" of pods.  The process is done only when it is actually
needed.

This option is automatically enabled when C<--copy-pod> is used.
If unwanted, you can specify C<--no-protect-pod>.

=item B<--quote-pod>

It will tweak the embedded ZIP archive so that the encoded script will
not contain any active pod specification.  The tweak is performed only
when it is really required, but if done, the output will loose
zip-transparency.

In most circumstances, C<--protect-pod> or C<-C> is enough, or
C<--base64> is more reliable.

=back

=head2 OTHER OPTIONS

=over 8

=item B<--inhibit-use-lib>

An experimental option.  It will nullify effect of C<'use lib ...'>,
so that local files not included in the archive will not be read.
It will break if any system library uses C<'lib'> pragma, thus
use of the snippet in the APIS section is recommended.

=back

=head1 APIS

There are currently no APIs visible to user scripts except import
hooks.  Package C<ZipPerlApp> is provided in the zipped script, so if
you need to change some behavior upon packaging, something like

    use FindBin;
    use if (! scalar %ZipPerlApp::), lib => $FindBin::Bin;

or

    BEGIN {
        if (! scalar %ZipPerlApp::) {
            require FindBin;
            require lib;
            lib->import($FindBin::Bin);
        }
    }

can be used.

=head1 LIMITATIONS

=over 2

=item *

Only pure Perl scripts or modules can be loaded from zip archive. For
example, autoloading (*.al) or dynamic loading (*.so, *.dll) will not
be available.

=item *

C<__FILE__> tokens in the archived file will have virtual values of
C<"I<archivename>/I<modulename>">, which does not exist in the real
file system.  This also holds for the "main script" to be referred to.
It means that the common technique for making a "dual-use"
module/script

    if (__FILE__ eq $0)

will not work.  Instead, please provide a short entry script as a main
script.

=item *

For compactness (and minimal dependency only to core modules), an
embedded parser for zip archives is extremely simple.  It can not
parse archives with any advanced features or partially-broken
archives.  If you modify the packed archive using usual zip archivers,
be aware of that.

=item *

All files are decoded into the memory at the beginning of the program
execution.  It is not wise to include unneeded files into the archive.

=back

=head1 IMPLEMENTATION

A zip archive of module files are stored in the C<__DATA__> section.
A minimal parser for Zip archives is embedded to the output script,
and it will extract the source codes of all modules to an on-memory
storage at the start-up.  An "import hook" subroutine is put into
Perl's C<@INC> facility to load those modules by C<require> or C<use>.

This enables use of C<__DATA__> sections in each included module.

=head1 DEPENDENCIES

Zipped scripts generated by this command will not depend on any
external modules, except those included in the Core modules of Perl
distributions as of version 5.24.1.

=head1 COMPARISON

C<PAR> is a "Perl Archive Toolkit" containing a similar tool, "C<pp>"
- PAR Packager.  It can be used to generate a standalone executable
from several perl files.  C<PAR> provides very richer functionality
compared to this tool: embedding binary shared objects, embedding even
Perl interpreter, etc.  At the same time, the behavior of a
C<PAR>-generated executable is quite complex: it uses temporary
directories and file caches, it depends on large non-core modules, and
it loads a lot of additional modules in start-up.  It introduces a
potential security attack risks, especially with scripts running with
elevated privileges e.g. with C<sudo>.

The pros and cons of C<zipperlapp> is the opposite: it can not
generate interpreter-embedded executables, it does not support shared
objects, and it does not support automatic searches of dependenty
libraries.  But, it runs quite simply and efficiently: it depends on
only the minimum numbers of core modules (even with I<no> binary
modules when option C<-C0> or C<-T> is used), and it uses no temporary
files and directories at all (on-memory store is used instead).  It is
very beneficial for small, trusted scripts which value transparency
and simplicity.

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
