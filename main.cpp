//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#include "stdafx.h"

#include <math.h>

#ifdef __APPLE__
#include <stdlib.h>
#include <string.h>
#endif

#include "bc7_compressed_block.h"
#include "bc7_decompress.h"
#include "CUDA/bc7_cuda.h"
#include "OpenCL/bc7_opencl.h"
#include "scoped_timer.h"
#include "tga/tga.h"

// Compare the original TGA with the one that was compressed with BC7.
//
// p_original:				Original TGA image.
// p_bc7_image:			The uncompressed image.
// num_pixels:				Number of pixels in the images.
// original_has_alpha:	Whether or not the original has an alpha channel.
//
static void bc7_compare_images(uint8_t const* p_original, uint8_t const* p_bc7_image, 
										 size_t num_pixels, bool original_has_alpha)
{
	uint64_t absolute_error = 0;

	// Mean-squared error.
	double mse = 0.0;	

	for (size_t pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

		// TGAs are BGRA.
		uint8_t const original_blue	= *p_original++;		
		uint8_t const original_green	= *p_original++;
		uint8_t const original_red		= *p_original++;		

		uint8_t original_alpha = 255;
		if (original_has_alpha == true) {

			original_alpha = *p_original++;
		}

		uint8_t const bc7_red	= *p_bc7_image++;
		uint8_t const bc7_green = *p_bc7_image++;
		uint8_t const bc7_blue	= *p_bc7_image++;
		uint8_t const bc7_alpha = *p_bc7_image++;

		int32_t diff_red		= original_red - bc7_red;
		int32_t diff_green	= original_green - bc7_green;
		int32_t diff_blue		= original_blue - bc7_blue;
		int32_t diff_alpha	= original_alpha - bc7_alpha;

		diff_red		= (diff_red < 0) ? -diff_red : diff_red;
		diff_green	= (diff_green < 0) ? -diff_green : diff_green;
		diff_blue	= (diff_blue < 0) ? -diff_blue : diff_blue;
		diff_alpha	= (diff_alpha < 0) ? -diff_alpha : diff_alpha;

		absolute_error += diff_red + diff_green + diff_blue + diff_alpha;

		mse += diff_red * diff_red + diff_green * diff_green + 
				 diff_blue * diff_blue + diff_alpha * diff_alpha;

	} // end for

	printf("RGBA absolute error: %llu\n", absolute_error);

	mse = mse / (4.0 * num_pixels);
	printf("RGBA mean-squared error: %f\n", mse);

	double rmse = sqrt(mse);
	printf("RGBA root-mean-squared error: %f\n", rmse);
}

#ifdef WIN32
int _tmain(int argc, _TCHAR* argv[])
#elif __APPLE__
int main(int argc, char *argv[])
#endif
{
	scoped_timer::initialize();

	if ((argc != 2) && (argc != 3)) {

		printf("usage: bc7_gpu image.tga [output.tga]");
		return -1;
	}

	// Load the TGA.
	tga_header image_header;
	uint8_t* p_tga_source = tga_load(image_header, argv[1]);
	if (p_tga_source == NULL) {

		return -1;
	}

	uint16_t const source_width = image_header.get_width();
	uint16_t const source_height = image_header.get_height();
	bool const has_alpha = (image_header.get_bits_per_pixel() == 32);

	if (source_width & 0x3) {

		printf("The width of the image must be a multiple of 4!\n");
		return -1;
	}

	if (source_height & 0x3) {

		printf("The height of the image must be a multiple of 4!\n");
		return -1;
	}

	// Allocate and fill in a 32-bit RGBA source buffer.
	size_t const num_pixels = source_width * source_height;
	uint8_t* p_source = reinterpret_cast< uint8_t* >(malloc(4 * num_pixels));
	{
		size_t dest_index = 0;
		size_t source_index = 0;
		for (size_t i = 0; i < num_pixels; i++) {		

			// TGAs are BGR so swap to RGB.
			p_source[ dest_index ]		= p_tga_source[ source_index + 2 ];
			p_source[ dest_index + 1 ] = p_tga_source[ source_index + 1 ];
			p_source[ dest_index + 2 ] = p_tga_source[ source_index ];

			if (has_alpha == true) {

				p_source[ dest_index + 3 ] = p_tga_source[ source_index + 3 ];

			} else {

				p_source[ dest_index + 3 ] = 255;
			}

			source_index += has_alpha ? 4 : 3;
			dest_index += 4;
		}
	}

	// Allocate memory for the destination buffer.
	size_t const num_blocks = image_header.get_width() * image_header.get_height() / 16;
	size_t const compressed_size = num_blocks * sizeof(bc7_compressed_block);
	bc7_compressed_block* p_compressed = reinterpret_cast< bc7_compressed_block* >(malloc(compressed_size));
	if (p_compressed == NULL) {

		printf("Failed to allocate memory for the compressed image!\n");
		return -1;
	}

	printf("Compressing '%s' %u x %u...\n", argv[1], source_width, source_height);

	// Compress the image.
#if defined(__BC7_OPENCL)

	if (bc7_opencl_compress(p_compressed, p_source, source_width, source_height) == false) {

		return -1;
	}

#elif defined(__BC7_CUDA)

	if (bc7_cuda_compress(p_compressed, p_source, source_width, source_height) == false) {

		return -1;	
	}

#endif

	// Allocate memory for the decompressed image (it's 32-bits per pixel).
	size_t const decompressed_size = source_width * source_height * 4;
	uint8_t* p_decompressed = reinterpret_cast< uint8_t* >(malloc(decompressed_size));
	if (p_decompressed == NULL) {

		printf("Failed to allocate memory for the decompressed image!\n");
		return -1;
	}

	// Decompress the image.
	if (bc7_decompress(p_decompressed, p_compressed, source_width, source_height) == false) {

		return -1;
	}

	// Compare the images.	
	bc7_compare_images(p_tga_source, p_decompressed, source_width * source_height, has_alpha);

	// Write out the decompressed image.
	if (argc == 3) {

		if (strcmp(argv[1], argv[2]) == 0) {

			printf("The input and output filenames are the same!\n");
			return -1;
		}

		image_header.set_bits_per_pixel(32);
		if (tga_write(image_header, argv[2], p_decompressed, decompressed_size) == false) {

			return -1;
		}
	}

	// Free the decompressed data.
	free(p_decompressed);

	// Free the compressed data.
	free(p_compressed);

	// Free the source data.
	free(p_source);

	// Free the TGA buffer.
	tga_destroy(&p_tga_source);

	return 0;
}

