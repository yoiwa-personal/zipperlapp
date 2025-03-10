# ZipTiny: a tiny implementation of zip archive creation,
# - implemented only with Perl core modules.
# - supporting SFX headers and trailers (or zip comments).

package ZipTiny;

our $VERSION = '1.1';

use 5.024;
use strict;
use bytes;
use IO::Compress::RawDeflate;
use Compress::Zlib;

use Carp;
our $DEBUG = 0;
our $SIZELIMIT = 1048576 * 64;

# read a single file and prepare for archiving
sub make_zipdata {

    # arguments:
    #   (file_name) -> compress this file.
    #   (entry_name, real_name) -> compress real_name, store as entry_name
    #   (entry_name, filehandle) -> compress filehandle, store as entry_name
    #   (entry_name, \$string) -> compress content of $string, store as entry_name
    #   (entry_name, \$string, modtime) -> ditto with modification time modtime (unix timestamp)

    my $closure;
    my ($entname, $content, $modtime) = @_;
    $content = $entname unless defined $content;
    my $fname = $entname;
    if (ref($content) eq '') {
	# filename
	my $fname = $content;
	open ($closure, "<", $content) or croak "error: $fname: cannot open: $!";
	$content = $closure;
	 # fallthrough
    }
    if (ref($content) eq "IO" || ref($content) eq "GLOB") {
	local $/;
	$! = undef;
	$modtime = (stat($content))[9];
	my $dat;
	my $n = read($content, $dat, $SIZELIMIT);
	croak "error: $fname: cannot read: $!" if $!;
	croak "error: $fname: too large input file (limit set to $SIZELIMIT)" if read($content, my $extra, 1) != 0;
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
    return {FNAME => $entname,
	    CONTENT => $content,
	    MTIME => $modtime};
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

sub prepare_zip {
    my @out = ();
    for my $e (@_) {
	if (ref $e eq 'HASH') {
	    push @out, $e;
	} elsif (ref $e eq 'ARRAY') {
	    my @e = @$e;
	    push @out, make_zipdata(@e);
	} else {
	    push @out, make_zipdata($e);
	}
    }
    return @out;
}

sub compress_entry {
    my ($ent, $compressflag) = @_;

    return if exists $ent->{CDATA};

    my $content = $ent->{CONTENT};
    my $cdata = $content;

    my $compressmethod = 0;
    my $versionrequired = 10;
    my $flags = 0;

    croak "error: $ent->{FNAME}: too large data" if (length($content) > $SIZELIMIT);

    if (lc $compressflag eq 'bzip') {
	require IO::Compress::Bzip2;
	IO::Compress::Bzip2::bzip2(\$content, \$cdata)
	    or confess "bzip2 compression failed";
	($compressmethod, $versionrequired, $flags) = (12, 46, 0);
    } elsif ($compressflag > 0) {
	IO::Compress::RawDeflate::rawdeflate(\$content, \$cdata, -Level => $compressflag)
	    or confess "rawdeflate failed";
	($compressmethod, $versionrequired) = (8, 20);
	$flags = ($compressflag > 7) ? 1 : ($compressflag > 2) ? 0 : 2;
    }
    printf STDERR "compressing %s: %d -> %d\n", $ent->{FNAME}, length($content), length($cdata) if $DEBUG;
    # undo compression if it is not shrunk
    if (length($content) <= length($cdata)) {
	$cdata = $content;
	($compressmethod, $versionrequired, $flags) = (0, 10, 0);
    }

    croak "error: $ent->{FNAME}: too large data after compression" if (length($cdata) > $SIZELIMIT);

    $ent->{CDATA} = $cdata;
    $ent->{COMPRESSMETHOD} = $compressmethod;
    $ent->{VERSIONREQUIRED} = $versionrequired;
    $ent->{FLAGS} = $flags;
}

# make a zip archive.
# mandatory argument: a list reference of list reference of argument for &make_zipdata.
# keyword arguments:
#   COMPRESS: zlib compression levels (1-9), 0 for no compression, 'bzip' for bzip2 compression.
#   HEADER: data prepended to archive
#   OFFSET: size of data to be prepented to archive (in addition to HEADER)
#   TRAILERCOMMENT: comment field of zip file, up to 65535 bytes.

sub make_zip {
    my ($entries, @options) = @_;
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

    my @entries = @$entries;

    $out .= $options{HEADER};

    for my $e (@entries) {
	$pos = length($out) + $offset;

	if (ref $e eq 'ARRAY') {
	    my @e = @$e;
	    $e = make_zipdata(@e);
	}

	my $name = $e->{FNAME};
	my $content = $e->{CONTENT};
	my $modtime = $e->{MTIME};

	my $crc = Compress::Zlib::crc32($content);

	compress_entry($e, $options{COMPRESS});

	my $cdata = $e->{CDATA};
	my $compressmethod = $e->{COMPRESSMETHOD};
	my $versionrequired = $e->{VERSIONREQUIRED};
	my $flags = $e->{FLAGS};

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
    print make_zip([["1.dat", \"data 1"],
		    ["2.dat", \"data 2"], [$0]],
		   COMPRESS => ($ARGV[0] // 9), HEADER => "#!!", TRAILERCOMMENT => "!!#");
}

1;
