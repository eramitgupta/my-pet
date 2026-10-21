/*
 * pet_core.h — C interface to the mypet Rust engine (libpet_core.a).
 *
 * Ownership: handles are created by *_new and released by *_free; *_free(NULL) is a no-op.
 * Threading: a handle must not be used from two threads at once; distinct handles are
 *            independent. The library spawns no threads.
 * Errors:    functions return PetStatus; panics inside Rust are caught and reported as
 *            PET_ERR_PANIC. Out-pointers are caller-owned and only written on PET_OK.
 * Colours:   gamma-encoded sRGB components in 0..1.
 *
 * Keep in sync with rust/pet-core/src/{ffi.rs,engine/mod.rs,monitoring/mod.rs}.
 * tests/header_check.rs verifies struct layouts; bump PET_CORE_ABI_VERSION on any change.
 */
#ifndef PET_CORE_H
#define PET_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PET_CORE_ABI_VERSION 2

typedef int32_t PetStatus;
enum {
    PET_OK = 0,
    PET_ERR_NULL = 1,    /* a required pointer was NULL */
    PET_ERR_SYS = 2,     /* a Mach/sysctl call failed */
    PET_ERR_PANIC = 3,   /* internal error, caught at the boundary */
    PET_ERR_INVALID = 4  /* an argument was out of range */
};

enum { PET_MEMORY_MODE_USAGE = 0, PET_MEMORY_MODE_PRESSURE = 1 };
enum { PET_PRESSURE_NORMAL = 1, PET_PRESSURE_WARN = 2, PET_PRESSURE_CRITICAL = 4 };
enum { PET_STATE_IDLE = 0, PET_STATE_WALK = 1, PET_STATE_RUN = 2, PET_STATE_JUMP = 3,
       PET_STATE_SLEEP = 4, PET_STATE_COUNT = 5 };

typedef struct PetEngine PetEngine; /* opaque: shared metrics sampler */
typedef struct PetActor PetActor;   /* opaque: one animated pet */

typedef struct {
    float r, g, b;
} PetColor;

typedef struct {
    float threshold; /* 0..100, ascending */
    PetColor color;
} PetGradientStop;

typedef struct {
    float cpu_percent;             /* 0..100, all cores */
    float ram_used_percent;        /* 0..100, Activity Monitor "Memory Used" / physical */
    float pressure_score;          /* 0..100, see docs/METRICS.md */
    uint8_t kernel_pressure_level; /* PET_PRESSURE_* */
    uint64_t ram_used_bytes;
    uint64_t ram_total_bytes;
    uint64_t swap_used_bytes;
    uint64_t compressed_bytes;
} PetMetrics;

typedef struct {
    uint32_t frames; /* 1..64 */
    float fps;       /* base frames per second at speed 1.0, 0..60 */
    uint8_t looping; /* bool */
} PetAnimSpec;

typedef struct {
    uint8_t memory_mode;      /* PET_MEMORY_MODE_* */
    uint8_t cpu_driven_speed; /* bool */
    uint8_t state;            /* PET_STATE_* whose animation is shown */
    uint8_t reserved;
    float manual_speed;       /* used when cpu_driven_speed == 0; clamped to 0.25..4 */
    PetAnimSpec animations[PET_STATE_COUNT]; /* indexed by PET_STATE_* */
} PetActorConfig;

typedef struct {
    float speed_multiplier;
    float memory_score;       /* the value the tint was derived from */
    PetColor tint;            /* smoothed gradient colour */
    uint32_t frame_index;     /* frame within the current state's animation */
    uint8_t state;            /* PET_STATE_* */
    uint8_t reserved[3];
} PetFrame;

uint32_t pet_core_abi_version(void);

/* Engine: create once, sample from one background queue. */
PetEngine *pet_engine_new(void);
void pet_engine_free(PetEngine *engine);
PetStatus pet_engine_sample(PetEngine *engine, PetMetrics *out);
PetStatus pet_engine_note_pressure_event(PetEngine *engine, uint8_t level);

/* Actor: one per visible pet, used from the main thread. */
PetActor *pet_actor_new(void);
void pet_actor_free(PetActor *actor);
PetStatus pet_actor_configure(PetActor *actor, const PetActorConfig *config);
PetStatus pet_actor_set_gradient(PetActor *actor, const PetGradientStop *stops, size_t count);
PetStatus pet_actor_set_bands(PetActor *actor, const PetColor colors[4], const float thresholds[3]);
PetStatus pet_actor_update_metrics(PetActor *actor, const PetMetrics *metrics);
PetStatus pet_actor_tick(PetActor *actor, double dt_seconds, PetFrame *out);

/* Stateless helper for UI previews. */
PetStatus pet_gradient_sample_bands(const PetColor colors[4], const float thresholds[3], float value,
                                    PetColor *out);

#ifdef __cplusplus
}
#endif

#endif /* PET_CORE_H */
