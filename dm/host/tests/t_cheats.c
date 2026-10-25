// Cheats (cheats.c): the Markdown and Atmosphere .txt parsers, build matching, and the dmnt VM on a fake guest memory (main at 0x80000000, heap at 0x90000000)
#include "../cheats.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define MAIN 0x80000000ull
#define HEAP 0x90000000ull
#define SZ 0x10000
static uint8_t g_main[SZ], g_heap[SZ];
static uint64_t g_keys;
static char g_log[256];
static uint8_t *at(uint64_t a, size_t n) {
    if (a >= MAIN && a + n <= MAIN + SZ) return g_main + (a - MAIN);
    if (a >= HEAP && a + n <= HEAP + SZ) return g_heap + (a - HEAP);
    return NULL;
}
static int rd(void *ctx, uint64_t a, void *b, size_t n) { (void)ctx; uint8_t *p = at(a, n); if (!p) return -1; memcpy(b, p, n); return 0; }
static int wr(void *ctx, uint64_t a, const void *b, size_t n) { (void)ctx; uint8_t *p = at(a, n); if (!p) return -1; memcpy(p, b, n); return 0; }
static uint64_t keys(void *ctx) { (void)ctx; return g_keys; }
static void lg(void *ctx, const char *s) { (void)ctx; snprintf(g_log, sizeof g_log, "%s", s); }
static const dm_cheat_env ENV = { { MAIN, SZ, HEAP, SZ, 0, 0, 0, 0 }, rd, wr, keys, lg, NULL };
static uint32_t u32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t u64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }

// Runs one program given as Atmosphere text
static dm_cheat_vm g_vm;
static int run(const char *code) {
    char t[2048]; snprintf(t, sizeof t, "[t]\n%s\n", code);
    dm_cheat_file f; assert(dm_cheats_parse(t, strlen(t), &f) == 1);
    uint8_t on = 1; assert(dm_cheat_vm_load(&g_vm, &f, &on) > 0);
    dm_cheats_free(&f);
    return dm_cheat_vm_run(&g_vm, &ENV);
}

static const char MD[] =
    "---\n"
    "title_id: 0100B99019412000\n"
    "build_id: 0123456789ABCDEF   # main's build ID, first 16 hex digits\n"
    "version: 1.0.1\n"
    "game: \"Mario vs. Donkey Kong\"\n"
    "---\n"
    "\n"
    "# Mario vs. Donkey Kong 1.0.1\n"
    "\n"
    "## Master code\n"
    "```dmnt master\n"
    "04000000 00000010 0000002A\n"
    "```\n"
    "\n"
    "## Infinite lives\n"
    "Keeps the lives\n"
    "counter at 99.\n"
    "\n"
    "```dmnt on\n"
    "04000000 00000020 00000063\n"
    "```\n"
    "\n"
    "## Not a cheat: a typo\n"
    "```dmnt\n"
    "0400000 00000020\n"
    "```\n"
    "\n"
    "## Moon jump (hold ZR)\n"
    "Some notes in a code block that is not dmnt:\n"
    "```text\n"
    "ZZZZ\n"
    "```\n"
    "```dmnt\n"
    "80000200\n"
    "04000000 00000030 00000001\n"
    "20000000\n"
    "```\n";

int main(void) {
    // Markdown
    dm_cheat_file f;
    assert(dm_cheats_parse(MD, strlen(MD), &f) == 3);
    assert(!strcmp(f.title_id, "0100B99019412000") && !strcmp(f.build_id, "0123456789ABCDEF") && !strcmp(f.version, "1.0.1") && !strcmp(f.game, "Mario vs. Donkey Kong"));
    assert(!strcmp(f.c[0].name, "Master code") && f.c[0].master && f.c[0].nops == 3);
    assert(!strcmp(f.c[1].name, "Infinite lives") && f.c[1].default_on && !f.c[1].master && !strcmp(f.c[1].desc, "Keeps the lives counter at 99."));
    assert(!strcmp(f.c[2].name, "Moon jump (hold ZR)") && f.c[2].nops == 5 && !f.c[2].default_on);
    assert(strstr(f.err, "Not a cheat: a typo"));
    assert(dm_cheats_match(&f, "0100b99019412000", "0123456789abcdef0011223344556677"));
    assert(!dm_cheats_match(&f, "0100B99019412000", "1123456789abcdef0011223344556677"));
    assert(!dm_cheats_match(&f, "010015100B514000", "0123456789abcdef0011223344556677"));
    // Master code always runs, and runs first; cheat 1 on, cheat 2 off
    uint8_t en[3] = { 0, 1, 0 };
    assert(dm_cheat_vm_load(&g_vm, &f, en) == 6);
    memset(g_main, 0, SZ);
    assert(dm_cheat_vm_run(&g_vm, &ENV) == 0);
    assert(u32(g_main + 0x10) == 42 && u32(g_main + 0x20) == 99 && u32(g_main + 0x30) == 0);
    en[2] = 1; assert(dm_cheat_vm_load(&g_vm, &f, en) == 11);
    g_keys = 0x200; assert(dm_cheat_vm_run(&g_vm, &ENV) == 0 && u32(g_main + 0x30) == 1);
    dm_cheats_free(&f);

    // Atmosphere .txt
    static const char TXT[] = "{Master}\r\n04000000 00000000 00000001\r\n\r\n[Max coins]\r\n04000000 00000004 000003E7\r\n[Empty]\r\n[Bad]\r\nnope\r\n";
    assert(dm_cheats_parse(TXT, strlen(TXT), &f) == 2);
    assert(f.c[0].master && !strcmp(f.c[0].name, "Master") && !strcmp(f.c[1].name, "Max coins") && f.c[1].nops == 3 && f.err[0]);
    assert(dm_cheats_match(&f, "anything", "anything"));
    dm_cheats_free(&f);

    // 0 store (8 bytes; region + offset register), 4 load static
    memset(g_main, 0, SZ); memset(g_heap, 0, SZ);
    assert(run("400F0000 00000000 00000100\n081F0000 00000008 11223344 55667788") == 0);
    assert(u64(g_heap + 0x108) == 0x1122334455667788ull);
    // 1 conditional with else: the if part runs when main+0x10 == 5, the else part otherwise
    const char *ifelse = "14050000 00000010 00000005\n04000000 00000020 00000001\n21000000\n04000000 00000020 00000002\n20000000";
    memset(g_main, 0, SZ); g_main[0x10] = 5; assert(run(ifelse) == 0 && u32(g_main + 0x20) == 1);
    memset(g_main, 0, SZ); assert(run(ifelse) == 0 && u32(g_main + 0x20) == 2);
    // nested blocks inside a skipped block are skipped whole
    memset(g_main, 0, SZ);
    assert(run("14050000 00000010 00000005\n14050000 00000010 00000000\n04000000 00000020 00000007\n21000000\n04000000 00000020 00000008\n20000000\n20000000\n04000000 00000024 00000009") == 0);
    assert(u32(g_main + 0x20) == 0 && u32(g_main + 0x24) == 9);
    // 8 keys: needs every key of the mask held
    memset(g_main, 0, SZ); g_keys = 0x100; assert(run("80000300\n04000000 00000020 00000001\n20000000") == 0 && u32(g_main + 0x20) == 0);
    g_keys = 0x300; assert(run("80000300\n04000000 00000020 00000001\n20000000") == 0 && u32(g_main + 0x20) == 1);
    // 3 loop + 6 store to address with increment: fills 4 words
    memset(g_heap, 0, SZ);
    assert(run("40010000 00000000 90000040\n30020000 00000004\n64011000 00000000 0000ABCD\n31020000") == 0);
    for (int i = 0; i < 4; i++) assert(u32(g_heap + 0x40 + 4 * i) == 0xABCD);
    assert(u32(g_heap + 0x50) == 0);
    // pointer chain: 5 load the heap pointer at main+0x100 into R0 and R1, 5 load [R1+0x8] (I=1), 7 add, A store R1 back at R0+8
    memset(g_main, 0, SZ); memset(g_heap, 0, SZ);
    uint64_t p = HEAP + 0x200; memcpy(g_main + 0x100, &p, 8); g_heap[0x208] = 10;
    assert(run("58000000 00000100\n58010000 00000100\n54111000 00000008\n74010000 00000005\nA4100200 00000008") == 0);
    assert(u32(g_heap + 0x208) == 15);
    // a pointer to nowhere: counted as a fault, the program goes on
    memset(g_main, 0, SZ);
    assert(run("58000000 00000100\n54101000 00000008\n04000000 00000020 00000003") == 0);
    assert(u32(g_main + 0x20) == 3 && g_vm.faults == 1);
    // 9 register arithmetic (immediate, then register xor), C0 compare with a value, A store to region + immediate (type 0 adds its offset register: R15, still 0)
    memset(g_main, 0, SZ);
    assert(run("40000000 00000000 00000006\n94010100 00000007\n94821000\nC0451400 0000000D\n040F0000 00000020 00000001\n20000000\nA4200400 00000024") == 0);
    assert(u32(g_main + 0x20) == 1 && u32(g_main + 0x24) == (13 ^ 6));
    // C2 save by mask, C1 clear, C2 restore, C3 write static register 0x80 (kept across loads and runs)
    memset(g_main, 0, SZ);
    assert(run("40000000 00000000 0000000B\nC2100001\nC1000030\nC2000001\nC3000800\nA4000400 00000020") == 0);
    assert(g_vm.static_reg[0x80] == 0xB && u32(g_main + 0x20) == 0xB);
    g_vm.static_reg[0x01] = 0x77;
    assert(run("C3000011\nA4100400 00000028") == 0 && u32(g_main + 0x28) == 0x77 && g_vm.static_reg[0x80] == 0xB);
    // an opcode the VM does not take stops the program there, and says so once
    g_log[0] = 0; assert(run("04000000 00000020 00000001\nB0000000\n04000000 00000024 00000001") == -1 && strstr(g_log, "b0000000"));
    // program too long
    dm_cheat big; memset(&big, 0, sizeof big); big.nops = DM_CHEAT_MAX_OPS;
    dm_cheat many[5]; for (int i = 0; i < 5; i++) many[i] = big;
    dm_cheat_file fb = { .c = many, .n = 5 }; uint8_t all[5] = { 1, 1, 1, 1, 1 };
    assert(dm_cheat_vm_load(&g_vm, &fb, all) == -1);
    puts("t_cheats: ok");
    return 0;
}
