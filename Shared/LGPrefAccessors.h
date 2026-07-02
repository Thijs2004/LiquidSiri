#pragma once

#import "LGSharedSupport.h"

#define LG_BOOL_PREF_FUNC(name, key, fallback) \
    static BOOL name(void) { return LG_prefBool(@key, fallback); }

#define LG_ENABLED_BOOL_PREF_FUNC(name, key, fallback) \
    static BOOL name(void) { return LG_globalEnabled() && LG_prefBool(@key, fallback); }

#define LG_FLOAT_PREF_FUNC(name, key, fallback) \
    static CGFloat name(void) { return LG_prefFloat(@key, fallback); }
