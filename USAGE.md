# NAME

zipperlapp - Make an executable perl script bundle using zip archive

# SYNOPSIS

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

# DESCRIPTION

This program bundles several Perl module files and wraps them as an
"executable" zip archive.  An output file can be invoked as a Perl
script, or (if a source file contains a `"#!"` line) as a directly
executable command.  Also, it can be handled by (almost every) zip
archiver as an "sfx" file.

Inside Perl scripts, all files contained in the archive is put in the
top of the searched library set.  The program can simply use `use` or
`require` statements to load the contained modules, without modifying
the `@INC` variable.

# ARGUMENTS

- **directory**

    If there are only one argument and it is a name of directory, All
    `*.pl`/`*.pm` files under that directory (recursively) are included.
    The directory name itself is truncated.

- **files**

    Otherwise, all files specified in the argument are included.

# OPTIONS

## INPUT/OUTPUT OPTIONS

- **--main, -m**

    specifies the main module which is automatically "require"-d.  Also, a
    "she-bang" line and continuous comment lines at the top of main module
    are copied to the output.

    If one and only one script with extension `'.pl'` is contained in the
    input set of modules, it is automatically detected.  Otherwise, the
    main module must be explicitly specified.

- **--includedir, -I**

    specifies the locations to search input files, in addition to the current
    directory.
    If this option is specified multiple times, the files will be searched
    in order of the specifications.

    This option will have two kinds of separate effects; when `'-Ilib File.pm'`
    is speficied in the command line, as an example:

    - The command will include `'lib/File.pm'` to the archive, if `'File.pm'`
    does not exist.  This behavior can be disabled by specifing
    `'--no-search-includedir'`.
    - The file `'lib/File.pm'` will be included to the archive as `'File.pm'`,
    triming the library part of the name. This happens either when the file is
    speficied explicitly or through `-I` option.
    This behavior can be disabled by specifing
    `'--no-trim-includedir'`.

        If two or more files will share the same name after this triming,
        it will be rejected as an error.

- **--output, -o**

    specifies the name of the output file.

    If omitted, either the name of the source directory or the base name
    of the main module is taken, with a postfix `'.plz'` is appended.

    It is always better and safer to specify the output file.

    A single hyphen (`-`) will let output go to the standard output.

## ARCHIVE OPTIONS

- **--compress**, **-C**

    specifies the compression level for the Deflate algorithm.

    If `-C` is specified without a digit, the highest level 9 is set.

    If not specified at all, the files are not compressed.
    It makes the content of the script almost transparently visible.
    Also, the script will not load zlib and other libraries run-time.

    Outputs generated without `-C` options will not contain decompression
    functionality, that means you need to add `-0` or similar options
    when you modify the contents with zip archivers.

- **--bzip**

    specifies to use BZIP2 algorithm for compression.

    This compression method is not common, but it was implemented around
    2003 (PKzip 4.6) to 2006 (Infozip 3.0f18), and most current
    implementation of zip archive supports bzip2 compression.

- **--base64, -B**

    It will encode the embedded ZIP archive with Base64 encoding.  It
    makes the script about 40% larger and also loses zip-transparent
    behavior as an sfx file, in trade for making the output script
    completely ASCII-clean.

- **--text-archive, -T**

    It will use its own plaintext archive format for storing modules.
    The output will not be compatible with zip archivers.

    Output scripts generated with this option will be plaintext, if all
    input modules are plaintext in ASCII or some specific ASCII-compatible
    encoding.  In addition to that, it is easier to modify its content by
    hand, because the format uses no byte-oriented structure.

    This format will be useful when (1) you need to edit module sources
    embedded in outputs by text editors, or (2) when the whole source code
    must be transparently visible for auditing or inspections (if even
    `-C0` is unsatisfactory).

    The combination with the `-B` option is possible but not very
    meaningful.

## POD HANDLING OPTIONS

- **--copy-pod, -p**

    If specified, it will copy all POD (Perl's plain old document format)
    sections in the main module to the output script.
    This option is requored when the script uses the POD data of itself
    e.g. by `Pod::Usage`.

    Alternatively, when compression (-C) is not used, it is likely that
    any pod-using modules may see pod sections from all of embedded
    modules within the zip file structure.  If only your main module
    contains a pod, you may be possibly depend on that "behavior" and not
    using this option, although it is not a reliable behavior.

- **--protect-pod**

    specifies to protect any POD data inside the zip archive from being
    processed.

    Unless either compression (-C) or Base64 encoding (-B) is used, POD
    sections in the original source scripts within the zip archive may be
    visible to POD data processors; it may either be or not be a good
    thing, depending on the situation.

    If `--protect-pod` is specified, a small POD is inserted to the output
    so that most pod processors will skip such ghost of PODs.

    This option is automatically enabled, when `--copy-pod` is used and
    a POD directive is actually contained in the archive binary.
    If the process is not wanted, you can specify `--no-protect-pod`.

- **--quote-pod**

    It will tweak the embedded ZIP archive so that the encoded script will
    not contain any active pod specification.  The tweak is performed only
    when it is really required, but if done, the output will loose
    zip-transparency.

    In most circumstances, either `--protect-pod` or `-C` is enough, or
    when zip-transparency is not needed, `--base64` is more reliable option.

## OTHER OPTIONS

- **--random-seed**

    specifies a seed integer for pseudorandom number generators.  Some
    features (e.g. `--text-archive` or `--protect-pod`) use random
    numbers to generate unique byte sequences in the archive.  This makes
    output archives for the same set of inputs to differ time-to-time.
    Specifying a random seed will make output somewhat deterministic.
    However, it is not a strong guarantee; the output may still differ by
    small change of inputs or even small environmental changes such as use
    of different machines or system library updates.  Main expected use of
    this option is to put the archive outputs to version control systems
    such as git or subversion, making differences as small as possible.

    In Perl, the seed will be an 32-bit integer.

- **--inhibit-use-lib**

    An experimental option:  it will nullify effect of `'use lib ...'`,
    so that local files not included in the archive will not be read.
    It will break if any system library uses `'lib'` pragma, thus
    use of the snippet in the APIS section is recommended.

# APIS

There are currently no APIs visible to user scripts except import
hooks.  The package `ZipPerlApp` is provided in the zipped script, so
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

# LIMITATIONS

- Only pure Perl scripts or modules can be loaded from zip archives. For
example, autoloading (\*.al) or dynamic loading (\*.so, \*.dll) will not
be available.
- `__FILE__` tokens in the archived file will have virtual values of
`"_archivename_/_modulename_"`, which does not exist in the real
file system.  This also holds for the "main script" to be referred to.
It means that the common technique for making a "dual-use"
module/script

        if (__FILE__ eq $0)

    will not work.  Instead, please provide a short entry script as a main
    script.

- For compactness (and minimal dependency only to core modules), an
embedded parser for zip archives is extremely simple.  It can not
parse archives with any advanced features or partially-broken
archives.  If you modify the packed archive using usual zip archivers,
be aware of that.
- All files are decoded into the memory at the beginning of the program
execution.  It is not wise to include unneeded files (especially large
ones) into the archive.
- If `DATA` handle is used, the marker token shall be `__DATA__`, not
`__END__`.  This is the defined behavior of Perl.

# IMPLEMENTATION

A zip archive of module files are stored in the `__DATA__` section.
A minimal parser for Zip archive format is embedded to the beginning
of the output script, and it will extract the source codes of all
modules to an on-memory storage at the start-up.  An import hook
subroutine is put into Perl's `@INC` facility to load those modules
by `require` or `use`.

This enables use of `__DATA__` sections in each included module.

# DEPENDENCIES

Zipped scripts generated by this command will not depend on any
external modules, except those included in the Core modules of Perl
distributions as of version 5.24.1.

# COMPARISON

`PAR` is a "Perl Archive Toolkit" containing a similar tool, "`pp`"
\- PAR Packager.  It can be used to generate a standalone executable
from several perl files.  `PAR` provides much richer functionality
compared to this tool: embedding binary shared objects, even embedding
Perl interpreter, etc.  At the same time, the behavior of a
`PAR`-generated executable is quite complex: it uses temporary
directories and file caches, it depends on large number of non-core
modules, and it loads a lot of additional modules at start-up.  These
introduce potential security attack risks, especially with scripts
running with elevated privileges e.g. with `sudo`.

The pros and cons of `zipperlapp` is the opposite: it can not
generate interpreter-embedded executables, it does not support shared
objects, and it does not support automatic searches of dependenty
libraries.  But, it runs quite simply and efficiently: it depends on
only the minimum numbers of core modules (even with _no_ external
binary libraries when option `-C0` or `-T` is used), and it uses no
temporary files and directories at all (on-memory store is used
instead).  It is very beneficial for small, trusted scripts which
value transparency and simplicity.

# REFERENCES

[Homepage](https://www.github.com/yoiwa-personal/zipperlapp)

[Python's "zipapp" implementation](https://docs.python.org/en/3/library/zipapp.html)

# AUTHOR/COPYRIGHT

Copyright 2019-2025 Yutaka OIWA <yutaka@oiwa.jp>.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

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
