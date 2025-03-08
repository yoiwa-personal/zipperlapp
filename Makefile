# Makefile for zipperlapp

COMPRESSION = -C9

all: zipperlapp

zipperlapp: zipperlapp.pl ZipTiny.pm
	./zipperlapp.pl -p $(COMPRESSION) -o $@ $^
	./zipperlapp -p $(COMPRESSION) -o $@ $^
	./zipperlapp -p $(COMPRESSION) -o $@ $^

# running three-time bootstrap as a test
#  1st to generate the packed binary
#  2nd to check whether the original script emits correct outputs
#  3rd to check whether the compiled script emitted correct outputs
