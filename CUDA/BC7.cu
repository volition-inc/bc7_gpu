//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

// Define this if you want to pick the best shapes to refine.
// In my tests, it was better to not cull shapes and use less iterations.
// You get about the same speed and better quality.
//#define __CULL_SHAPES

// 4x4 block of pixels
#define NUM_PIXELS_PER_BLOCK 16

// Maximum size of a palette.
#define MAX_PALETTE_SIZE 16

// Total number of weights for the palettes.
#define NUM_PALETTE_WEIGHTS (4 + 8 + 16)

// Maximum number of iterations for Gradient Descent.
#if defined(__CULL_SHAPES)

   // We need more iterations when culling shapes. This results
   // in about the same speed as non-culling.
   #define GD_MAX_ITERATIONS 8

#else

   // We don't need as many iterations when we are testing all
   // the shapes.  This results in about the same speed as culling
   // and better quality.
   #define GD_MAX_ITERATIONS 4

#endif // #if defined(__CULL_SHAPES)

// Multiplier for adjusting the endpoints.
#define GD_ADJUSTMENT_FACTOR 0.1f

// Interpolation constants.
#define BC7_INTERPOLATION_MAX_WEIGHT			64
#define BC7_INTERPOLATION_INV_MAX_WEIGHT		0.015625f
#define BC7_INTERPOLATION_MAX_WEIGHT_SHIFT	6
#define BC7_INTERPOLATION_ROUND					32

// The delta when calculating the error gradient.
#define ERROR_GRADIENT_DELTA 1.0f 

// Maximum value of a float.
#define FLT_MAX 3.402823466e+38f

// Smallest value such that (1.0 + FLT_EPSILON) != 1.0
#define FLT_EPSILON 1.192092896e-07f

// Maximum integer value.
#define UINT_MAX 0xffffffff

// Maximum number of subsets for a mode.
#define BC7_MAX_SUBSETS 3

// Maximum number of ways to partition up the 16 pixels.
#define BC7_MAX_SHAPES 64

#if defined(__CULL_SHAPES)

   // The number of best shapes (arrangements of partitioning up the pixels) to refine further instead
   // of using all the shapes.
   #define BC7_MAX_BEST_SHAPES 16

#endif // #if defined(__CULL_SHAPES)

// Number of modes that BC7 has.
#define BC7_NUM_MODES 8

// Flags for swapping quantized endpoints.
#define BC7_SWAP_RGB    0x1
#define BC7_SWAP_ALPHA  0x2

//----------------------
// Types.
//----------------------

typedef unsigned char uchar;
typedef unsigned int uint;
typedef uint uint2x4[2][4];
typedef float float2x4[2][4];
typedef uchar4 pixel_type;

// The type of parity used for a mode. If a mode has a parity bit then the least
// significant bit of the color channels uses the parity bit.
enum bc7_parity_bit_type {

	PARITY_BIT_NONE = 0,
	PARITY_BIT_SHARED,
	PARITY_BIT_PER_ENDPOINT
};

// This stores the quantized endpoints and parity bits (if there are any).
struct bc7_quantized_endpoints {

   // The quantized endpoints.
   // Note: If a mode has parity bits, this still stores the least significant bit.
   uint2x4 m_endpoints[ BC7_MAX_SUBSETS ];

   // The parity bits (depending on the mode).
   uint m_parity_bits[ 2 * BC7_MAX_SUBSETS ];
};

// This describes a BC7 mode.
struct bc7_mode {

	// The mode's index.
	uint m_mode_index;

	// The full precision (including the parity bit) for each channel of the endpoints.
	uint m_endpoint_precision[4];

	// Number of subsets.
	uint m_num_subsets;

	// Number of bits for the ways to partition up the 16 pixels 
	// among the subsets.
	uint m_num_shape_bits;

	// Number of bits for the color channel swaps with the alpha channel.
	uint m_num_rotation_bits;

	// Number of bits for the index selection bit.
	uint m_num_isb_bits;

	// The type of parity used for this mode.
	bc7_parity_bit_type m_parity_bit_type;

	// Number of bits for the color palette indices.
	uint m_num_index_bits_1;

	// The size of the color palette (1 << m_num_index_bits).
	uint m_palette_size_1;

	// The starting index into the Palette_weights for this palette.
	uint m_palette_start_1;

	// Number of bits for the alpha palette indices.
	uint m_num_index_bits_2;

	// The size of the alpha palette (1 << m_num_index_bits2);
	uint m_palette_size_2;

	// The starting index into the Palette_weights for this palette.
	uint m_palette_start_2;
};

// A description of the compressed block of pixels.
struct bc7_compressed_block {

	// The total error for the block.
	uint m_error;

	// The endpoints of the line that the palette is generated from for each subset.	
	bc7_quantized_endpoints m_quantized_endpoints;

	// The indices into the palette for each pixel.
	uchar m_palette_indices_1[ NUM_PIXELS_PER_BLOCK ];
	uchar m_palette_indices_2[ NUM_PIXELS_PER_BLOCK ]; 

	// This tells which color channel was swapped with the alpha channel (if any).
	uchar m_rotation;

	// This tells whether the index selection bit was set.
	uchar m_index_selection_bit;

	// This tells which shape was used.
	uchar m_shape;
};

//----------------------
// Input
//----------------------

// Interpolation weights for different sized palettes.
__constant__ uchar const Palette_weights[ NUM_PALETTE_WEIGHTS ] = {

	// 4 element palette
	0, 21, 43, 64,

	// 8 element palette
	0, 9, 18, 27, 37, 46, 55, 64,

	// 16 element palette
	0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64
};

//----------------------
// Constants
//----------------------

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
__constant__ bc7_mode BC7_modes[ BC7_NUM_MODES ] = {

	// Mode 0
	{ 0, { 5, 5, 5, 0 }, 3, 4, 0, 0, PARITY_BIT_PER_ENDPOINT, 3, 8, 4, 0, 0, 0 },

	// Mode 1
	{ 1, { 7, 7, 7, 0 }, 2, 6, 0, 0, PARITY_BIT_SHARED, 3, 8, 4, 0, 0, 0 },

	// Mode 2
	{ 2, { 5, 5, 5, 0 }, 3, 6, 0, 0, PARITY_BIT_NONE, 2, 4, 0, 0, 0, 0 },

	// Mode 3
	{ 3, { 8, 8, 8, 0 }, 2, 6, 0, 0, PARITY_BIT_PER_ENDPOINT, 2, 4, 0, 0, 0, 0 },

	// Mode 4
	{ 4, { 5, 5, 5, 6 }, 1, 0, 2, 1, PARITY_BIT_NONE, 2, 4, 0, 3, 8, 4 },

	// Mode 5
	{ 5, { 7, 7, 7, 8 }, 1, 0, 2, 0, PARITY_BIT_NONE, 2, 4, 0, 2, 4, 0 },

	// Mode 6
	{ 6, { 8, 8, 8, 8 }, 1, 0, 0, 0, PARITY_BIT_PER_ENDPOINT, 4, 16, 12, 0, 0, 0 },

	// Mode 7
	{ 7, { 6, 6, 6, 6 }, 2, 6, 0, 0, PARITY_BIT_PER_ENDPOINT, 2, 4, 0, 0, 0, 0 }
};

// This table determines how pixels are partitioned up in the subsets.
//
__constant__ uchar Partition_table[ BC7_MAX_SUBSETS ][ BC7_MAX_SHAPES ][ NUM_PIXELS_PER_BLOCK ] =
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
__constant__ uchar Anchor_table[ BC7_MAX_SUBSETS ][ BC7_MAX_SHAPES ][ BC7_MAX_SUBSETS ] =
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

//----------------------
// Output
//----------------------

// The compressed and encoded block of pixels.
struct bc7_encoded_block {

	// 128 bits
	uint m_bits[4];
};

//----------------------
// Globals
//----------------------


//----------------------
// Functions
//----------------------

// Clamp a given value to the range [min, max].
//
// value: 	The value to clamp.
// min:		The minimum of the range.
// max:		The maximum of the range.
//
// returns: The clamped value.
//
__device__
float clamp_float(float value, float min, float max)
{
	float result;
	result = fmaxf(value, min);
	result = fminf(result, max);

	return result;
}

// Find the minimum of each slot for two float4s.
//
// a: The first float4.
// b: The second float4.
//
// returns: Each slot has the minimum of a and b.
//
__device__
float4 min_float4(float4 a, float4 b)
{
	float4 result;

	result.x = fminf(a.x, b.x);
	result.y = fminf(a.y, b.y);
	result.z = fminf(a.z, b.z);
	result.w = fminf(a.w, b.w);

	return result;
}

// Find the maximum of each slot for two float4s.
//
// a: The first float4.
// b: The second float4.
//
// returns: Each slot has the maximum of a and b.
//
__device__
float4 max_float4(float4 a, float4 b)
{
	float4 result;

	result.x = fmaxf(a.x, b.x);
	result.y = fmaxf(a.y, b.y);
	result.z = fmaxf(a.z, b.z);
	result.w = fmaxf(a.w, b.w);

	return result;
}

// Clamp each slot of the float4 to [min, max].
//
// a: 	The vector to clamp.
// min:	The minimum of the range.
// max: 	The maximum of the range.
//
// returns: The clamped vector.
//
__device__
float4 clamp_float4(float4 a, float min, float max)
{
	float4 result;

	result.x = clamp_float(a.x, min, max);
	result.y = clamp_float(a.y, min, max);
	result.z = clamp_float(a.z, min, max);
	result.w = clamp_float(a.w, min, max);

	return result;
}

// Subtract two vectors.
//
__device__
float3 subtract_float3(float3 a, float3 b)
{
	float3 result;

	result.x = a.x - b.x;
	result.y = a.y - b.y;
	result.z = a.z - b.z;

	return result;
}

// Subtract two vectors.
//
__device__
float4 subtract_float4(float4 a, float4 b)
{
	float4 result;

	result.x = a.x - b.x;
	result.y = a.y - b.y;
	result.z = a.z - b.z;
	result.w = a.w - b.w;

	return result;
}

// Subtract two vectors.
//
__device__
uint3 subtract_uint3(uint3 a, uint3 b)
{
	uint3 result;

	result.x = a.x - b.x;
	result.y = a.y - b.y;
	result.z = a.z - b.z;

	return result;
}

// Subtract two vectors.
//
__device__
uint4 subtract_uint4(uint4 a, uint4 b)
{
	uint4 result;

	result.x = a.x - b.x;
	result.y = a.y - b.y;
	result.z = a.z - b.z;
	result.w = a.w - b.w;

	return result;
}

// Calculate the dot product.
//
__device__
float dot_float3(float3 a, float3 b)
{
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

// Calculate the dot product.
//
__device__
float dot_float4(float4 a, float4 b)
{
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

// Normalize the vector.
//
// inverse_length:	(output) 1 / length or 0 if the vector is the zero vector.
// v:						The vector to normalize.
//
// returns: The normalized vector.
//
__device__
float3 normalize_float3(float& inverse_length, float3 v)
{
	float length_squared = dot_float3(v, v);
	if (length_squared < FLT_EPSILON) {

		inverse_length = 0.0f;
		return make_float3(0.0f, 0.0f, 0.0f);
	}

	inverse_length = rsqrtf(length_squared);

	float3 result;
	result.x = v.x * inverse_length;
	result.y = v.y * inverse_length;
	result.z = v.z * inverse_length;

	return result;	
}

// Normalize the vector.
//
// inverse_length:	(output) 1 / length or 0 if the vector is the zero vector.
// v:						The vector to normalize.
//
// returns: The normalized vector.
//
__device__
float4 normalize_float4(float& inverse_length, float4 v)
{
	float length_squared = dot_float4(v, v);
	if (length_squared < FLT_EPSILON) {

		inverse_length = 0.0f;
		return make_float4(0.0f, 0.0f, 0.0f, 0.0f);
	}

	inverse_length = rsqrtf(length_squared);

	float4 result;
	result.x = v.x * inverse_length;
	result.y = v.y * inverse_length;
	result.z = v.z * inverse_length;
	result.w = v.w * inverse_length;

	return result;
}

// Clamp a given value to the range [min, max].
//
// value: 	(input/output) The value to clamp.
// min:		The minimum of the range.
// max:		The maximum of the range.
//
__device__
void clamp_float2x4(float2x4 value, float min, float max)
{
	value[0][0] = clamp_float(value[0][0], min, max);
	value[0][1] = clamp_float(value[0][1], min, max);
	value[0][2] = clamp_float(value[0][2], min, max);
	value[0][3] = clamp_float(value[0][3], min, max);

	value[1][0] = clamp_float(value[1][0], min, max);
	value[1][1] = clamp_float(value[1][1], min, max);
	value[1][2] = clamp_float(value[1][2], min, max);
	value[1][3] = clamp_float(value[1][3], min, max);
}

// Copy a float2x4.
//
// copy: (output) The copy.
// a:		The value to copy.
//
__device__
void copy_float2x4(float2x4 copy, float2x4 const a)
{
	copy[0][0] = a[0][0];
	copy[0][1] = a[0][1];
	copy[0][2] = a[0][2];
	copy[0][3] = a[0][3];

	copy[1][0] = a[1][0];
	copy[1][1] = a[1][1];
	copy[1][2] = a[1][2];
	copy[1][3] = a[1][3];	
}

// Calculate the length of the float2x4
//
// a: The float2x4 to calculate the length for.
//
// returns: The lengths of each float4.
//
__device__
float2 length_float2x4(float2x4 const a)
{
	float2 result;

	result.x = sqrtf(a[0][0] * a[0][0] + a[0][1] * a[0][1] +
						  a[0][2] * a[0][2] + a[0][3] * a[0][3]);

	result.y = sqrtf(a[1][0] * a[1][0] + a[1][1] * a[1][1] +
						  a[1][2] * a[1][2] + a[1][3] * a[1][3]);

	return result;
}

// Sets a float2x4.
//
// result: 	(output) The result.
// x1 - w2: The values of the float2x4.
//
__device__
void set_float2x4(float2x4 result,
						float x1, float y1, float z1, float w1,
						float x2, float y2, float z2, float w2)
{
	result[0][0] = x1;
	result[0][1] = y1;
	result[0][2] = z1;
	result[0][3] = w1;

	result[1][0] = x2;
	result[1][1] = y2;
	result[1][2] = z2;
	result[1][3] = w2;
}

// Copy a uint2x4.
//
// copy: (output) The copy.
// a:		The value to copy.
//
__device__
void copy_uint2x4(uint2x4 copy, const uint2x4 a)
{
	copy[0][0] = a[0][0];
	copy[0][1] = a[0][1];
	copy[0][2] = a[0][2];
	copy[0][3] = a[0][3];

	copy[1][0] = a[1][0];
	copy[1][1] = a[1][1];
	copy[1][2] = a[1][2];
	copy[1][3] = a[1][3];	
}

// Calculate the squared length.
//
// a: The vector.
//
// returns: The squared length of a.
//
__device__
uint squared_length_uint3(uint3 a)
{
	return a.x * a.x + a.y * a.y + a.z * a.z;
}

// Calculate the squared length.
//
// a: The vector.
//
// returns: The squared length of a.
//
__device__
uint squared_length_uint4(uint4 a)
{
	return a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w;
}

// Get the subset index for the given pixel.
//
// shape_index:		The shape index.
// pixel_index:		The pixel index within the block.
// p_mode:				The current mode.
//
// returns: The subset index.
//
__device__
uint bc7_get_subset_for_pixel(uint shape_index, uint pixel_index,
										bc7_mode const* p_mode)
{	
	return Partition_table[ p_mode->m_num_subsets - 1 ][ shape_index ][ pixel_index ];
}

// Get the index within the block of 16 pixels that is called the anchor index for a given setup. The anchor index 
// is assumed to not have the high bit set which saves one bit. If the high bit is set, the 
// endpoints and indices are swapped so it is not set.
//
// shape_index:		The shape index.
// subset_index:		The subset index.
// p_mode:				The current mode.
//
// returns: The anchor index.
//
__device__
uint bc7_get_anchor_index(uint shape_index, uint subset_index,
								  bc7_mode const* p_mode)
{
	return Anchor_table[ p_mode->m_num_subsets - 1 ][ shape_index ][ subset_index ];
}

// Swap a color channel with the alpha channel because some modes have better precision 
// in the alpha channel and it may reduce the error.
//
// pixels:		(input/output) The pixels.
// rotation:	This determines which channel is swapped with the alpha channel.
//
__device__
void bc7_swap_channels(pixel_type pixels[ NUM_PIXELS_PER_BLOCK ], uint rotation)
{
	switch (rotation) {
	case 0:
		{
			// Don't swap.
			break;
		}
	case 1:
		{
			// Swap red and alpha.
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

				uchar temp = pixels[ pixel_iter ].x;
				pixels[ pixel_iter ].x = pixels[ pixel_iter ].w;
				pixels[ pixel_iter ].w = temp;
			}

			break;
		}
	case 2:
		{
			// Swap green and alpha.
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

				uchar temp = pixels[ pixel_iter ].y;
				pixels[ pixel_iter ].y = pixels[ pixel_iter ].w;
				pixels[ pixel_iter ].w = temp;
			}

			break;
		}
	case 3:
		{
			// Swap blue and alpha.
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

				uchar temp = pixels[ pixel_iter ].z;
				pixels[ pixel_iter ].z = pixels[ pixel_iter ].w;
				pixels[ pixel_iter ].w = temp;
			}

			break;
		}
	}
}

// Calculate the parity bits from the least significant bits of the channels
// of the endpoints.
//
// p_quantized_endpoints:  (input/output) The quantized endpoints.
// p_mode:                 The current mode.
//
__device__
void bc7_calculate_parity_bits(bc7_quantized_endpoints* p_quantized_endpoints,
                               bc7_mode const* p_mode)
{
   if (p_mode->m_parity_bit_type == PARITY_BIT_NONE) {

      return;
   }

   // Get the number of channels for this mode.
   uint const num_channels = (p_mode->m_mode_index < 4) ? 3 : 4;

   // Count how many least significant bits are set. A parity bit 
   // will be set if there are a majority of least significant bits set.
   uint lsb_count[ 2 * BC7_MAX_SUBSETS ] = { 0 };
   for (uint channel = 0; channel < num_channels; channel++) {

      for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

         uint const channel_value_0 = p_quantized_endpoints->m_endpoints[ subset_iter ][0][ channel ];
         uint const channel_value_1 = p_quantized_endpoints->m_endpoints[ subset_iter ][1][ channel ];

         if (p_mode->m_parity_bit_type == PARITY_BIT_SHARED) {

            // The endpoints within a subset share the parity bit.
            lsb_count[ subset_iter ] += channel_value_0 & 0x1;
            lsb_count[ subset_iter ] += channel_value_1 & 0x1;

         } else {

            // Each endpoint has it's own parity bit.
            uint const index = 2 * subset_iter;
            lsb_count[ index ] += channel_value_0 & 0x1;
            lsb_count[ index + 1 ] += channel_value_1 & 0x1;               
         }

      } // end for

   } // end for

   // Find the parity bits.
   uint num_parity_bits;
   uint halfway;
   if (p_mode->m_parity_bit_type == PARITY_BIT_SHARED) {

      num_parity_bits = p_mode->m_num_subsets;
      halfway = num_channels;

   } else {

      num_parity_bits = 2 * p_mode->m_num_subsets;
      halfway = num_channels >> 1;
   }

   for (uint parity_iter = 0; parity_iter < num_parity_bits; parity_iter++) {

      // See if the least significant bit was set the majority of the time.
      uint const parity_bit = (lsb_count[ parity_iter ] > halfway) ? 1 : 0;
      p_quantized_endpoints->m_parity_bits[ parity_iter ] = parity_bit;

   } // end for   
}

// Quantize the endpoints to the desired precision.
//
// p_quantized_endpoints:  (output) The quantized endpoints.
// endpoints_f: 	         The endpoints to quantize.
// p_mode:                 The current mode.
//
// returns: The quantized endpoints.
//
__device__
void bc7_quantize_endpoints(bc7_quantized_endpoints* p_quantized_endpoints, 
                            float2x4 const endpoints_f[ BC7_MAX_SUBSETS ],
									 bc7_mode const* p_mode)
{
   // This will scale the channels of the endpoints so they have the correct precision
   // before the parity bit is found (if there is one for this mode).
   float4 precision_factor;
   {
     precision_factor.x = ((1 << p_mode->m_endpoint_precision[0]) - 1) / 255.0f;
     precision_factor.y = ((1 << p_mode->m_endpoint_precision[1]) - 1) / 255.0f;
     precision_factor.z = ((1 << p_mode->m_endpoint_precision[2]) - 1) / 255.0f;
     precision_factor.w = ((1 << p_mode->m_endpoint_precision[3]) - 1) / 255.0f;
   } 

   // Quantize all the endpoints.
   for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

   	p_quantized_endpoints->m_endpoints[ subset_iter ][0][0] = __float2uint_rn(endpoints_f[ subset_iter ][0][0] * precision_factor.x) & 0xff;
   	p_quantized_endpoints->m_endpoints[ subset_iter ][0][1] = __float2uint_rn(endpoints_f[ subset_iter ][0][1] * precision_factor.y) & 0xff;
   	p_quantized_endpoints->m_endpoints[ subset_iter ][0][2] = __float2uint_rn(endpoints_f[ subset_iter ][0][2] * precision_factor.z) & 0xff;
   	p_quantized_endpoints->m_endpoints[ subset_iter ][0][3] = __float2uint_rn(endpoints_f[ subset_iter ][0][3] * precision_factor.w) & 0xff;

   	p_quantized_endpoints->m_endpoints[ subset_iter ][1][0] = __float2uint_rn(endpoints_f[ subset_iter ][1][0] * precision_factor.x) & 0xff;
   	p_quantized_endpoints->m_endpoints[ subset_iter ][1][1] = __float2uint_rn(endpoints_f[ subset_iter ][1][1] * precision_factor.y) & 0xff;
   	p_quantized_endpoints->m_endpoints[ subset_iter ][1][2] = __float2uint_rn(endpoints_f[ subset_iter ][1][2] * precision_factor.z) & 0xff;
   	p_quantized_endpoints->m_endpoints[ subset_iter ][1][3] = __float2uint_rn(endpoints_f[ subset_iter ][1][3] * precision_factor.w) & 0xff;

   } // end for

   // Calculate the parity bits if this mode has them.
   bc7_calculate_parity_bits(p_quantized_endpoints, p_mode);
}

// Unquantize the endpoints.
//
// endpoints:		         (output) The unquantized endpoints.
// p_quantized_endpoints: 	The quantized endpoints.
// p_mode:                 The current mode.
//
__device__
void bc7_unquantize_endpoints(uint2x4 endpoints[ BC7_MAX_SUBSETS ], 
                              bc7_quantized_endpoints const* p_quantized_endpoints,
										bc7_mode const* p_mode)
{
   // First apply the parity bits (if there are any).
   switch (p_mode->m_parity_bit_type) {

      case PARITY_BIT_NONE:
      {
         for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

            endpoints[ subset_iter ][0][0] = p_quantized_endpoints->m_endpoints[ subset_iter ][0][0];
            endpoints[ subset_iter ][0][1] = p_quantized_endpoints->m_endpoints[ subset_iter ][0][1];
            endpoints[ subset_iter ][0][2] = p_quantized_endpoints->m_endpoints[ subset_iter ][0][2];
            endpoints[ subset_iter ][0][3] = p_quantized_endpoints->m_endpoints[ subset_iter ][0][3];

            endpoints[ subset_iter ][1][0] = p_quantized_endpoints->m_endpoints[ subset_iter ][1][0];
            endpoints[ subset_iter ][1][1] = p_quantized_endpoints->m_endpoints[ subset_iter ][1][1];
            endpoints[ subset_iter ][1][2] = p_quantized_endpoints->m_endpoints[ subset_iter ][1][2];
            endpoints[ subset_iter ][1][3] = p_quantized_endpoints->m_endpoints[ subset_iter ][1][3];

         } // end for
         
         break;
      }

      case PARITY_BIT_SHARED:
      {
         // The endpoints share a parity bit within a subset.         
         for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

            uint const parity_bit = p_quantized_endpoints->m_parity_bits[ subset_iter ];

            // Overwrite the least significant bits with the parity bit.
            endpoints[ subset_iter ][0][0] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][0] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][0][1] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][1] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][0][2] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][2] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][0][3] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][3] & 0xfe) | parity_bit;

            endpoints[ subset_iter ][1][0] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][0] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][1][1] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][1] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][1][2] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][2] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][1][3] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][3] & 0xfe) | parity_bit;

         } // end for

         break;
      }

      case PARITY_BIT_PER_ENDPOINT:
      {
         // Each endpoint has a parity bit for its channels.
         uint parity_iter = 0;
         for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

            uint parity_bit = p_quantized_endpoints->m_parity_bits[ parity_iter++ ];

            // Overwrite the least significant bits with the parity bit.
            endpoints[ subset_iter ][0][0] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][0] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][0][1] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][1] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][0][2] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][2] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][0][3] = (p_quantized_endpoints->m_endpoints[ subset_iter ][0][3] & 0xfe) | parity_bit;

            parity_bit = p_quantized_endpoints->m_parity_bits[ parity_iter++ ];

            endpoints[ subset_iter ][1][0] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][0] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][1][1] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][1] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][1][2] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][2] & 0xfe) | parity_bit;
            endpoints[ subset_iter ][1][3] = (p_quantized_endpoints->m_endpoints[ subset_iter ][1][3] & 0xfe) | parity_bit;

         } // end for

         break;
      }

      default:
      {
         break;
      }

   } // end switch

   // Now expand the bits.
   for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

   	endpoints[ subset_iter ][0][0] = endpoints[ subset_iter ][0][0] << (8 - p_mode->m_endpoint_precision[0]);
   	endpoints[ subset_iter ][0][1] = endpoints[ subset_iter ][0][1] << (8 - p_mode->m_endpoint_precision[1]);
   	endpoints[ subset_iter ][0][2] = endpoints[ subset_iter ][0][2] << (8 - p_mode->m_endpoint_precision[2]);
   	endpoints[ subset_iter ][0][3] = endpoints[ subset_iter ][0][3] << (8 - p_mode->m_endpoint_precision[3]);

   	endpoints[ subset_iter ][1][0] = endpoints[ subset_iter ][1][0] << (8 - p_mode->m_endpoint_precision[0]);
   	endpoints[ subset_iter ][1][1] = endpoints[ subset_iter ][1][1] << (8 - p_mode->m_endpoint_precision[1]);
   	endpoints[ subset_iter ][1][2] = endpoints[ subset_iter ][1][2] << (8 - p_mode->m_endpoint_precision[2]);
   	endpoints[ subset_iter ][1][3] = endpoints[ subset_iter ][1][3] << (8 - p_mode->m_endpoint_precision[3]);

   	// Propagate the high bits in to the low bits.
   	endpoints[ subset_iter ][0][0] |= endpoints[ subset_iter ][0][0] >> p_mode->m_endpoint_precision[0];
   	endpoints[ subset_iter ][0][1] |= endpoints[ subset_iter ][0][1] >> p_mode->m_endpoint_precision[1];
   	endpoints[ subset_iter ][0][2] |= endpoints[ subset_iter ][0][2] >> p_mode->m_endpoint_precision[2];
   	endpoints[ subset_iter ][0][3] |= endpoints[ subset_iter ][0][3] >> p_mode->m_endpoint_precision[3];

   	endpoints[ subset_iter ][1][0] |= endpoints[ subset_iter ][1][0] >> p_mode->m_endpoint_precision[0];
   	endpoints[ subset_iter ][1][1] |= endpoints[ subset_iter ][1][1] >> p_mode->m_endpoint_precision[1];
   	endpoints[ subset_iter ][1][2] |= endpoints[ subset_iter ][1][2] >> p_mode->m_endpoint_precision[2];
   	endpoints[ subset_iter ][1][3] |= endpoints[ subset_iter ][1][3] >> p_mode->m_endpoint_precision[3];

      endpoints[ subset_iter ][0][0] &= 0xff;
      endpoints[ subset_iter ][0][1] &= 0xff;
      endpoints[ subset_iter ][0][2] &= 0xff;
      endpoints[ subset_iter ][0][3] &= 0xff;

      endpoints[ subset_iter ][1][0] &= 0xff;
      endpoints[ subset_iter ][1][1] &= 0xff;
      endpoints[ subset_iter ][1][2] &= 0xff;
      endpoints[ subset_iter ][1][3] &= 0xff;

   	if (p_mode->m_endpoint_precision[3] == 0) {

   		// There is no alpha channel, set it to fully opaque.
   		endpoints[ subset_iter ][0][3] = 255;
   		endpoints[ subset_iter ][1][3] = 255;
   	}

   } // end for
}

// Compare the pixels to the palette generated by the endpoints
// and calculate a total error.
//
// endpoints:	The endpoints in color space.
// pixels:		The pixels from the image.
// num_pixels:	Number of pixels.
// swap_palette_index_precision:	If this is 1 then swap Palette_size_1 and Palette_size_2.
// p_mode:		The current mode.
//
// returns: The total error.
//
__device__
float bc7_calculate_total_error(float2x4 const endpoints, 
										  pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels,
										  uint swap_palette_index_precision,
										  bc7_mode const* p_mode)
{
	// Figure out the palette sizes.
	uint palette_size_1 = p_mode->m_palette_size_1;
	uint palette_size_2 = p_mode->m_palette_size_2;

	if (swap_palette_index_precision == 1) {

		palette_size_1 = p_mode->m_palette_size_2;
		palette_size_2 = p_mode->m_palette_size_1;
	}
	
	float total_error = 0.0f;

	if (p_mode->m_mode_index < 4) {

		// There is just one palette for color for modes 0, 1, 2, 3.

		// Calculate the direction of the color.
		float3 line_direction;
		{
			line_direction.x = endpoints[1][0] - endpoints[0][0];
			line_direction.y = endpoints[1][1] - endpoints[0][1];
			line_direction.z = endpoints[1][2] - endpoints[0][2];
		}

		float inverse_line_length;
		line_direction = normalize_float3(inverse_line_length, line_direction);

		// Calculate the step between weights.
		float weight_step_1 = BC7_INTERPOLATION_MAX_WEIGHT / (palette_size_1 - 1.0f);

		// Calculate the error for color.
		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			float3 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
			}

			// Project the pixel onto the line defined by the endpoints.
			float3 offset;
			{
				offset.x = pixel.x - endpoints[0][0];
				offset.y = pixel.y - endpoints[0][1];
				offset.z = pixel.z - endpoints[0][2];
			}

			float t = dot_float3(offset, line_direction) * inverse_line_length;
			t = clamp_float(t, 0.0f, 1.0f);

			// Get the index of the closest palette color.			
			uint color_index = __float2uint_rn(t * (palette_size_1 - 1.0f));

			// Generate the color by interpolating between the endpoints.
			float3 palette_color;
			{
				// Get the weights.
				float weight1 = rintf(color_index * weight_step_1);
				float weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

				palette_color.x = (endpoints[0][0] * weight0 + endpoints[1][0] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.y = (endpoints[0][1] * weight0 + endpoints[1][1] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.z = (endpoints[0][2] * weight0 + endpoints[1][2] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
			}

			// Calculate the error which is the sum of squared differences.
			float3 difference = subtract_float3(pixel, palette_color);
			float error = dot_float3(difference, difference);

			// Accumulate the error.
			total_error += error;

		} // end for

	} else if (p_mode->m_mode_index < 6) {

		// There are separate color and alpha palettes for modes 4, 5.

		// Calculate the direction of the color.
		float3 line_direction;
		{
			line_direction.x = endpoints[1][0] - endpoints[0][0];
			line_direction.y = endpoints[1][1] - endpoints[0][1];
			line_direction.z = endpoints[1][2] - endpoints[0][2];
		}

		float inverse_line_length;
		line_direction = normalize_float3(inverse_line_length, line_direction);

		// Calculate the step between weights.
		float weight_step_1 = BC7_INTERPOLATION_MAX_WEIGHT / (palette_size_1 - 1.0f);

		// Calculate the error for color.
		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			float3 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
			}

			// Project the pixel onto the line defined by the endpoints.
			float3 offset;
			{
				offset.x = pixel.x - endpoints[0][0];
				offset.y = pixel.y - endpoints[0][1];
				offset.z = pixel.z - endpoints[0][2];
			}

			float t = dot_float3(offset, line_direction) * inverse_line_length;
			t = clamp_float(t, 0.0f, 1.0f);

			// Get the index of the closest palette color.			
			uint color_index = __float2uint_rn(t * (palette_size_1 - 1.0f));

			// Generate the color by interpolating between the endpoints.
			float3 palette_color;
			{
				// Get the weights.
				float weight1 = rintf(weight_step_1 * color_index);
				float weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

				palette_color.x = (endpoints[0][0] * weight0 + endpoints[1][0] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.y = (endpoints[0][1] * weight0 + endpoints[1][1] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.z = (endpoints[0][2] * weight0 + endpoints[1][2] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
			}

			// Calculate the error which is the sum of squared differences.
			float3 difference = subtract_float3(pixel, palette_color);
			float error = dot_float3(difference, difference);

			// Accumulate the error.
			total_error += error;

		} // end for

		// Get the length and inverse length of the alpha channel.
		float alpha_length = endpoints[1][3] - endpoints[0][3];
		float inverse_alpha_length = 0.0f;
		if (alpha_length > 0.0f) {

			inverse_alpha_length = 1.0f / alpha_length;
		}

		// Calculate the step between weights.
		float weight_step_2 = BC7_INTERPOLATION_MAX_WEIGHT / (palette_size_2 - 1.0f);

		// Calculate the error for alpha.
		float total_error = 0.0f;
		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			// Get the alpha of the pixel.
			float pixel_alpha = pixels[ pixel_iter ].w;

			// Get the alpha offset from the first endpoint.
			float alpha_offset = pixel_alpha - endpoints[0][3];
			
			// Parameterize the alpha value.
			float t = clamp_float(alpha_offset * inverse_alpha_length, 0.0f, 1.0f);

			// Get the index of the closest palette alpha.
			uint alpha_index = __float2uint_rn(t * (palette_size_2 - 1.0f));

			// Generate the alpha value by interpolating between the endpoints.
			float palette_alpha;
			{
				// Get the weights.
				float weight1 = rintf(weight_step_2 * alpha_index);
				float weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

				palette_alpha = (endpoints[0][3] * weight0 + endpoints[1][3] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
			}

			// Calculate the error.
			float difference = pixel_alpha - palette_alpha;
			float error = difference * difference;

			// Accumulate the error.
			total_error += error;

		} // end for

	} else {

		// There are no separate color and alpha palettes for modes 6, 7.

		// Calculate the direction of the color.
		float4 line_direction;
		{
			line_direction.x = endpoints[1][0] - endpoints[0][0];
			line_direction.y = endpoints[1][1] - endpoints[0][1];
			line_direction.z = endpoints[1][2] - endpoints[0][2];
			line_direction.w = endpoints[1][3] - endpoints[0][3];
		}

		float inverse_line_length;
		line_direction = normalize_float4(inverse_line_length, line_direction);

		// Calculate the step between weights.
		float weight_step_1 = BC7_INTERPOLATION_MAX_WEIGHT / (palette_size_1 - 1.0f);

		// Calculate the total error.			
		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			float4 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
				pixel.w = pixels[ pixel_iter ].w;
			}

			// Project the pixel onto the line defined by the endpoints.
			float4 offset;
			{
				offset.x = pixel.x - endpoints[0][0];
				offset.y = pixel.y - endpoints[0][1];
				offset.z = pixel.z - endpoints[0][2];
				offset.w = pixel.w - endpoints[0][3];
			}

			float t;
			{
				t = dot_float4(offset, line_direction) * inverse_line_length;
				t = clamp_float(t, 0.0f, 1.0f);
			}

			// Get the index of the closest palette color.			
			uint color_index = __float2uint_rn(t * (palette_size_1 - 1.0f));

			// Generate the color by interpolating between the endpoints.
			float4 palette_color;
			{
				// Get the weights.
				float weight1 = rintf(weight_step_1 * color_index);
				float weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

				palette_color.x = (endpoints[0][0] * weight0 + endpoints[1][0] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.y = (endpoints[0][1] * weight0 + endpoints[1][1] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.z = (endpoints[0][2] * weight0 + endpoints[1][2] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
				palette_color.w = (endpoints[0][3] * weight0 + endpoints[1][3] * weight1) * BC7_INTERPOLATION_INV_MAX_WEIGHT;
			}

			// Calculate the error which is the sum of squared differences.
			float4 difference = subtract_float4(pixel, palette_color);
			float error = dot_float4(difference, difference);

			// Accumulate the error.
			total_error += error;

		} // end for			
	}

	return total_error;
}

// Calculate a partial derivative of the error.
//
// endpoints:			The endpoints in color space.
// pixels:				The pixels from the image.
// num_pixels:			Number of pixels.
// endpoint_index:	Index of the endpoint.
// axis_index:			Which axis to compute the partial derivative for.
// swap_palette_index_precision:	If this is 1 then swap Palette_size_1 and Palette_size_2.
// p_mode:				The current mode.
//
// returns: The partial derivative of the error.
//
__device__
float bc7_calculate_error_partial_derivative(float2x4 const endpoints, 
															pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels,
															uint endpoint_index, uint axis_index,
															uint swap_palette_index_precision,
															bc7_mode const* p_mode)
{
	// Calculate the "left" endpoint.
	float2x4 left_endpoints;
	copy_float2x4(left_endpoints, endpoints);
	{
		left_endpoints[ endpoint_index ][ axis_index ] -= ERROR_GRADIENT_DELTA;

		// Clamp the endpoints to the bounds of the color space.
		left_endpoints[ endpoint_index ][ axis_index ] = clamp_float(left_endpoints[ endpoint_index ][ axis_index ], 0.0f, 255.0f);
	}

	// Calculate the "right" endpoint.
	float2x4 right_endpoints;
	copy_float2x4(right_endpoints, endpoints);
	{
		right_endpoints[ endpoint_index ][ axis_index ] += ERROR_GRADIENT_DELTA;

		// Clamp the endpoints to the bounds of the color space.
		right_endpoints[ endpoint_index ][ axis_index ] = clamp_float(right_endpoints[ endpoint_index ][ axis_index ], 0.0f, 255.0f);
	}

	// Get the error for the two points.
	float left_error = bc7_calculate_total_error(left_endpoints, pixels, num_pixels, swap_palette_index_precision, p_mode);
	float right_error = bc7_calculate_total_error(right_endpoints, pixels, num_pixels, swap_palette_index_precision, p_mode);

	// Approximate the partial derivative with the central difference.
	return 0.5f * (right_error - left_error) / ERROR_GRADIENT_DELTA;
}

// Calculate the gradient of the error between the pixels and the palette
// generated from the endpoints.
//
// error_gradient:	(output) The gradient of the error.
// endpoints:			The endpoints in color space.
// pixels:				The pixels from the image.
// num_pixels:			Number of pixels.
// swap_palette_index_precision:	If this is 1 then swap Palette_size_1 and Palette_size_2.
// p_mode:				The current mode.
//
// returns: The gradient of the error. The first float4 is the gradient of
//			   the first endpoint and the second float4 is the gradient of
//				the second endpoint.
//
__device__
void bc7_calculate_error_gradient(float2x4 error_gradient, float2x4 const endpoints, 
											 pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels,
											 uint swap_palette_index_precision,
											 bc7_mode const* p_mode)
{	
	error_gradient[0][0] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 0, 0, swap_palette_index_precision, p_mode);
	error_gradient[0][1] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 0, 1, swap_palette_index_precision, p_mode);
	error_gradient[0][2] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 0, 2, swap_palette_index_precision, p_mode);
	error_gradient[0][3] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 0, 3, swap_palette_index_precision, p_mode);

	error_gradient[1][0] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 1, 0, swap_palette_index_precision, p_mode);
	error_gradient[1][1] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 1, 1, swap_palette_index_precision, p_mode);
	error_gradient[1][2] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 1, 2, swap_palette_index_precision, p_mode);
	error_gradient[1][3] = bc7_calculate_error_partial_derivative(endpoints, pixels, num_pixels, 1, 3, swap_palette_index_precision, p_mode);
}

// This performs Gradient Descent to find the best fit line segment to the block of pixels.
// The initial condition affects the result, it can find a local minimum error without finding
// the global minimum error.
//
// quantized_endpoints:	(output) The quantized endpoints for the best fit line segment.
// in_endpoints:			The initial endpoints.
// pixels:					The pixels from the image.
// num_pixels:				Number of pixels.
// swap_palette_index_precision:	If this is 1 then swap Palette_size and Palette_size_2.
// p_mode:					The current mode.
//
__device__
void bc7_gradient_descent(float2x4 endpoints, float2x4 const in_endpoints, 
								  pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels,
								  uint swap_palette_index_precision,
								  bc7_mode const* p_mode)
{
	float epsilon = 128.0f * FLT_EPSILON;

	// Initialize the endpoints that will be adjusted.
	copy_float2x4(endpoints, in_endpoints);

	// Iteratively find the minimum error.
	float last_error = FLT_MAX;
	uint num_iterations;
	for (num_iterations = 0; num_iterations < GD_MAX_ITERATIONS; num_iterations++) {

		// Get the gradient of the error function.
		float2x4 error_gradient;
		bc7_calculate_error_gradient(error_gradient, endpoints, pixels, num_pixels, swap_palette_index_precision, p_mode);

		// If the gradient is near zero we are at a local minimum.
		float2 error_gradient_magnitude = length_float2x4(error_gradient);
		if ((error_gradient_magnitude.x < epsilon) 
		&&  (error_gradient_magnitude.y < epsilon)) {

			// Increment for stats.
			num_iterations++;
			break;
		}

		// Adjust the endpoints in the direction opposite of the error gradient to reduce the error.
		float2x4 possible_endpoints;
		possible_endpoints[0][0] = endpoints[0][0] - GD_ADJUSTMENT_FACTOR * error_gradient[0][0];
		possible_endpoints[0][1] = endpoints[0][1] - GD_ADJUSTMENT_FACTOR * error_gradient[0][1];
		possible_endpoints[0][2] = endpoints[0][2] - GD_ADJUSTMENT_FACTOR * error_gradient[0][2];
		possible_endpoints[0][3] = endpoints[0][3] - GD_ADJUSTMENT_FACTOR * error_gradient[0][3];		
		possible_endpoints[1][0] = endpoints[1][0] - GD_ADJUSTMENT_FACTOR * error_gradient[1][0];
		possible_endpoints[1][1] = endpoints[1][1] - GD_ADJUSTMENT_FACTOR * error_gradient[1][1];
		possible_endpoints[1][2] = endpoints[1][2] - GD_ADJUSTMENT_FACTOR * error_gradient[1][2];
		possible_endpoints[1][3] = endpoints[1][3] - GD_ADJUSTMENT_FACTOR * error_gradient[1][3];

		// Clamp the endpoints to the bounds of the color space.
		clamp_float2x4(possible_endpoints, 0.0f, 255.0f);

		// Calculate the new error.
		float error = bc7_calculate_total_error(possible_endpoints, pixels, num_pixels, swap_palette_index_precision, p_mode);
		if (error >= last_error) { 

			// No improvement.
			// Increment for stats.
			num_iterations++;
			break;
		}

		copy_float2x4(endpoints, possible_endpoints);
		last_error = error;

	} // end for

	// Clamp the endpoints to the bounds of the color space.
	clamp_float2x4(endpoints, 0.0f, 255.0f);
}

// Swap the quantized endpoints.
//
// p_quantized_endpoints:  (input/output) The quantized endpoints to swap.
// subset_index:           The index of the subset of the particular endpoints to swap.
// swap_mode:              Which channels to swap.
// p_mode:                 The current mode.
//
__device__
void bc7_swap_quantized_endpoints(bc7_quantized_endpoints* p_quantized_endpoints, 
                                  uint subset_index, uint swap_mode,
                                  bc7_mode const* p_mode)
{
   if (swap_mode & BC7_SWAP_RGB) {

      uint3 temp;
      temp.x = p_quantized_endpoints->m_endpoints[ subset_index ][0][0];
      temp.y = p_quantized_endpoints->m_endpoints[ subset_index ][0][1];
      temp.z = p_quantized_endpoints->m_endpoints[ subset_index ][0][2];

      p_quantized_endpoints->m_endpoints[ subset_index ][0][0] = p_quantized_endpoints->m_endpoints[ subset_index ][1][0];
      p_quantized_endpoints->m_endpoints[ subset_index ][0][1] = p_quantized_endpoints->m_endpoints[ subset_index ][1][1];
      p_quantized_endpoints->m_endpoints[ subset_index ][0][2] = p_quantized_endpoints->m_endpoints[ subset_index ][1][2];

      p_quantized_endpoints->m_endpoints[ subset_index ][1][0] = temp.x;
      p_quantized_endpoints->m_endpoints[ subset_index ][1][1] = temp.y;
      p_quantized_endpoints->m_endpoints[ subset_index ][1][2] = temp.z;      
   }

   if (swap_mode & BC7_SWAP_ALPHA) {

      uint temp = p_quantized_endpoints->m_endpoints[ subset_index ][0][3];
      p_quantized_endpoints->m_endpoints[ subset_index ][0][3] = p_quantized_endpoints->m_endpoints[ subset_index ][1][3];
      p_quantized_endpoints->m_endpoints[ subset_index ][1][3] = temp;
   }

   if (p_mode->m_parity_bit_type == PARITY_BIT_PER_ENDPOINT) {

      // Re-calculate the parity bits since the endpoints were swapped.
      bc7_calculate_parity_bits(p_quantized_endpoints, p_mode);
   }
}

// Assign each pixel to a palette color and get the error for the entire block.
//
// p_quantized_endpoints:  (input/output) The quantized endpoints.
// assigned_pixels_1:      (output) An index into the first palette for each pixel.
// assigned_pixels_2:      (output) An index into the second palette for each pixel.
// pixels:					   The pixels from the image.
// swap_palette_index_precision:	If this is 1 then swap Palette_size and Palette_size_2.
// shape_index:			   The current shape index.
// p_mode:					   The current mode.
//
// returns: The error for the entire block.
//
__device__
uint bc7_assign_pixels(bc7_quantized_endpoints* p_quantized_endpoints,
                       uchar assigned_pixels_1[ NUM_PIXELS_PER_BLOCK ],
							  uchar assigned_pixels_2[ NUM_PIXELS_PER_BLOCK ],							  
							  pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ],
							  uint swap_palette_index_precision,
							  uint shape_index,
							  bc7_mode const* p_mode)
{
	// Unquantize the endpoints so we can assign palette indices.
	uint2x4 endpoints[ BC7_MAX_SUBSETS ];
	bc7_unquantize_endpoints(endpoints, p_quantized_endpoints, p_mode);

	// Figure out the palette sizes.
	uint palette_size_1 = p_mode->m_palette_size_1;
	uint palette_size_2 = p_mode->m_palette_size_2;

	// Figure out the starting weight indices of the palettes.
	uint palette_start_1 = p_mode->m_palette_start_1;
	uint palette_start_2 = p_mode->m_palette_start_2;

	if (swap_palette_index_precision == 1) {

		palette_size_1 = p_mode->m_palette_size_2;
		palette_size_2 = p_mode->m_palette_size_1;

		palette_start_1 = p_mode->m_palette_start_2;
		palette_start_2 = p_mode->m_palette_start_1;
	}
	
	uint total_error = 0;
	if (palette_size_2 == 0) {

		// There are no separate color and alpha palettes.		

		// Go through the pixels and pick the best color in the palette.				
		for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

			uint4 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
				pixel.w = pixels[ pixel_iter ].w;
			}

         // Get the subset for this pixel.
         uint subset_index = bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode);

			// Go through the palette.
			uint best_error = UINT_MAX;
			uint best_color_index = UINT_MAX;			
			for (uint color_iter = 0; color_iter < palette_size_1; color_iter++) {

				// Generate the color by interpolating between the endpoints.
				uint4 palette_color;
				{
					uint weight1 = Palette_weights[ palette_start_1 + color_iter ];					
					uint weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

					palette_color.x = (endpoints[ subset_index ][0][0] * weight0 + endpoints[ subset_index ][1][0] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
					palette_color.y = (endpoints[ subset_index ][0][1] * weight0 + endpoints[ subset_index ][1][1] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
					palette_color.z = (endpoints[ subset_index ][0][2] * weight0 + endpoints[ subset_index ][1][2] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
					palette_color.w = (endpoints[ subset_index ][0][3] * weight0 + endpoints[ subset_index ][1][3] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
				}

				// Calculate the error which is the sum of squared differences.
				uint4 difference = subtract_uint4(pixel, palette_color);
				uint error = squared_length_uint4(difference);

				if (error < best_error) {

					best_error = error;
					best_color_index = color_iter;
				}

			} // end for

			// Store the index for this pixel.
			assigned_pixels_1[ pixel_iter ] = best_color_index;
			assigned_pixels_2[ pixel_iter ] = best_color_index;

			// Accumulate the error.
			total_error += best_error;			

		} // end for

		// Swap endpoints and palette indices as needed to ensure anchor indices don't have their
		// high bit set. This saves one bit per block in the final output.
		uint const high_bit_mask = palette_size_1 >> 1;
      for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

   		uint const anchor_index = bc7_get_anchor_index(shape_index, subset_iter, p_mode);

   		// Is the high bit of the anchor index set?
   		if ((assigned_pixels_1[ anchor_index ] & high_bit_mask) == 0) {

            continue;
         }

			// Swap endpoints.
         bc7_swap_quantized_endpoints(p_quantized_endpoints, subset_iter, BC7_SWAP_RGB | BC7_SWAP_ALPHA, p_mode);

			// Swap indices.
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

            if (bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode) == subset_iter) {

   				assigned_pixels_1[ pixel_iter ] = palette_size_1 - 1 - assigned_pixels_1[ pixel_iter ];
	  			   assigned_pixels_2[ pixel_iter ] = assigned_pixels_1[ pixel_iter ];
            }

			} // end for

      } // end for

	} else {

		// There are separate color and alpha palettes.		

		// Go through the pixels and pick the best color in the palette.
		uint pixel_iter;
		for (pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {
			
			uint3 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
			}

         uint subset_index = bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode);

			// Go through the palette.
			uint best_error = UINT_MAX;
			uint best_color_index = UINT_MAX;			
			for (uint color_iter = 0; color_iter < palette_size_1; color_iter++) {

				// Generate the color by interpolating between the endpoints.
				uint3 palette_color;
				{
					uint weight1 = Palette_weights[ palette_start_1 + color_iter ];					
					uint weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

					palette_color.x = (endpoints[ subset_index ][0][0] * weight0 + endpoints[ subset_index ][1][0] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
					palette_color.y = (endpoints[ subset_index ][0][1] * weight0 + endpoints[ subset_index ][1][1] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
					palette_color.z = (endpoints[ subset_index ][0][2] * weight0 + endpoints[ subset_index ][1][2] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
				}

				// Calculate the error which is the sum of squared differences.
				uint3 difference = subtract_uint3(pixel, palette_color);
				uint error = squared_length_uint3(difference);

				if (error < best_error) {

					best_error = error;
					best_color_index = color_iter;
				}

			} // end for

			// Store the index for this pixel.
			assigned_pixels_1[ pixel_iter ] = best_color_index;

			// Accumulate the error.
			total_error += best_error;

		} // end for

		// Swap endpoints and palette indices as needed to ensure anchor indices don't have their
		// high bit set. This saves one bit per block in the final output.
		uint const high_bit_mask_1 = palette_size_1 >> 1;
      for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

   		uint const anchor_index_1 = bc7_get_anchor_index(shape_index, subset_iter, p_mode);

   		// Is the high bit of the anchor index set?
   		if ((assigned_pixels_1[ anchor_index_1 ] & high_bit_mask_1) == 0) {

            continue;
         }

			// Swap endpoints (color channels only).
         bc7_swap_quantized_endpoints(p_quantized_endpoints, subset_iter, BC7_SWAP_RGB, p_mode);

			// Swap indices.
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

            if (bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode) == subset_iter) {

				  assigned_pixels_1[ pixel_iter ] = palette_size_1 - 1 - assigned_pixels_1[ pixel_iter ];
            }

			} // end for

      } // end for

		// Go through the pixels and pick the best alpha in the palette.
		for (pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

			uint pixel_alpha = pixels[ pixel_iter ].w;

         uint subset_index = bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode);

			// Go through the palette.
			uint best_error = UINT_MAX;
			uint best_alpha_index = UINT_MAX;			
			for (uint alpha_iter = 0; alpha_iter < palette_size_2; alpha_iter++) {

				// Generate the alpha value by interpolating between the endpoints.
				uint palette_alpha;
				{
					uint weight1 = Palette_weights[ palette_start_2 + alpha_iter ];					
					uint weight0 = BC7_INTERPOLATION_MAX_WEIGHT - weight1;

					palette_alpha = (endpoints[ subset_index ][0][3] * weight0 + endpoints[ subset_index ][1][3] * weight1 + BC7_INTERPOLATION_ROUND) >> BC7_INTERPOLATION_MAX_WEIGHT_SHIFT;
				}

				// Calculate the error.
				uint difference = pixel_alpha - palette_alpha;
				uint error = difference * difference;

				if (error < best_error) {

					best_error = error;
					best_alpha_index = alpha_iter;
				}

			} // end for

			// Store the index for this pixel.
			assigned_pixels_2[ pixel_iter ] = best_alpha_index;

			// Accumulate the error.
			total_error += best_error;

		} // end for

		// Swap endpoints and palette indices as needed to ensure anchor indices don't have their
		// high bit set. This saves one bit per block in the final output.
		uint const high_bit_mask_2 = palette_size_2 >> 1;
      uint const anchor_index_2 = 0;
      for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {   		

   		// Is the high bit of the anchor index set?
   		if ((assigned_pixels_2[ anchor_index_2 ] & high_bit_mask_2) == 0) {

            continue;
         }

			// Swap endpoints (alpha channel only).
         bc7_swap_quantized_endpoints(p_quantized_endpoints, subset_iter, BC7_SWAP_ALPHA, p_mode);

			// Swap indices.
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

            if (bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode) == subset_iter) {

				  assigned_pixels_2[ pixel_iter ] = palette_size_2 - 1 - assigned_pixels_2[ pixel_iter ];
            }

			} // end for

      } // end for
	}

	return total_error;
}

// Attempt to find the best endpoints for a set of pixels.
//
// endpoints:        (output) The endpoints and pixels assigned to palette indices.
// pixels:				The list of pixels.
// num_pixels:			The number of pixels in the list.
// swap_palette_index_precision:	If this is 1 then swap Palette_size and Palette_size_2.
// p_mode:				The current mode.
//
__device__
void bc7_find_endpoints(float2x4 endpoints,
								pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels,
								uint swap_palette_index_precision,
								bc7_mode const* p_mode)
{
	// Calculate the bounding box in color space of the pixels.
	float2x4 initial_endpoints;
	{
		float4 pixels_min = make_float4(FLT_MAX, FLT_MAX, FLT_MAX, FLT_MAX);
		float4 pixels_max = make_float4(-FLT_MAX, -FLT_MAX, -FLT_MAX, -FLT_MAX);

		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			float4 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
				pixel.w = pixels[ pixel_iter ].w;
			}

			pixels_min = min_float4(pixels_min, pixel);
			pixels_max = max_float4(pixels_max, pixel);

		} // end for

		set_float2x4(initial_endpoints, 
						 pixels_min.x, pixels_min.y, pixels_min.z, pixels_min.w,
						 pixels_max.x, pixels_max.y, pixels_max.z, pixels_max.w);
	}

	// Find a local minimum in error.		
	bc7_gradient_descent(endpoints, initial_endpoints, pixels, num_pixels,
                        swap_palette_index_precision, p_mode);
}

#if defined(__CULL_SHAPES)

// Calculate how much the distribution of a set of pixels is like a line.
//
// pixels:		The list of pixels.
// num_pixels:	The number of pixels in the list.
//
// returns: A value in the range [0, 1] where 0 means the set of pixels are
//				like a sphere and 1 means they make up a line.
//
__device__
float bc7_calculate_linearity_rgb(pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels)
{
	// Measure the linearity by calculating the eccentricity of the point cloud. The eccentricity
	// value is in the range [0, 1] with 0 being a circle and 1 being a line. I could only
	// find a 2d formula for this:
	//
	// eccentricity = sqrt((U20 - U02)^2 + 4 * U11^2)) / (U20 + U02)
	//
	// Where U20, U02, and U11 are central moments of different orders:
	//
	// Upq = 1/N * sum{ (X - Xc)^p * (Y - Yc)^q }
	//
	// Where (Xc, Yc) is the average position of the points (center of mass).
	//
	// Since we are only comparing linearities, we don't have to do the square root:
	//
	// linearity = eccentricity^2 = ((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
	//
	// This is derived from calculating the eigenvalues of the covariance matrix. Three dimensions (RGB)
	// would require finding the roots of a qubic equation and 4 dimensions (RGBA) would require 
	// finding the roots of a quartic equation which are giant messes. So just calculate linearity
	// in 2d for the different combinations of planes and average them.

	float inv_num_pixels = 1.0f / num_pixels;

	// Calculate the center of mass.
	float3 center_of_mass = { 0.0f, 0.0f, 0.0f };
	{
		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			float3 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;				
			}

			center_of_mass.x += pixel.x;
			center_of_mass.y += pixel.y;
			center_of_mass.z += pixel.z;

		} // end for

		center_of_mass.x *= inv_num_pixels;
		center_of_mass.y *= inv_num_pixels;
		center_of_mass.z *= inv_num_pixels;
	}

	// Calculate U20, U02, U11:
	float3 u20_and_u02 = { 0.0f, 0.0f, 0.0f };
	float3 u11 = { 0.0f, 0.0f, 0.0f };
	for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

		float3 pixel;
		{
			pixel.x = pixels[ pixel_iter ].x;
			pixel.y = pixels[ pixel_iter ].y;
			pixel.z = pixels[ pixel_iter ].z;
		}

		float3 difference;
		difference.x = pixel.x - center_of_mass.x;
		difference.y = pixel.y - center_of_mass.y;
		difference.z = pixel.z - center_of_mass.z;

		float3 squared_difference;
		squared_difference.x = difference.x * difference.x;
		squared_difference.y = difference.y * difference.y;
		squared_difference.z = difference.z * difference.z;

		// U20: (X - Xc)^2 * (Y - Yc)^0
		// U02: (X - Xc)^0 * (Y - Yc)^2
		u20_and_u02.x += squared_difference.x;
		u20_and_u02.y += squared_difference.y;
		u20_and_u02.z += squared_difference.z;

		// U11: (X - Xc)^1 * (Y - Yc)^1
		u11.x += difference.x * difference.y;
		u11.y += difference.x * difference.z;
		u11.z += difference.y * difference.z;

	} // end for

	// Upq = 1/N * sum{ (X - Xc)^p * (Y - Yc)^q }
	u20_and_u02.x *= inv_num_pixels;
	u20_and_u02.y *= inv_num_pixels;
	u20_and_u02.z *= inv_num_pixels;

	u11.x *= inv_num_pixels;
	u11.y *= inv_num_pixels;
	u11.z *= inv_num_pixels;

	// Calculate (4 * U11^2).
	u11.x *= 4.0f * u11.x;
	u11.y *= 4.0f * u11.y;
	u11.z *= 4.0f * u11.z;

	// RG plane.
	float rg_linearity = 1.0f;
	{
		float u20 = u20_and_u02.x;
		float u02 = u20_and_u02.y;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11.x;
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			rg_linearity = numer / denom;
		}
	}

	// RB plane.
	float rb_linearity = 1.0f;
	{
		float u20 = u20_and_u02.x;
		float u02 = u20_and_u02.z;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11.y;
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			rb_linearity = numer / denom;
		}
	}

	// GB plane.
	float gb_linearity = 1.0f;
	{
		float u20 = u20_and_u02.y;
		float u02 = u20_and_u02.z;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11.z;
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			gb_linearity = numer / denom;
		}
	}

	// Get the average linearity.
	float linearity = (rg_linearity + rb_linearity + gb_linearity) * 0.33333333333333f;

	return linearity;
}

// Calculate how much the distribution of a set of pixels is like a line.
//
// pixels:		The list of pixels.
// num_pixels:	The number of pixels in the list.
//
// returns: A value in the range [0, 1] where 0 means the set of pixels are
//				like a sphere and 1 means they make up a line.
//
__device__
float bc7_calculate_linearity_rgba(pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ], uint num_pixels)
{
	// Measure the linearity by calculating the eccentricity of the point cloud. The eccentricity
	// value is in the range [0, 1] with 0 being a circle and 1 being a line. I could only
	// find a 2d formula for this:
	//
	// eccentricity = sqrt((U20 - U02)^2 + 4 * U11^2)) / (U20 + U02)
	//
	// Where U20, U02, and U11 are central moments of different orders:
	//
	// Upq = 1/N * sum{ (X - Xc)^p * (Y - Yc)^q }
	//
	// Where (Xc, Yc) is the average position of the points (center of mass).
	//
	// Since we are only comparing linearities, we don't have to do the square root:
	//
	// linearity = eccentricity^2 = ((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
	//
	// This is derived from calculating the eigenvalues of the covariance matrix. Three dimensions (RGB)
	// would require finding the roots of a qubic equation and 4 dimensions (RGBA) would require 
	// finding the roots of a quartic equation which are giant messes. So just calculate linearity
	// in 2d for the different combinations of planes and average them.

	float inv_num_pixels = 1.0f / num_pixels;

	// Calculate the center of mass.
	float4 center_of_mass = { 0.0f, 0.0f, 0.0f, 0.0f };
	{
		for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

			float4 pixel;
			{
				pixel.x = pixels[ pixel_iter ].x;
				pixel.y = pixels[ pixel_iter ].y;
				pixel.z = pixels[ pixel_iter ].z;
				pixel.w = pixels[ pixel_iter ].w;				
			}

			center_of_mass.x += pixel.x;
			center_of_mass.y += pixel.y;
			center_of_mass.z += pixel.z;
			center_of_mass.w += pixel.w;

		} // end for

		center_of_mass.x *= inv_num_pixels;
		center_of_mass.y *= inv_num_pixels;
		center_of_mass.z *= inv_num_pixels;
		center_of_mass.w *= inv_num_pixels;
	}

	// Calculate U20, U02, U11:
	float4 u20_and_u02 = { 0.0f, 0.0f, 0.0f, 0.0f };
	float u11[6] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
	for (uint pixel_iter = 0; pixel_iter < num_pixels; pixel_iter++) {

		float4 pixel;
		{
			pixel.x = pixels[ pixel_iter ].x;
			pixel.y = pixels[ pixel_iter ].y;
			pixel.z = pixels[ pixel_iter ].z;
			pixel.w = pixels[ pixel_iter ].w;			
		}

		float4 difference;
		difference.x = pixel.x - center_of_mass.x;
		difference.y = pixel.y - center_of_mass.y;
		difference.z = pixel.z - center_of_mass.z;
		difference.w = pixel.w - center_of_mass.w;

		float4 squared_difference;
		squared_difference.x = difference.x * difference.x;
		squared_difference.y = difference.y * difference.y;
		squared_difference.z = difference.z * difference.z;
		squared_difference.w = difference.w * difference.w;

		// U20: (X - Xc)^2 * (Y - Yc)^0
		// U02: (X - Xc)^0 * (Y - Yc)^2
		u20_and_u02.x += squared_difference.x;
		u20_and_u02.y += squared_difference.y;
		u20_and_u02.z += squared_difference.z;
		u20_and_u02.w += squared_difference.w;

		// U11: (X - Xc)^1 * (Y - Yc)^1
		u11[0] += difference.x * difference.y;
		u11[1] += difference.x * difference.z;
		u11[2] += difference.x * difference.w;
		u11[3] += difference.y * difference.z;
		u11[4] += difference.y * difference.w;
		u11[5] += difference.z * difference.w;

	} // end for

	// Upq = 1/N * sum{ (X - Xc)^p * (Y - Yc)^q }
	u20_and_u02.x *= inv_num_pixels;	
	u20_and_u02.y *= inv_num_pixels;
	u20_and_u02.z *= inv_num_pixels;
	u20_and_u02.w *= inv_num_pixels;

	u11[0] *= inv_num_pixels;
	u11[1] *= inv_num_pixels;
	u11[2] *= inv_num_pixels;
	u11[3] *= inv_num_pixels;
	u11[4] *= inv_num_pixels;
	u11[5] *= inv_num_pixels;

	// Calculate (4 * U11^2).
	u11[0] *= 4.0f * u11[0];
	u11[1] *= 4.0f * u11[1];
	u11[2] *= 4.0f * u11[2];
	u11[3] *= 4.0f * u11[3];
	u11[4] *= 4.0f * u11[4];
	u11[5] *= 4.0f * u11[5];

	// RG plane.
	float rg_linearity = 1.0f;
	{
		float u20 = u20_and_u02.x;
		float u02 = u20_and_u02.y;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11[0];
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			rg_linearity = numer / denom;
		}
	}

	// RB plane.
	float rb_linearity = 1.0f;
	{
		float u20 = u20_and_u02.x;
		float u02 = u20_and_u02.z;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11[1];
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			rb_linearity = numer / denom;
		}
	}

	// RA plane.
	float ra_linearity = 1.0f;
	{
		float u20 = u20_and_u02.x;
		float u02 = u20_and_u02.w;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11[2];
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			ra_linearity = numer / denom;
		}
	}

	// GB plane.
	float gb_linearity = 1.0f;
	{
		float u20 = u20_and_u02.y;
		float u02 = u20_and_u02.z;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11[3];
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			gb_linearity = numer / denom;
		}
	}

	// GA plane.
	float ga_linearity = 1.0f;
	{
		float u20 = u20_and_u02.y;
		float u02 = u20_and_u02.w;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11[4];
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			ga_linearity = numer / denom;
		}
	}

	// BA plane.
	float ba_linearity = 1.0f;
	{
		float u20 = u20_and_u02.z;
		float u02 = u20_and_u02.w;

		//	((U20 - U02)^2 + 4 * U11^2) / (U20 + U02)^2
		float u20_minus_u02 = u20 - u02;
		float u20_plus_u02 = u20 + u02;
		float numer = u20_minus_u02 * u20_minus_u02 + u11[5];
		float denom = u20_plus_u02 * u20_plus_u02;

		// If the denominator is zero that means all the points are at the center
		// of mass in this plane so the linearity is considered 1.
		if (denom > 0.0f) {

			ba_linearity = numer / denom;
		}
	}	

	// Get the average linearity.
	float linearity = (rg_linearity + rb_linearity + ra_linearity + 
							 gb_linearity + ga_linearity + ba_linearity) * 0.16666666666667f;

	return linearity;
}

// Get the best shapes to refine.
//
// best_shape_indices: 	(output) List of the indices of the best shapes.
// pixels:					The block of pixels.
// p_mode:					The current mode.
//
// returns: Number of best shapes.
//
__device__
uint bc7_get_best_shapes(uint best_shape_indices[ BC7_MAX_BEST_SHAPES ],
								 pixel_type const pixels[ NUM_PIXELS_PER_BLOCK ],
								 bc7_mode const* p_mode)
{
	uint const num_shapes = 1 << p_mode->m_num_shape_bits;
	if (num_shapes == 1) {

		best_shape_indices[0] = 0;
		return 1;
	}

	// Use a fraction of the number of shapes for the best shapes.
	const uint max_best_shapes = min(BC7_MAX_BEST_SHAPES, num_shapes >> 2);

	// Iterate through the shapes and get the best shapes to refine by
	// finding the shapes with the highest linearity.
	uint num_best_shapes = 0;	
	float best_linearities[ BC7_MAX_BEST_SHAPES ];
	for (uint shape_index = 0; shape_index < num_shapes; shape_index++) {

		// Calculate the average linearity of the subsets.
		float linearity = 0.0f;
		for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

			// Get the subset of pixels.
			pixel_type subset_pixels[ NUM_PIXELS_PER_BLOCK ];
			uint num_subset_pixels = 0;
			for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

				if (bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode) == subset_iter) {

					subset_pixels[ num_subset_pixels++ ] = pixels[ pixel_iter ];
				}

			} // end for
			
			if (p_mode->m_mode_index < 4) {

				// Non-alpha modes.
				linearity += bc7_calculate_linearity_rgb(subset_pixels, num_subset_pixels);  

			} else {

				// Alpha modes.
				linearity += bc7_calculate_linearity_rgba(subset_pixels, num_subset_pixels);
			}				

		} // end for

		linearity /= p_mode->m_num_subsets;

		// Find where this shape goes.
		uint best_shape_iter;
		for (best_shape_iter = 0; best_shape_iter < num_best_shapes; best_shape_iter++) {

			if (linearity <= best_linearities[ best_shape_iter ]) {

				continue;
			}

			// Insert the shape in this slot.
			num_best_shapes = min(num_best_shapes + 1, max_best_shapes);

			// Shift the slots down.
			for (uint shift_iter = (num_best_shapes - 1); shift_iter > best_shape_iter; shift_iter--) {

				best_shape_indices[ shift_iter ] = best_shape_indices[ shift_iter - 1 ];
				best_linearities[ shift_iter ] = best_linearities[ shift_iter - 1 ];
			}

			best_shape_indices[ best_shape_iter ] = shape_index;			
			best_linearities[ best_shape_iter ] = linearity;

			break;

		} // end for

		// Is there room at the end?
		if ((best_shape_iter == num_best_shapes) 
		&&  (num_best_shapes < max_best_shapes)) {

			best_shape_indices[ num_best_shapes ] = shape_index;			
			best_linearities[ num_best_shapes ] = linearity;

			num_best_shapes++;
		}

	} // end for

	return num_best_shapes;
}

#endif // #if defined(__CULL_SHAPES)

// Store a value with the given number of bits.
//
// p_bits:					(output) The buffer to store to.
// p_start_bit_index:	(input/output) The current bit index to start storing data.
// signed_num_bits:		The number of bits.
// value:					The value to store.
//
__device__
void bc7_set_bits(uint* p_bits, uint* p_start_bit_index, int signed_num_bits, uint value)
{
	if (signed_num_bits <= 0) {

		return;
	}

	uint const num_bits = (uint)signed_num_bits;
	uint const start_bit_index = *p_start_bit_index;
	uint const slot_index = start_bit_index >> 5;
	uint const slot_index_end = (start_bit_index + num_bits - 1) >> 5;
	uint const slot_bit_index = start_bit_index & 31;

	if (slot_index != slot_index_end) {

		// The value will span an integer boundary.
		uint slot_value_1 = p_bits[ slot_index ];
		uint slot_value_2 = p_bits[ slot_index_end ];

		// Clear out the current bits.
		uint const num_bits_1 = 32 - slot_bit_index;
		uint const num_bits_2 = num_bits - num_bits_1;
		uint const mask_1 = (1 << num_bits_1) - 1;
		uint const mask_2 = (1 << num_bits_2) - 1;
		slot_value_1 &= ~(mask_1 << slot_bit_index);
		slot_value_2 &= ~mask_2;

		// Set the new values.
		slot_value_1 |= value << slot_bit_index;
		slot_value_2 |= value >> num_bits_1;

		// Store them.
		p_bits[ slot_index ] = slot_value_1;
		p_bits[ slot_index_end ] = slot_value_2;

	} else {

		uint slot_value = p_bits[ slot_index ];

		// Clear out the current bits.
		uint const mask = (1 << num_bits) - 1;
		slot_value &= ~(mask << slot_bit_index);

		// Set the new value.
		slot_value |= value << slot_bit_index;

		// Store it.
		p_bits[ slot_index ] = slot_value;
	}

	*p_start_bit_index = start_bit_index + num_bits;
}

// Encode the compressed block.
//
// p_out_encoded_block:	(output) The encoded block.
// p_compressed_block:	The compressed block to encode.
// p_mode:					The mode used to compress the pixels.
//
__device__
void bc7_encode_compressed_block(bc7_encoded_block* p_out_encoded_block,
											bc7_compressed_block const* p_compressed_block,
											bc7_mode const* p_mode)
{
	bc7_encoded_block encoded_block = { 0 };

	uint bit_index = 0;

	// Mode. There are N zeroes followed by a 1, where N is the mode index.
	bc7_set_bits(encoded_block.m_bits, &bit_index, p_mode->m_mode_index, 0);	
	bc7_set_bits(encoded_block.m_bits, &bit_index, 1, 1);

	// Shape index.
	bc7_set_bits(encoded_block.m_bits, &bit_index, p_mode->m_num_shape_bits, p_compressed_block->m_shape);

	// Rotation.
	bc7_set_bits(encoded_block.m_bits, &bit_index, p_mode->m_num_rotation_bits, p_compressed_block->m_rotation);

	// Index selection.
	bc7_set_bits(encoded_block.m_bits, &bit_index, p_mode->m_num_isb_bits, p_compressed_block->m_index_selection_bit);

	// Get the number of channels for this mode.
	uint const num_channels = (p_mode->m_mode_index < 4) ? 3 : 4;

	// Color.
	for (uint channel = 0; channel < num_channels; channel++) {

		for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

         uint channel_precision = p_mode->m_endpoint_precision[ channel ];
         uint channel_value_0 = p_compressed_block->m_quantized_endpoints.m_endpoints[ subset_iter ][0][ channel ];
         uint channel_value_1 = p_compressed_block->m_quantized_endpoints.m_endpoints[ subset_iter ][1][ channel ];

         if (p_mode->m_parity_bit_type != PARITY_BIT_NONE) {

            channel_precision--;
            channel_value_0 >>= 1;
            channel_value_1 >>= 1;
         }

			bc7_set_bits(encoded_block.m_bits, &bit_index, 
							 channel_precision,
							 channel_value_0);

			bc7_set_bits(encoded_block.m_bits, &bit_index, 
							 channel_precision,
							 channel_value_1);

		} // end for

	} // end for

   // Parity bits.
	if (p_mode->m_parity_bit_type != PARITY_BIT_NONE) {

		uint num_parity_bits;
		if (p_mode->m_parity_bit_type == PARITY_BIT_SHARED) {

         // The endpoints within a subset share a parity bit.
			num_parity_bits = p_mode->m_num_subsets;

		} else {

         // Each endpoint has its own parity bit.
			num_parity_bits = 2 * p_mode->m_num_subsets;
		}

		for (uint parity_iter = 0; parity_iter < num_parity_bits; parity_iter++) {

			uint const parity_bit = p_compressed_block->m_quantized_endpoints.m_parity_bits[ parity_iter ];
			bc7_set_bits(encoded_block.m_bits, &bit_index, 1, parity_bit);

		} // end for
	}

	// Primary indices.
	uchar const* p_palette_indices_1 = p_compressed_block->m_index_selection_bit ? p_compressed_block->m_palette_indices_2 : p_compressed_block->m_palette_indices_1;
	{
		// Get all the anchor indices.
		uint anchor_indices[ BC7_MAX_SUBSETS ];
		for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {

		 	anchor_indices[ subset_iter ] = bc7_get_anchor_index(p_compressed_block->m_shape, subset_iter, p_mode);

		} // end for

		// Encode all the indices.
		for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

			uint index_precision = p_mode->m_num_index_bits_1;

			// See if this pixel is an anchor.			
			for (uint subset_iter = 0; subset_iter < p_mode->m_num_subsets; subset_iter++) {
				
				if (pixel_iter == anchor_indices[ subset_iter ]) {

					// The anchor index is written with one less bit because the leading bit is
					// assumed to be zero.
					index_precision--;
					break;
				}

			} // end for

			bc7_set_bits(encoded_block.m_bits, &bit_index, index_precision, 
							 p_palette_indices_1[ pixel_iter ]);

		} // end for
	}

	// Secondary indices.
	if (p_mode->m_num_index_bits_2 > 0) {

		uchar const* p_palette_indices_2 = p_compressed_block->m_index_selection_bit ? p_compressed_block->m_palette_indices_1 : p_compressed_block->m_palette_indices_2;
		for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

			// The first index is always the anchor index.
			uint const index_precision = (pixel_iter == 0) ? (p_mode->m_num_index_bits_2 - 1) : p_mode->m_num_index_bits_2;

			bc7_set_bits(encoded_block.m_bits, &bit_index, index_precision,
				 			 p_palette_indices_2[ pixel_iter ]);

		} // end for
	}

	// Store the result to global memory.
	*p_out_encoded_block = encoded_block;
}

// Compress and encode the block of pixels for the given mode.
//
// p_encoded_blocks:	(output) A compressed and encoded block if the error is better.
// pixels:				The block of pixels to compress.
// block_index: 		The global index of the block of pixels to compress.
// p_mode:				The current mode.
// input_error:		The current best error.
//
// returns: The new error (or the same error if there was no improvement).
//
__device__
uint bc7_compress(bc7_encoded_block* p_encoded_blocks,
					   pixel_type pixels[ NUM_PIXELS_PER_BLOCK ],
					   uint block_index,
					   bc7_mode const* p_mode,
					   uint const input_error)
{
	// Initialize the error for this block.
	bc7_compressed_block compressed_block;
	{
		compressed_block.m_error = UINT_MAX;
	}

#if defined(__CULL_SHAPES)

	// Get the best shapes to refine.
	uint best_shape_indices[ BC7_MAX_BEST_SHAPES ];
	uint num_shapes = bc7_get_best_shapes(best_shape_indices, pixels, p_mode);

#else

   // We'll iterate over all the shapes.
   uint num_shapes = 1 << p_mode->m_num_shape_bits;

#endif // #if defined(__CULL_SHAPES)

	uint const num_rotations = 1 << p_mode->m_num_rotation_bits;
	uint const num_isb_states = 1 << p_mode->m_num_isb_bits;
	uint const num_subsets = p_mode->m_num_subsets;

	// Iterate through the channel rotations.
	for (uint rotation_iter = 0; rotation_iter < num_rotations; rotation_iter++) { 

		// Potentially swap a color channel with the alpha channel to improve precision.
		bc7_swap_channels(pixels, rotation_iter);
      
		// Iterate through the states of the index selection bit.
		for (uint isb_iter = 0; isb_iter < num_isb_states; isb_iter++) {

			// Iterate through the shapes.
			for (uint shape_iter = 0; shape_iter < num_shapes; shape_iter++) {
				
         #if defined(__CULL_SHAPES)
			
         	uint const shape_index = best_shape_indices[ shape_iter ];

         #else

            uint const shape_index = shape_iter;

         #endif // #if defined(__CULL_SHAPES)

				// Iterate through the subsets in the shape and run gradient descent.
            float2x4 gd_subset_results[ BC7_MAX_SUBSETS ];
				for (uint subset_iter = 0; subset_iter < num_subsets; subset_iter++) {

					// Get the subset of pixels.
					pixel_type subset_pixels[ NUM_PIXELS_PER_BLOCK ];
					uint num_subset_pixels = 0;
					for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

						if (bc7_get_subset_for_pixel(shape_index, pixel_iter, p_mode) == subset_iter) {

							subset_pixels[ num_subset_pixels++ ] = pixels[ pixel_iter ];
						}

					} // end for

					// Find the endpoints.
					bc7_find_endpoints(gd_subset_results[ subset_iter ],
                                  subset_pixels, num_subset_pixels, 
											 isb_iter, p_mode);

				} // end for            

            // Quantize the endpoints to the final precision including the parity bits.
            bc7_quantized_endpoints quantized_endpoints;
            bc7_quantize_endpoints(&quantized_endpoints, gd_subset_results, p_mode);

             // Assign palette indices to each pixel and calculate the error.
            uchar palette_indices_1[ NUM_PIXELS_PER_BLOCK ];
            uchar palette_indices_2[ NUM_PIXELS_PER_BLOCK ];                     
            uint shape_error = bc7_assign_pixels(&quantized_endpoints,
                                                 palette_indices_1, palette_indices_2,                                                 
                                                 pixels, isb_iter, shape_index, p_mode);  

				// Save the results if the error is better.
				if (shape_error < compressed_block.m_error) {
										
					compressed_block.m_rotation = rotation_iter;
					compressed_block.m_index_selection_bit = isb_iter;
					compressed_block.m_shape = shape_index;					
					compressed_block.m_error = shape_error;
               compressed_block.m_quantized_endpoints = quantized_endpoints;									

					// Copy the palette indices over.
					for (uint pixel_iter = 0; pixel_iter < NUM_PIXELS_PER_BLOCK; pixel_iter++) {

						compressed_block.m_palette_indices_1[ pixel_iter ] = palette_indices_1[ pixel_iter ];
						compressed_block.m_palette_indices_2[ pixel_iter ] = palette_indices_2[ pixel_iter ];

					} // end for
				}

			} // end for

		} // end for		

		// Swap the channels back.
		bc7_swap_channels(pixels, rotation_iter);

	} // end for

	if (compressed_block.m_error < input_error) {

		// Write out the new best compressed block.
		bc7_encode_compressed_block(&p_encoded_blocks[ block_index ], 
											 &compressed_block, 
											 p_mode);		

		return compressed_block.m_error;
	}

	return input_error;
}

// The kernel.
//
// p_encoded_blocks:	(output) A compressed and encoded block of pixels.
// p_source_pixels:	The image pixels.
// width_in_blocks:  The width of the image in 4x4 blocks.
// height_in_blocks: The height of the image in 4x4 blocks.
//
extern "C" __global__ 
void bc7_kernel(bc7_encoded_block* p_encoded_blocks,					 
					 pixel_type const* p_source_pixels,						
					 uint width_in_blocks, uint height_in_blocks)
{
   uint const pixel_block_x = blockIdx.x * blockDim.x + threadIdx.x;
   uint const pixel_block_y = blockIdx.y * blockDim.y + threadIdx.y;
   if ((pixel_block_x >= width_in_blocks)
   ||  (pixel_block_y >= height_in_blocks)) {

      return;
   }

	// Load the pixels for this thread.
   uint const source_width = 4 * width_in_blocks;
   uint dest_index = 0;
   uint source_index = 4 * (pixel_block_y * source_width + pixel_block_x);
   pixel_type pixels[ NUM_PIXELS_PER_BLOCK ];
   for (uint pixel_y = 0; pixel_y < 4; pixel_y++) {

      for (uint pixel_x = 0; pixel_x < 4; pixel_x++) {

         pixels[ dest_index++ ] = p_source_pixels[ source_index++ ];
      }

      source_index += (source_width - 4);
   }

	// Go through the modes and find the one with the least error for
	// this block of 4x4 pixels.
   uint const pixel_block_index = pixel_block_y * width_in_blocks + pixel_block_x;   
	uint error = UINT_MAX;
	for (uint mode_iter = 0; mode_iter < BC7_NUM_MODES; mode_iter++) {
	
		error = bc7_compress(p_encoded_blocks, pixels, pixel_block_index, &BC7_modes[ mode_iter ], error);

	} // end for
}
