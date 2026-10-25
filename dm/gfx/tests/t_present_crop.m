// Present crop regression: colored 8×8 texture, closed-form RGBA expectations; real Metal rendering, no dependence on the game or on cross-run determinism.
// nvn_mtl.m's nvn_game_fps is a weak default and hle_nvn.c gives the strong definition; in one translation unit that is a redefinition, so the weak one is renamed (this test does not look at the frame-rate target)
#define nvn_game_fps nvn_game_fps_mtl_default
#include "../nvn/nvn_mtl.m"
#undef nvn_game_fps
#define g_ft g_ft_hle   // both files have a static g_ft (nvn_mtl.m's fragment argument table, hle_nvn.c's textures a flush can mark CPU-written), so hle_nvn.c's is renamed too
#include "../nvn/hle_nvn.c"
#undef g_ft
uint64_t g_t0_ns;   // process start time from host main.c (used by hle_nvn's per-frame @t_s); unit test stub
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
#ifdef CROP_LEGACY_HEADER
#include CROP_LEGACY_HEADER
#define ENCODE legacy_present_encode
#else
#define ENCODE present_encode
#endif
static int failed, cases;
#define EXPECT(n, w, v) do { int a=(w),b=(v); cases++; printf("%s expected %d → got %d %s\n",n,a,b,a==b?"✓":"✗");failed+=a!=b; } while(0)
static const uint8_t colors[4][4]={{255,0,0,255},{0,255,0,255},{0,0,255,255},{255,255,0,255}};

static void check(id<MTLTexture> src, const char *name, const int crop[4], int w, int h, int color) {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageRenderTarget;
    id<MTLTexture> dst=[g_dev newTextureWithDescriptor:d];id<MTLCommandBuffer> cb=[g_q commandBuffer];
    EXPECT("encode succeeds",1,ENCODE(cb,src,dst,crop));[cb commit];[cb waitUntilCompleted];
    EXPECT("GPU done",MTLCommandBufferStatusCompleted,cb.status);
    uint8_t *out=malloc(w*h*4);[dst getBytes:out bytesPerRow:w*4 fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
    int bad=0;
    for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
        int q=color;
        if(q==4) { // square valid area onto a 2:1 target: 4 black columns on each side, the middle 8 columns all red.
            static const uint8_t black[4]={0,0,0,255};
            const uint8_t *want=x<4||x>=12?black:colors[0];bad+=memcmp(out+4*(y*w+x),want,4)!=0;continue;
        }
        if(q==-2) { // crop=(1,1,4,4): 3×3 red, last column green, last row blue, bottom-right 1 cell yellow.
            q=(x+1>=4)+2*(y+1>=4);
        } else if(q<0) { // same-size default whole frame: the boundary is dead center.
            q=(x>=w/2)+2*(y>=h/2);
        }
        bad+=memcmp(out+4*(y*w+x),colors[q],4)!=0;
    }
    EXPECT(name,0,bad);free(out);
}

int main(void) { @autoreleasepool {
    mtl_init();
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> src=[g_dev newTextureWithDescriptor:d];uint8_t px[8*8*4];
    for(int y=0;y<8;y++)for(int x=0;x<8;x++)memcpy(px+4*(y*8+x),colors[(x>=4)+2*(y>=4)],4);
    [src replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 withBytes:px bytesPerRow:32];
    int zero[4]={0},tl[4]={0,0,4,4},tr[4]={4,0,4,4},bl[4]={0,4,4,4},br[4]={4,4,4,4},one[4]={3,3,1,1},inset[4]={1,1,4,4};
    check(src,"default whole frame 64 pixels",zero,8,8,-1);
    check(src,"NULL default whole frame 64 pixels",NULL,8,8,-1);
    check(src,"top-left crop scaled up, 256 pixels all red",tl,16,16,0);
    check(src,"non-zero x crop scaled up, 256 pixels all green",tr,16,16,1);
    check(src,"non-zero y crop scaled up, 256 pixels all blue",bl,16,16,2);
    check(src,"bottom-right crop at the edge, 256 pixels all yellow",br,16,16,3);
    check(src,"single texel scaled up without crossing edges, 256 pixels all red",one,16,16,0);
    check(src,"non-zero x and y offset, 16 pixels byte-identical to a hand-written sub-rectangle",inset,4,4,-2);
    check(src,"aspect of the valid area kept, 128 pixels red in the middle / black on both sides",tl,16,8,4);
#ifndef CROP_LEGACY_HEADER
    {
        // sRGB swapchain: present sends the raw bytes (as the Switch's scan-out does) without decoding first; unfixed, 128/64/200 decode to about 55/13/148
        MTLTextureDescriptor *sd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:8 height:8 mipmapped:NO];sd.storageMode=MTLStorageModeShared;sd.usage=MTLTextureUsageShaderRead;
        id<MTLTexture> s8=[g_dev newTextureWithDescriptor:sd];uint8_t g[8*8*4];
        for(int i=0;i<64;i++){g[4*i]=128;g[4*i+1]=64;g[4*i+2]=200;g[4*i+3]=255;}
        [s8 replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 withBytes:g bytesPerRow:32];
        MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
        id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
        EXPECT("sRGB source encode succeeds",1,ENCODE(cb,s8,dst,zero));[cb commit];[cb waitUntilCompleted];
        uint8_t o[8*8*4];[dst getBytes:o bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];
        int bad=0;for(int i=0;i<64;i++)bad+=abs(o[4*i]-128)>1||abs(o[4*i+1]-64)>1||abs(o[4*i+2]-200)>1;
        EXPECT("sRGB swapchain present sends raw bytes, 64 pixels",0,bad);
    }
#endif
#ifndef CROP_LEGACY_HEADER
    {
        // Present filters (front.h mtl_present_filter_set): the quadrant picture 8x8 → 32x32. Bilinear blends about four columns and rows around the middle seam; the pixel filter
        // (sharp bilinear) blends at most one of each, every other pixel one quadrant's colour exactly
        int mixed[DM_PFX_N]={0}; float k=-1;
        for(int m=0;m<DM_PFX_N;m++) {
            mtl_present_filter_set(m,1);
            MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:32 height:32 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
            id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
            EXPECT("filtered encode succeeds",1,ENCODE(cb,src,dst,zero));[cb commit];[cb waitUntilCompleted];
            static uint8_t o[32*32*4];[dst getBytes:o bytesPerRow:128 fromRegion:MTLRegionMake2D(0,0,32,32) mipmapLevel:0];
            for(int i=0;i<32*32;i++){int pure=0;for(int q=0;q<4;q++)pure|=memcmp(o+4*i,colors[q],3)==0;mixed[m]+=!pure;}
        }
        printf("pixels between two colours: off %d, sharpen %d, pixel %d, crt %d, lottes %d, lcd %d\n",mixed[0],mixed[1],mixed[2],mixed[3],mixed[4],mixed[5]);
        EXPECT("bilinear blends the seam over more than one column and row",1,mixed[DM_PFX_OFF]>2*32);
        EXPECT("pixel filter blends at most one column and one row",1,mixed[DM_PFX_PIXEL]<=2*32);
        // On one flat colour sharpening changes nothing, and the CRT filter's scanlines make a source row's edge darker than its centre (4 output rows per source row)
        uint8_t flat[8*8*4];for(int i=0;i<64;i++){flat[4*i]=flat[4*i+1]=flat[4*i+2]=128;flat[4*i+3]=255;}
        id<MTLTexture> fl=[g_dev newTextureWithDescriptor:d];[fl replaceRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0 withBytes:flat bytesPerRow:32];
        for(int m=DM_PFX_SHARPEN;m<=DM_PFX_CRT;m+=DM_PFX_CRT-DM_PFX_SHARPEN) {
            mtl_present_filter_set(m,1);
            MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:32 height:32 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
            id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
            ENCODE(cb,fl,dst,zero);[cb commit];[cb waitUntilCompleted];
            static uint8_t o[32*32*4];[dst getBytes:o bytesPerRow:128 fromRegion:MTLRegionMake2D(0,0,32,32) mipmapLevel:0];
            if(m==DM_PFX_SHARPEN){int bad=0;for(int i=0;i<32*32;i++)bad+=abs(o[4*i]-128)>1||abs(o[4*i+1]-128)>1||abs(o[4*i+2]-128)>1;EXPECT("sharpen leaves a flat colour as it is, 1024 pixels",0,bad);}
            else{int edge=0,mid=0;for(int x=0;x<32;x++){edge+=o[4*(0*32+x)]+o[4*(0*32+x)+1]+o[4*(0*32+x)+2];mid+=o[4*(2*32+x)]+o[4*(2*32+x)+1]+o[4*(2*32+x)+2];}
                printf("crt row sums: edge %d, centre %d\n",edge,mid);EXPECT("CRT scanline: a source row's edge darker than its centre",1,edge<mid);}
        }
        {   // scanlines every 2 source rows: 8 output rows per line on the 4x picture, so output row 0 is a line's edge and row 4 its centre
            mtl_present_filter_set(DM_PFX_CRT,1);mtl_present_scanline_set(2);
            MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:32 height:32 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
            id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
            ENCODE(cb,fl,dst,zero);[cb commit];[cb waitUntilCompleted];
            static uint8_t o[32*32*4];[dst getBytes:o bytesPerRow:128 fromRegion:MTLRegionMake2D(0,0,32,32) mipmapLevel:0];
            int r0=0,r2=0,r4=0;for(int x=0;x<32;x++){r0+=o[4*(0*32+x)];r2+=o[4*(2*32+x)];r4+=o[4*(4*32+x)];}
            printf("crt 2-row scanline red sums: rows 0 %d, 2 %d, 4 %d\n",r0,r2,r4);
            EXPECT("CRT scanline set to 2 rows: the line's centre (row 4) brighter than its quarter (row 2) and its edge (row 0)",1,r4>r2&&r2>r0);
            mtl_present_scanline_set(0);EXPECT("scanline back to auto",0,mtl_present_scanline());
        }
        // CRT-Lottes and LCD Grid on the flat colour, 4 output pixels per cell: Lottes' beam is darker at a row's edge (output row 0) than at its centre (row 2), and the LCD grid's gap
        // darkens a cell's edge row; CRT at 1:1 (a line one output pixel high) fades its scanlines out, every row the same
        for(int m=DM_PFX_LOTTES;m<=DM_PFX_LCD;m++) {
            mtl_present_filter_set(m,1);
            MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:32 height:32 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
            id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
            EXPECT(m==DM_PFX_LOTTES?"CRT-Lottes encode succeeds":"LCD Grid encode succeeds",1,ENCODE(cb,fl,dst,zero));[cb commit];[cb waitUntilCompleted];
            static uint8_t o[32*32*4];[dst getBytes:o bytesPerRow:128 fromRegion:MTLRegionMake2D(0,0,32,32) mipmapLevel:0];
            int edge=0,mid=0;for(int x=0;x<32;x++)for(int q=0;q<3;q++){edge+=o[4*(0*32+x)+q];mid+=o[4*(2*32+x)+q];}
            printf("%s row sums: edge %d, centre %d\n",m==DM_PFX_LOTTES?"lottes":"lcd",edge,mid);
            EXPECT(m==DM_PFX_LOTTES?"CRT-Lottes: a cell row's edge darker than its centre":"LCD Grid: a cell's edge row darker than its centre",1,edge<mid&&mid>0);
        }
        {
            mtl_present_filter_set(DM_PFX_CRT,1);
            MTLTextureDescriptor *od=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];od.storageMode=MTLStorageModeShared;od.usage=MTLTextureUsageRenderTarget;
            id<MTLTexture> dst=[g_dev newTextureWithDescriptor:od];id<MTLCommandBuffer> cb=[g_q commandBuffer];
            ENCODE(cb,fl,dst,zero);[cb commit];[cb waitUntilCompleted];
            uint8_t o[8*8*4];[dst getBytes:o bytesPerRow:32 fromRegion:MTLRegionMake2D(0,0,8,8) mipmapLevel:0];
            int spread=0;for(int y=1;y<8;y++)for(int x=0;x<8;x++)spread=MAX(spread,abs(o[4*(y*8+x)]-o[4*x]));
            printf("crt at 1:1: largest difference from row 0 %d\n",spread);
            EXPECT("CRT at 1:1: scanlines faded out, every row as row 0",1,spread<=1);
        }
        mtl_present_filter_set(99,7);
        int m=mtl_present_filter(&k);
        EXPECT("an unknown filter is off",DM_PFX_OFF,m);EXPECT("strength clamped to 1 (x100)",100,(int)(k*100+0.5f));
        mtl_present_filter_set(DM_PFX_OFF,0.5f);
        check(src,"filter off again: the default whole frame as before, 64 pixels",zero,8,8,-1);
    }
#endif
    int invalid[4][4]={{-1,0,4,4},{0,-1,4,4},{0,0,0,4},{7,0,4,4}};
    for(int i=0;i<4;i++) {
        MTLTextureDescriptor *dd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:8 mipmapped:NO];dd.usage=MTLTextureUsageRenderTarget;dd.storageMode=MTLStorageModeShared;
        id<MTLTexture> dst=[g_dev newTextureWithDescriptor:dd];
        EXPECT("invalid crop is not encoded and does not fake success by stretching the whole image",0,ENCODE([g_q commandBuffer],src,dst,invalid[i]));
    }
    // Real QueuePresent entry: set crop and enqueue first, then immediately change the window; the present ticket must keep that frame's copy.
    PFNNVNDEVICEGETPROCADDRESSPROC get=(PFNNVNDEVICEGETPROCADDRESSPROC)h_nvnBootstrapLoader("nvnDeviceGetProcAddress");
    NVNT_nvnWindowSetCrop set=(NVNT_nvnWindowSetCrop)get(NULL,"nvnWindowSetCrop");
    NVNT_nvnQueuePresentTexture present=(NVNT_nvnQueuePresentTexture)get(NULL,"nvnQueuePresentTexture");
    tex_t tex={.magic=MAGIC('T', 'E', 'X', 0), .serial =10001};tex.d.width=tex.d.height=8;tex.d.depth=tex.d.levels=1;tex.d.format=NVN_FORMAT_RGBA8;tex.d.target=NVN_TEXTURE_TARGET_2D;serial_put(tex.serial,src);
    win_t win={.ntex=1};win.tex[0]=(NVNtexture *)&tex;set((NVNwindow *)&win,4,4,4,4);
    mtl_present_test_stall(100000000);present(NULL,(NVNwindow *)&win,0);uint64_t tk=win.ticket[0];set((NVNwindow *)&win,0,0,8,8);
#ifdef CROP_LEGACY_HEADER
    EXPECT("old queue struct has no room for a four-value copy (struct check)",1,sizeof(pq_item)>=sizeof(tex_t)+sizeof(double)+sizeof(uint64_t)+sizeof br);
#else
    pthread_mutex_lock(&g_pq_mu);if(!tk)tk=g_pq_in;   // a present snapshot (DM_PRESENT_SNAP; with the encode thread too) hands back no ticket: the frame is the last one queued
    int saved=memcmp(g_pq[(tk-1)%PQ].crop,br,sizeof br)==0;pthread_mutex_unlock(&g_pq_mu);
    EXPECT("real QueuePresent: the frame's crop copy does not change with the window",1,saved);
#endif
    mtl_present_wait(tk);mtl_present_test_stall(0);
    printf("== %d checks, %d failed ==\n",cases,failed);return failed!=0;
} }
