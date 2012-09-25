//
// Copyright (c) 2012, Volition, Inc.
// All rights reserved.
//

#include "platform.h"

#ifdef WIN32
#include <windows.h>
#elif __APPLE__
static double Fake_mac_counter = 0.0;
#include <string.h>
#else
#error "UNSUPPORTED PLATFORM"
#endif




// --------------------
//
// Global Variables
//
// --------------------

#ifdef WIN32
double plat_perf_counter() 
{
	LARGE_INTEGER end;
	QueryPerformanceCounter(&end);
	return static_cast<double>(end.QuadPart);
}

double plat_perf_frequency() 
{
	LARGE_INTEGER frequency;
	QueryPerformanceFrequency(&frequency);
	return static_cast<double>(end.QuadPart);
}

plat_err plat_fopen_s(FILE ** p_file, char const* p_filename, char const* p_access)
{
	return fopen_s(p_file, p_filename, p_access);
}

plat_err plat_strncat_s(char *restrict dest, size_t numberOfElements, const char *restrict src) 
{
	return strncat_s(dest, numberOfElements, src, _TRUNACTE);
}

#elif __APPLE__
// TODO: Implement Mac OS X version of double perf_counter()
#pragma mark -
double plat_perf_counter() 
{
	return Fake_mac_counter + 10000.0;
}

double plat_perf_frequency() {
	return 1000.0;
}

plat_err plat_fopen_s(FILE ** p_file, char const* p_filename, char const* p_access)
{
	*p_file = fopen(p_filename, p_access);
	if (*p_file == NULL) {
		printf("Failed to open \"%s\"!\n", p_filename);
		return errno;
	}

	return 0;
}

plat_err plat_strncat_s(char * dest, size_t numberOfElements, const char * src) 
{
	dest = strncat(dest, src, numberOfElements - strlen(dest) - 1);
	return 0;
}


#else
#error "UNSUPPORTED PLATFORM"
#endif
