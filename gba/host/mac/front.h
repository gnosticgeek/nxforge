// The part of nxnative's front.h (dm/host/front.h) the sidebar reads (quick_settings_mac.h includes "front.h"): the
// picture settings. The Game Boy Advance player (gba_front_mac.m) implements them for its own 240 x 160 picture, with
// the same numbers, so the sidebar and the saved settings mean the same in both players.
#pragma once
#include <stdint.h>
#include <stdlib.h>

enum { DM_PFX_OFF, DM_PFX_SHARPEN, DM_PFX_PIXEL, DM_PFX_CRT, DM_PFX_LOTTES, DM_PFX_LCD, DM_PFX_N };
int mtl_present_filter(float *strength);
void mtl_present_filter_set(int mode, float strength);
int mtl_aniso(void);
void mtl_aniso_set(int n);
int mtl_present_upscale(void);
void mtl_present_upscale_set(int on);
enum { DM_PAA_OFF, DM_PAA_FXAA, DM_PAA_N };
int mtl_present_aa(void);
void mtl_present_aa_set(int mode);
int mtl_present_edr(void);
void mtl_present_edr_set(int on);
int mtl_present_edr_strength(void);
void mtl_present_edr_strength_set(int strength);
float mtl_present_edr_headroom(void);
int mtl_present_interp(void);
void mtl_present_interp_set(int mode);
int mtl_present_interp_active(void);
enum { DM_PIXEL_OFF, DM_PIXEL_SHARP, DM_PIXEL_SMOOTH, DM_PIXEL_AUTO, DM_PIXEL_N };
int mtl_present_pixel(void);
void mtl_present_pixel_set(int mode);
int mtl_present_pixel_active(void);
int mtl_present_pixel_grid(float *art_w, float *art_h, float *scale);
int mtl_present_scanline(void);
void mtl_present_scanline_set(int rows);
enum { DM_PSCALE_FIT, DM_PSCALE_STRETCH, DM_PSCALE_INTEGER, DM_PSCALE_N };
int mtl_present_scale(void);
void mtl_present_scale_set(int mode);
enum { DM_PBORDER_OFF, DM_PBORDER_GLOW, DM_PBORDER_ART, DM_PBORDER_N };
int mtl_present_border(void);
void mtl_present_border_set(int mode);
int mtl_present_times(double *ms, int max, double *age);
uint64_t mtl_present_count(void);
void mtl_present_inset(float share);
