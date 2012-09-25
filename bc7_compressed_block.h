//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __BC7_DESTINATION_BLOCK_H
#define __BC7_DESTINATION_BLOCK_H

#include <stdint.h>

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

// A compressed block of pixels.
struct bc7_compressed_block {

	uint8_t m_data[16];
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


#endif // __BC7_DESTINATION_BLOCK_H
