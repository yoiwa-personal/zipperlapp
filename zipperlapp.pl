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

our $VERSION = "2.2.1";

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

	   'version' => sub { print "$VERSION"; exit 0; },
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

=encoding utf-8

=head1 NAME

zipperlapp - Create executable Perl script bundles using ZIP archives

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

    --copy-pod          -p           copy POD from main module
    --[no-]protect-pod               hide unwanted PODs from processors
    --quote-pod                      quote PODs in archive (zip incompatible)

    --inhibit-use-lib                disable 'use lib' pragma
    --random-seed=...                specify random seed

    --help                           show help

=head1 DESCRIPTION

This program bundles several Perl module files and wraps them into an
"executable" ZIP archive. An output file can be invoked as a Perl
script or (if a source file contains a C<"#!"> line) as a directly
executable command. It can also be handled by almost any ZIP
archiver as a self-extracting ("sfx") archive.

Inside Perl scripts, all files contained in the archive are placed at
the beginning of the library search path. The bundled script can
simply use C<use> or C<require> statements to load the contained
modules, without modifying the C<@INC> variable.


=head1 ARGUMENTS

=over 8

=item B<directory>

If there is only one argument and it is the name of a directory, all
C<*.pl>/C<*.pm> files under that directory (recursively) are included.
The directory name itself is truncated.

=item B<files>

Otherwise, all files specified in the arguments are included.

=back

=head1 OPTIONS

=head2 INPUT/OUTPUT OPTIONS

=over 8

=item B<--main, -m>

Specifies the main module which is automatically C<require>-d. Also, a
shebang line and contiguous comment lines at the top of the main module
are copied to the output.

If one and only one script with the extension C<'.pl'> is contained in the
input set of modules, it is automatically detected. Otherwise, the
main module must be explicitly specified.

=item B<--includedir, -I>

Specifies the locations to search for input files, in addition to the current
directory.
If this option is specified multiple times, the files will be searched
in order of specification.

This option has two separate effects; for example, when C<'-Ilib File.pm'>
is specified on the command line:

=over 2

=item *

The command will include C<'lib/File.pm'> in the archive if C<'File.pm'>
does not exist. This behavior can be disabled by specifying
C<'--no-search-includedir'>.

=item *

The file C<'lib/File.pm'> will be included in the archive as C<'File.pm'>,
trimming the library path prefix. This happens whether the file is
specified explicitly or through the C<-I> option.
This behavior can be disabled by specifying
C<'--no-trim-includedir'>.

=back

If two or more files share the same name after this trimming,
the command will abort with an error.

=item B<--output, -o>

Specifies the name of the output file.

If omitted, either the name of the source directory or the base name
of the main module is used, with the extension C<'.plz'> appended.

It is always better and safer to specify the output file explicitly.

A single hyphen (C<->) sends the output to standard output.

=back

=head2 ARCHIVE OPTIONS

=over 8

=item B<--compress>, B<-C>

Specifies the compression level for the Deflate algorithm.

If C<-C> is specified without a digit, the highest level (9) is set.

If omitted entirely, the files are not compressed.
This makes the content of the script almost transparently visible.
Also, the script will not need to load zlib and other libraries at runtime.

Outputs generated without the C<-C> option will not contain decompression
functionality, meaning you need to add C<-0> or similar options
when modifying the contents using ZIP archivers.

=item B<--bzip>

Specifies the use of the Bzip2 algorithm for compression.

Although this compression method is less common, it was introduced between
2003 (PKzip 4.6) and 2006 (Info-ZIP 3.0f18), and most current
ZIP archiver implementations support Bzip2 compression.

=item B<--base64, -B>

Encodes the embedded ZIP archive with Base64 encoding. It
makes the script about 40% larger and loses its ZIP-transparent
sfx capability in exchange for making the output script
completely ASCII-clean.

=item B<--text-archive, -T>

Uses a custom plaintext archive format for storing modules.
The output will not be compatible with ZIP archivers.

Output scripts generated with this option will be plaintext if all
input modules are plaintext ASCII or an ASCII-compatible
encoding. Additionally, it makes it easier to modify contents by
hand, because the format does not use byte-oriented binary structures.

This format is useful when (1) you need to edit embedded module sources
using standard text editors, or (2) the entire source code
must be transparently visible for auditing or inspection (if even
C<-C0> is unsatisfactory).

Combination with the C<-B> option is possible, but not particularly useful.

=back

=head2 POD HANDLING OPTIONS

=over 8

=item B<--copy-pod, -p>

If specified, this copies all POD (Perl's Plain Old Documentation)
sections in the main module to the output script.
This option is required when the script uses its own POD data,
e.g., via C<Pod::Usage>.

Alternatively, when compression (C<-C>) is not used, POD-processing modules
might see POD sections from all embedded modules within the ZIP file structure.
If only your main module contains POD, you might rely on this behavior
without using this option, though it is not a guaranteed behavior.

=item B<--protect-pod>

Protects any POD data inside the ZIP archive from being
processed.

Unless compression (C<-C>) or Base64 encoding (C<-B>) is used, POD
sections in the original source scripts within the ZIP archive may be
visible to POD processors, which may or may not be desirable.

If C<--protect-pod> is specified, a small POD header is inserted into the output
so that most POD processors will skip the hidden POD data.

This option is automatically enabled when C<--copy-pod> is used and
a POD directive is contained within the archive binary.
If this behavior is unwanted, you can specify C<--no-protect-pod>.

=item B<--quote-pod>

Tweaks the embedded ZIP archive so that the encoded script will
not contain any active POD specifications. The tweak is performed only
when necessary; however, doing so will cause the output to lose
ZIP transparency.

In most cases, either C<--protect-pod> or C<-C> is sufficient, or
when ZIP transparency is not needed, C<--base64> is a more reliable option.

=back

=head2 OTHER OPTIONS

=over 8

=item B<--random-seed>

Specifies a seed integer for pseudorandom number generators. Some
features (e.g., C<--text-archive> or C<--protect-pod>) use random
numbers to generate unique byte sequences in the archive. This causes
output archives for the same set of inputs to differ over time.
Specifying a random seed makes the output deterministic.
However, this is not a strict guarantee; the output may still differ due to
minor input changes or environmental factors (such as running on different
machines or system library updates). The primary intended use of
this option is for storing archive outputs in version control systems
such as Git or Subversion, keeping diffs as small as possible.

In Perl, the seed must be a 32-bit integer.

=item B<--inhibit-use-lib>

An experimental option: nullifies the effect of C<'use lib ...'>,
preventing local files not included in the archive from being loaded.
This will break if any system library uses the C<'lib'> pragma, so
using the code snippet in the APIS section is recommended instead.

=back

=head1 APIS

There are currently no APIs exposed to user scripts except import
hooks. The package C<ZipPerlApp> is provided inside the zipped script, so
if you need to alter behavior upon packaging, a construct such as:

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

Only pure Perl scripts or modules can be loaded from ZIP archives. For
example, autoloading (C<*.al>) or dynamic loading (C<*.so>, C<*.dll>) are not
supported.

=item *

C<__FILE__> tokens inside archived files will report virtual values such as
C<"I<archivename>/I<modulename>">, which do not exist on the real
filesystem. This also applies to the main script.
As a consequence, the common technique for making a dual-use
module/script:

    if (__FILE__ eq $0)

will not work. Instead, please provide a short entry script as the main
script.

=item *

For compactness (and minimal dependency on core modules only), the
embedded ZIP archive parser is extremely simple. It cannot
parse archives containing advanced features or partially corrupted
archives. Keep this in mind if you modify the packed archive using
standard ZIP tools.

=item *

All files are decoded into memory at start-up.
Including unnecessary or large files in the archive is discouraged.

=item *

If the C<DATA> handle is used, the marker token must be C<__DATA__>, not
C<__END__>. This is standard Perl behavior.

=back

=head1 IMPLEMENTATION

A ZIP archive containing the module files is stored in the C<__DATA__> section.
A minimal parser for the ZIP archive format is embedded at the beginning
of the output script. It extracts the source code of all
modules into memory at start-up. An import hook
subroutine is placed in Perl's C<@INC> facility to load these modules
via C<require> or C<use>.

This also enables the use of C<__DATA__> sections within each included module.

=head1 DEPENDENCIES

Zipped scripts generated by this command do not depend on any
external modules, except those included in the core modules of Perl
distributions as of version 5.24.1.

=head1 COMPARISON

C<PAR> is a "Perl Archive Toolkit" containing a similar tool named "C<pp>"
(PAR Packager). It can be used to generate standalone executables
from several Perl files. C<PAR> provides much richer functionality
compared to this tool, such as embedding binary shared objects or even
a Perl interpreter. However, the behavior of a
C<PAR>-generated executable is complex: it uses temporary
directories and file caches, depends on a large number of non-core
modules, and loads many additional modules at start-up. This
introduces potential security risks, especially for scripts
running with elevated privileges (e.g., via C<sudo>).

The pros and cons of C<zipperlapp> are the opposite: it cannot
generate interpreter-embedded executables, does not support shared
objects, and does not support automatic dependency resolution.
However, it operates simply and efficiently: it depends only on a minimum
number of core modules (and I<no> external binary libraries when using C<-C0> or C<-T>),
and uses no temporary files or directories (everything is handled in memory).
This makes it highly beneficial for small, trusted scripts where transparency and simplicity are valued.

=head1 REFERENCES

L<Homepage|https://www.github.com/yoiwa-personal/zipperlapp>

L<Python's "zipapp" implementation|https://docs.python.org/en/3/library/zipapp.html>

=head1 AUTHOR/COPYRIGHT

Copyright 2019-2026 Yutaka OIWA <yutaka@oiwa.jp>.

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
software, which contain code snippets copied from this software, may
be used and distributed under terms of your choice, as long as the
sole purpose of these works is not to redistribute the code snippets,
this software, or modified works thereof. The "AS-IS BASIS" clause
above still applies in these cases.

(In short, you can freely use this software to package YOUR software
and the Apache License will not apply to YOURS.)

=cut
