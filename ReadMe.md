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

	Compressing 'images/earth.tga' 1024 x 1024... (http://tinyurl.com/8rt7wzc)
	CUDA device: GeForce GTX 560
	Run kernel : 2.597 seconds
	bc7_cuda_compress : 3.301 seconds
	RGBA absolute error: 2500684
	RGBA mean-squared error: 1.867799
	RGBA root-mean-squared error: 1.366674
	
	Compressing 'images/japanese_garden.tga' 4592 x 3056... (http://tinyurl.com/9e9xm87)
	CUDA device: GeForce GTX 560
	Run kernel : 43.765 seconds
	bc7_cuda_compress : 43.886 seconds
	RGBA absolute error: 43960775
	RGBA mean-squared error: 1.911637
	RGBA root-mean-squared error: 1.382620
	
	Compressing 'images/kodim01.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim01.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.246 seconds
	bc7_cuda_compress : 1.367 seconds
	RGBA absolute error: 1271134
	RGBA mean-squared error: 1.650247
	RGBA root-mean-squared error: 1.284619
	
	Compressing 'images/kodim02.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim02.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.247 seconds
	bc7_cuda_compress : 1.356 seconds
	RGBA absolute error: 989354
	RGBA mean-squared error: 1.242250
	RGBA root-mean-squared error: 1.114563
	
	Compressing 'images/kodim03.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim03.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.246 seconds
	bc7_cuda_compress : 1.348 seconds
	RGBA absolute error: 656886
	RGBA mean-squared error: 0.792077
	RGBA root-mean-squared error: 0.889987
	
	Compressing 'images/kodim04.tga' 512 x 768... (http://r0k.us/graphics/kodak/kodim04.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.246 seconds
	bc7_cuda_compress : 1.349 seconds
	RGBA absolute error: 985358
	RGBA mean-squared error: 1.293538
	RGBA root-mean-squared error: 1.137338
	
	Compressing 'images/kodim05.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim05.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.248 seconds
	bc7_cuda_compress : 1.360 seconds
	RGBA absolute error: 1520807
	RGBA mean-squared error: 2.807116
	RGBA root-mean-squared error: 1.675445
	
	Compressing 'images/kodim06.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim06.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.246 seconds
	bc7_cuda_compress : 1.348 seconds
	RGBA absolute error: 1091974
	RGBA mean-squared error: 1.498057
	RGBA root-mean-squared error: 1.223951
	
	Compressing 'images/kodim21.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim21.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.248 seconds
	bc7_cuda_compress : 1.350 seconds
	RGBA absolute error: 1104006
	RGBA mean-squared error: 1.527505
	RGBA root-mean-squared error: 1.235923
	
	Compressing 'images/kodim23.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim23.html)
	CUDA device: GeForce GTX 560
	Run kernel : 1.246 seconds
	bc7_cuda_compress : 1.349 seconds
	RGBA absolute error: 813875
	RGBA mean-squared error: 1.016289
	RGBA root-mean-squared error: 1.008112
	
	Compressing 'images/mandelbrot.tga' 2560 x 1920... (http://tinyurl.com/co6a9r)
	CUDA device: GeForce GTX 560
	Run kernel : 13.874 seconds
	bc7_cuda_compress : 13.981 seconds
	RGBA absolute error: 25827552
	RGBA mean-squared error: 7.587682
	RGBA root-mean-squared error: 2.754575

OpenCL:

	Compressing 'images/earth.tga' 1024 x 1024... (http://tinyurl.com/8rt7wzc)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 3.379 seconds
	bc7_opencl_compress : 3.655 seconds
	RGBA absolute error: 2500700
	RGBA mean-squared error: 1.867800
	RGBA root-mean-squared error: 1.366675
	
	Compressing 'images/japanese_garden.tga' 4592 x 3056... (http://tinyurl.com/9e9xm87)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 57.845 seconds
	bc7_opencl_compress : 58.139 seconds
	RGBA absolute error: 43960766
	RGBA mean-squared error: 1.911637
	RGBA root-mean-squared error: 1.382620
	
	Compressing 'images/kodim01.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim01.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.579 seconds
	bc7_opencl_compress : 1.832 seconds
	RGBA absolute error: 1271118
	RGBA mean-squared error: 1.650266
	RGBA root-mean-squared error: 1.284627
	
	Compressing 'images/kodim02.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim02.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.560 seconds
	bc7_opencl_compress : 1.831 seconds
	RGBA absolute error: 989354
	RGBA mean-squared error: 1.242250
	RGBA root-mean-squared error: 1.114563
	
	Compressing 'images/kodim03.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim03.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.012 seconds
	Run kernel : 1.570 seconds
	bc7_opencl_compress : 1.846 seconds
	RGBA absolute error: 656875
	RGBA mean-squared error: 0.792077
	RGBA root-mean-squared error: 0.889987
	
	Compressing 'images/kodim04.tga' 512 x 768... (http://r0k.us/graphics/kodak/kodim04.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.565 seconds
	bc7_opencl_compress : 1.838 seconds
	RGBA absolute error: 985354
	RGBA mean-squared error: 1.293535
	RGBA root-mean-squared error: 1.137337
	
	Compressing 'images/kodim05.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim05.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.553 seconds
	bc7_opencl_compress : 1.827 seconds
	RGBA absolute error: 1520811
	RGBA mean-squared error: 2.807114
	RGBA root-mean-squared error: 1.675445
	
	Compressing 'images/kodim06.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim06.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.558 seconds
	bc7_opencl_compress : 1.832 seconds
	RGBA absolute error: 1091975
	RGBA mean-squared error: 1.498063
	RGBA root-mean-squared error: 1.223954
	
	Compressing 'images/kodim21.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim21.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.591 seconds
	bc7_opencl_compress : 1.865 seconds
	RGBA absolute error: 1104006
	RGBA mean-squared error: 1.527505
	RGBA root-mean-squared error: 1.235923
	
	Compressing 'images/kodim23.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim23.html)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.011 seconds
	Run kernel : 1.547 seconds
	bc7_opencl_compress : 1.820 seconds
	RGBA absolute error: 813879
	RGBA mean-squared error: 1.016283
	RGBA root-mean-squared error: 1.008109
	
	Compressing 'images/mandelbrot.tga' 2560 x 1920... (http://tinyurl.com/co6a9r)
	OpenCL device: GeForce GTX 560
	Create and build program : 0.012 seconds
	Run kernel : 18.373 seconds
	bc7_opencl_compress : 18.655 seconds
	RGBA absolute error: 25827552
	RGBA mean-squared error: 7.587684
	RGBA root-mean-squared error: 2.754575

You'll notice that the CUDA version is noticeably faster (~30-40%) with conceptually identical code.

Here are the results on a Radeon HD 5800:

	Compressing 'images/earth.tga' 1024 x 1024... (http://tinyurl.com/8rt7wzc)
	OpenCL device: Cypress
	Create and build program : 10.978 seconds
	Run kernel : 6.310 seconds
	bc7_opencl_compress : 17.798 seconds
	RGBA absolute error: 2500707
	RGBA mean-squared error: 1.867790
	RGBA root-mean-squared error: 1.366671
	
	Compressing 'images/japanese_garden.tga' 4592 x 3056... (http://tinyurl.com/9e9xm87)
	OpenCL device: Cypress
	Create and build program : 10.744 seconds
	Run kernel : 92.614 seconds
	bc7_opencl_compress : 103.899 seconds
	RGBA absolute error: 43960712
	RGBA mean-squared error: 1.911637
	RGBA root-mean-squared error: 1.382620
	
	Compressing 'images/kodim01.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim01.html)
	OpenCL device: Cypress
	Create and build program : 10.882 seconds
	Run kernel : 2.660 seconds
	bc7_opencl_compress : 14.060 seconds
	RGBA absolute error: 1271086
	RGBA mean-squared error: 1.650277
	RGBA root-mean-squared error: 1.284631
	
	Compressing 'images/kodim02.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim02.html)
	OpenCL device: Cypress
	Create and build program : 10.952 seconds
	Run kernel : 2.656 seconds
	bc7_opencl_compress : 14.130 seconds
	RGBA absolute error: 989343
	RGBA mean-squared error: 1.242225
	RGBA root-mean-squared error: 1.114551
	
	Compressing 'images/kodim03.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim03.html)
	OpenCL device: Cypress
	Create and build program : 10.579 seconds
	Run kernel : 2.655 seconds
	bc7_opencl_compress : 13.764 seconds
	RGBA absolute error: 656878
	RGBA mean-squared error: 0.792070
	RGBA root-mean-squared error: 0.889983
	
	Compressing 'images/kodim04.tga' 512 x 768... (http://r0k.us/graphics/kodak/kodim04.html)
	OpenCL device: Cypress
	Create and build program : 10.616 seconds
	Run kernel : 2.657 seconds
	bc7_opencl_compress : 13.782 seconds
	RGBA absolute error: 985379
	RGBA mean-squared error: 1.293552
	RGBA root-mean-squared error: 1.137344
	
	Compressing 'images/kodim05.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim05.html)
	OpenCL device: Cypress
	Create and build program : 10.619 seconds
	Run kernel : 2.660 seconds
	bc7_opencl_compress : 13.784 seconds
	RGBA absolute error: 1520816
	RGBA mean-squared error: 2.807115
	RGBA root-mean-squared error: 1.675445
	
	Compressing 'images/kodim06.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim06.html)
	OpenCL device: Cypress
	Create and build program : 11.285 seconds
	Run kernel : 2.661 seconds
	bc7_opencl_compress : 14.437 seconds
	RGBA absolute error: 1091995
	RGBA mean-squared error: 1.498072
	RGBA root-mean-squared error: 1.223957
	
	Compressing 'images/kodim21.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim21.html)
	OpenCL device: Cypress
	Create and build program : 10.490 seconds
	Run kernel : 2.652 seconds
	bc7_opencl_compress : 13.667 seconds
	RGBA absolute error: 1103990
	RGBA mean-squared error: 1.527490
	RGBA root-mean-squared error: 1.235917
	
	Compressing 'images/kodim23.tga' 768 x 512... (http://r0k.us/graphics/kodak/kodim23.html)
	OpenCL device: Cypress
	Create and build program : 10.740 seconds
	Run kernel : 2.653 seconds
	bc7_opencl_compress : 13.893 seconds
	RGBA absolute error: 813873
	RGBA mean-squared error: 1.016269
	RGBA root-mean-squared error: 1.008102
	
	Compressing 'images/mandelbrot.tga' 2560 x 1920... (http://tinyurl.com/co6a9r)
	OpenCL device: Cypress
	Create and build program : 10.873 seconds
	Run kernel : 31.025 seconds
	bc7_opencl_compress : 42.405 seconds
	RGBA absolute error: 25827645
	RGBA mean-squared error: 7.587698
	RGBA root-mean-squared error: 2.754578

Interestingly, it seems like the AMD driver isn't caching the compiled program like NVIDIA is.

Contact
-------

I'd like to hear feedback, results, and improvements!

Jeremiah Zanin
jeremiah.zanin@volition-inc.com
jjzanin@gmail.com
@jjzanin
