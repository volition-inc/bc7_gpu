//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#pragma once		// Include this file only once

#ifndef __SCOPED_TIMER_H
#define __SCOPED_TIMER_H

#include <stdio.h>

#include "platform.h"

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
		m_frequency = plat_perf_frequency();
	}

	// Constructor.
	scoped_timer(char const* p_label)
		: m_label(p_label)
	{ 
		m_start = plat_perf_counter();
	}

	// Destructor.
	~scoped_timer()
	{
		double end = plat_perf_counter();

		double elapsed_time = (end - m_start) / m_frequency;
		
		printf("%s : %.3f seconds\n", m_label, elapsed_time);
	}

	// The frequency of the timer.
	static double m_frequency;

	// The starting time.
	double m_start;

	// The label for the timed scope.
	char const* m_label;		
};

#endif // __SCOPED_TIMER_H
