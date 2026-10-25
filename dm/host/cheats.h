// Cheats: Atmosphere's dmnt cheat codes, read from Markdown (or Atmosphere's own .txt), run by a VM that behaves like dmnt's (cheats.c).
// A cheat file belongs to one build of one game: title_id (the base game's, as Atmosphere's contents/<title ID>/cheats/) and build_id (main's NSO build ID; Atmosphere names its files
// with the first 8 bytes, 16 hex digits, and any prefix of at least that length matches module_t.build_id). The format is in docs/cheats.md.
// The core has no host dependencies (memory, keys and the log come in through dm_cheat_env), so dm/host/tests/t_cheats.c runs it on any machine; cheats_host.c ties it to the host.
#pragma once
#include <stddef.h>
#include <stdint.h>

#define DM_CHEAT_MAX_OPS 0x100        // dwords in one cheat (Atmosphere's CheatEntry)
#define DM_CHEAT_MAX_PROGRAM 0x400    // dwords of all enabled cheats together (Atmosphere's MaximumProgramOpcodeCount)

typedef struct {
    char name[64];
    char desc[256];        // the Markdown prose under the heading, one line
    uint32_t ops[DM_CHEAT_MAX_OPS];
    unsigned nops;
    int master;            // Atmosphere's {Master code}: always on, runs first
    int default_on;        // ```dmnt on: enabled the first time the file is seen
} dm_cheat;

typedef struct {
    char title_id[17], build_id[33], version[32], game[64], source[256];
    dm_cheat *c; unsigned n;
    char err[256];         // the first problem met while parsing (the cheat it is in is left out); empty when none
} dm_cheat_file;

// Parses a Markdown cheat file, or an Atmosphere .txt (told apart by the first character that is not blank: '[' or '{'). Returns the number of cheats, -1 when nothing usable was found.
int dm_cheats_parse(const char *text, size_t len, dm_cheat_file *out);
void dm_cheats_free(dm_cheat_file *f);
// 1 when the file is for this game and build (title IDs compare whole, build IDs by the file's prefix of 16 or more hex digits, case ignored); a file without title_id or build_id matches
// any (an Atmosphere .txt names them only in its path, which the caller checks)
int dm_cheats_match(const dm_cheat_file *f, const char *title_id, const char *build_id);

// Where the guest's memory is: Atmosphere's four regions that cheat addresses are relative to (MemoryAccessType 0..3)
typedef struct { uint64_t main_base, main_size, heap_base, heap_size, alias_base, alias_size, aslr_base, aslr_size; } dm_cheat_regions;
typedef struct {
    dm_cheat_regions r;
    int (*read)(void *ctx, uint64_t addr, void *buf, size_t n);          // 0 = done; anything else = the address is not readable, the VM goes on (as dmnt's failed debug reads)
    int (*write)(void *ctx, uint64_t addr, const void *buf, size_t n);   // 0 = done
    uint64_t (*keys_held)(void *ctx);                                    // nn::hid::NpadButton bits of player 1 (dm_input.h order), stick directions from bit 16
    void (*log)(void *ctx, const char *line);                            // FFF debug log and refused writes; may be NULL
    void *ctx;
} dm_cheat_env;

typedef struct {
    uint32_t prog[DM_CHEAT_MAX_PROGRAM]; unsigned nprog;
    unsigned ip, depth;
    uint64_t reg[16], saved[16]; unsigned loop_top[16];
    uint64_t static_reg[256];   // 0x00..0x7F read by the cheats (set by the host), 0x80..0xFF written by them; they last across runs
    uint64_t runs, faults;      // faults: reads and writes the env refused
    int bad;                    // the program stopped on an opcode it could not decode (ip names it)
} dm_cheat_vm;

// Builds the program from the file's master codes and the cheats whose enabled[i] is set (in file order, as Atmosphere). Returns the dwords loaded, -1 when they do not fit.
int dm_cheat_vm_load(dm_cheat_vm *vm, const dm_cheat_file *f, const uint8_t *enabled);
// Runs the program once from the top (registers cleared, static registers kept). Returns 0, or -1 when it stopped on an opcode it could not decode.
int dm_cheat_vm_run(dm_cheat_vm *vm, const dm_cheat_env *env);

// The host's cheats (cheats_host.c) as the Mac's Quick settings sidebar sees them (main thread). Flags of a cheat: on now, a master code, a code patch (made at load:
// a change shows at the next launch), made at this launch. A change to the set is saved by the sidebar (DMQuickSettings.cheats.<game>) and runs from the next frame
enum { DM_CHEAT_ON = 1, DM_CHEAT_MASTER = 2, DM_CHEAT_CODE = 4, DM_CHEAT_APPLIED = 8 };
unsigned dm_cheats_count(void);
void dm_cheats_info(unsigned i, const char **name, const char **desc, int *flags);
void dm_cheats_set(unsigned i, int on);
void dm_cheats_rescan(void);           // read the folder again
const char *dm_cheats_dir(void);       // the cheats folder
const char *dm_cheats_build(void);     // main's build ID (32 hex digits; "" before the game is loaded)
const char *dm_cheats_path(void);      // the file in use, "" when none
const char *dm_cheats_version(void);   // its front matter's version, "" when none
const char *dm_cheats_problem(void);   // the first cheat it left out and why, "" when none
