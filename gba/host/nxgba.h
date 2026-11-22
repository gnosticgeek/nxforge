// The Game Boy Advance host's C interface (gba/host/src/lib.rs): one game's machine, its translated code, sound,
// cartridge save, save states and cheats. The Mac player (gba_front_mac.m) is its only caller besides nxgba-run.
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NxGba NxGba;

typedef struct nxgba_info {
    uint64_t frames;
    uint64_t native_blocks;
    uint64_t fallback_steps;
    uint32_t misses_rom, misses_ram;  // distinct entry points that ran in the interpreter this run
    uint32_t blocks;                  // translated blocks in the game's library
    uint32_t save_kind;               // 0 none, 1 SRAM, 2 Flash 64K, 3 Flash 128K, 4 EEPROM
    uint32_t save_bytes;
    uint32_t rom_bytes;
    uint32_t has_rtc;
    uint32_t hle_live;                // 1 while Enhanced audio plays the engine's floating-point re-render
} nxgba_info;

enum {
    NXGBA_A = 1 << 0, NXGBA_B = 1 << 1, NXGBA_SELECT = 1 << 2, NXGBA_START = 1 << 3,
    NXGBA_RIGHT = 1 << 4, NXGBA_LEFT = 1 << 5, NXGBA_UP = 1 << 6, NXGBA_DOWN = 1 << 7,
    NXGBA_R = 1 << 8, NXGBA_L = 1 << 9,
};

// translation: the game's translated code (game.dylib), or NULL to interpret. sav: the cartridge save's file, or NULL.
NxGba *nxgba_open(const char *rom, const char *translation, const char *sav, char *err, int32_t cap);
void nxgba_close(NxGba *);
void nxgba_keys(NxGba *, uint32_t down);
int32_t nxgba_run_frame(NxGba *);
const uint16_t *nxgba_pixels(NxGba *);                  // 240 x 160, 15-bit
void nxgba_rgba(NxGba *, uint8_t *out, uint32_t mode);  // mode 0 raw, 1 the handheld screen's colours
// Any thread (the device's render callback): `frames` interleaved stereo pairs at `rate`.
void nxgba_audio_render(NxGba *, float *out, int32_t frames, double rate);
int32_t nxgba_audio_fill(NxGba *);
int32_t nxgba_audio_target(void);
void nxgba_audio_consumer(NxGba *, int32_t on);
void nxgba_audio_set(NxGba *, int32_t enhanced, int32_t bass, int32_t wide, float volume);
int32_t nxgba_save_flush(NxGba *);
int32_t nxgba_state_save(NxGba *, int32_t slot);
int32_t nxgba_state_load(NxGba *, int32_t slot);
int32_t nxgba_state_has(NxGba *, int32_t slot);
void nxgba_reset(NxGba *);
void nxgba_get_info(NxGba *, nxgba_info *out);
// which 0 the header's title, 1 the game code, 2 the ROM's SHA-1, 3 its SHA-256, 4 what Enhanced audio does here
const char *nxgba_text(NxGba *, int32_t which);
int32_t nxgba_misses_write(NxGba *, const char *also);
int32_t nxgba_cheats_load(NxGba *, const char *text);
int32_t nxgba_cheat_count(NxGba *);
const char *nxgba_cheat_text(NxGba *, int32_t i, int32_t what);  // what 0 the name, 1 why it cannot be applied
int32_t nxgba_cheat_on(NxGba *, int32_t i);
void nxgba_cheat_set(NxGba *, int32_t i, int32_t on);

#ifdef __cplusplus
}
#endif
