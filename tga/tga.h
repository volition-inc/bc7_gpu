//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __TGA_H
#define __TGA_H

// --------------------
//
// Defines/Macros
//
// --------------------


// --------------------
//
// Enumerated types
//
// --------------------


// --------------------
//
// Structures/Classes
//
// --------------------

// The TGA header.
struct tga_header {

	uint8_t m_id_length;
	uint8_t m_color_map_type;
	uint8_t m_image_type;

	uint16_t get_x_origin() const 
	{
		return (m_image_specification[1] << 8) | m_image_specification[0];
	}

	uint16_t get_y_origin() const 
	{
		return (m_image_specification[3] << 8) | m_image_specification[2];
	}

	uint16_t get_width() const 
	{
		return (m_image_specification[5] << 8) | m_image_specification[4];
	}

	uint16_t get_height() const 
	{
		return (m_image_specification[7] << 8) | m_image_specification[6];
	}

	uint8_t get_bits_per_pixel() const 
	{
		return m_image_specification[8];
	}

	void set_bits_per_pixel(uint8_t bits_per_pixel)
	{
		m_image_specification[8] = bits_per_pixel;
	}

	uint8_t get_descriptor() const 
	{
		return m_image_specification[9];
	}

	uint8_t get_origin() const 
	{
		uint8_t const descriptor = get_descriptor();
		return (descriptor >> 4) & 0x3;
	}

private:

	uint8_t m_color_map_specification[5];
	uint8_t m_image_specification[10];
};

// --------------------
//
// Variables
//
// --------------------


// --------------------
//
// Prototypes
//
// --------------------

// Load a TGA image.
//
// header:		(output) The TGA header.
// p_filename:	The filename of the TGA to load.
//
// returns: A pointer to the image buffer.
//
uint8_t* tga_load(tga_header& header, char const* p_filename);

// Free the TGA image.
//
// p_buffer: (input/output) A pointer to the buffer. This is set to NULL.
//
void tga_destroy(uint8_t** p_buffer);

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
					uint8_t const* p_data, size_t data_size);

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
						 tga_header const& header);

#endif // __TGA_H
