// miniaudio ships as a single header that is also its own implementation: the
// declarations come from including it normally, the definitions only when
// MINIAUDIO_IMPLEMENTATION is set, which must happen in exactly one
// translation unit. That unit is this file.
//
// Nothing is configured here. The features we do not want are switched off in
// Package.swift, where they sit next to the rest of the build settings instead
// of being buried in a source file.
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
