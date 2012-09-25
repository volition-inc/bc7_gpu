//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __BC7_DECOMPRESS_H
#define __BC7_DECOMPRESS_H

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

// Decompress BC7 data.
bool bc7_decompress(uint8_t* p_decompressed, bc7_compressed_block const* p_compressed,
						  size_t image_width, size_t image_height);

#endif // __BC7_DECOMPRESS_H
