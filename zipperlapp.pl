#!/usr/bin/perl
# zipperlapp - Make an executable perl script bundle using zip archive
#
# https://github.com/yoiwa-personal/zipperlapp/
#
# Copyright 2019 Yutaka OIWA <yutaka@oiwa.jp>.
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
use Fcntl;
use File::Basename "basename";
use File::Temp "tempfile";
use File::Find ();
use Data::Dumper ();
use Getopt::Long qw(:config posix_default bundling permute);
use Pod::Usage;
use Cwd;

use FindBin;
use if (! scalar %ZipPerlApp::), lib => $FindBin::Bin;
use ZipTiny;

our $VERSION = "1.99.1";

my $debug = 0;
my $compression = 0;
my $bzipcompression = 0;
my $out = undef;
my $mainopt = undef;
my $copy_pod = 0;
my $quote_pod = 0;
my $protect_pod = 1;
my $textarchive = 0;
my $base64 = 0;

GetOptions(
	   'compress|C:9' => \$compression,
	   'bzip' => \$bzipcompression,
	   'output|o:s' => \$out,
	   'main|m:s' => \$mainopt,
	   'copy-pod|p' => \$copy_pod,
	   'quote-pod' => \$quote_pod,
	   'protect-pod' => sub { $protect_pod = 2 },
	   'no-protect-pod' => sub { $protect_pod = 0 },
	   'base64|B' => \$base64,
	   'text-archive|T' => \$textarchive,
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

my $cwd = getcwd;

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
    my ($fname, $ismain) = @_;
    die "$fname: name is absolute\n" if $fname =~ m@^/@s;
    $fname =~ s@^(\./)+@@s;
    while ($fname =~ s@/./@/@s) {}
    while ($fname =~ s@(/[^/]+/../)@/@s) {}
    die "$fname: name contains ..\n" if $fname =~ m@(^|/)../@s;
    return ($fname, $fname);
}

sub add_file {
    my ($fname, $trim) = @_;
    # behavior of main mode:
    #  1: add if *.pl, duplication is error
    #  2: add if first
    #  3: noop

    my ($fname, $ename) = canonicalize_filename($fname);
    die "cannot find $fname: $!" unless -e $fname;
    die "$fname is not a plain file" unless -f $fname;
    if (exists $enames{$ename}) {
	if ($fname ne $enames{$ename}) {
	    die "duplicated files: $fname and $enames{$ename} will be same name in the archive";
	} else {
	    # skip;
	}
    } else {
	$ename =~ s(^\Q$trim\E)()s if defined $trim;
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
	push @files, [$fname, $ename];
    }
}

sub add_dir {
    my ($fname, $trim) = @_;
    File::Find::find
	({wanted => sub {
	      my $f = $File::Find::name;
	      return if $f =~ m((^|\/)\.[^\/]*$)s;
	      add_file($f, $trim) if $f =~ /\.p[lm]$/s;
	  },
	  no_chdir => 1
	 }, $fname);
}

if (defined $mainopt) {
    $main = $mainopt;
    $possible_out = $main;
    $maintype = 3;
}

if (-d $ARGV[0]) {
    die "if the first file is a directory, it must be the only argument" unless (scalar @ARGV == 1);
    $dir = $ARGV[0];
    $possible_out = $ARGV[0];
    $maintype = 1;
} else {
    $maintype = 2;
}

for (@ARGV) {
    if (-f $_) {
	add_file($_);
    } elsif (-d $_) {
	s@\/+$@@s;
	add_dir($_, ($maintype == 1 ? "$dir/" : undef));
    } else {
	die "unknown type of argument: $_\n";
    }
}

if (! defined $out) {
    if (!$possible_out or $possible_out eq '.') {
	die "cannot guess name";
    }
    $out = basename $possible_out; # for a while
    $out =~ s/(\.pl)?$/\.plz/;
    say "output is set to: $out";
}
if ($maintype != 3) {
    say "main file set to $main";
}

my $zipdir = $cwd;

die "no main files guessed" unless (defined $main);

if (! exists $enames{$main}) {
    die "no main file $main will be contained in archive";
}

for my $f (@files) {
    printf "%s <- %s\n", $f->[1], $f->[0];
}

my $pod = "";
my $podsw = 0;

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

my $mode = ($shebang =~ /\A#!/ ? 0777 : 0666);

# initial try with minimal quotations

my ($headerdata, $zipdata) = create_sfx(\@files, $shebang, $pod, $textarchive, $compression, $base64, 0, ($protect_pod == 2));

if ((($protect_pod == 1) || $quote_pod) && quote_required($zipdata)) {
    # retry with quotations
    print STDERR "detected unquoted pods -- retry with quoting/protection enabled\n" if $debug;
    $protect_pod = !$quote_pod;
    ($headerdata, $zipdata) = create_sfx(\@files, $shebang, $pod, $textarchive, $compression, $base64, $quote_pod, !$quote_pod);
}

print "writing to $out\n";

chdir $zipdir or die "chdir: $!";

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
	$pod .= "\n=begin POD_ESCAPE_ZipPerlApp\n\n=cut\n"
	  if ($pod ne "" or $protect_pod > 1);
    } elsif ($pod ne "") {
	$pod .= "=cut\n";
    }
    if ($base64) {
	$quote = 'base64';
    } elsif ($quote) {
	$quote = 'quote';
    }

    # prepare launching script

    our %config = (main => $main, dequote => $quote);
    our @features = ("MAIN",
		     ($quote ? ("QUOTE") : ()),
		     ($compression ? ("COMPRESSION") : ()),
		     ($bzipcompression ? ("BZIPCOMPRESSION") : ()),
		     ($textarchive ? ("TEXTARCHIVE") : ("ZIPARCHIVE")),
		    );

    our $script = &script(\@features,
			  CONFIG => Data::Dumper->Dump([\%config], ['*CONFIG']),
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
			  TRAILER => "");
    }
    if ($quote eq 'quote') {
	$zipdata =~ s/^=/==/mg;
	# quoting breaks archive structure.
	$zipdata =~ s/PK([\0-\37][\0-\37])/PK\0$1/g;
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
	}
	$zipdat .= "TXD\n$sep\n$fname\n$sep\n$dat\n$sep\n";
    }
    $zipdat .= "TXE\n";
    return $zipdat;
}

sub quote_required {
    my ($zipdat) = @_;
    my $count = ($zipdat =~ m/\n=/s);
    return $count;
}

#my $embpod_maybe = ($zipdat =~ /^(=[a-zA-Z])/m);


sub script () {
    my ($features, %replace) = @_;
    my $script = &script_body();

    1 while $script =~ s[^#BEGIN\ ([A-Z]+)\n(.*?)^#END\ \1\n]
			[grep ($_ eq $1, @$features) ? $2 : ""]mseg;
    $script =~ s/@@([A-Z]+)@@/%replace{$1}/eg;
    return $script;
}

sub script_body () { <<'EOS'; }
# This script is packaged by zipperlapp
use 5.024;
no utf8;
use strict;
package @@PKGNAME@@;

our %source;
#BEGIN COMPRESSION
my $zlib_loaded = 0;
#END COMPRESSION
#BEGIN BZIPCOMPRESSION
my $bzlib_loaded = 0;
#END BZIPCOMPRESSION
our @@CONFIG@@

sub fatal {
    die("error processing zipped script: @_")
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
	    fatal "unsupported: deferred length" if ($flags & 0x8 != 0);
	    my $fname = read_data($fnamelen);
	    my $ext = read_data($extlen);
	    my $dat = read_data($csize);
	    if ($comp == 0) {
		fatal "malformed data: bad length" if $csize != $size;
#BEGIN COMPRESSION
	    } elsif ($comp == 8) {
		unless ($zlib_loaded) {
		    require IO::Uncompress::RawInflate;
		    require Compress::Zlib;
		    $zlib_loaded = 1;
		}
		open my $fh, "<", \$dat or fatal "string IO failed.";
		my $buf = '';
		my $z = IO::Uncompress::RawInflate->new($fh, Transparent => 0)
		  or fatal "IO::Uncompress::RawInflate failed: $IO::Uncompress::Inflate::InflateError\n";
		my $status = $z->read($buf, $size);
		fatal "Inflate failed: length mismatch" if $status != $size;
		fatal "Inflate failed: crc mismatch" unless Compress::Zlib::crc32($buf) == $crc;
		$dat = $buf;
#END COMPRESSION
#BEGIN BZIPCOMPRESSION
	    } elsif ($comp == 12) {
		unless ($bzlib_loaded) {
		    require IO::Uncompress::Bunzip2;
		    require Compress::Zlib;
		    $bzlib_loaded = 1;
		}
		open my $fh, "<", \$dat or fatal "string IO failed.";
		my $buf = '';
		my $z = IO::Uncompress::Bunzip2->new($fh)
		  or fatal "IO::Uncompress::Bunzip2: $IO::Uncompress::Bunzip2::Bunzip2Error\n";
		my $status = $z->read($buf, $size);
		fatal "Inflate failed: length mismatch" if $status != $size;
		fatal "Inflate failed: crc mismatch" unless Compress::Zlib::crc32($buf), $crc;
		$dat = $buf;
#END BZIPCOMPRESSION
	    } else {
		fatal "unknown compression";
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

=head2 ARGUMENTS

=over 8

=item B<directory>

If there are only one argument and it is a name of directory, All
C<*.pl>/C<*.pm> files under that directory (recursively) are included.
The directory name itself is truncated.

=item B<files>

Otherwise, all files specified in the argument are included.

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
            require lib $FindBin::Bin;
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

=head1 REFERENCE

L<Homepage|https://www.github.com/yoiwa-personal/zipperlapp>

L<Python's "zipapp" implementation|https://docs.python.org/en/3/library/zipapp.html>

=head1 AUTHOR/COPYRIGHT

Copyright 2019 Yutaka OIWA <yutaka@oiwa.jp>.

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
