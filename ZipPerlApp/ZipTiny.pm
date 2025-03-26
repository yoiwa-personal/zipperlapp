# ZipTiny: a tiny implementation of zip archive creation,
# - implemented only with Perl core modules.
# - supporting SFX headers and trailers (or zip comments).
#
# Part of zipperlapp. (c) 2025 Yutaka OIWA.
# Licensed under Apache License Version 2.0.
# See README.md for details.

package ZipPerlApp::ZipTiny v2.1.0;

=pod

=head1 NAME

ZipPerlApp::ZipTiny: a tiny implementation of zip archive creation
supporting SFX headers and zip comments.

=head1 DESCRIPTION

This module creates a simple zip archive, supporting SFX headers and
zip comments.

=head1 MODULES

=cut

use 5.024;
use strict;
use bytes;
our $DEBUG = 0;
our $SIZELIMIT = 1048576 * 64;
use Carp;

use Hash::Util;

=head2 class ZipPerlApp::ZipTiny::CompressEntry

CompressEntry represents a file entry for zip archive.
Automatically generated from ZipTiny.

=head3 Readable fields

The following fields are readable by using the
method of corresponding names.

=over 4

=item fname:

a "file name" in zip archive.

=item content:

an uncompressed data in the archive.

=item mtime:

a modification time of the archive, in Unix timestamp.
Note that zip archive will only have a 2-second duration.

=item source:

an informative source of the content.
Only used as for a diagnostic purpose.

=item parent:

the ZipTiny module instance generating the CompressEntry instance.
Used to refer sizelimit configuration.

=item cdata, zipflags:

C<cdata> is the compressed data stream to be stored in acrhive.
Only available after C<ZipTiny::make_zip> is called.

C<zipflags> contains an array reference for zip archive fields
versionrequired, compress method, generic flag (bits 1-2).

=back

=cut

package ZipPerlApp::ZipTiny::CompressEntry {
    use IO::Compress::RawDeflate ();
    use Compress::Zlib ();

    use Carp;
    sub new {
	my $class = shift;

	my $h = { fname => undef,
		  content => undef,
		  mtime => undef,
		  source => undef,
		  parent => undef,
		  @_ };

	die unless scalar keys %$h == 5;

	die unless defined $h->{fname} &&
	  defined $h->{content} &&
	  defined $h->{mtime};

	$h->{compressflag} = undef;
	$h->{cdata} = undef;
	$h->{zipflags} = undef;

	bless $h, $class;
	Hash::Util::lock_ref_keys($h);
	return $h;
    }

    sub fname { return $_[0]->{fname} }
    sub content { return $_[0]->{content} }
    sub mtime { return $_[0]->{mtime} }
    sub cdata { return $_[0]->{cdata} }
    sub zipflags { return @{$_[0]->{zipflags}} }
    sub source { return $_[0]->{source} }

    sub compress {
	my ($self, $compressflag) = @_;

	return if defined $self->{compressflag} && $self->{compressflag} eq $compressflag;

	my $fname = $self->fname;
	my $content = $self->content;
	my $cdata = $content;

	my @zipflags = (0, 10, 0);

	croak "error: $fname: too large data"
	  if (defined $self->{parent} && length($content) > $self->{parent}{sizelimit});

	if (lc $compressflag eq 'bzip') {
	    require IO::Compress::Bzip2;
	    IO::Compress::Bzip2::bzip2(\$content, \$cdata)
		or confess "bzip2 compression failed";
	    @zipflags = (12, 46, 0);
	} elsif ($compressflag > 0) {
	    IO::Compress::RawDeflate::rawdeflate(\$content, \$cdata, -Level => $compressflag)
		or confess "rawdeflate failed";
	    my $flags = ($compressflag > 7) ? 1 : ($compressflag > 2) ? 0 : 2;
	    @zipflags = (8, 20, $flags);
	}
	printf STDERR "compressing %s: %d -> %d\n", $self->{FNAME}, length($content), length($cdata) if $DEBUG;
	# undo compression if it is not shrunk
	if (length($content) <= length($cdata)) {
	    $cdata = $content;
	    @zipflags = (0, 10, 0);
	}

	croak "error: $fname: too large data after compression"
	  if (defined $self->{parent} && length($cdata) > $self->{parent}{sizelimit});

	$self->{cdata} = $cdata;
	$self->{compressflag} = $compressflag;
	$self->{zipflags} = \@zipflags;
    }

=head3 Method compress(compressflag)

generates a compress data stream for the entry.

Argument compress flag is either an integer 0--9 (for zlib compression levels) or
the string 'bzip' for Bzip2 encryption.

Usually not needed to call it directly; ZipTiny::make_zip will call it automatically.

=cut

}

=head2 class ZipPerlApp::ZipTiny

ZipTiny is a factory instance for generating a zip archive.
The general sequence to use is: first to create instance by C<new>,
add files by C<add_entry> or C<add_entries>, and generate a zip archive
by C<make_zip>.

=cut

sub new {
    my $class = shift;

    my $self = {};
    $self->{entries} = [];
    $self->{entries_hash} = {};
    $self->{sizelimit} = $SIZELIMIT;
    $self->{debug} = $DEBUG;

    bless $self, $class;
    Hash::Util::lock_ref_keys($self);

    $self->add_entries(@_) if @_;

    return $self;
}

=head3 Method new([list...])

instantiates a factory for zip archive.

if a list of arguments are given,
these are processed as C<add_entries> below, as a shortcut.

=cut

sub __setopt {
    my $self = shift;
    my ($sizelimit, $debug) = @_;
    $self->{sizelimit} = ($sizelimit // 64 * 1048576);
    $self->{debug} = $debug;
}

sub add_entry {
    my $self = shift;
    my ($entname, $content, $modtime) = @_;

    my $source = $content;
    die "duplicated entry $entname" if exists $self->{entries_hash}->{$entname};

    $content = $entname unless defined $content;

    my $closure;

    my $fname = $entname;
    if (ref($content) eq '') {
	# filename
	open ($closure, "<", $content) or croak "error: $content: cannot open: $!";
	$content = $closure;
	# fallthrough
    }
    if (ref($content) eq "IO" || ref($content) eq "GLOB") {
	local $/;
	$! = undef;
	$modtime = (stat($content))[9];
	my $dat;
	my $n = read($content, $dat, $self->{sizelimit});
	croak "error: $fname: cannot read: $!" if $!;
	croak "error: $fname: too large input file (limit set to $self->{sizelimit})" if read($content, my $extra, 1) != 0;
	$content = $dat;
    } elsif (ref($content) eq 'SCALAR') {
        $content = $$content . "";
    } else {
	croak "bad argument to make_zipdata";
    }
    $modtime = time() if !defined $modtime;
    if (defined $closure) {
	close $closure or croak "cannot close $fname: $!";
    }

    my $obj = ZipPerlApp::ZipTiny::CompressEntry->new
      ( fname => $entname,
	content => $content,
	source => $source,
	mtime => $modtime,
	parent => $self
      );

    push @{$self->{entries}}, $obj;
    $self->{entries_hash}->{$entname} = $obj;
}


=head3 Method add_entry(entry name, [sources...])

adds a file entry to the zip archive.

The first argument is always file name to be stored in the archive.
The possible patterns for arguments are as follows:

=over 4

=item (entry_name):

stores the file named entry_name.

=item (entry_name, real_name)

stores the file named real_name, but stored as entry_name.

=item (entry_name, filehandle)

stores the content read from the filehandle.

=item (entry_name, \$string)

stores the content of the C<$string>.

=item (entry_name, \$string, modtime)

stores the content of the C<$string>.
Its modification time is set to modtime.

=back

=cut


# convert unix timestamp to FAT/MSDOS format used in zip archive.
# depending on TZ setting.

sub dosdate ($) {
    my ($unixtime) = (@_);
    my ($s, $m, $h, $d, $my, $y) = localtime $unixtime;

    return 0 if ($y < 80);

    my $time = ($h << 11) | ($m << 5) |  ($s >> 1);
    my $date = (($y - 80) << 9) | (($my + 1) << 5) | ($d);

    return ((($date & 0xffff) << 16) | ($time & 0xffff));
}

sub add_entries {
    my $self = shift;

    for my $e (@_) {
	if (ref $e eq 'HASH') {
	    die;
	} elsif (ref $e eq 'ARRAY') {
	    my @e = @$e;
	    $self->add_entry(@e);
	} else {
	    $self->add_entry($e);
	}
    }
}

=head3 Method add_entry(entry...)

adds several file entries to the zip archive.

Each argument is a list reference containing arguments to
C<add_entry>.

=cut

sub include_q {
    my ($self, $f) = @_;
    return exists $self->{entries_hash}->{$f};
}

sub find_entry {
    my ($self, $f) = @_;
    return $self->{entries_hash}->{$f};
}

sub entries {
    my $self = shift;
    my @r = ();
    (@r, @{$self->{entries}});
}

=head3 Method include_q(entry_name)

returns true if the file entry_name is already added to the archive.

=head3 Method find_entry(entry_name)

returns an instance of C<CompressEntry> for the entry named entry_name.
It returns C<undef> if not found.

=head3 Method entries

returns an fresh list of added files as instances of C<CompressEntry>.
Modifying the list will have no effect to the generated archive.

=cut

sub make_zip {
    my ($self, @options) = @_;

    if ($self eq 'ZipPerlApp::ZipTiny') {
	$self = shift @options;
    }
    if (ref $self eq 'ARRAY') {
	# called as a class method.
	$self = ZipPerlApp::ZipTiny->new(@$self);
    }

    my %options = ( compress => 9,
		    header => "",
		    trailercomment => "",
		    offset => 0);
    %options = ( %options, @options );
    croak "error: make_zip: bad keyword arguments" unless scalar(keys %options) == 4;

    my $offset = $options{offset};
    my $pos = $offset;
    my $out = "";
    my $gheader_accumulate = "";
    my $fcount = 0;

    my @entries = @{$self->{entries}};

    $out .= $options{header};

    for my $e (@entries) {
	$pos = length($out) + $offset;

	my $name = $e->fname;
	my $content = $e->content;
	my $modtime = $e->mtime;

	my $crc = Compress::Zlib::crc32($content);

	$e->compress($options{compress});

	my $cdata = $e->cdata;
	my ($compressmethod, $versionrequired, $flags) = $e->zipflags;

	$flags = (($flags << 1) & 6);
	my $header = pack("VvvvVVVVvv",
			  0x04034b50,
			  $versionrequired,
			  $flags,
			  $compressmethod,
			  dosdate($modtime),
			  $crc,
			  length $cdata,
			  length $content,
			  length $name,
			  0 # extra field len
			 ) . $name;
	my $gheader = pack("VvvvvVVVVvvvvvVV",
			   0x02014b50,
			   0x031e, # version made by: 3.0 Unix
			   $versionrequired,
			   $flags,
			   $compressmethod,
			   dosdate($modtime),
			   $crc,
			   length $cdata,
			   length $content,
			   length $name,
			   0, # extra field len
			   0, # file commen length
			   0, # disk number,
			   0, # int file attr,
			   0100644 << 16, # ext file attr: file, -rw-r--r--
			   $pos
			 ) . $name;

	$out .= $header;
	$out .= $cdata;
	$gheader_accumulate .= $gheader;
	$fcount++;
    }

    $pos = length($out) + $offset;
    my $trailer = $options{trailercomment};
    my $ecd = pack("VvvvvVVv",
		   0x06054b50,
		   0,
		   0,
		   $fcount,
		   $fcount,
		   length $gheader_accumulate,
		   $pos,
		   length $trailer);
    $out .= $gheader_accumulate;
    $out .= $ecd;
    $out .= $trailer;
    return $out;
}


=head3 Method make_zip([kwd => value, ...])

generates a zip archive and returns as a string.
This method can be called several times for the same instance.

Available keyword argument are as follows:

=over 4

=item compress:

zlib compression levels (1-9), 0 for no compression, 'bzip' for bzip2 compression.

=item header:

data prepended to archive

=item offset:

size of data to be prepented to archive (in addition to HEADER)

=item trailercomment:

comment field of zip file, up to 65535 bytes.

=back

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

=cut

if ($0 eq __FILE__) {
#     my $e = ZipPerlApp::ZipTiny->new
#       ( ["1.dat", \"data 1"],
# 	["2.dat", \"data 2"],
# 	[$0]);
#     print $e->make_zip(COMPRESS => ($ARGV[0] // 9), HEADER => "#!!", TRAILERCOMMENT => "!!#");
    my $z = ZipPerlApp::ZipTiny::make_zip
      ( [["1.dat", \"data 1"],
	 ["2.dat", \"data 2"],
	 [$0]],
	COMPRESS => ($ARGV[0] // 9), HEADER => "#!!", TRAILERCOMMENT => "!!#");
    print $z;
}

1;
