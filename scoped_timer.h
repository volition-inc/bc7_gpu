//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __SCOPED_TIMER_H
#define __SCOPED_TIMER_H

#include <windows.h>
#include <stdio.h>

// --------------------
//
// Defines/Macros
//
// --------------------

// Create a timer for the current scope.
#define SCOPED_TIMER(label) scoped_timer __scoped_timer_##label__(label)

// --------------------
//
// Structures/Classes
//
// --------------------

// Time a scope.
struct scoped_timer {

	// Initialize the scoped_timer system.
	static void initialize()
	{			
		QueryPerformanceFrequency(&m_frequency);
	}

	// Constructor.
	scoped_timer(char const* p_label)
		: m_label(p_label)
	{ 
		QueryPerformanceCounter(&m_start);
	}

	// Destructor.
	~scoped_timer()
	{
		LARGE_INTEGER end;
		QueryPerformanceCounter(&end);

		double elapsed_time = (end.QuadPart - m_start.QuadPart) / static_cast< double >(m_frequency.QuadPart);

		printf("%s : %.3f seconds\n", m_label, elapsed_time);
	}

	// The frequency of the timer.
	static LARGE_INTEGER m_frequency;

	// The starting time.
	LARGE_INTEGER m_start;

	// The label for the timed scope.
	char const* m_label;		
};

#endif // __SCOPED_TIMER_H
