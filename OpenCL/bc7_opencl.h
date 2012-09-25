//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __BC7_OPENCL_H
#define __BC7_OPENCL_H

#include "bc7_gpu.h"

#if defined(__BC7_OPENCL)

#include "bc7_compressed_block.h"

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

// Compress a texture to the BC7 format using OpenCL.
//
// p_destination: The buffer to store the compressed texture. It is assumed that the buffer is the
//						correct size (source size / 4).
// p_source:		The source image data. This must be 32-bit RGBA.
// width:			Width of the image in pixels. Must be a multiple of 4.
// height:			Height of the image in pixels. Must be a multiple of 4.
// 
// returns: True if successful.
//
bool bc7_opencl_compress(bc7_compressed_block* p_destination, uint8_t const* p_source, size_t width, size_t height);

#endif // #if defined(__BC7_OPENCL)

#endif // __BC7_OPENCL_H
