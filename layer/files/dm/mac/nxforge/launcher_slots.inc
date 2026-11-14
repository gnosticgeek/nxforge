// NXForge: quick-save slots, the launcher's half (included by launcher.c; the sidebar's half is quick_settings_mac.swift SaveSlots). To load a slot the host writes the slot's
// data folder (<save's folder>/save-slots/<n>/data) into the file DM_LAUNCHER_SLOT_LOAD names, has already checked the slot and kept the current save as a snapshot, and quits
// as Restart game does. With the host stopped, each part of the save (save, save_device) is replaced here by a clone of the slot's: cloned beside it, then swapped in with one
// rename (RENAME_SWAP), so a part is never half replaced; the old one is removed after. The host's next mount clears its leftover work folders. The next start is told how it
// went (DM_SLOT_LOADED: the slot's folder, or "!" and why it was not loaded), and the toast says so.
#include <sys/clonefile.h>
static int slot_part(const char *from, const char *to, char *why, size_t nwhy) {
    char tmp[PATH_MAX]; struct stat s;
    snprintf(tmp, sizeof tmp, "%s.slot-load", to);
    removefile(tmp, NULL, REMOVEFILE_RECURSIVE);   // a leftover of a load cut short
    if (stat(from, &s)) {   // the slot has no such part (no device save then): the current one goes; it is in the snapshot the host made
        if (stat(to, &s)) return 1;
        if (rename(to, tmp)) { snprintf(why, nwhy, "could not move %s aside (%s)", to, strerror(errno)); return 0; }
        removefile(tmp, NULL, REMOVEFILE_RECURSIVE); return 1;
    }
    if (clonefile(from, tmp, 0) && copyfile(from, tmp, NULL, COPYFILE_ALL | COPYFILE_RECURSIVE)) {
        snprintf(why, nwhy, "could not copy the slot (%s)", strerror(errno)); removefile(tmp, NULL, REMOVEFILE_RECURSIVE); return 0;
    }
    if (stat(to, &s)) { if (!rename(tmp, to)) return 1; }
    else if (!renamex_np(tmp, to, RENAME_SWAP)) { removefile(tmp, NULL, REMOVEFILE_RECURSIVE); return 1; }   // tmp now holds the old save
    snprintf(why, nwhy, "could not put the slot in place (%s)", strerror(errno)); removefile(tmp, NULL, REMOVEFILE_RECURSIVE); return 0;
}
static void slot_load(const char *req, const char *save) {
    unsetenv("DM_SLOT_LOADED");
    FILE *f = fopen(req, "r"); if (!f) return;
    char dir[PATH_MAX] = "", why[PATH_MAX + 64] = "", folder[PATH_MAX];
    if (!fgets(dir, sizeof dir, f)) dir[0] = 0;
    fclose(f); unlink(req);
    dir[strcspn(dir, "\r\n")] = 0;
    // only a slot of this save: <save's folder>/save-slots/<n>/data
    char base[PATH_MAX]; snprintf(base, sizeof base, "%s", save ? save : "");
    for (size_t n = strlen(base); n > 1 && base[n - 1] == '/'; n--) base[n - 1] = 0;   // as the sidebar reads DM_SAVE
    save = base;
    snprintf(folder, sizeof folder, "%s", save); char *sl = strrchr(folder, '/'); if (sl) *sl = 0;
    size_t fl = strlen(folder);
    if (!*dir || strncmp(dir, folder, fl) || strncmp(dir + fl, "/save-slots/", 12) || strstr(dir, "/../")) snprintf(why, sizeof why, "the request named no slot of this save (%s)", dir);
    else {
        char from[PATH_MAX], to[PATH_MAX];
        snprintf(from, sizeof from, "%s/save", dir);
        if (slot_part(from, save, why, sizeof why)) {
            snprintf(from, sizeof from, "%s/save_device", dir); snprintf(to, sizeof to, "%s_device", save);
            slot_part(from, to, why, sizeof why);
        }
    }
    if (*why) { fprintf(stderr, "[RED] launcher: quick-save slot not loaded: %s\n", why); char v[sizeof why + 1]; snprintf(v, sizeof v, "!%s", why); setenv("DM_SLOT_LOADED", v, 1); }
    else { fprintf(stderr, "launcher: quick-save slot %s loaded into %s\n", dir, save); setenv("DM_SLOT_LOADED", dir, 1); }
}
