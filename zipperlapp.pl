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

use ZipPerlApp::SFXGenerate;

our $VERSION = "2.1.0";

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

	   'sizelimit=i' => \$sizelimit,
	   'random-seed=i' => sub { srand $_[1] },
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

my $progout_fh = \*STDOUT;

if ($out eq '-') {
    print STDERR "output is stdout\n";
    $out = \*STDOUT;
    $progout_fh = \*STDERR;
}

ZipPerlApp::SFXGenerate->zipperlapp
  (
   \@ARGV,
   out => $out,
   mainopt => $mainopt,
   compression => $compression,
   base64 => $base64,
   textarchive => $textarchive,
   copy_pod => $copy_pod,
   protect_pod => $protect_pod,
   quote_pod => $quote_pod,
   includedir => \@includedir,
   searchincludedir => $searchincludedir,
   trimlibname => $trimlibname,
   sizelimit => $sizelimit,
   progout_fh => $progout_fh,
   inhibit_lib => $inhibit_lib,
   debug => $debug
  );
exit(0);


=head1 NAME

zipperlapp - Make an executable perl script bundle using zip archive

=head1 SYNOPSIS

  zipperlapp [options] {directory | file ...}

  Options:
    --main              -m module    specify main entry module
    --output=file       -o file      output file

    --includedir        -I           locations to find input files
    --[no-]search-includedir         search files from -I library directories
    --[no-]trim-includedir           trim -I library paths from names

    --compress[={0-9}]  -C[{0-9}]    apply compression
    --bzip                           apply Bzip2 compression
    --base64            -B           encode with BASE64
    --text-archive      -T           use text-based archive format

    --copy-pod          -p           copy pod from main module
    --[no-]protect-pod               hide unwanted pods from processors
    --quote-pod                      quote pods in archive (zip incompatible)

    --inhibit-use-lib                disable 'use lib' pragma
    --random-seed=...                specify random seed

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

specifies the main module which is automatically "require"-d.  Also, a
"she-bang" line and continuous comment lines at the top of main module
are copied to the output.

If one and only one script with extension C<'.pl'> is contained in the
input set of modules, it is automatically detected.  Otherwise, the
main module must be explicitly specified.

=item B<--includedir, -I>

specifies the locations to search input files, in addition to the current
directory.
If this option is specified multiple times, the files will be searched
in order of the specifications.

This option will have two kinds of separate effects; when C<'-Ilib File.pm'>
is speficied in the command line, as an example:

=over 2

=item *

The command will include C<'lib/File.pm'> to the archive, if C<'File.pm'>
does not exist.  This behavior can be disabled by specifing
C<'--no-search-includedir'>.

=item *

The file C<'lib/File.pm'> will be included to the archive as C<'File.pm'>,
triming the library part of the name. This happens either when the file is
speficied explicitly or through C<-I> option.
This behavior can be disabled by specifing
C<'--no-trim-includedir'>.

If two or more files will share the same name after this triming,
it will be rejected as an error.

=back

=item B<--output, -o>

specifies the name of the output file.

If omitted, either the name of the source directory or the base name
of the main module is taken, with a postfix C<'.plz'> is appended.

It is always better and safer to specify the output file.

A single hyphen (C<->) will let output go to the standard output.

=back

=head2 ARCHIVE OPTIONS

=over 8

=item B<--compress>, B<-C>

specifies the compression level for the Deflate algorithm.

If C<-C> is specified without a digit, the highest level 9 is set.

If not specified at all, the files are not compressed.
It makes the content of the script almost transparently visible.
Also, the script will not load zlib and other libraries run-time.

Outputs generated without C<-C> options will not contain decompression
functionality, that means you need to add C<-0> or similar options
when you modify the contents with zip archivers.

=item B<--bzip>

specifies to use BZIP2 algorithm for compression.

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

The combination with the C<-B> option is possible but not very
meaningful.

=back

=head2 POD HANDLING OPTIONS

=over 8

=item B<--copy-pod, -p>

If specified, it will copy all POD (Perl's plain old document format)
sections in the main module to the output script.
This option is requored when the script uses the POD data of itself
e.g. by C<Pod::Usage>.

Alternatively, when compression (-C) is not used, it is likely that
any pod-using modules may see pod sections from all of embedded
modules within the zip file structure.  If only your main module
contains a pod, you may be possibly depend on that "behavior" and not
using this option, although it is not a reliable behavior.

=item B<--protect-pod>

specifies to protect any POD data inside the zip archive from being
processed.

Unless either compression (-C) or Base64 encoding (-B) is used, POD
sections in the original source scripts within the zip archive may be
visible to POD data processors; it may either be or not be a good
thing, depending on the situation.

If C<--protect-pod> is specified, a small POD is inserted to the output
so that most pod processors will skip such ghost of PODs.

This option is automatically enabled, when C<--copy-pod> is used and
a POD directive is actually contained in the archive binary.
If the process is not wanted, you can specify C<--no-protect-pod>.

=item B<--quote-pod>

It will tweak the embedded ZIP archive so that the encoded script will
not contain any active pod specification.  The tweak is performed only
when it is really required, but if done, the output will loose
zip-transparency.

In most circumstances, either C<--protect-pod> or C<-C> is enough, or
when zip-transparency is not needed, C<--base64> is more reliable option.

=back

=head2 OTHER OPTIONS

=over 8

=item B<--random-seed>

specifies a seed integer for pseudorandom number generators.  Some
features (e.g. C<--text-archive> or C<--protect-pod>) use random
numbers to generate unique byte sequences in the archive.  This makes
output archives for the same set of inputs to differ time-to-time.
Specifying a random seed will make output somewhat deterministic.
However, it is not a strong guarantee; the output may still differ by
small change of inputs or even small environmental changes such as use
of different machines or system library updates.  Main expected use of
this option is to put the archive outputs to version control systems
such as git or subversion, making differences as small as possible.

In Perl, the seed will be an 32-bit integer.

=item B<--inhibit-use-lib>

An experimental option:  it will nullify effect of C<'use lib ...'>,
so that local files not included in the archive will not be read.
It will break if any system library uses C<'lib'> pragma, thus
use of the snippet in the APIS section is recommended.

=back

=head1 APIS

There are currently no APIs visible to user scripts except import
hooks.  The package C<ZipPerlApp> is provided in the zipped script, so
if you need to change some behavior upon packaging, something like

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

can be used.  For a main entry script,

    use FindBin;
    use if (__FILE__ eq $0), lib => $FindBin::Bin;

also works.

=head1 LIMITATIONS

=over 2

=item *

Only pure Perl scripts or modules can be loaded from zip archives. For
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
execution.  It is not wise to include unneeded files (especially large
ones) into the archive.

=item *

If C<DATA> handle is used, the marker token shall be C<__DATA__>, not
C<__END__>.  This is the defined behavior of Perl.

=back

=head1 IMPLEMENTATION

A zip archive of module files are stored in the C<__DATA__> section.
A minimal parser for Zip archive format is embedded to the beginning
of the output script, and it will extract the source codes of all
modules to an on-memory storage at the start-up.  An import hook
subroutine is put into Perl's C<@INC> facility to load those modules
by C<require> or C<use>.

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
only the minimum numbers of core modules (even with I<no> external
binary libraries when option C<-C0> or C<-T> is used), and it uses no
temporary files and directories at all (on-memory store is used
instead).  It is very beneficial for small, trusted scripts which
value transparency and simplicity.

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
