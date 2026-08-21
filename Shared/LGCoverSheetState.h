#ifndef LG_COVER_SHEET_STATE_H
#define LG_COVER_SHEET_STATE_H

#include <stdbool.h>
#include <stdint.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#if __has_include(<roothide.h>)
#include <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

#define LG_COVER_SHEET_STATE_MAGIC 0x4c474353u
static inline const char *LGCoverSheetStatePath(void) {
    return "/var/mobile/Library/Accessibility/liquidglass-coversheet-state.bin";
}

typedef struct {
    uint32_t magic;
    uint32_t sequence;
    uint32_t active;

    uint32_t deviceOrientation;
    float originXRatio;
    float originYRatio;
    float pixelsPerPoint;
} LGCoverSheetSharedState;

static inline LGCoverSheetSharedState *
LGCoverSheetMapSharedState(bool writable) {
    static LGCoverSheetSharedState *readOnlyState;
    static LGCoverSheetSharedState *writableState;
    LGCoverSheetSharedState **slot =
        writable ? &writableState : &readOnlyState;
    if (*slot) return *slot;

    int flags = writable ? (O_RDWR | O_CREAT) : O_RDONLY;
    int fd = open(LGCoverSheetStatePath(), flags, 0666);
    if (fd < 0) return NULL;
    if (writable &&
        ftruncate(fd, (off_t)sizeof(LGCoverSheetSharedState)) != 0) {
        close(fd);
        return NULL;
    }

    struct stat info = {};
    if (fstat(fd, &info) != 0 ||
        info.st_size < (off_t)sizeof(LGCoverSheetSharedState)) {
        close(fd);
        return NULL;
    }

    int protection = PROT_READ | (writable ? PROT_WRITE : 0);
    void *mapping = mmap(NULL, sizeof(LGCoverSheetSharedState), protection,
                         MAP_SHARED, fd, 0);
    close(fd);
    if (mapping == MAP_FAILED) return NULL;

    *slot = (LGCoverSheetSharedState *)mapping;
    if (writable && (*slot)->magic != LG_COVER_SHEET_STATE_MAGIC) {
        memset(*slot, 0, sizeof(**slot));
        (*slot)->magic = LG_COVER_SHEET_STATE_MAGIC;
    }
    return *slot;
}

static inline void
LGCoverSheetWriteSharedState(bool active, float originXRatio,
                             float originYRatio, float pixelsPerPoint,
                             uint32_t deviceOrientation) {
    LGCoverSheetSharedState *state = LGCoverSheetMapSharedState(true);
    if (!state) return;

    uint32_t sequence =
        __atomic_load_n(&state->sequence, __ATOMIC_RELAXED);
    uint32_t writing = (sequence + 1u) | 1u;
    __atomic_store_n(&state->sequence, writing, __ATOMIC_RELEASE);
    state->active = active ? 1u : 0u;
    state->deviceOrientation = deviceOrientation;
    state->originXRatio = originXRatio;
    state->originYRatio = originYRatio;
    state->pixelsPerPoint = pixelsPerPoint;
    __atomic_store_n(&state->sequence, writing + 1u, __ATOMIC_RELEASE);
}

static inline bool
LGCoverSheetReadSharedState(LGCoverSheetSharedState *snapshot) {
    if (!snapshot) return false;
    LGCoverSheetSharedState *state = LGCoverSheetMapSharedState(false);
    if (!state || state->magic != LG_COVER_SHEET_STATE_MAGIC) return false;

    for (int attempt = 0; attempt < 4; attempt++) {
        uint32_t before =
            __atomic_load_n(&state->sequence, __ATOMIC_ACQUIRE);
        if (before & 1u) continue;
        memcpy(snapshot, state, sizeof(*snapshot));
        uint32_t after =
            __atomic_load_n(&state->sequence, __ATOMIC_ACQUIRE);
        if (before == after && !(after & 1u) &&
            snapshot->magic == LG_COVER_SHEET_STATE_MAGIC) {
            return true;
        }
    }
    return false;
}

#endif
