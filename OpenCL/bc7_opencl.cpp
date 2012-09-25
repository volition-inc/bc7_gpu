//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#include <stdio.h>

#ifdef WIN32
#include <cl/opencl.h>
#elif __APPLE__
#include <OpenCL/opencl.h>
#else
#error "UNSUPPORTED PLATFORM"
#endif

#include "bc7_opencl.h"
#include "scoped_timer.h"

#if defined(__BC7_OPENCL)

#pragma comment(lib, "OpenCL.lib")

// --------------------
//
// Defines/Macros
//
// --------------------

// This will write out the driver-compiled code.
//#define __WRITE_OUT_DRIVER_COMPILED_CODE

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

// Load the program and build it.
//
// program:						(output) The program.
// p_program_filename:		The filename of the program.
// context:						The OpenCL context.
// device_id:					The device to build the program for.
//
// returns: True if successful.
//
static bool bc7_opencl_create_and_build_program(cl_program& program, char const* p_program_filename, 
																cl_platform_id platform, cl_context context, 
																cl_device_id device_id)
{
	SCOPED_TIMER("Create and build program");

	// Load the code.
	FILE* p_file = NULL;
	plat_err fopen_result = plat_fopen_s(&p_file, p_program_filename, "rb");
	if (fopen_result != 0) {

		printf("Failed to open \"%s\"!\n", p_program_filename);
		return false;
	}

	// Get the size of the program.
	fseek(p_file, 0, SEEK_END);
	size_t program_size = ftell(p_file);
	fseek(p_file, 0, SEEK_SET);

	// Allocate memory for the program.
	char* p_program_buffer = new char[ program_size ];

	// Read the program in to memory.
	if (fread(p_program_buffer, program_size, 1, p_file) != 1) {

		printf("Failed to read \"%s\" in to memory!\n", p_program_filename);
		return false;
	}

	fclose(p_file);

	// Create the program.
	cl_int result;
	program = clCreateProgramWithSource(context, 1, const_cast< char const** >(&p_program_buffer), &program_size, &result);
	if (result != CL_SUCCESS) {

		printf("Failed to create the program!\n");
		return false;
	}

	delete [] p_program_buffer;

	// Setup the compile options.
	char compile_options[256] = {0};
	plat_strncat_s(compile_options, sizeof(compile_options), "-Werror ");
	plat_strncat_s(compile_options, sizeof(compile_options), "-cl-denorms-are-zero ");
	plat_strncat_s(compile_options, sizeof(compile_options), "-cl-fast-relaxed-math ");

	// Build the program.
	result = clBuildProgram(program, 1, &device_id, compile_options, NULL, NULL);		
	if (result != CL_SUCCESS) {

		printf("Failed to build the program!\n");

		char message[128 * 1024];
		result = clGetProgramBuildInfo(program, device_id, CL_PROGRAM_BUILD_LOG, sizeof(message), message, NULL);
		if (result == CL_SUCCESS) {
#ifdef __APPLE__
#pragma GCC diagnostic ignored "-Wformat-security"
#endif
			printf(message);
		}

		return false;
	}

#if defined(__WRITE_OUT_DRIVER_COMPILED_CODE)
	// This will write out the driver-compiled code.
	{
		size_t compiled_size = 0;
		result = clGetProgramInfo(program, CL_PROGRAM_BINARY_SIZES, sizeof(compiled_size), &compiled_size, NULL);

		uint8_t* p_binary = new uint8_t[ compiled_size ];
		result = clGetProgramInfo(program, CL_PROGRAM_BINARIES, sizeof(p_binary), &p_binary, NULL);

		FILE* p_file = NULL;
		errno_t fopen_result = fopen_s(&p_file, "bc7_driver_compiled.code", "wb");
		if (fopen_result == 0) {

			fwrite(p_binary, compiled_size, 1, p_file);
		}

		fclose(p_file);
	}
#endif // __WRITE_OUT_DRIVER_COMPILED_CODE

	return true;
}

// --------------------
//
// External Functions
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
bool bc7_opencl_compress(bc7_compressed_block* p_destination, uint8_t const* p_source, size_t width, size_t height)
{
	SCOPED_TIMER("bc7_opencl_compress");

	if (width & 0x3) {

		printf("The width of the image must be a multiple of 4!\n");
		return false;
	}

	if (height & 0x3) {

		printf("The height of the image must be a multiple of 4!\n");
		return false;
	}

	size_t const width_in_blocks = width / 4;
	size_t const height_in_blocks = height / 4;

	cl_int result;

	// Get the platform id.
	cl_uint const max_platforms = 4;
	cl_uint num_platforms = 0;
	cl_platform_id platform_ids[ max_platforms ];
	result = clGetPlatformIDs(max_platforms, platform_ids, &num_platforms);
	if (result != CL_SUCCESS) {

		printf("Failed to get the OpenCL platforms!\n");
		return false;
	}

	// Search for a GPU.
	cl_platform_id platform_id = NULL;
	cl_device_id device_id = NULL;
	for (uint32_t i = 0; i < num_platforms; i++) {

		// Get the device ids.			
		result = clGetDeviceIDs(platform_ids[i], CL_DEVICE_TYPE_GPU, 1, &device_id, NULL);
		if (result == CL_SUCCESS) {

			platform_id = platform_ids[i];
			break;
		}

	} // end for

	if (result != CL_SUCCESS) {

		printf("Failed to get an OpenCL GPU device!\n");
		return false;
	}

	// Show the device info.
	{
		char device_name[256] = {0};
		clGetDeviceInfo(device_id, CL_DEVICE_NAME, sizeof(device_name), device_name, NULL);
		printf("OpenCL device: %s\n", device_name);
	}

	// Create a context.
	cl_context context = clCreateContext(NULL, 1, &device_id, NULL, NULL, &result); 
	if (result != CL_SUCCESS) {

		printf("Failed to create a CUDA context!\n");
		return false;
	}

	// Create the program.
	cl_program program;
	if (bc7_opencl_create_and_build_program(program, "OpenCL/BC7.opencl", platform_id, context, device_id) == false) {

		return false;
	}

	// Allocate the 32-bit source buffer in device memory.
	size_t const source_buffer_size = 4 * width * height;
	cl_mem device_source_buffer = clCreateBuffer(context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR, 
																source_buffer_size, (void*)p_source, &result);
	if (result != CL_SUCCESS) {

		printf("Failed to allocate the source buffer on the device!\n");
		return false;
	}

	// Number of 4x4 blocks of pixels.
	size_t const num_blocks = width * height / 16;

	// Allocate the destination buffer in device memory.	
	size_t const destination_size = num_blocks * sizeof(bc7_compressed_block);
	cl_mem device_destination_buffer = clCreateBuffer(context, CL_MEM_WRITE_ONLY,
																	  destination_size, NULL, &result);
	if (result != CL_SUCCESS) {

		printf("Failed to allocate the destination buffer on the device!\n");
		return false;
	}

	// Get a handle to the kernel.
	cl_kernel kernel = clCreateKernel(program, "bc7_kernel", &result);
	if (result != CL_SUCCESS) {

		printf("Failed to create the kernel!\n");
		return false;
	}

	// Create the command queue.
	cl_command_queue_properties queue_properties = 0;		
	cl_command_queue command_queue = clCreateCommandQueue(context, device_id, queue_properties, &result);
	if (result != CL_SUCCESS) {

		printf("Failed to create the command queue!\n");
		return false;
	}
	
	{
		SCOPED_TIMER("Run kernel");

		// Set the kernel arguments.
		{
			result  = clSetKernelArg(kernel, 0, sizeof(device_destination_buffer), &device_destination_buffer);
			if (result != CL_SUCCESS) {

				printf("Failed to set the destination kernel argument!\n");
				return false;
			}

			result = clSetKernelArg(kernel, 1, sizeof(device_source_buffer), &device_source_buffer);
			if (result != CL_SUCCESS) {

				printf("Failed to set the source kernel argument!\n");
				return false;
			}

			result = clSetKernelArg(kernel, 2, sizeof(width_in_blocks), &width_in_blocks);
			if (result != CL_SUCCESS) {

				printf("Failed to set the width in pixel blocks kernel argument!\n");
				return false;
			}

			result = clSetKernelArg(kernel, 3, sizeof(height_in_blocks), &height_in_blocks);
			if (result != CL_SUCCESS) {

				printf("Failed to set the height in pixel blocks kernel argument!\n");
				return false;
			}
		}

		// Run the kernel.
		size_t const local_work_size[] = { 8, 8 };
		size_t const global_work_size[] = {

			((width_in_blocks + local_work_size[0] - 1) / local_work_size[0]) * local_work_size[0],
			((height_in_blocks + local_work_size[1] - 1) / local_work_size[1]) * local_work_size[1]
		};

		result = clEnqueueNDRangeKernel(command_queue,
												  kernel,
												  2,														  															
												  NULL,
												  global_work_size,
												  local_work_size,
												  0, NULL, NULL);
		if (result != CL_SUCCESS) {

			printf("Failed to launch the kernel!\n");
			return false;
		}

		// Copy the results from device to host memory.
		result = clEnqueueReadBuffer(command_queue, device_destination_buffer, true, 
											  0, num_blocks * sizeof(bc7_compressed_block),
											  p_destination, 0, NULL, NULL);
		if (result != CL_SUCCESS) {

			printf("Failed to copy the results from the device!\n");
			return false;
		}
	}

	// Cleanup.
	clReleaseCommandQueue(command_queue);
	clReleaseKernel(kernel);
	clReleaseMemObject(device_destination_buffer);
	clReleaseMemObject(device_source_buffer);		
	clReleaseProgram(program);
	clReleaseContext(context);	

	return true;
}

#endif // #if defined(__BC7_OPENCL)
