// Cheats: the Markdown / Atmosphere .txt parser and a VM that runs Atmosphere's dmnt cheat opcodes (cheats.h). Opcode layouts follow Atmosphere's dmnt_cheat_vm.cpp;
// what the VM does not take (load type 5 with I > 1, C4 extended key masks, float arithmetic) stops the program like an undecodable opcode, and the log says which.
#include "cheats.h"
#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

// ---- Parser
static int ieq_prefix(const char *a, const char *b) { while (*a && *b) { if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0; a++; b++; } return 1; }
static void copy_trim(char *dst, size_t cap, const char *s, size_t n) {
    while (n && isspace((unsigned char)*s)) { s++; n--; }
    while (n && isspace((unsigned char)s[n - 1])) n--;
    if (n >= 2 && (s[0] == '"' || s[0] == '\'') && s[n - 1] == s[0]) { s++; n -= 2; }
    if (n >= cap) n = cap - 1;
    memcpy(dst, s, n); dst[n] = 0;
}
static void set_err(dm_cheat_file *f, unsigned line, const char *what, const char *name) {
    if (!f->err[0]) snprintf(f->err, sizeof f->err, "line %u: %s%s%s", line, what, name && *name ? " in " : "", name ? name : "");
}
static dm_cheat *new_cheat(dm_cheat_file *f, const char *name, size_t n) {
    dm_cheat *c = realloc(f->c, (f->n + 1) * sizeof *c);
    if (!c) return NULL;
    f->c = c; c = &f->c[f->n++]; memset(c, 0, sizeof *c);
    copy_trim(c->name, sizeof c->name, name, n);
    return c;
}
// One line of code: 8-digit hex words separated by blanks. Returns 0, or -1 (bad word / too long: the cheat is dropped)
static int add_words(dm_cheat *c, const char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        while (i < n && isspace((unsigned char)s[i])) i++;
        if (i == n) break;
        size_t j = i; uint32_t v = 0;
        while (j < n && isxdigit((unsigned char)s[j])) { v = v << 4 | (uint32_t)(isdigit((unsigned char)s[j]) ? s[j] - '0' : (tolower((unsigned char)s[j]) - 'a' + 10)); j++; }
        if (j - i != 8 || (j < n && !isspace((unsigned char)s[j]))) return -1;
        if (c->nops == DM_CHEAT_MAX_OPS) return -1;
        c->ops[c->nops++] = v; i = j;
    }
    return 0;
}
static void drop_last(dm_cheat_file *f) { if (f->n) f->n--; }
static void front_matter(dm_cheat_file *f, const char *s, size_t n) {
    const char *colon = memchr(s, ':', n); if (!colon) return;
    size_t k = (size_t)(colon - s), vn = n - k - 1; const char *v = colon + 1;
    for (size_t i = 0; i + 1 < vn; i++) if (v[i] == ' ' && v[i + 1] == '#') { vn = i; break; }   // a trailing YAML comment
    char key[32]; copy_trim(key, sizeof key, s, k);
    if (!strcmp(key, "title_id")) copy_trim(f->title_id, sizeof f->title_id, v, vn);
    else if (!strcmp(key, "build_id")) copy_trim(f->build_id, sizeof f->build_id, v, vn);
    else if (!strcmp(key, "version")) copy_trim(f->version, sizeof f->version, v, vn);
    else if (!strcmp(key, "game")) copy_trim(f->game, sizeof f->game, v, vn);
    else if (!strcmp(key, "source")) copy_trim(f->source, sizeof f->source, v, vn);
}

// Markdown: optional front matter (--- ... ---) with title_id, build_id, version, game, source; each "## " heading starts a cheat, its prose is the description,
// and its code is in fenced blocks whose info string starts with dmnt (```dmnt, ```dmnt master, ```dmnt on). Other headings and fences are text.
static void parse_md(const char *t, size_t len, dm_cheat_file *f) {
    dm_cheat *c = NULL; int fence = 0, code = 0, fm = 0, broken = 0; unsigned ln = 0;
    for (size_t p = 0; p < len;) {
        const char *s = t + p; const char *e = memchr(s, '\n', len - p); size_t n = e ? (size_t)(e - s) : len - p; p += n + 1; ln++;
        if (n && s[n - 1] == '\r') n--;
        if (ln == 1 && n == 3 && !memcmp(s, "---", 3)) { fm = 1; continue; }
        if (fm) { if (n == 3 && !memcmp(s, "---", 3)) fm = 0; else front_matter(f, s, n); continue; }
        size_t i = 0; while (i < n && i < 3 && s[i] == ' ') i++;
        if (n - i >= 3 && !memcmp(s + i, "```", 3)) {
            if (fence) { fence = 0; code = 0; continue; }
            fence = 1; const char *info = s + i + 3; size_t in = n - i - 3;
            while (in && *info == ' ') { info++; in--; }
            code = c && in >= 4 && ieq_prefix(info, "dmnt") && (in == 4 || info[4] == ' ');
            if (!c && in >= 4 && ieq_prefix(info, "dmnt")) set_err(f, ln, "code before the first ## heading", NULL);
            if (code) for (size_t k = 4; k < in;) {
                while (k < in && info[k] == ' ') k++;
                size_t w = k; while (w < in && info[w] != ' ') w++;
                if (w - k == 6 && !memcmp(info + k, "master", 6)) c->master = 1;
                else if (w - k == 2 && !memcmp(info + k, "on", 2)) c->default_on = 1;
                k = w;
            }
            continue;
        }
        if (fence) { if (code && !broken && add_words(c, s, n)) { set_err(f, ln, "not a list of 8-digit hex words (or over 256 of them)", c->name); broken = 1; } continue; }
        if (n - i >= 3 && s[i] == '#' && s[i + 1] == '#' && s[i + 2] == ' ') {
            if (c && (broken || !c->nops)) { if (!broken) set_err(f, ln - 1, "no ```dmnt code", c->name); drop_last(f); }
            c = new_cheat(f, s + i + 3, n - i - 3); broken = 0; continue;
        }
        if (n - i >= 2 && s[i] == '#' && (s[i + 1] == ' ' || s[i + 1] == '#')) continue;   // other headings
        if (c && n > i && !c->nops) {   // prose before the code: the description
            size_t dl = strlen(c->desc); if (dl && dl < sizeof c->desc - 1) c->desc[dl++] = ' ';
            copy_trim(c->desc + dl, sizeof c->desc - dl, s + i, n - i);
        }
    }
    if (c && (broken || !c->nops)) { if (!broken) set_err(f, ln, "no ```dmnt code", c->name); drop_last(f); }
}

// Atmosphere's cheat .txt: [Name] starts a cheat, {Name} the master code, the lines after it are its code
static void parse_txt(const char *t, size_t len, dm_cheat_file *f) {
    dm_cheat *c = NULL; int broken = 0; unsigned ln = 0;
    for (size_t p = 0; p < len;) {
        const char *s = t + p; const char *e = memchr(s, '\n', len - p); size_t n = e ? (size_t)(e - s) : len - p; p += n + 1; ln++;
        if (n && s[n - 1] == '\r') n--;
        size_t i = 0; while (i < n && isspace((unsigned char)s[i])) i++;
        if (i == n) continue;
        if (s[i] == '[' || s[i] == '{') {
            const char *close = memchr(s + i, s[i] == '[' ? ']' : '}', n - i);
            if (c && (broken || !c->nops)) drop_last(f);
            c = new_cheat(f, s + i + 1, close ? (size_t)(close - s - i - 1) : n - i - 1); broken = 0;
            if (c && s[i] == '{') c->master = 1;
            continue;
        }
        if (!c) { set_err(f, ln, "code before the first [name]", NULL); continue; }
        if (!broken && add_words(c, s + i, n - i)) { set_err(f, ln, "not a list of 8-digit hex words (or over 256 of them)", c->name); broken = 1; }
    }
    if (c && (broken || !c->nops)) drop_last(f);
}

int dm_cheats_parse(const char *text, size_t len, dm_cheat_file *out) {
    memset(out, 0, sizeof *out);
    size_t i = 0; while (i < len && isspace((unsigned char)text[i])) i++;
    if (i < len && (text[i] == '[' || text[i] == '{')) parse_txt(text, len, out); else parse_md(text, len, out);
    return out->n ? (int)out->n : -1;
}
void dm_cheats_free(dm_cheat_file *f) { free(f->c); f->c = NULL; f->n = 0; }
int dm_cheats_match(const dm_cheat_file *f, const char *title_id, const char *build_id) {
    if (f->title_id[0] && strcasecmp(f->title_id, title_id)) return 0;
    if (!f->build_id[0]) return 1;
    size_t n = strlen(f->build_id);
    return n >= 16 && strlen(build_id) >= n && !strncasecmp(f->build_id, build_id, n);
}

// ---- VM
int dm_cheat_vm_load(dm_cheat_vm *vm, const dm_cheat_file *f, const uint8_t *enabled) {
    uint64_t keep[256]; memcpy(keep, vm->static_reg, sizeof keep);
    memset(vm, 0, sizeof *vm); memcpy(vm->static_reg, keep, sizeof keep);
    for (int pass = 0; pass < 2; pass++)   // master codes first (Atmosphere keeps the master code as cheat 0)
        for (unsigned i = 0; i < f->n; i++) {
            const dm_cheat *c = &f->c[i];
            if (pass == 0 ? !c->master : (c->master || !enabled || !enabled[i])) continue;
            if (vm->nprog + c->nops > DM_CHEAT_MAX_PROGRAM) { vm->nprog = 0; return -1; }
            memcpy(vm->prog + vm->nprog, c->ops, c->nops * sizeof *c->ops); vm->nprog += c->nops;
        }
    return (int)vm->nprog;
}

enum { OP_STORE_STATIC = 0, OP_BEGIN_COND = 1, OP_END_COND = 2, OP_LOOP = 3, OP_LOAD_STATIC = 4, OP_LOAD_MEM = 5, OP_STORE_TO_ADDR = 6, OP_ARITH_STATIC = 7,
       OP_BEGIN_KEY = 8, OP_ARITH_REG = 9, OP_STORE_REG = 0xA, OP_BEGIN_REG_COND = 0xC0, OP_SAVE_RESTORE = 0xC1, OP_SAVE_RESTORE_MASK = 0xC2, OP_STATIC_REG = 0xC3,
       OP_PAUSE = 0xFF0, OP_RESUME = 0xFF1, OP_DEBUG_LOG = 0xFFF };
typedef struct {
    unsigned op, width, mem, reg, reg2, reg3, sub, cond;   // fields shared by the opcodes (their meaning per opcode in decode)
    int flag, flag2;
    uint64_t addr, value, mask;
} op_t;

static int width_ok(unsigned w) { return w == 1 || w == 2 || w == 4 || w == 8; }
static int next(dm_cheat_vm *vm, uint32_t *v) { if (vm->ip >= vm->nprog) return 0; *v = vm->prog[vm->ip++]; return 1; }
static int next_int(dm_cheat_vm *vm, unsigned w, uint64_t *v) {
    uint32_t a, b;
    if (w == 8) { if (!next(vm, &a) || !next(vm, &b)) return 0; *v = (uint64_t)a << 32 | b; return 1; }
    if (!next(vm, &a)) return 0;
    *v = w == 1 ? (uint8_t)a : w == 2 ? (uint16_t)a : a; return 1;
}
static int is_begin(unsigned op) { return op == OP_BEGIN_COND || op == OP_BEGIN_KEY || op == OP_BEGIN_REG_COND; }

// Decodes the opcode at ip and moves ip past it. 0 = could not (the program stops there)
static int decode(dm_cheat_vm *vm, op_t *o) {
    uint32_t w, x; memset(o, 0, sizeof *o);
    if (!next(vm, &w)) return 0;
    o->op = w >> 28;
    if (o->op >= 0xC) o->op = w >> 24;
    if (o->op >= 0xF0) o->op = w >> 20;
    switch (o->op) {
    case OP_STORE_STATIC:   // 0TMR00AA AAAAAAAA VVVVVVVV (VVVVVVVV)
        o->width = w >> 24 & 0xF; o->mem = w >> 20 & 0xF; o->reg = w >> 16 & 0xF;
        if (!next(vm, &x)) return 0;
        o->addr = (uint64_t)(w & 0xFF) << 32 | x;
        return width_ok(o->width) && next_int(vm, o->width, &o->value);
    case OP_BEGIN_COND:     // 1TMC00AA AAAAAAAA VVVVVVVV (VVVVVVVV)
        o->width = w >> 24 & 0xF; o->mem = w >> 20 & 0xF; o->cond = w >> 16 & 0xF;
        if (!next(vm, &x)) return 0;
        o->addr = (uint64_t)(w & 0xFF) << 32 | x;
        return width_ok(o->width) && next_int(vm, o->width, &o->value);
    case OP_END_COND:       // 20000000 end, 21000000 else
        o->flag = (w >> 24 & 0xF) == 1; return 1;
    case OP_LOOP:           // 300R0000 VVVVVVVV start, 310R0000 end
        o->flag = (w >> 24 & 0xF) == 0; o->reg = w >> 16 & 0xF;
        if (o->flag) { if (!next(vm, &x)) return 0; o->value = x; }
        return 1;
    case OP_LOAD_STATIC:    // 400R0000 VVVVVVVV VVVVVVVV
        o->reg = w >> 16 & 0xF; return next_int(vm, 8, &o->value);
    case OP_LOAD_MEM:       // 5TMRI0AA AAAAAAAA; I = 0 region + A, 1 register R + A
        o->width = w >> 24 & 0xF; o->mem = w >> 20 & 0xF; o->reg = w >> 16 & 0xF; o->sub = w >> 12 & 0xF;
        if (!next(vm, &x)) return 0;
        o->addr = (uint64_t)(w & 0xFF) << 32 | x;
        return width_ok(o->width) && o->sub <= 1;
    case OP_STORE_TO_ADDR:  // 6T0RIor0 VVVVVVVV VVVVVVVV
        o->width = w >> 24 & 0xF; o->reg = w >> 16 & 0xF; o->flag = (w >> 12 & 0xF) != 0; o->flag2 = (w >> 8 & 0xF) != 0; o->reg2 = w >> 4 & 0xF;
        return width_ok(o->width) && next_int(vm, 8, &o->value);
    case OP_ARITH_STATIC:   // 7T0RC000 VVVVVVVV
        o->width = w >> 24 & 0xF; o->reg = w >> 16 & 0xF; o->sub = w >> 12 & 0xF;
        if (!next(vm, &x)) return 0;
        o->value = x; return width_ok(o->width) && o->sub <= 4;
    case OP_BEGIN_KEY:      // 8kkkkkkk
        o->mask = w & 0x0FFFFFFF; return 1;
    case OP_ARITH_REG:      // 9TCRS0s0, or 9TCRS100 VVVVVVVV (VVVVVVVV)
        o->width = w >> 24 & 0xF; o->sub = w >> 20 & 0xF; o->reg = w >> 16 & 0xF; o->reg2 = w >> 12 & 0xF; o->flag = (w >> 8 & 0xF) != 0;
        if (!width_ok(o->width) || o->sub > 9) return 0;
        if (o->flag) return next_int(vm, o->width, &o->value);
        o->reg3 = w >> 4 & 0xF; return 1;
    case OP_STORE_REG:      // ATSRIOxa (aaaaaaaa): store register S at address register R with offset type O
        o->width = w >> 24 & 0xF; o->reg = w >> 20 & 0xF; o->reg2 = w >> 16 & 0xF; o->flag = (w >> 12 & 0xF) != 0; o->sub = w >> 8 & 0xF;
        if (!width_ok(o->width) || o->sub > 5) return 0;
        if (o->sub == 1) o->reg3 = w >> 4 & 0xF;
        if (o->sub >= 3) o->mem = w >> 4 & 0xF;
        if (o->sub == 2 || o->sub == 4 || o->sub == 5) { if (!next(vm, &x)) return 0; o->addr = (uint64_t)(w & 0xF) << 32 | x; }
        return 1;
    case OP_BEGIN_REG_COND: // C0TcSX..: compare register S with memory, a register or a value (X picks which)
        o->width = w >> 20 & 0xF; o->cond = w >> 16 & 0xF; o->reg = w >> 12 & 0xF; o->sub = w >> 8 & 0xF;
        if (!width_ok(o->width)) return 0;
        switch (o->sub) {
        case 0: o->mem = w >> 4 & 0xF; if (!next(vm, &x)) return 0; o->addr = (uint64_t)(w & 0xF) << 32 | x; return 1;   // memory, region + A
        case 1: o->mem = w >> 4 & 0xF; o->reg3 = w & 0xF; return 1;                                                      // memory, region + register
        case 2: o->reg2 = w >> 4 & 0xF; if (!next(vm, &x)) return 0; o->addr = (uint64_t)(w & 0xF) << 32 | x; return 1;  // address register + A
        case 3: o->reg2 = w >> 4 & 0xF; o->reg3 = w & 0xF; return 1;                                                      // address register + offset register
        case 4: return next_int(vm, o->width, &o->value);                                                                 // a value
        case 5: o->reg2 = w >> 4 & 0xF; return 1;                                                                         // another register
        }
        return 0;
    case OP_SAVE_RESTORE:   // C10D0Sx0
        o->reg = w >> 16 & 0xF; o->reg2 = w >> 8 & 0xF; o->sub = w >> 4 & 0xF; return o->sub <= 3;
    case OP_SAVE_RESTORE_MASK:   // C2x0XXXX
        o->sub = w >> 20 & 0xF; o->mask = w & 0xFFFF; return o->sub <= 3;
    case OP_STATIC_REG:     // C3000XXx
        o->sub = w >> 4 & 0xFF; o->reg = w & 0xF; return 1;
    case OP_PAUSE: case OP_RESUME: return 1;
    case OP_DEBUG_LOG:      // FFFTIX##
        o->width = w >> 16 & 0xF; o->sub = w >> 12 & 0xF; o->cond = w >> 8 & 0xF;
        if (!width_ok(o->width)) return 0;
        switch (o->cond) {
        case 0: o->mem = w >> 4 & 0xF; if (!next(vm, &x)) return 0; o->addr = (uint64_t)(w & 0xF) << 32 | x; return 1;
        case 1: o->mem = w >> 4 & 0xF; o->reg3 = w & 0xF; return 1;
        case 2: o->reg2 = w >> 4 & 0xF; if (!next(vm, &x)) return 0; o->addr = (uint64_t)(w & 0xF) << 32 | x; return 1;
        case 3: o->reg2 = w >> 4 & 0xF; o->reg3 = w & 0xF; return 1;
        case 4: o->reg = w >> 4 & 0xF; return 1;
        }
        return 0;
    }
    return 0;
}

// Skips the rest of a block whose condition failed: to its else (is_if) or its end, nested blocks included (dmnt SkipConditionalBlock)
static void skip_block(dm_cheat_vm *vm, int is_if) {
    if (!vm->depth) return;
    unsigned want = vm->depth - 1; op_t o;
    while (vm->depth > want && decode(vm, &o)) {
        if (is_begin(o.op)) vm->depth++;
        else if (o.op == OP_END_COND) {
            if (!o.flag) vm->depth--;
            else if (is_if && vm->depth - 1 == want) break;
        }
    }
}

static uint64_t region(const dm_cheat_env *env, unsigned mem, uint64_t rel) {
    const dm_cheat_regions *r = &env->r;
    switch (mem) { case 0: return r->main_base + rel; case 1: return r->heap_base + rel; case 2: return r->alias_base + rel; case 3: return r->aslr_base + rel; }
    return rel;
}
static uint64_t trunc_w(uint64_t v, unsigned w) { return w == 1 ? (uint8_t)v : w == 2 ? (uint16_t)v : w == 4 ? (uint32_t)v : v; }
static int rd(dm_cheat_vm *vm, const dm_cheat_env *env, uint64_t a, unsigned w, uint64_t *v) {
    uint64_t x = 0;   // little-endian, as the guest
    if (env->read(env->ctx, a, &x, w)) { vm->faults++; return 0; }
    *v = trunc_w(x, w); return 1;
}
static void wr(dm_cheat_vm *vm, const dm_cheat_env *env, uint64_t a, unsigned w, uint64_t v) { if (env->write(env->ctx, a, &v, w)) vm->faults++; }
static int compare(unsigned cond, uint64_t a, uint64_t b) {
    switch (cond) { case 1: return a > b; case 2: return a >= b; case 3: return a < b; case 4: return a <= b; case 5: return a == b; case 6: return a != b; }
    return 0;
}
static void say(const dm_cheat_env *env, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void say(const dm_cheat_env *env, const char *fmt, ...) {
    if (!env->log) return;
    char b[160]; va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap); env->log(env->ctx, b);
}

int dm_cheat_vm_run(dm_cheat_vm *vm, const dm_cheat_env *env) {
    memset(vm->reg, 0, sizeof vm->reg); memset(vm->saved, 0, sizeof vm->saved); memset(vm->loop_top, 0, sizeof vm->loop_top);
    vm->ip = 0; vm->depth = 0; vm->bad = 0; vm->runs++;
    uint64_t keys = env->keys_held ? env->keys_held(env->ctx) : 0;
    op_t o;
    for (;;) {
        unsigned at = vm->ip;
        if (at >= vm->nprog) return 0;
        if (!decode(vm, &o)) {
            vm->bad = 1; vm->ip = at;
            if (vm->runs == 1) say(env, "cheats: stopped at dword %u (%08x): an opcode the VM does not take", at, vm->prog[at]);
            return -1;
        }
        if (is_begin(o.op)) vm->depth++;
        uint64_t a, v, c;
        switch (o.op) {
        case OP_STORE_STATIC: wr(vm, env, region(env, o.mem, o.addr + vm->reg[o.reg]), o.width, o.value); break;
        case OP_BEGIN_COND:
            if (!rd(vm, env, region(env, o.mem, o.addr), o.width, &v) || !compare(o.cond, v, o.value)) skip_block(vm, 1);
            break;
        case OP_END_COND: if (o.flag) skip_block(vm, 0); else if (vm->depth) vm->depth--; break;   // an else reached by running the if part skips to the end
        case OP_LOOP:
            if (o.flag) { vm->reg[o.reg] = o.value; vm->loop_top[o.reg] = vm->ip; }
            else if (--vm->reg[o.reg]) vm->ip = vm->loop_top[o.reg];
            break;
        case OP_LOAD_STATIC: vm->reg[o.reg] = o.value; break;
        case OP_LOAD_MEM:
            a = o.sub ? vm->reg[o.reg] + o.addr : region(env, o.mem, o.addr);
            if (rd(vm, env, a, o.width, &v)) vm->reg[o.reg] = v;
            break;
        case OP_STORE_TO_ADDR:
            a = vm->reg[o.reg] + (o.flag2 ? vm->reg[o.reg2] : 0);
            wr(vm, env, a, o.width, o.value);
            if (o.flag) vm->reg[o.reg] += o.width;
            break;
        case OP_ARITH_STATIC:
            v = vm->reg[o.reg];
            switch (o.sub) { case 0: v += o.value; break; case 1: v -= o.value; break; case 2: v *= o.value; break; case 3: v <<= o.value; break; case 4: v >>= o.value; break; }
            vm->reg[o.reg] = trunc_w(v, o.width);
            break;
        case OP_BEGIN_KEY: if ((keys & o.mask) != o.mask) skip_block(vm, 1); break;
        case OP_ARITH_REG: {
            uint64_t x = vm->reg[o.reg2], y = o.flag ? o.value : vm->reg[o.reg3];
            switch (o.sub) {
            case 0: v = x + y; break; case 1: v = x - y; break; case 2: v = x * y; break; case 3: v = x << y; break; case 4: v = x >> y; break;
            case 5: v = x & y; break; case 6: v = x | y; break; case 7: v = ~x; break; case 8: v = x ^ y; break; default: v = x; break;
            }
            vm->reg[o.reg] = trunc_w(v, o.width);
            break;
        }
        case OP_STORE_REG:
            v = vm->reg[o.reg]; a = vm->reg[o.reg2];
            switch (o.sub) {
            case 1: a += vm->reg[o.reg3]; break;
            case 2: a += o.addr; break;
            case 3: a = region(env, o.mem, vm->reg[o.reg2]); break;
            case 4: a = region(env, o.mem, o.addr); break;
            case 5: a = region(env, o.mem, vm->reg[o.reg2] + o.addr); break;
            }
            wr(vm, env, a, o.width, v);
            if (o.flag) vm->reg[o.reg2] += o.width;
            break;
        case OP_BEGIN_REG_COND:
            v = trunc_w(vm->reg[o.reg], o.width);
            switch (o.sub) {
            case 0: a = region(env, o.mem, o.addr); break;
            case 1: a = region(env, o.mem, vm->reg[o.reg3]); break;
            case 2: a = vm->reg[o.reg2] + o.addr; break;
            case 3: a = vm->reg[o.reg2] + vm->reg[o.reg3]; break;
            default: a = 0; break;
            }
            if (o.sub <= 3) { if (!rd(vm, env, a, o.width, &c)) { skip_block(vm, 1); break; } }
            else c = o.sub == 4 ? o.value : trunc_w(vm->reg[o.reg2], o.width);
            if (!compare(o.cond, v, c)) skip_block(vm, 1);
            break;
        case OP_SAVE_RESTORE:
            switch (o.sub) {
            case 0: vm->reg[o.reg] = vm->saved[o.reg2]; break; case 1: vm->saved[o.reg] = vm->reg[o.reg2]; break;
            case 2: vm->saved[o.reg] = 0; break; case 3: vm->reg[o.reg] = 0; break;
            }
            break;
        case OP_SAVE_RESTORE_MASK:
            for (int i = 0; i < 16; i++) if (o.mask >> i & 1)
                switch (o.sub) { case 0: vm->reg[i] = vm->saved[i]; break; case 1: vm->saved[i] = vm->reg[i]; break; case 2: vm->saved[i] = 0; break; case 3: vm->reg[i] = 0; break; }
            break;
        case OP_STATIC_REG: if (o.sub < 0x80) vm->reg[o.reg] = vm->static_reg[o.sub]; else vm->static_reg[o.sub] = vm->reg[o.reg]; break;
        case OP_PAUSE: case OP_RESUME: break;   // dmnt stops the game's threads between the two; here the writes in between race the game as all others do
        case OP_DEBUG_LOG:
            switch (o.cond) {
            case 0: a = region(env, o.mem, o.addr); break;
            case 1: a = region(env, o.mem, vm->reg[o.reg3]); break;
            case 2: a = vm->reg[o.reg2] + o.addr; break;
            case 3: a = vm->reg[o.reg2] + vm->reg[o.reg3]; break;
            default: a = 0; break;
            }
            if (o.cond == 4) say(env, "cheats: log %x = %#llx", o.sub, (unsigned long long)trunc_w(vm->reg[o.reg], o.width));
            else if (rd(vm, env, a, o.width, &v)) say(env, "cheats: log %x = %#llx", o.sub, (unsigned long long)v);
            break;
        }
    }
}
