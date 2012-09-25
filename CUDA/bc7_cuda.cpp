//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#include <stdio.h>

#include <cuda.h>

#include "bc7_cuda.h"
#include "scoped_timer.h"

#if defined(__BC7_CUDA)

#pragma comment(lib, "CUDA.lib")

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

// Compress a texture to the BC7 format using CUDA.
//
// p_destination: The buffer to store the compressed texture. It is assumed that the buffer is the
//						correct size (source size / 4).
// p_source:		The source image data. This must be 32-bit RGBA.
// width:			Width of the image in pixels. Must be a multiple of 4.
// height:			Height of the image in pixels. Must be a multiple of 4.
// 
// returns: True if successful.
//
bool bc7_cuda_compress(bc7_compressed_block* p_destination, uint8_t const* p_source, size_t width, size_t height)
{
	SCOPED_TIMER("bc7_cuda_compress");

	if (width & 0x3) {

		printf("The width of the image must be a multiple of 4!\n");
		return false;
	}

	if (height & 0x3) {

		printf("The height of the image must be a multiple of 4!\n");
		return false;
	}

	size_t width_in_blocks = width / 4;
	size_t height_in_blocks = height / 4;

	CUresult result;

	// Initialize the driver API.
	result = cuInit(0);
	if (result != CUDA_SUCCESS) {

		printf("Failed to initialize CUDA!\n");
		return false;
	}

	// Get a handle to the first device.
	CUdevice cu_device; 
	result = cuDeviceGet(&cu_device, 0); 
	if (result != CUDA_SUCCESS) {

		printf("Failed to get a CUDA device!\n");
		return false;
	}

	// Show device info.
	{
		// Get the name of the device.
		char device_name[256] = {0};
		result = cuDeviceGetName(device_name, sizeof(device_name), cu_device);
		if (result != CUDA_SUCCESS) {

			printf("Failed to get the name of the CUDA device!\n");
			return false;
		}

		printf("CUDA device: %s\n", device_name);
	}

	// Create a context.
	CUcontext cu_context; 
	result = cuCtxCreate(&cu_context, 0, cu_device); 
	if (result != CUDA_SUCCESS) {

		printf("Failed to create a CUDA context!\n");
		return false;
	}
	
	// Load the code.
	char const* p_module_name = "CUDA/BC7.ptx";
	CUmodule cu_module; 
	result = cuModuleLoad(&cu_module, p_module_name);
	if (result != CUDA_SUCCESS) {

		printf("Failed to load the module \"%s\"!\n", p_module_name);
		return false;
	}

	// Allocate the 32-bit source buffer in device memory.
	CUdeviceptr device_source_buffer; 
	size_t const source_buffer_size = 4 * width * height;
	result = cuMemAlloc(&device_source_buffer, source_buffer_size);
	if (result != CUDA_SUCCESS) {

		printf("Failed to allocate the source buffer on the device!\n");
		return false;
	}

	// Copy the source data to device memory.
	result = cuMemcpyHtoD(device_source_buffer, p_source, source_buffer_size);
	if (result != CUDA_SUCCESS) {

		printf("Failed to copy the source data to the device!\n");
		return false;
	}

	// Number of 4x4 blocks of pixels.
	size_t const num_blocks = width * height / 16;

	// Allocate the destination buffer in device memory.
	CUdeviceptr device_destination_buffer;
	size_t const destination_buffer_size = num_blocks * sizeof(bc7_compressed_block);
	result = cuMemAlloc(&device_destination_buffer, destination_buffer_size);
	if (result != CUDA_SUCCESS) {

		printf("Failed to allocate the destination buffer on the device!\n");
		return false;
	}

	// Get a handle to the kernel.
	CUfunction kernel; 
	result = cuModuleGetFunction(&kernel, cu_module, "bc7_kernel");
	if (result != CUDA_SUCCESS) {

		printf("Failed to find the kernel function!\n");
		return false;
	}

	{
		SCOPED_TIMER("Run kernel");

		// Run the kernel.
		size_t const block_dim = 8;
		size_t const grid_dim_x = (width_in_blocks + block_dim - 1) / block_dim;
		size_t const grid_dim_y = (height_in_blocks + block_dim - 1) / block_dim;

		void* args[] = { 

			&device_destination_buffer, 
			&device_source_buffer,					
			&width_in_blocks,
			&height_in_blocks
		}; 

		result = cuLaunchKernel(kernel,
										grid_dim_x, grid_dim_y, 1,
										block_dim, block_dim, 1,
										0, 0, args, 0);
		if (result != CUDA_SUCCESS) {

			printf("Failed to launch the kernel!\n");
			return false;
		}				

		// Copy the results from device to host memory.
		result = cuMemcpyDtoH(p_destination, device_destination_buffer, destination_buffer_size);
		if (result != CUDA_SUCCESS) {

			printf("Failed to copy the results from the device!\n");
			return false;
		}
	}

	// Cleanup.
	cuMemFree(device_destination_buffer);
	cuMemFree(device_source_buffer);
	cuModuleUnload(cu_module);
	cuCtxDestroy(cu_context);

	return true;
}

#endif // #if defined(__BC7_CUDA)
