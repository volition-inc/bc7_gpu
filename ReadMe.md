About
-----

This program compresses a texture using the GPU into the BC7 format and compares the results with 
the original image. You can optionally write out an uncompressed version of the texture to see the 
results. It only supports TGA images and is pretty bare bones to demonstrate how to use the code.

	usage: bc7_gpu image.tga [output.tga]

There is an OpenCL version and a CUDA version which can be switched with the #defines in 
"bc7_gpu.h". Hopefully it is fairly straight forward to incorporate the code into another tool. You
would use the following files:

	./bc7_gpu.h
	./bc7_compressed_block.h
	./bc7_decompress.h
	./bc7_decompress.cpp
	./CUDA/bc7_cuda.h
	./CUDA/bc7_cuda.cpp
	./CUDA/BC7.cu
	./OpenCL/bc7_opencl.h
	./OpenCL/bc7_opencl.cpp
	./OpenCL/BC7.opencl

This is a Visual Studio 2010 solution and it depends on the CUDA SDK to build (which should be easy
to change). The OpenCL version of the program does work on AMD cards as well.

The program will probably trip the "Timeout Detection and Recovery" for images that are large
enough. You can either disable the timeout in the registry or only dispatch portions of an image in
a loop.

Algorithm
---------

BC7 is a block compression scheme that compresses a 4x4 block of 24-bit or 32-bit pixels into 16 
bytes. Two colors in RGB or RGBA space are used as endpoints for interpolation to calculate the rest
of the block of pixels. BC7 has up to 3 sets of endpoints, where DXT1-5 just have one set. Since a 
GPU has several hundred, possibly thousands of threads, each thread runs the compression algorithm 
on a 4x4 block of pixels. BC7 has a large search space: there are 8 different modes, up to 64 ways 
to partition up the 16 pixels (called a "shape"), channel swapping, etc. The GPU code iterates over 
the 8 modes, optionally calculates which "shapes" are the best to refine, and refines them choosing 
the lowest error from the resulting combination of mode, shape, etc.

There is a define called __CULL_SHAPES that will chose the best shapes to refine using a linearity
measure of the set of pixels. The more linear a set of pixels are, the better they are going to fit
a line segment. I have found that just testing all the shapes resulted in higher quality and about
the same speed when using less Gradient Descent iterations.

Once the shapes to refine are chosen, a bounding box is found for each set of pixels. The 
minimum and maximum are used as the initial endpoints for the line segment. Gradient Descent is then 
used over several iterations to adjust the endpoints to minimize the error using floating point 
precision. Once that is finished, the endpoints are quantized to the correct precision and the 
pixels are assigned indices to the quantized palette.

I tried doing a local search after the endpoints were quantized but didn't see much of an 
improvement in quality and the performance suffered quite a bit.

Results
-------

CUDA:

	Compressing 'images/avatar.tga' 2560 x 1600...
	CUDA device: GeForce GTX 560
	Run kernel : 12.256 seconds
	bc7_cuda_compress : 12.915 seconds
	RGBA absolute error: 4550012
	RGBA mean-squared error: 0.441167
	RGBA root-mean-squared error: 0.664204
	
	Compressing 'images/house.tga' 2160 x 1636...
	CUDA device: GeForce GTX 560
	Run kernel : 11.169 seconds
	bc7_cuda_compress : 11.240 seconds
	RGBA absolute error: 13577773
	RGBA mean-squared error: 2.670688
	RGBA root-mean-squared error: 1.634224
	
	Compressing 'images/kodim01.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.311 seconds
	RGBA absolute error: 1271134
	RGBA mean-squared error: 1.650247
	RGBA root-mean-squared error: 1.284619
	
	Compressing 'images/kodim02.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.310 seconds
	RGBA absolute error: 989354
	RGBA mean-squared error: 1.242250
	RGBA root-mean-squared error: 1.114563
	
	Compressing 'images/kodim03.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.244 seconds
	bc7_cuda_compress : 1.309 seconds
	RGBA absolute error: 656886
	RGBA mean-squared error: 0.792077
	RGBA root-mean-squared error: 0.889987
	
	Compressing 'images/kodim04.tga' 512 x 768...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.310 seconds
	RGBA absolute error: 985358
	RGBA mean-squared error: 1.293538
	RGBA root-mean-squared error: 1.137338
	
	Compressing 'images/kodim05.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.311 seconds
	RGBA absolute error: 1520807
	RGBA mean-squared error: 2.807116
	RGBA root-mean-squared error: 1.675445
	
	Compressing 'images/kodim06.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.310 seconds
	RGBA absolute error: 1091974
	RGBA mean-squared error: 1.498057
	RGBA root-mean-squared error: 1.223951
	
	Compressing 'images/kodim21.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.311 seconds
	RGBA absolute error: 1104006
	RGBA mean-squared error: 1.527505
	RGBA root-mean-squared error: 1.235923
	
	Compressing 'images/kodim23.tga' 768 x 512...
	CUDA device: GeForce GTX 560
	Run kernel : 1.245 seconds
	bc7_cuda_compress : 1.332 seconds
	RGBA absolute error: 813875
	RGBA mean-squared error: 1.016289
	RGBA root-mean-squared error: 1.008112
	
	Compressing 'images/mandelbrot.tga' 2560 x 1920...
	CUDA device: GeForce GTX 560
	Run kernel : 13.877 seconds
	bc7_cuda_compress : 13.951 seconds
	RGBA absolute error: 25827552
	RGBA mean-squared error: 7.587682
	RGBA root-mean-squared error: 2.754575
	
	Compressing 'images/vfx_vue_sky.tga' 1024 x 1024...
	CUDA device: GeForce GTX 560
	Run kernel : 3.028 seconds
	bc7_cuda_compress : 3.098 seconds
	RGBA absolute error: 1066101
	RGBA mean-squared error: 0.314854
	RGBA root-mean-squared error: 0.561118

OpenCL:

	Compressing 'images/avatar.tga' 2560 x 1600...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 16.182 seconds
	bc7_opencl_compress : 16.351 seconds
	RGBA absolute error: 4550036
	RGBA mean-squared error: 0.441167
	RGBA root-mean-squared error: 0.664204
	
	Compressing 'images/house.tga' 2160 x 1636...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 14.370 seconds
	bc7_opencl_compress : 14.524 seconds
	RGBA absolute error: 13577814
	RGBA mean-squared error: 2.670691
	RGBA root-mean-squared error: 1.634225
	
	Compressing 'images/kodim01.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.561 seconds
	bc7_opencl_compress : 1.732 seconds
	RGBA absolute error: 1271118
	RGBA mean-squared error: 1.650266
	RGBA root-mean-squared error: 1.284627
	
	Compressing 'images/kodim02.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.574 seconds
	bc7_opencl_compress : 1.777 seconds
	RGBA absolute error: 989354
	RGBA mean-squared error: 1.242250
	RGBA root-mean-squared error: 1.114563
	
	Compressing 'images/kodim03.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.560 seconds
	bc7_opencl_compress : 1.722 seconds
	RGBA absolute error: 656875
	RGBA mean-squared error: 0.792077
	RGBA root-mean-squared error: 0.889987
	
	Compressing 'images/kodim04.tga' 512 x 768...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.571 seconds
	bc7_opencl_compress : 1.726 seconds
	RGBA absolute error: 985354
	RGBA mean-squared error: 1.293535
	RGBA root-mean-squared error: 1.137337
	
	Compressing 'images/kodim05.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.567 seconds
	bc7_opencl_compress : 1.752 seconds
	RGBA absolute error: 1520811
	RGBA mean-squared error: 2.807114
	RGBA root-mean-squared error: 1.675445
	
	Compressing 'images/kodim06.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.585 seconds
	bc7_opencl_compress : 1.776 seconds
	RGBA absolute error: 1091975
	RGBA mean-squared error: 1.498063
	RGBA root-mean-squared error: 1.223954
	
	Compressing 'images/kodim21.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.574 seconds
	bc7_opencl_compress : 1.732 seconds
	RGBA absolute error: 1104006
	RGBA mean-squared error: 1.527505
	RGBA root-mean-squared error: 1.235923
	
	Compressing 'images/kodim23.tga' 768 x 512...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 1.560 seconds
	bc7_opencl_compress : 1.739 seconds
	RGBA absolute error: 813879
	RGBA mean-squared error: 1.016283
	RGBA root-mean-squared error: 1.008109
	
	Compressing 'images/mandelbrot.tga' 2560 x 1920...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 18.314 seconds
	bc7_opencl_compress : 18.475 seconds
	RGBA absolute error: 25827552
	RGBA mean-squared error: 7.587684
	RGBA root-mean-squared error: 2.754575
	
	Compressing 'images/vfx_vue_sky.tga' 1024 x 1024...
	OpenCL device: GeForce GTX 560
	Create and build program : 0.003 seconds
	Run kernel : 3.996 seconds
	bc7_opencl_compress : 4.146 seconds
	RGBA absolute error: 1066058
	RGBA mean-squared error: 0.314847
	RGBA root-mean-squared error: 0.561112

You'll notice that the CUDA version is noticeably faster (~30-40%) with conceptually identical code.

Here are the results on a Radeon HD 5800:

	Compressing 'images/avatar.tga' 2560 x 1600...
	OpenCL device: Cypress
	Create and build program : 11.437 seconds
	Run kernel : 26.408 seconds
	bc7_opencl_compress : 38.206 seconds
	RGBA absolute error: 4549991
	RGBA mean-squared error: 0.441159
	RGBA root-mean-squared error: 0.664198
	
	Compressing 'images/house.tga' 2160 x 1636...
	OpenCL device: Cypress
	Create and build program : 11.428 seconds
	Run kernel : 23.578 seconds
	bc7_opencl_compress : 35.339 seconds
	RGBA absolute error: 13577779
	RGBA mean-squared error: 2.670689
	RGBA root-mean-squared error: 1.634224
	
	Compressing 'images/kodim01.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 10.690 seconds
	Run kernel : 2.659 seconds
	bc7_opencl_compress : 13.646 seconds
	RGBA absolute error: 1271086
	RGBA mean-squared error: 1.650277
	RGBA root-mean-squared error: 1.284631
	
	Compressing 'images/kodim02.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 10.541 seconds
	Run kernel : 2.661 seconds
	bc7_opencl_compress : 13.546 seconds
	RGBA absolute error: 989343
	RGBA mean-squared error: 1.242225
	RGBA root-mean-squared error: 1.114551
	
	Compressing 'images/kodim03.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 10.822 seconds
	Run kernel : 2.659 seconds
	bc7_opencl_compress : 13.781 seconds
	RGBA absolute error: 656878
	RGBA mean-squared error: 0.792070
	RGBA root-mean-squared error: 0.889983
	
	Compressing 'images/kodim04.tga' 512 x 768...
	OpenCL device: Cypress
	Create and build program : 10.706 seconds
	Run kernel : 2.658 seconds
	bc7_opencl_compress : 13.671 seconds
	RGBA absolute error: 985379
	RGBA mean-squared error: 1.293552
	RGBA root-mean-squared error: 1.137344
	
	Compressing 'images/kodim05.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 10.473 seconds
	Run kernel : 2.659 seconds
	bc7_opencl_compress : 13.449 seconds
	RGBA absolute error: 1520816
	RGBA mean-squared error: 2.807115
	RGBA root-mean-squared error: 1.675445
	
	Compressing 'images/kodim06.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 10.668 seconds
	Run kernel : 2.653 seconds
	bc7_opencl_compress : 13.624 seconds
	RGBA absolute error: 1091995
	RGBA mean-squared error: 1.498072
	RGBA root-mean-squared error: 1.223957
	
	Compressing 'images/kodim21.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 11.326 seconds
	Run kernel : 2.656 seconds
	bc7_opencl_compress : 14.272 seconds
	RGBA absolute error: 1103990
	RGBA mean-squared error: 1.527490
	RGBA root-mean-squared error: 1.235917
	
	Compressing 'images/kodim23.tga' 768 x 512...
	OpenCL device: Cypress
	Create and build program : 11.410 seconds
	Run kernel : 2.652 seconds
	bc7_opencl_compress : 14.349 seconds
	RGBA absolute error: 813873
	RGBA mean-squared error: 1.016269
	RGBA root-mean-squared error: 1.008102
	
	Compressing 'images/mandelbrot.tga' 2560 x 1920...
	OpenCL device: Cypress
	Create and build program : 11.316 seconds
	Run kernel : 31.018 seconds
	bc7_opencl_compress : 42.624 seconds
	RGBA absolute error: 25827645
	RGBA mean-squared error: 7.587698
	RGBA root-mean-squared error: 2.754578
	
	Compressing 'images/vfx_vue_sky.tga' 1024 x 1024...
	OpenCL device: Cypress
	Create and build program : 11.301 seconds
	Run kernel : 6.678 seconds
	bc7_opencl_compress : 18.259 seconds
	RGBA absolute error: 1066070
	RGBA mean-squared error: 0.314844
	RGBA root-mean-squared error: 0.561109

Interestingly, it seems like the AMD driver isn't caching the compiled program like NVIDIA is.

Contact
-------

I'd like to hear feedback, results, and improvements!

Jeremiah Zanin
jeremiah.zanin@volition-inc.com
jjzanin@gmail.com
@jjzanin
