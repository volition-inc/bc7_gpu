//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#include <malloc.h>
#include <stdint.h>
#include <stdio.h>

#include "tga.h"

// --------------------
//
// Defines/Macros
//
// --------------------


// --------------------
//
// Enumerated Types
//
// --------------------


// --------------------
//
// Structures/Classes
//
// --------------------


// --------------------
//
// Global Variables
//
// --------------------


// --------------------
//
// Local Variables
//
// --------------------


// --------------------
//
// Internal Functions
//
// --------------------


// --------------------
//
// External Functions
//
// --------------------

// Load a TGA image.
//
// header:		(output) The TGA header.
// p_filename:	The filename of the TGA to load.
//
// returns: A pointer to the image buffer.
//
uint8_t* tga_load(tga_header& header, char const* p_filename)
{
	FILE* p_infile;
	errno_t result = fopen_s(&p_infile, p_filename, "rb");
	if (result != 0) {

		printf("Failed to open \"%s\"!\n", p_filename);
		return NULL;
	}

	size_t num_read = fread(&header, sizeof(header), 1, p_infile);
	if (num_read != 1) {

		printf("Failed to read the header for \"%s\"!\n", p_filename);

		fclose(p_infile);
		return NULL;
	}

	if (header.m_image_type != 2) {

		printf("Failed to load \"%s\". Only uncompressed true-color images are supported.\n", p_filename);

		fclose(p_infile);
		return NULL;
	}

	uint16_t const width = header.get_width();
	uint16_t const height = header.get_height();
	uint8_t const bits_per_pixel = header.get_bits_per_pixel();

	if ((bits_per_pixel != 24) && (bits_per_pixel != 32)) {

		printf("Failed to load \"%s\".Only 24 and 32 bit images are supported!\n", p_filename);

		fclose(p_infile);
		return NULL;
	}

	size_t const data_size = width * height * bits_per_pixel / 8;
	uint8_t* p_image_data = reinterpret_cast< uint8_t* >(malloc(data_size));
	if (p_image_data == NULL) {

		printf("Failed to allocate %u bytes for the image \"%s\"!\n", data_size, p_filename);
		return NULL;
	}

	num_read = fread(p_image_data, data_size, 1, p_infile);
	if (num_read != 1) {

		printf("Failed to read the image data \"%s\"!\n", p_filename);

		fclose(p_infile);
		return NULL;
	}

	fclose(p_infile);

	return p_image_data;
}

// Free the TGA image.
//
// p_buffer: (input/output) A pointer to the buffer. This is set to NULL.
//
void tga_destroy(uint8_t** p_buffer)
{
	free(*p_buffer);
	*p_buffer = NULL;
}

// Write out a TGA image.
// Note: This expects a 32-bit RGBA source and 32-bit target.
//
// header:		The TGA header.
// p_filename:	The filename of the TGA to write out.
// p_data:		The 32-bit RGBA image data.
// data_size:	The size of the image data in bytes.
//
// returns: True if successful.
//
bool tga_write(tga_header const& header, char const* p_filename,
					uint8_t const* p_data, size_t data_size)
{
	if (data_size & 0x3) {

		printf("Expecting 32 bits for the source image!\n");
		return false;
	}

	if (header.get_bits_per_pixel() != 32) {

		printf("Expecting 32 bits for the output image!\n");
		return false;
	}

	FILE* p_outfile;
	errno_t result = fopen_s(&p_outfile, p_filename, "wb");
	if (result != 0) {

		printf("Failed to open \"%s\"!\n", p_filename);
		return NULL;
	}

	// Write out the header.
	fwrite(&header, sizeof(header), 1, p_outfile);

	// Write out the image data.
	size_t const num_pixels = data_size / 4;
	for (size_t pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

		uint8_t const red		= *p_data++;
		uint8_t const green	= *p_data++;
		uint8_t const blue	= *p_data++;
		uint8_t const alpha	= *p_data++;

		// TGAs are BGRA.
		fwrite(&blue, sizeof(blue), 1, p_outfile);
		fwrite(&green, sizeof(green), 1, p_outfile);
		fwrite(&red, sizeof(red), 1, p_outfile);
		fwrite(&alpha, sizeof(alpha), 1, p_outfile);

	} // end for

	fclose(p_outfile);

	return true;
}

// Get a pixel from the image.
//
// red:				(output) The red channel.
// green:			(output) The green channel.
// blue:				(output) The blue channel.
// alpha:			(output) The alpha channel.
// p_image_data:	The TGA image data.
// x:					The x coordinate of the pixel.
// y:					The y coordinate of the pixel.
// header:			The TGA header.
//
void tga_get_pixel(uint8_t& red, uint8_t& green, uint8_t& blue, uint8_t& alpha,
						 uint8_t const* p_image_data, uint32_t x, uint32_t y,
						 tga_header const& header)
{
	uint32_t const width = header.get_width();
	uint32_t const height = header.get_height();
	uint32_t const bytes_per_pixel = header.get_bits_per_pixel() >> 3;

	uint32_t pixel_x = x;
	uint32_t pixel_y = y;
	switch (header.get_origin()) {
		case 0: {

			// Bottom left.
			pixel_y = (height - 1) - y;
			break;
		}
		case 1: {
			// Bottom right.
			pixel_x = (width - 1) - x;
			pixel_y = (height - 1) - y;
			break;
		}
		case 2: {

			// Top left.		
			pixel_x = x;
			pixel_y = y;
			break;
		}
		case 3: {

			// Top right.
			pixel_x = (width - 1) - x;
			break;
		}
		default: {

			break;
		}
	}

	uint32_t const index = (pixel_y * width + pixel_x) * bytes_per_pixel;

	blue  = p_image_data[ index ];
	green = p_image_data[ index + 1 ];
	red   = p_image_data[ index + 2 ];

	alpha = 255;
	if (bytes_per_pixel == 4) {

		alpha = p_image_data[ index + 3 ];
	}
}
