//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#include <assert.h>
#include <stdio.h>

#include "bc7_compressed_block.h"
#include "bc7_decompress.h"

// --------------------
//
// Defines/Macros
//
// --------------------

// BC7 compresses a block of 4x4 pixels.
#define BC7_NUM_PIXELS_PER_BLOCK 16

// Number of modes that BC7 has.
#define BC7_NUM_MODES 8

// Maximum number of subsets for a mode.
#define BC7_MAX_SUBSETS 3

// Maximum number of ways to partition up the 16 pixels.
#define BC7_MAX_SHAPES 64

// Total number of weights for the palettes.
#define BC7_NUM_PALETTE_WEIGHTS (4 + 8 + 16)

// Interpolation constants.
#define BC7_INTERPOLATION_MAX_WEIGHT			64
#define BC7_INTERPOLATION_MAX_WEIGHT_SHIFT	6
#define BC7_INTERPOLATION_ROUND					32

// --------------------
//
// Enumerated Types
//
// --------------------

// The type of parity used for a mode. If a mode has a parity bit then the least
// significant bit of the color channels uses the parity bit.
enum bc7_parity_bit_type {

	PARITY_BIT_NONE = 0,
	PARITY_BIT_SHARED,
	PARITY_BIT_PER_ENDPOINT
};

// --------------------
//
// Structures/Classes
//
// --------------------

// This describes a BC7 mode.
struct bc7_mode {

	// The full precision (including the parity bit) for each channel of the endpoints.
	uint32_t m_endpoint_precision[4];

	// Number of subsets.
	uint32_t m_num_subsets;

	// Number of bits for the ways to partition up the 16 pixels 
	// among the subsets.
	uint32_t m_num_shape_bits;

	// Number of bits for the color channel swaps with the alpha channel.
	uint32_t m_num_rotation_bits;

	// Number of bits for the index selection bit.
	uint32_t m_num_isb_bits;

	// The type of parity used for this mode.
	bc7_parity_bit_type m_parity_bit_type;

	// Number of bits for the color palette indices.
	uint32_t m_num_index_bits_1;

	// The size of the color palette (1 << m_num_index_bits).
	uint32_t m_palette_size_1;

	// The starting index into the Palette_weights for this palette.
	uint32_t m_palette_start_1;

	// Number of bits for the alpha palette indices.
	uint32_t m_num_index_bits_2;

	// The size of the alpha palette (1 << m_num_index_bits2);
	uint32_t m_palette_size_2;

	// The starting index into the Palette_weights for this palette.
	uint32_t m_palette_start_2;
};

// This is a 4x4 block of 32-bit pixels.
struct bc7_decompressed_block {

	uint8_t m_pixels[4][4][4];
};

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

// Mode CB AB NS PB RB ISB EPB SPB IB IB2
// ---- -- -- -- -- -- --- --- --- -- ---
// 0    4  0  3  4  0  0   1   0   3  0
// 1    6  0  2  6  0  0   0   1   3  0
// 2    5  0  3  6  0  0   0   0   2  0
// 3    7  0  2  6  0  0   1   0   2  0
// 4    5  6  1  0  2  1   0   0   2  3
// 5    7  8  1  0  2  0   0   0   2  2
// 6    7  7  1  0  0  0   1   0   4  0
// 7    5  5  2  6  0  0   1   0   2  0
//
// The columns are as as follows:
//
// CB: 	Color bits
// AB: 	Alpha bits
// NS: 	Number of subsets in each partition
// PB: 	Partition bits
// RB: 	Rotation bits
// ISB: 	Index selection bits
// EPB: 	Endpoint P-bits
// SPB: 	Shared P-bits
// IB: 	Index bits per element
// IB2: 	Secondary index bits per element
//
static bc7_mode BC7_modes[ BC7_NUM_MODES ] = {

	// Mode 0
	{ { 5, 5, 5, 0 }, 3, 4, 0, 0, PARITY_BIT_PER_ENDPOINT, 3, 8, 4, 0, 0, 0 },

	// Mode 1
	{ { 7, 7, 7, 0 }, 2, 6, 0, 0, PARITY_BIT_SHARED, 3, 8, 4, 0, 0, 0 },

	// Mode 2
	{ { 5, 5, 5, 0 }, 3, 6, 0, 0, PARITY_BIT_NONE, 2, 4, 0, 0, 0, 0 },

	// Mode 3
	{ { 8, 8, 8, 0 }, 2, 6, 0, 0, PARITY_BIT_PER_ENDPOINT, 2, 4, 0, 0, 0, 0 },

	// Mode 4
	{ { 5, 5, 5, 6 }, 1, 0, 2, 1, PARITY_BIT_NONE, 2, 4, 0, 3, 8, 4 },

	// Mode 5
	{ { 7, 7, 7, 8 }, 1, 0, 2, 0, PARITY_BIT_NONE, 2, 4, 0, 2, 4, 0 },

	// Mode 6
	{ { 8, 8, 8, 8 }, 1, 0, 0, 0, PARITY_BIT_PER_ENDPOINT, 4, 16, 12, 0, 0, 0 },

	// Mode 7
	{ { 6, 6, 6, 6 }, 2, 6, 0, 0, PARITY_BIT_PER_ENDPOINT, 2, 4, 0, 0, 0, 0 }
};

// This table determines how pixels are partitioned up in the subsets.
//
static uint8_t Partition_table[ BC7_MAX_SUBSETS ][ BC7_MAX_SHAPES ][ BC7_NUM_PIXELS_PER_BLOCK ] =
{
	{   // 1 Region case has no subsets (all 0)
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	},

	{   // BC6H/BC7 Partition Set for 2 Subsets
		{ 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1 }, // Shape 0
		{ 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, // Shape 1
		{ 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1 }, // Shape 2
		{ 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 1 }, // Shape 3
		{ 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1 }, // Shape 4
		{ 0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1 }, // Shape 5
		{ 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1 }, // Shape 6
		{ 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1 }, // Shape 7
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1 }, // Shape 8
		{ 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, // Shape 9
		{ 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1 }, // Shape 10
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1 }, // Shape 11
		{ 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, // Shape 12
		{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1 }, // Shape 13
		{ 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, // Shape 14
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1 }, // Shape 15
		{ 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1 }, // Shape 16
		{ 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 }, // Shape 17
		{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0 }, // Shape 18
		{ 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0 }, // Shape 19
		{ 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 }, // Shape 20
		{ 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0 }, // Shape 21
		{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0 }, // Shape 22
		{ 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1 }, // Shape 23
		{ 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0 }, // Shape 24
		{ 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0 }, // Shape 25
		{ 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0 }, // Shape 26
		{ 0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0 }, // Shape 27
		{ 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0 }, // Shape 28
		{ 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 }, // Shape 29
		{ 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0 }, // Shape 30
		{ 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0 }, // Shape 31

		// BC7 Partition Set for 2 Subsets (second-half)
		{ 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1 }, // Shape 32
		{ 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1 }, // Shape 33
		{ 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0 }, // Shape 34
		{ 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0 }, // Shape 35
		{ 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0 }, // Shape 36
		{ 0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0 }, // Shape 37
		{ 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1 }, // Shape 38
		{ 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1 }, // Shape 39
		{ 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0 }, // Shape 40
		{ 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0 }, // Shape 41
		{ 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0 }, // Shape 42
		{ 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0 }, // Shape 43
		{ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0 }, // Shape 44
		{ 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1 }, // Shape 45
		{ 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1 }, // Shape 46
		{ 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0 }, // Shape 47
		{ 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0 }, // Shape 48
		{ 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0 }, // Shape 49
		{ 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0 }, // Shape 50
		{ 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0 }, // Shape 51
		{ 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1 }, // Shape 52
		{ 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1 }, // Shape 53
		{ 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0 }, // Shape 54
		{ 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0 }, // Shape 55
		{ 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1 }, // Shape 56
		{ 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1 }, // Shape 57
		{ 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1 }, // Shape 58
		{ 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1 }, // Shape 59
		{ 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1 }, // Shape 60
		{ 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0 }, // Shape 61
		{ 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0 }, // Shape 62
		{ 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1 }  // Shape 63
	},

	{   // BC7 Partition Set for 3 Subsets
		{ 0, 0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 1, 2, 2, 2, 2 }, // Shape 0
		{ 0, 0, 0, 1, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 2, 1 }, // Shape 1
		{ 0, 0, 0, 0, 2, 0, 0, 1, 2, 2, 1, 1, 2, 2, 1, 1 }, // Shape 2
		{ 0, 2, 2, 2, 0, 0, 2, 2, 0, 0, 1, 1, 0, 1, 1, 1 }, // Shape 3
		{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2 }, // Shape 4
		{ 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 2, 2 }, // Shape 5
		{ 0, 0, 2, 2, 0, 0, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1 }, // Shape 6
		{ 0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1 }, // Shape 7
		{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2 }, // Shape 8
		{ 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2 }, // Shape 9
		{ 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2 }, // Shape 10
		{ 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2 }, // Shape 11
		{ 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2 }, // Shape 12
		{ 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2, 2, 0, 1, 2, 2 }, // Shape 13
		{ 0, 0, 1, 1, 0, 1, 1, 2, 1, 1, 2, 2, 1, 2, 2, 2 }, // Shape 14
		{ 0, 0, 1, 1, 2, 0, 0, 1, 2, 2, 0, 0, 2, 2, 2, 0 }, // Shape 15
		{ 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 2, 1, 1, 2, 2 }, // Shape 16
		{ 0, 1, 1, 1, 0, 0, 1, 1, 2, 0, 0, 1, 2, 2, 0, 0 }, // Shape 17
		{ 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 2, 2 }, // Shape 18
		{ 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 1, 1, 1, 1 }, // Shape 19
		{ 0, 1, 1, 1, 0, 1, 1, 1, 0, 2, 2, 2, 0, 2, 2, 2 }, // Shape 20
		{ 0, 0, 0, 1, 0, 0, 0, 1, 2, 2, 2, 1, 2, 2, 2, 1 }, // Shape 21
		{ 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 2, 2, 0, 1, 2, 2 }, // Shape 22
		{ 0, 0, 0, 0, 1, 1, 0, 0, 2, 2, 1, 0, 2, 2, 1, 0 }, // Shape 23
		{ 0, 1, 2, 2, 0, 1, 2, 2, 0, 0, 1, 1, 0, 0, 0, 0 }, // Shape 24
		{ 0, 0, 1, 2, 0, 0, 1, 2, 1, 1, 2, 2, 2, 2, 2, 2 }, // Shape 25
		{ 0, 1, 1, 0, 1, 2, 2, 1, 1, 2, 2, 1, 0, 1, 1, 0 }, // Shape 26
		{ 0, 0, 0, 0, 0, 1, 1, 0, 1, 2, 2, 1, 1, 2, 2, 1 }, // Shape 27
		{ 0, 0, 2, 2, 1, 1, 0, 2, 1, 1, 0, 2, 0, 0, 2, 2 }, // Shape 28
		{ 0, 1, 1, 0, 0, 1, 1, 0, 2, 0, 0, 2, 2, 2, 2, 2 }, // Shape 29
		{ 0, 0, 1, 1, 0, 1, 2, 2, 0, 1, 2, 2, 0, 0, 1, 1 }, // Shape 30
		{ 0, 0, 0, 0, 2, 0, 0, 0, 2, 2, 1, 1, 2, 2, 2, 1 }, // Shape 31
		{ 0, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 2, 1, 2, 2, 2 }, // Shape 32
		{ 0, 2, 2, 2, 0, 0, 2, 2, 0, 0, 1, 2, 0, 0, 1, 1 }, // Shape 33
		{ 0, 0, 1, 1, 0, 0, 1, 2, 0, 0, 2, 2, 0, 2, 2, 2 }, // Shape 34
		{ 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0 }, // Shape 35
		{ 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0 }, // Shape 36
		{ 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0 }, // Shape 37
		{ 0, 1, 2, 0, 2, 0, 1, 2, 1, 2, 0, 1, 0, 1, 2, 0 }, // Shape 38
		{ 0, 0, 1, 1, 2, 2, 0, 0, 1, 1, 2, 2, 0, 0, 1, 1 }, // Shape 39
		{ 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0, 1, 1 }, // Shape 40
		{ 0, 1, 0, 1, 0, 1, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2 }, // Shape 41
		{ 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 2, 1, 2, 1, 2, 1 }, // Shape 42
		{ 0, 0, 2, 2, 1, 1, 2, 2, 0, 0, 2, 2, 1, 1, 2, 2 }, // Shape 43
		{ 0, 0, 2, 2, 0, 0, 1, 1, 0, 0, 2, 2, 0, 0, 1, 1 }, // Shape 44
		{ 0, 2, 2, 0, 1, 2, 2, 1, 0, 2, 2, 0, 1, 2, 2, 1 }, // Shape 45
		{ 0, 1, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 0, 1, 0, 1 }, // Shape 46
		{ 0, 0, 0, 0, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1 }, // Shape 47
		{ 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 2, 2, 2, 2 }, // Shape 48
		{ 0, 2, 2, 2, 0, 1, 1, 1, 0, 2, 2, 2, 0, 1, 1, 1 }, // Shape 49
		{ 0, 0, 0, 2, 1, 1, 1, 2, 0, 0, 0, 2, 1, 1, 1, 2 }, // Shape 50
		{ 0, 0, 0, 0, 2, 1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 2 }, // Shape 51
		{ 0, 2, 2, 2, 0, 1, 1, 1, 0, 1, 1, 1, 0, 2, 2, 2 }, // Shape 52
		{ 0, 0, 0, 2, 1, 1, 1, 2, 1, 1, 1, 2, 0, 0, 0, 2 }, // Shape 53
		{ 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 2, 2 }, // Shape 54
		{ 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 2, 1, 1, 2 }, // Shape 55
		{ 0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 2, 2, 2, 2, 2, 2 }, // Shape 56
		{ 0, 0, 2, 2, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 2, 2 }, // Shape 57
		{ 0, 0, 2, 2, 1, 1, 2, 2, 1, 1, 2, 2, 0, 0, 2, 2 }, // Shape 58
		{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2 }, // Shape 59
		{ 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1 }, // Shape 60
		{ 0, 2, 2, 2, 1, 2, 2, 2, 0, 2, 2, 2, 1, 2, 2, 2 }, // Shape 61
		{ 0, 1, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 }, // Shape 62
		{ 0, 1, 1, 1, 2, 0, 1, 1, 2, 2, 0, 1, 2, 2, 2, 0 }  // Shape 63
	}
};

// This table determines which palette indices are anchor indices.
//
static uint8_t Anchor_table[ BC7_MAX_SUBSETS ][ BC7_MAX_SHAPES ][ BC7_MAX_SUBSETS ] =
{
	{   // No fix-ups for 1st subset for BC6H or BC7
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0},
		{ 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}, { 0, 0, 0}
	},

	{   // BC6H/BC7 Partition Set Fixups for 2 Subsets
		{ 0,15, 0}, { 0,15, 0}, { 0,15, 0}, { 0,15, 0},
		{ 0,15, 0}, { 0,15, 0}, { 0,15, 0}, { 0,15, 0},
		{ 0,15, 0}, { 0,15, 0}, { 0,15, 0}, { 0,15, 0},
		{ 0,15, 0}, { 0,15, 0}, { 0,15, 0}, { 0,15, 0},
		{ 0,15, 0}, { 0, 2, 0}, { 0, 8, 0}, { 0, 2, 0},
		{ 0, 2, 0}, { 0, 8, 0}, { 0, 8, 0}, { 0,15, 0},
		{ 0, 2, 0}, { 0, 8, 0}, { 0, 2, 0}, { 0, 2, 0},
		{ 0, 8, 0}, { 0, 8, 0}, { 0, 2, 0}, { 0, 2, 0},

		// BC7 Partition Set Fixups for 2 Subsets (second-half)
		{ 0,15, 0}, { 0,15, 0}, { 0, 6, 0}, { 0, 8, 0},
		{ 0, 2, 0}, { 0, 8, 0}, { 0,15, 0}, { 0,15, 0},
		{ 0, 2, 0}, { 0, 8, 0}, { 0, 2, 0}, { 0, 2, 0},
		{ 0, 2, 0}, { 0,15, 0}, { 0,15, 0}, { 0, 6, 0},
		{ 0, 6, 0}, { 0, 2, 0}, { 0, 6, 0}, { 0, 8, 0},
		{ 0,15, 0}, { 0,15, 0}, { 0, 2, 0}, { 0, 2, 0},
		{ 0,15, 0}, { 0,15, 0}, { 0,15, 0}, { 0,15, 0},
		{ 0,15, 0}, { 0, 2, 0}, { 0, 2, 0}, { 0,15, 0}
	},

	{   // BC7 Partition Set Fixups for 3 Subsets
		{ 0, 3,15}, { 0, 3, 8}, { 0,15, 8}, { 0,15, 3},
		{ 0, 8,15}, { 0, 3,15}, { 0,15, 3}, { 0,15, 8},
		{ 0, 8,15}, { 0, 8,15}, { 0, 6,15}, { 0, 6,15},
		{ 0, 6,15}, { 0, 5,15}, { 0, 3,15}, { 0, 3, 8},
		{ 0, 3,15}, { 0, 3, 8}, { 0, 8,15}, { 0,15, 3},
		{ 0, 3,15}, { 0, 3, 8}, { 0, 6,15}, { 0,10, 8},
		{ 0, 5, 3}, { 0, 8,15}, { 0, 8, 6}, { 0, 6,10},
		{ 0, 8,15}, { 0, 5,15}, { 0,15,10}, { 0,15, 8},
		{ 0, 8,15}, { 0,15, 3}, { 0, 3,15}, { 0, 5,10},
		{ 0, 6,10}, { 0,10, 8}, { 0, 8, 9}, { 0,15,10},
		{ 0,15, 6}, { 0, 3,15}, { 0,15, 8}, { 0, 5,15},
		{ 0,15, 3}, { 0,15, 6}, { 0,15, 6}, { 0,15, 8},
		{ 0, 3,15}, { 0,15, 3}, { 0, 5,15}, { 0, 5,15},
		{ 0, 5,15}, { 0, 8,15}, { 0, 5,15}, { 0,10,15},
		{ 0, 5,15}, { 0,10,15}, { 0, 8,15}, { 0,13,15},
		{ 0,15, 3}, { 0,12,15}, { 0, 3,15}, { 0, 3, 8}
	}
};

// Interpolation weights for different sized palettes.
static uint8_t Palette_weights[ BC7_NUM_PALETTE_WEIGHTS ] = {

	// 4 element palette
	0, 21, 43, 64,

	// 8 element palette
	0, 9, 18, 27, 37, 46, 55, 64,

	// 16 element palette
	0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64
};

// --------------------
//
// Internal Functions
//
// --------------------

// Get N bits from the buffer.
//
// bits:				(output) The resulting bits.
// bit_index:		(input/output) The current bit index within the buffer.
// p_buffer:		The buffer of bits.
// buffer_size:	The size of the buffer in bytes.
// num_bits:		The number of bits to retrieve.
//
// returns: True if successful.
//
static bool bc7_get_bits(uint8_t& bits, size_t& bit_index, 
								 uint8_t const* p_buffer, size_t buffer_size,
								 size_t num_bits)
{
	// Initialize the output.
	bits = 0;

	if (num_bits > 8) {

		printf("bc7_get_bits: Too many bits requested: '%u', max is 8!\n", (unsigned int)num_bits);
		return false;
	}

	if ((bit_index + num_bits) > (8 * buffer_size)) {

		printf("bc7_get_bits: Requesting too many bits (bit index: %u, num bits: %u), "
				 "buffer size is '%u' bytes!\n", (unsigned int)bit_index, (unsigned int)num_bits, (unsigned int)buffer_size);
		return false;
	}

	size_t bit_count = 0;
	while (num_bits > 0) {

		size_t const byte_index = bit_index / 8;
		size_t const bit_offset = bit_index & 0x7;

		size_t remaining_num_bits = 8 - bit_offset;
		if (remaining_num_bits > num_bits) {

			remaining_num_bits = num_bits;
		}

		size_t const mask = ((1 << remaining_num_bits) - 1) << bit_offset;
		size_t const new_bits = (mask & p_buffer[ byte_index ]) >> bit_offset;

		bits |= new_bits << bit_count;

		num_bits -= remaining_num_bits;
		bit_index += remaining_num_bits;
		bit_count += remaining_num_bits;
	}

	return true;
}

// Calculate the color channel given two endpoints and the weight.
//
// channel_0:	The first endpoint.
// channel_1:	The second endpoint.
// weight:		The weight to use for interpolation.
//
// returns: The calculated color channel.
//
static uint8_t bc7_interpolate_channel(uint8_t channel_0, uint8_t channel_1, uint8_t weight)
{
	uint8_t const weight_1 = weight;
	uint8_t const weight_0 = BC7_INTERPOLATION_MAX_WEIGHT - weight_1;

	uint8_t const channel = (channel_0 * weight_0 + channel_1 * weight_1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;

	return channel;
}

// Decompress a 4x4 block of pixels.
//
// decompressed_block:	(output) The decompressed block of pixels.
// compressed_block:		The compressed block of pixels.
//
// returns: True if successful.
//
static bool bc7_decompress_block(bc7_decompressed_block& decompressed_block, 
											bc7_compressed_block const& compressed_block)
{
	// Get the mode number by counting the number of cleared bits in the
	// first byte.
	uint32_t mode_index = 0;
	size_t bit_index = 0;
	for (;;) {
		
		uint8_t bit;
		if (bc7_get_bits(bit, bit_index, compressed_block.m_data, sizeof(compressed_block.m_data), 1) == false) {

			return false;
		}

		if (bit == 1) {

			break;
		}

		mode_index++;
	}

	if (mode_index >= BC7_NUM_MODES) {

		printf("Invalid mode '%u'! Must be 0 - %u.\n", mode_index, BC7_NUM_MODES - 1);
		return false;
	}

	bc7_mode const& mode = BC7_modes[ mode_index ];

	// Get the shape index.
	size_t const num_shape_bits = mode.m_num_shape_bits;
	uint8_t shape_index;
	if (bc7_get_bits(shape_index, bit_index, compressed_block.m_data, 
						  sizeof(compressed_block.m_data), num_shape_bits) == false) {

		return false;
	}

	// Get the rotation index.
	size_t const num_rotation_bits = mode.m_num_rotation_bits;
	uint8_t rotation_index;
	if (bc7_get_bits(rotation_index, bit_index, compressed_block.m_data, 
						  sizeof(compressed_block.m_data), num_rotation_bits) == false) {

		return false;
	}

	// Get the index selection.
	size_t const num_isb_bits = mode.m_num_isb_bits;
	uint8_t index_selection_bit;
	if (bc7_get_bits(index_selection_bit, bit_index, compressed_block.m_data, 
						  sizeof(compressed_block.m_data), num_isb_bits) == false) {

		return false;
	}

	// Color.
	uint32_t const num_channels = (mode_index < 4) ? 3 : 4;
	uint8_t endpoints[ BC7_MAX_SUBSETS ][2][4];
	{
		uint32_t const num_subsets = mode.m_num_subsets;		
		for (uint32_t channel = 0; channel < num_channels; channel++) {

			for (uint32_t subset_iter = 0; subset_iter < num_subsets; subset_iter++) {

				uint32_t channel_precision = mode.m_endpoint_precision[ channel ];

				if (mode.m_parity_bit_type != PARITY_BIT_NONE) {

					channel_precision--;
				}

				// Get the color channel for the first endpoint.
				if (bc7_get_bits(endpoints[ subset_iter ][0][ channel ], bit_index, compressed_block.m_data, 
									  sizeof(compressed_block.m_data), channel_precision) == false) {

					return false;
				}

				// Get the color channel for the second endpoint.
				if (bc7_get_bits(endpoints[ subset_iter ][1][ channel ], bit_index, compressed_block.m_data,
									  sizeof(compressed_block.m_data), channel_precision) == false) {

					return false;
				}

			} // end for

		} // end for
	}

	// Parity bits.
	if (mode.m_parity_bit_type != PARITY_BIT_NONE) {
		
		uint32_t num_parity_bits;
		if (mode.m_parity_bit_type == PARITY_BIT_SHARED) {

			// The endpoints within a subset share a parity bit.
			num_parity_bits = mode.m_num_subsets;

		} else {

			// Each endpoint has its own parity bit.
			num_parity_bits = 2 * mode.m_num_subsets;
		}

		// Get the parity bits.
		uint8_t parity_bits[ 2 * BC7_MAX_SUBSETS ] = {0};
		for (uint32_t parity_iter = 0; parity_iter < num_parity_bits; parity_iter++) {

			if (bc7_get_bits(parity_bits[ parity_iter ], bit_index, compressed_block.m_data,
								  sizeof(compressed_block.m_data), 1) == false) {

				return false;
			}

		} // end for

		// Apply the parity bits to the colors.
		for (uint32_t channel = 0; channel < num_channels; channel++) {

			for (uint32_t subset_iter = 0; subset_iter < mode.m_num_subsets; subset_iter++) {

				if (mode.m_parity_bit_type == PARITY_BIT_SHARED) {

					// The endpoints within a subset share a parity bit.
					uint8_t const parity_bit = parity_bits[ subset_iter ];
					endpoints[ subset_iter ][0][ channel ] = (endpoints[ subset_iter ][0][ channel ] << 1) | parity_bit;
					endpoints[ subset_iter ][1][ channel ] = (endpoints[ subset_iter ][1][ channel ] << 1) | parity_bit;

				} else {

					// Each endpoint has its own parity bit.
					uint8_t const parity_bit_1 = parity_bits[ 2 * subset_iter ];
					endpoints[ subset_iter ][0][ channel ] = (endpoints[ subset_iter ][0][ channel ] << 1) | parity_bit_1;

					uint8_t const parity_bit_2 = parity_bits[ 2 * subset_iter + 1 ];
					endpoints[ subset_iter ][1][ channel ] = (endpoints[ subset_iter ][1][ channel ] << 1) | parity_bit_2;
				}

			} // end for

		} // end for
	}

	// Unquantize the colors.
	{
		for (uint32_t subset_iter = 0; subset_iter < mode.m_num_subsets; subset_iter++) {

			for (uint32_t channel = 0; channel < num_channels; channel++) {

				// Shift the most significant bits up.
				endpoints[ subset_iter ][0][ channel ] = endpoints[ subset_iter ][0][ channel ] << (8 - mode.m_endpoint_precision[ channel ]);
				endpoints[ subset_iter ][1][ channel ] = endpoints[ subset_iter ][1][ channel ] << (8 - mode.m_endpoint_precision[ channel ]);

				// Propagate the high bits into the low bits.
				endpoints[ subset_iter ][0][ channel ] |= endpoints[ subset_iter][0][ channel ] >> mode.m_endpoint_precision[ channel ];
				endpoints[ subset_iter ][1][ channel ] |= endpoints[ subset_iter][1][ channel ] >> mode.m_endpoint_precision[ channel ];				

			} // end for

			if (num_channels == 3) {

				// There is no alpha channel, it is fully opaque.
				endpoints[ subset_iter ][0][3] = 255;
				endpoints[ subset_iter ][1][3] = 255;
			}

		} // end for
	}

	// Primary indices.
	uint8_t primary_indices[ BC7_NUM_PIXELS_PER_BLOCK ] = {0};
	{
		for (uint32_t pixel_iter = 0; pixel_iter < BC7_NUM_PIXELS_PER_BLOCK; pixel_iter++) {

			uint32_t index_precision = mode.m_num_index_bits_1;

			// See if this pixel is an anchor.
			for (uint32_t subset_iter = 0; subset_iter < mode.m_num_subsets; subset_iter++) {

				if (pixel_iter == Anchor_table[ mode.m_num_subsets - 1 ][ shape_index ][ subset_iter ]) {

					// The anchor has one less bit of precision.
					index_precision--;
					break;
				}

			} // end for

			if (bc7_get_bits(primary_indices[ pixel_iter ], bit_index, compressed_block.m_data,
								  sizeof(compressed_block.m_data), index_precision) == false) {

				return false;
			}

		} // end for
	}

	// Secondary indices.
	uint8_t secondary_indices[ BC7_NUM_PIXELS_PER_BLOCK ] = {0};
	if (mode.m_num_index_bits_2 > 0) {

		for (uint32_t pixel_iter = 0; pixel_iter < BC7_NUM_PIXELS_PER_BLOCK; pixel_iter++) {

			// The first index is always the anchor index.
			uint32_t const index_precision = (pixel_iter == 0) ? (mode.m_num_index_bits_2 - 1) : mode.m_num_index_bits_2;

			if (bc7_get_bits(secondary_indices[ pixel_iter ], bit_index, compressed_block.m_data,
								  sizeof(compressed_block.m_data), index_precision) == false) {

				return false;
			}

		} // end for
	}

	uint8_t const* p_indices_1 = primary_indices;
	uint8_t const* p_indices_2 = primary_indices;

	uint8_t const* p_weights_1 = &Palette_weights[ mode.m_palette_start_1 ];
	uint8_t const* p_weights_2 = &Palette_weights[ mode.m_palette_start_1 ];

	uint32_t num_weights_1 = mode.m_palette_size_1;
	uint32_t num_weights_2 = mode.m_palette_size_1;

	// Are there a second set of indices?
	if (mode.m_num_index_bits_2 > 0) {

		p_indices_2 = secondary_indices;
		p_weights_2 = &Palette_weights[ mode.m_palette_start_2 ];
		num_weights_2 = mode.m_palette_size_2;
	}

	// Do we need to swap?
	if (index_selection_bit == 1) {

		uint8_t const* p_temp = p_indices_1;
		p_indices_1 = p_indices_2;
		p_indices_2 = p_temp;

		p_temp = p_weights_1;
		p_weights_1 = p_weights_2;
		p_weights_2 = p_temp;

		uint32_t temp = num_weights_1;
		num_weights_1 = num_weights_2;
		num_weights_2 = temp;
	}

	// Interpolate the colors.
	uint32_t pixel_index = 0;
	for (uint32_t pixel_y = 0; pixel_y < 4; pixel_y++) {

		for (uint32_t pixel_x = 0; pixel_x < 4; pixel_x++) {

			// Get which subset this pixel belongs to.
			uint8_t const subset_index = Partition_table[ mode.m_num_subsets - 1 ][ shape_index ][ pixel_index ];
			
			// Get the indices for the weights.
			uint8_t const weight_index_1 = p_indices_1[ pixel_index ];
			uint8_t const weight_index_2 = p_indices_2[ pixel_index ];

			// Get the weights.
			assert(weight_index_1 < num_weights_1);
			uint8_t const weight_1 = p_weights_1[ weight_index_1 ];

			assert(weight_index_2 < num_weights_2);
			uint8_t const weight_2 = p_weights_2[ weight_index_2 ];

			// Calculate the channels.
			uint8_t red		= bc7_interpolate_channel(endpoints[ subset_index ][0][0], endpoints[ subset_index ][1][0], weight_1);
			uint8_t green	= bc7_interpolate_channel(endpoints[ subset_index ][0][1], endpoints[ subset_index ][1][1], weight_1);
			uint8_t blue	= bc7_interpolate_channel(endpoints[ subset_index ][0][2], endpoints[ subset_index ][1][2], weight_1);
			uint8_t alpha	= bc7_interpolate_channel(endpoints[ subset_index ][0][3], endpoints[ subset_index ][1][3], weight_2);

			switch (rotation_index) {
			case 0:
				{
					// Don't swap.
					break;
				}
			case 1:
				{
					// Swap red and alpha.
					uint8_t temp = red;
					red = alpha;
					alpha = temp;

					break;
				}
			case 2:
				{
					// Swap green and alpha.
					uint8_t temp = green;
					green = alpha;
					alpha = temp;

					break;
				}
			case 3:
				{
					// Swap blue and alpha.
					uint8_t temp = blue;
					blue = alpha;
					alpha = temp;

					break;
				}
			default:
				{
					printf("Invalid rotation '%u'!\n", rotation_index);
					return false;
				}
			}

			decompressed_block.m_pixels[ pixel_y ][ pixel_x ][0] = red;
			decompressed_block.m_pixels[ pixel_y ][ pixel_x ][1] = green;
			decompressed_block.m_pixels[ pixel_y ][ pixel_x ][2] = blue;
			decompressed_block.m_pixels[ pixel_y ][ pixel_x ][3] = alpha;

			pixel_index++;

		} // end for

	} // end for

	return true;
}

// --------------------
//
// External Functions
//
// --------------------

// Decompress BC7 data.
//
// p_decompressed:	(output) The decompressed data.
// p_compressed:		The compressed data.
// image_width:		Width of the image in pixels.
// image_height:		Height of the image in pixels.
//
// returns: True if successful.
//
bool bc7_decompress(uint8_t* p_decompressed, bc7_compressed_block const* p_compressed,
						  size_t image_width, size_t image_height)
{
	if (image_width & 0x3) {

		printf("The width of the image must be a multiple of 4!\n");
		return false;
	}

	if (image_height & 0x3) {

		printf("The height of the image must be a multiple of 4!\n");
		return false;
	}

	size_t const width_in_blocks = image_width / 4;
	size_t const height_in_blocks = image_height / 4;

	// Go through the blocks and decompress them.
	size_t block_index = 0;
	for (size_t block_y = 0; block_y < height_in_blocks; block_y++) {

		for (size_t block_x = 0; block_x < width_in_blocks; block_x++) {

			// Decompress the block.
			bc7_decompressed_block decompressed_block;
			if (bc7_decompress_block(decompressed_block, p_compressed[ block_index++ ]) == false) {

				return false;
			}			

			// Store the pixels in the image.
			size_t dest_y = block_y * 4;
			for (uint32_t pixel_y = 0; pixel_y < 4; pixel_y++) {

				size_t dest_x = block_x * 4;
				for (uint32_t pixel_x = 0; pixel_x < 4; pixel_x++) {

					uint8_t const red		= decompressed_block.m_pixels[ pixel_y ][ pixel_x ][0];
					uint8_t const green	= decompressed_block.m_pixels[ pixel_y ][ pixel_x ][1];
					uint8_t const blue	= decompressed_block.m_pixels[ pixel_y ][ pixel_x ][2];
					uint8_t const alpha	= decompressed_block.m_pixels[ pixel_y ][ pixel_x ][3];

					size_t const dest = 4 * (dest_y * image_width + dest_x);

					p_decompressed[ dest + 0 ] = red;
					p_decompressed[ dest + 1 ] = green;
					p_decompressed[ dest + 2 ] = blue;
					p_decompressed[ dest + 3 ] = alpha;

					dest_x++;

				} // end for

				dest_y++;

			} // end for

		} // end for

	} // end for

	return true;
}
