CC=g++
CPPFLAGS=-I.
DEPS = bc7_gpu.h
FFLAGS=-framework OpenCL

all:: bc7_gpu

clear: clear_screen all
clear_screen:
	clear

OBJ = main.o tga/tga.o bc7_decompress.o platform.o scoped_timer.o OpenCL/bc7_opencl.o

%o:%.c $(DEPS)
	$(CC) $(CPPFLAGS) -c -o $@ $<

bc7_gpu: $(OBJ)
	$(CC) -o $@ $^ $(CPPFLAGS) $(FFLAGS)

.PHONY: clean
.PHONY: clear
clean:
	rm -rf *.o bc7
