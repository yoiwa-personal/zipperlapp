# zipperlapp - Create executable Perl script bundles using ZIP archives

This program bundles several Perl module files and wraps them into an
"executable" ZIP archive. An output file can be invoked as a Perl
script or (if the source file contains a `#!` line) as a directly
executable command. It can also be handled by almost any ZIP
archiver as a self-extracting ("sfx") archive.

Inside Perl scripts, all files contained in the archive are placed at the
beginning of the library search path. The bundled script can simply use `use` or
`require` statements to load the contained modules, without modifying
the `@INC` variable.

Run `zipperlapp --help` or `perldoc zipperlapp` for usage.

[USAGE.md](USAGE.md) contains auto-converted documentation for viewing on GitHub.

## Executables and Source Code

The standalone portable script, processed by `zipperlapp` itself, is
available via a [direct link](https://github.com/yoiwa-personal/zipperlapp/releases/latest/download/zipperlapp) 
or from [Releases](https://github.com/yoiwa-personal/zipperlapp/releases).

To regenerate it from source (`zipperlapp.pl`), see the `Makefile` for instructions.

## Author, Copyright, and License

Copyright 2019-2026 Yutaka OIWA <yutaka@oiwa.jp>.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

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
