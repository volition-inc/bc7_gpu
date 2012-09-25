//
// Copyright (c) 2012 THQ Inc.
// All rights reserved.
//

#include "scoped_timer.h"

// --------------------
//
// Global Variables
//
// --------------------

// Allocate the static member.
LARGE_INTEGER scoped_timer::m_frequency;
