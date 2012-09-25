//
// Copyright (c) 2012, Volition, Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __PLATFORM_H
#define __PLATFORM_H

#ifdef WIN32
typedef errno_t plat_err;
#elif __APPLE__
#include <errno.h>
typedef int plat_err;
#else
#error "UNSUPPORTED PLATFORM"
#endif

#include <stdio.h>

double plat_perf_counter();
double plat_perf_frequency();

//
// TODO: The __APPLE__ platform versions of the *_s functions are unsafe
plat_err plat_fopen_s(FILE **, char const*, char const*);
plat_err plat_strncat_s(char *dest, size_t numberOfElements, const char* src);

#endif // __PLATFORM_H