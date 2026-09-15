# NAME

zipperlapp - Create executable Perl script bundles using ZIP archives

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

      --copy-pod          -p           copy POD from main module
      --[no-]protect-pod               hide unwanted PODs from processors
      --quote-pod                      quote PODs in archive (zip incompatible)

      --inhibit-use-lib                disable 'use lib' pragma
      --random-seed=...                specify random seed

      --help                           show help

# DESCRIPTION

This program bundles several Perl module files and wraps them into an
"executable" ZIP archive. An output file can be invoked as a Perl
script or (if a source file contains a `"#!"` line) as a directly
executable command. It can also be handled by almost any ZIP
archiver as a self-extracting ("sfx") archive.

Inside Perl scripts, all files contained in the archive are placed at
the beginning of the library search path. The bundled script can
simply use `use` or `require` statements to load the contained
modules, without modifying the `@INC` variable.

# ARGUMENTS

- **directory**

    If there is only one argument and it is the name of a directory, all
    `*.pl`/`*.pm` files under that directory (recursively) are included.
    The directory name itself is truncated.

- **files**

    Otherwise, all files specified in the arguments are included.

# OPTIONS

## INPUT/OUTPUT OPTIONS

- **--main, -m**

    Specifies the main module which is automatically `require`-d. Also, a
    shebang line and contiguous comment lines at the top of the main module
    are copied to the output.

    If one and only one script with the extension `'.pl'` is contained in the
    input set of modules, it is automatically detected. Otherwise, the
    main module must be explicitly specified.

- **--includedir, -I**

    Specifies the locations to search for input files, in addition to the current
    directory.
    If this option is specified multiple times, the files will be searched
    in order of specification.

    This option has two separate effects; for example, when `'-Ilib File.pm'`
    is specified on the command line:

    - The command will include `'lib/File.pm'` in the archive if `'File.pm'`
    does not exist. This behavior can be disabled by specifying
    `'--no-search-includedir'`.
    - The file `'lib/File.pm'` will be included in the archive as `'File.pm'`,
    trimming the library path prefix. This happens whether the file is
    specified explicitly or through the `-I` option.
    This behavior can be disabled by specifying
    `'--no-trim-includedir'`.

    If two or more files share the same name after this trimming,
    the command will abort with an error.

- **--output, -o**

    Specifies the name of the output file.

    If omitted, either the name of the source directory or the base name
    of the main module is used, with the extension `'.plz'` appended.

    It is always better and safer to specify the output file explicitly.

    A single hyphen (`-`) sends the output to standard output.

## ARCHIVE OPTIONS

- **--compress**, **-C**

    Specifies the compression level for the Deflate algorithm.

    If `-C` is specified without a digit, the highest level (9) is set.

    If omitted entirely, the files are not compressed.
    This makes the content of the script almost transparently visible.
    Also, the script will not need to load zlib and other libraries at runtime.

    Outputs generated without the `-C` option will not contain decompression
    functionality, meaning you need to add `-0` or similar options
    when modifying the contents using ZIP archivers.

- **--bzip**

    Specifies the use of the Bzip2 algorithm for compression.

    Although this compression method is less common, it was introduced between
    2003 (PKzip 4.6) and 2006 (Info-ZIP 3.0f18), and most current
    ZIP archiver implementations support Bzip2 compression.

- **--base64, -B**

    Encodes the embedded ZIP archive with Base64 encoding. It
    makes the script about 40% larger and loses its ZIP-transparent
    sfx capability in exchange for making the output script
    completely ASCII-clean.

- **--text-archive, -T**

    Uses a custom plaintext archive format for storing modules.
    The output will not be compatible with ZIP archivers.

    Output scripts generated with this option will be plaintext if all
    input modules are plaintext ASCII or an ASCII-compatible
    encoding. Additionally, it makes it easier to modify contents by
    hand, because the format does not use byte-oriented binary structures.

    This format is useful when (1) you need to edit embedded module sources
    using standard text editors, or (2) the entire source code
    must be transparently visible for auditing or inspection (if even
    `-C0` is unsatisfactory).

    Combination with the `-B` option is possible, but not particularly useful.

## POD HANDLING OPTIONS

- **--copy-pod, -p**

    If specified, this copies all POD (Perl's Plain Old Documentation)
    sections in the main module to the output script.
    This option is required when the script uses its own POD data,
    e.g., via `Pod::Usage`.

    Alternatively, when compression (`-C`) is not used, POD-processing modules
    might see POD sections from all embedded modules within the ZIP file structure.
    If only your main module contains POD, you might rely on this behavior
    without using this option, though it is not a guaranteed behavior.

- **--protect-pod**

    Protects any POD data inside the ZIP archive from being
    processed.

    Unless compression (`-C`) or Base64 encoding (`-B`) is used, POD
    sections in the original source scripts within the ZIP archive may be
    visible to POD processors, which may or may not be desirable.

    If `--protect-pod` is specified, a small POD header is inserted into the output
    so that most POD processors will skip the hidden POD data.

    This option is automatically enabled when `--copy-pod` is used and
    a POD directive is contained within the archive binary.
    If this behavior is unwanted, you can specify `--no-protect-pod`.

- **--quote-pod**

    Tweaks the embedded ZIP archive so that the encoded script will
    not contain any active POD specifications. The tweak is performed only
    when necessary; however, doing so will cause the output to lose
    ZIP transparency.

    In most cases, either `--protect-pod` or `-C` is sufficient, or
    when ZIP transparency is not needed, `--base64` is a more reliable option.

## OTHER OPTIONS

- **--random-seed**

    Specifies a seed integer for pseudorandom number generators. Some
    features (e.g., `--text-archive` or `--protect-pod`) use random
    numbers to generate unique byte sequences in the archive. This causes
    output archives for the same set of inputs to differ over time.
    Specifying a random seed makes the output deterministic.
    However, this is not a strict guarantee; the output may still differ due to
    minor input changes or environmental factors (such as running on different
    machines or system library updates). The primary intended use of
    this option is for storing archive outputs in version control systems
    such as Git or Subversion, keeping diffs as small as possible.

    In Perl, the seed must be a 32-bit integer.

- **--inhibit-use-lib**

    An experimental option: nullifies the effect of `'use lib ...'`,
    preventing local files not included in the archive from being loaded.
    This will break if any system library uses the `'lib'` pragma, so
    using the code snippet in the APIS section is recommended instead.

# APIS

There are currently no APIs exposed to user scripts except import
hooks. The package `ZipPerlApp` is provided inside the zipped script, so
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

# LIMITATIONS

- Only pure Perl scripts or modules can be loaded from ZIP archives. For
example, autoloading (`*.al`) or dynamic loading (`*.so`, `*.dll`) are not
supported.
- `__FILE__` tokens inside archived files will report virtual values such as
`"_archivename_/_modulename_"`, which do not exist on the real
filesystem. This also applies to the main script.
As a consequence, the common technique for making a dual-use
module/script:

        if (__FILE__ eq $0)

    will not work. Instead, please provide a short entry script as the main
    script.

- For compactness (and minimal dependency on core modules only), the
embedded ZIP archive parser is extremely simple. It cannot
parse archives containing advanced features or partially corrupted
archives. Keep this in mind if you modify the packed archive using
standard ZIP tools.
- All files are decoded into memory at start-up.
Including unnecessary or large files in the archive is discouraged.
- If the `DATA` handle is used, the marker token must be `__DATA__`, not
`__END__`. This is standard Perl behavior.

# IMPLEMENTATION

A ZIP archive containing the module files is stored in the `__DATA__` section.
A minimal parser for the ZIP archive format is embedded at the beginning
of the output script. It extracts the source code of all
modules into memory at start-up. An import hook
subroutine is placed in Perl's `@INC` facility to load these modules
via `require` or `use`.

This also enables the use of `__DATA__` sections within each included module.

# DEPENDENCIES

Zipped scripts generated by this command do not depend on any
external modules, except those included in the core modules of Perl
distributions as of version 5.24.1.

# COMPARISON

`PAR` is a "Perl Archive Toolkit" containing a similar tool named "`pp`"
(PAR Packager). It can be used to generate standalone executables
from several Perl files. `PAR` provides much richer functionality
compared to this tool, such as embedding binary shared objects or even
a Perl interpreter. However, the behavior of a
`PAR`-generated executable is complex: it uses temporary
directories and file caches, depends on a large number of non-core
modules, and loads many additional modules at start-up. This
introduces potential security risks, especially for scripts
running with elevated privileges (e.g., via `sudo`).

The pros and cons of `zipperlapp` are the opposite: it cannot
generate interpreter-embedded executables, does not support shared
objects, and does not support automatic dependency resolution.
However, it operates simply and efficiently: it depends only on a minimum
number of core modules (and _no_ external binary libraries when using `-C0` or `-T`),
and uses no temporary files or directories (everything is handled in memory).
This makes it highly beneficial for small, trusted scripts where transparency and simplicity are valued.

# REFERENCES

[Homepage](https://www.github.com/yoiwa-personal/zipperlapp)

[Python's "zipapp" implementation](https://docs.python.org/en/3/library/zipapp.html)

# AUTHOR/COPYRIGHT

Copyright 2019-2026 Yutaka OIWA <yutaka@oiwa.jp>.

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
software, which contain code snippets copied from this software, may
be used and distributed under terms of your choice, as long as the
sole purpose of these works is not to redistribute the code snippets,
this software, or modified works thereof. The "AS-IS BASIS" clause
above still applies in these cases.

(In short, you can freely use this software to package YOUR software
and the Apache License will not apply to YOURS.)
