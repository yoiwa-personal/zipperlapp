COMPRESSION = -C0

all: zipperlapp

zipperlapp: zipperlapp.pl ZipTiny.pm
	./zipperlapp.pl -p $(COMPRESSION) -o $@ $^
	./zipperlapp -p $(COMPRESSION) -o $@ $^
	./zipperlapp -p $(COMPRESSION) -o $@ $^

# runnint three times bootstrap as a test
#  1st to generate
#  2nd to check whether the original script emits correct outputs
#  3rd to check whether the compiled script emits correct outputs
