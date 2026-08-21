#pragma once

#include <stddef.h>
#include <string.h>

typedef struct {
    const char *identifier;
    const char *filterType;
    const char *preferencePrefix;
    float cornerRadiusRatio;
    float bezelRatio;
    float glassThickness;
    float refractionScale;
    float refractiveIndex;
    float blur;
    float specularOpacity;
    float dispersionStrength;
    const char *lightTintHex;
    const char *darkTintHex;
} LGHostDefinition;

//   name             filter                           pref             radii           bezel                          thick  refr  index  blur  spec   disp  light        dark
#define LG_HOST_REGISTRY(X) \
    X(Default,        "dylv.liquidglass.refraction",   "Default",       28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       18.0f, 2.6f, 1.85f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(FolderIcon,     "dylv.liquidglass.folder",       "FolderIcon",    28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       18.0f, 2.6f, 1.85f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(OpenFolder,     "dylv.liquidglass.openfolder",   "OpenFolder",    28.0f / 220.0f, (28.0f / 220.0f) * 0.9f,       18.0f, 2.6f, 1.85f, 0.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(Dock,           "dylv.liquidglass.dock",         "Dock",          0.35f,          (28.0f / 220.0f) * 1.44f,      20.0f, 2.5f, 1.60f, 3.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(Banner,         "dylv.liquidglass.banner",       "Banner",        28.0f / 220.0f, 0.25f,                         22.0f, 1.6f, 1.60f, 3.0f, 1.0f,  0.0f, "#FFFFFFCC", "#00000080") \
    X(Notification,   "dylv.liquidglass.notification", "Notification",  28.0f / 220.0f, 0.25f,                         22.0f, 1.6f, 1.60f, 3.0f, 1.0f,  0.0f, "#FFFFFF00", "#00000000") \
    X(ControlCenter,  "dylv.liquidglass.cc",           "ControlCenter", 28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       20.0f, 1.9f, 1.60f, 0.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(AppLibrary,     "dylv.liquidglass.applibpod",    "AppLibrary",    28.0f / 220.0f, (28.0f / 220.0f) * 1.26f,      20.0f, 2.2f, 1.60f, 0.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(AppLibSearch,   "dylv.liquidglass.applibsearch", "AppLibSearch",  0.50f,          (28.0f / 220.0f) * 1.8f,       18.0f, 1.8f, 1.60f, 0.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(Spotlight,      "dylv.liquidglass.spotlight",    "Spotlight",     0.50f,          (28.0f / 220.0f) * 1.8f,       18.0f, 1.8f, 1.60f, 0.0f, 1.0f,  0.0f, "#FFFFFFCC", "#0000004d") \
    X(SearchPill,     "dylv.liquidglass.searchpill",   "SearchPill",    0.50f,          (28.0f / 220.0f) * 1.08f,      18.0f, 1.6f, 1.70f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(Widgets,        "dylv.liquidglass.widget",       "Widgets",       28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       20.0f, 2.2f, 1.60f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#0000004D") \
    X(ContextMenu,    "dylv.liquidglass.contextmenu",  "ContextMenu",   28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       20.0f, 1.5f, 1.50f, 8.0f, 1.0f,  0.0f, "#FFFFFFCC", "#0000004c") \
    X(Alerts,         "dylv.liquidglass.alerts",       "Alerts",        28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       20.0f, 1.5f, 1.50f, 3.0f, 1.0f,  0.0f, "#FFFFFFCC", "#0000004c") \
    X(QuickActions,   "dylv.liquidglass.quickaction",  "QuickActions",  0.50f,          (28.0f / 220.0f) * 1.8f,       16.0f, 1.6f, 1.40f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(Passcode,       "dylv.liquidglass.passcode",     "Passcode",      0.50f,          (28.0f / 220.0f) * 2.52f,      16.0f, 1.4f, 1.60f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#0000001F") \
    X(Clock,          "dylv.liquidglass.clock",        "Clock",         0.00f,          (28.0f / 220.0f) * 1.8f,       20.0f, 1.5f, 1.50f, 2.0f, 1.0f,  0.0f, "#FFFFFF4C", "#FFFFFF4C") \
    X(PrefsSlider,    "dylv.liquidglass.prefsslider",  "PrefsSlider",   0.50f,          (28.0f / 220.0f) * 2.16f,      18.0f, 2.5f, 1.60f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(PrefsSwitch,    "dylv.liquidglass.prefsswitch",  "PrefsSwitch",   0.50f,          (28.0f / 220.0f) * 1.62f,      18.0f, 2.5f, 1.60f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(PrefsButton,    "dylv.liquidglass.prefsbutton",  "PrefsButton",   0.50f,          (28.0f / 220.0f) * 2.52f,      18.0f, 2.0f, 1.60f, 3.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(PrefsSegment,   "dylv.liquidglass.prefssegment", "PrefsSegment",  0.50f,          (28.0f / 220.0f) * 2.52f,      22.0f, 2.5f, 1.60f, 0.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000") \
    X(CoverSheet,     "dylv.liquidglass.coversheet",   "CoverSheet",    0.00f,          (28.0f / 220.0f) * 0.72f,      32.0f, 1.5f, 1.50f, 0.0f, 0.00f,  5.0f, "#FFFFFF1A", "#00000000") \
    X(TabBar,         "dylv.liquidglass.tabbar",       "TabBar",        0.50f,          0.50f,                         18.0f, 2.2f, 1.75f, 3.0f, 1.0f,  0.0f, "#FFFFFF1A", "#FFFFFF14") \
    X(TabBarSelection,"dylv.liquidglass.tabbarselect", "TabBarSelection",0.50f,         0.50f,                         18.0f, 2.2f, 1.75f, 0.0f, 1.0f,  0.0f, "#FFFFFF1A", "#FFFFFF14") \
    X(Keyboard,       "dylv.liquidglass.keyboard",     "Keyboard",      0.00f,          (28.0f / 220.0f) * 1.8f,       20.0f, 1.9f, 1.60f, 8.0f, 0.00f,  0.0f, "#FFFFFFCC", "#0000004d") \
    X(AppIcons,       "dylv.liquidglass.appicons",     "AppIcons",      28.0f / 220.0f, (28.0f / 220.0f) * 1.8f,       18.0f, 2.6f, 1.85f, 1.0f, 1.0f,  0.0f, "#FFFFFF1A", "#00000000")

enum LGHostIdentifier {
#define LG_HOST_ENUM(identifier, ...) LGHostIdentifier##identifier,
    LG_HOST_REGISTRY(LG_HOST_ENUM)
#undef LG_HOST_ENUM
    LGHostIdentifierCount
};

static const LGHostDefinition kLGHostRegistry[LGHostIdentifierCount] = {
#define LG_HOST_ENTRY(identifier, filter, prefix, radius, bezel, thickness, refraction, index, blurValue, specular, dispersion, lightTint, darkTint) \
    { #identifier, filter, prefix, radius, bezel, thickness, refraction, index, blurValue, specular, dispersion, lightTint, darkTint },
    LG_HOST_REGISTRY(LG_HOST_ENTRY)
#undef LG_HOST_ENTRY
};

static inline enum LGHostIdentifier LGHostIdentifierForDefinition(const LGHostDefinition *host) {
    return host ? (enum LGHostIdentifier)(host - kLGHostRegistry) : LGHostIdentifierCount;
}

static inline const LGHostDefinition *LGHostDefinitionForPreferencePrefix(const char *prefix) {
    if (!prefix) return NULL;
    for (size_t i = 0; i < LGHostIdentifierCount; ++i)
        if (strcmp(kLGHostRegistry[i].preferencePrefix, prefix) == 0) return &kLGHostRegistry[i];
    return NULL;
}

static inline const LGHostDefinition *LGHostDefinitionForFilterType(const char *filterType) {
    if (!filterType) return NULL;
    for (size_t i = 0; i < LGHostIdentifierCount; ++i) {
        const char *base = kLGHostRegistry[i].filterType;
        size_t length = strlen(base);

        if (strncmp(filterType, base, length) == 0 &&
            (filterType[length] == '\0' || filterType[length] == '.')) return &kLGHostRegistry[i];
    }
    return NULL;
}

static inline enum LGHostIdentifier LGHostIdentifierForFilterType(const char *filterType) {
    return LGHostIdentifierForDefinition(LGHostDefinitionForFilterType(filterType));
}
