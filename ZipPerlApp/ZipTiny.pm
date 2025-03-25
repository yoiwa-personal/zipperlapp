# ZipTiny: a tiny implementation of zip archive creation,
# - implemented only with Perl core modules.
# - supporting SFX headers and trailers (or zip comments).
#
# Part of zipperlapp. (c) 2025 Yutaka OIWA.
# Licensed under Apache License Version 2.0.
# See README.md for details.

package ZipPerlAll::ZipTiny v2.1.0;

use 5.024;
use strict;
use bytes;
our $DEBUG = 0;
our $SIZELIMIT = 1048576 * 64;
use Carp;

use Hash::Util;

package ZipPerlAll::ZipTiny::CompressEntry {
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
}

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

sub __setopt {
    my $self = shift;
    my ($sizelimit, $debug) = @_;
    $self->{sizelimit} = ($sizelimit // 64 * 1048576);
    $self->{debug} = $debug;
}

# read a single file and prepare for archiving
sub add_entry {
    # arguments:
    #   (file_name) -> compress this file.
    #   (entry_name, real_name) -> compress real_name, store as entry_name
    #   (entry_name, filehandle) -> compress filehandle, store as entry_name
    #   (entry_name, \$string) -> compress content of $string, store as entry_name
    #   (entry_name, \$string, modtime) -> ditto with modification time modtime (unix timestamp)

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

    my $obj = ZipPerlAll::ZipTiny::CompressEntry->new
      ( fname => $entname,
	content => $content,
	source => $source,
	mtime => $modtime,
	parent => $self
      );

    push @{$self->{entries}}, $obj;
    $self->{entries_hash}->{$entname} = $obj;
}

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

# prepare for archiving multiple files.
# Input: a list of list reference of argument for &make_zipdata

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

# make a zip archive.
# mandatory argument: a list reference of list reference of argument for &make_zipdata.
# keyword arguments:
#   COMPRESS: zlib compression levels (1-9), 0 for no compression, 'bzip' for bzip2 compression.
#   HEADER: data prepended to archive
#   OFFSET: size of data to be prepented to archive (in addition to HEADER)
#   TRAILERCOMMENT: comment field of zip file, up to 65535 bytes.

sub make_zip {
    my ($self, @options) = @_;

    if ($self eq 'ZipPerlAll::ZipTiny') {
	$self = shift @options;
    }
    if (ref $self eq 'ARRAY') {
	# called as a class method.
	$self = ZipPerlAll::ZipTiny->new(@$self);
    }

    my %options = ( COMPRESS => 9,
		    HEADER => "",
		    TRAILERCOMMENT => "",
		    OFFSET => 0);
    %options = ( %options, @options );
    croak "error: make_zip: bad keyword arguments" unless scalar(keys %options) == 4;

    my $offset = $options{OFFSET};
    my $pos = $offset;
    my $out = "";
    my $gheader_accumulate = "";
    my $fcount = 0;

    my @entries = @{$self->{entries}};

    $out .= $options{HEADER};

    for my $e (@entries) {
	$pos = length($out) + $offset;

	my $name = $e->fname;
	my $content = $e->content;
	my $modtime = $e->mtime;

	my $crc = Compress::Zlib::crc32($content);

	$e->compress($options{COMPRESS});

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
    my $trailer = $options{TRAILERCOMMENT};
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

if ($0 eq __FILE__) {
#     my $e = ZipPerlAll::ZipTiny->new
#       ( ["1.dat", \"data 1"],
# 	["2.dat", \"data 2"],
# 	[$0]);
#     print $e->make_zip(COMPRESS => ($ARGV[0] // 9), HEADER => "#!!", TRAILERCOMMENT => "!!#");
    my $z = ZipPerlAll::ZipTiny::make_zip
      ( [["1.dat", \"data 1"],
	 ["2.dat", \"data 2"],
	 [$0]],
	COMPRESS => ($ARGV[0] // 9), HEADER => "#!!", TRAILERCOMMENT => "!!#");
    print $z;
}

1;
