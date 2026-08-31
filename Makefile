# Makefile for zipperlapp

COMPRESSION = -C9
ZIPPERLAPPOPT = -p $(COMPRESSION) --random-seed=314159265

all: zipperlapp USAGE.md
all-githubflow: zipperlapp

zipperlapp: zipperlapp.pl ZipPerlApp/SFXGenerate.pm ZipPerlApp/ZipTiny.pm
	./zipperlapp.pl $(ZIPPERLAPPOPT) -o $@ $^
	./zipperlapp $(ZIPPERLAPPOPT) -o $@ $^
	./zipperlapp $(ZIPPERLAPPOPT) -o $@ $^

# running three-time bootstrap as a test
#  1st to generate the packed binary
#  2nd to check whether the original script emits correct outputs
#  3rd to check whether the compiled script emitted correct outputs

USAGE.md: zipperlapp.pl
	pod2markdown $^ > $@

release: zipperlapp
	version=$$(./zipperlapp --version) && test -n "$$version" && \
	git tag "v$$version" && git push origin "v$$version"
