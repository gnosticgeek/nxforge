// tex_fit's 2D array view of a cube and of a cube array: a shader that declares a 2D array where the texture is a cube reads the cube's faces as its layers, six to a cube, as
// Maxwell keeps them (The Legend of Zelda: Ocarina of Time (Switch 2): texture ID 906, a 2D array descriptor whose Metal texture is a cube, in slot 7 of two pixel shaders that
// declare a 2D array). Before, no view bridged it: a type mismatch whose reads are undefined on Metal
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)
enum { W = 4, TID = 3 };
static uint8_t texel(NSUInteger slice, int c) { return (uint8_t)(8 * slice + c + 1); }   // every face (slice) and channel its own value
static id<MTLTexture> filled(MTLTextureType type, NSUInteger cubes) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor new];
    d.textureType = type; d.width = d.height = W; d.arrayLength = cubes; d.mipmapLevelCount = 1;
    d.pixelFormat = MTLPixelFormatRGBA8Unorm; d.storageMode = MTLStorageModeShared; d.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:d];
    for (NSUInteger s = 0; s < 6 * cubes; s++) {
        uint8_t px[W * W * 4];
        for (NSUInteger i = 0; i < W * W; i++) for (int c = 0; c < 4; c++) px[4 * i + c] = texel(s, c);
        [t replaceRegion:MTLRegionMake2D(0, 0, W, W) mipmapLevel:0 slice:s withBytes:px bytesPerRow:4 * W bytesPerImage:4 * W * W];
    }
    return t;
}
static void read_layer(id<MTLComputePipelineState> pipeline, id<MTLTexture> t, uint32_t layer, float out[4]) {
    id<MTLBuffer> b = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared]; memset(b.contents, 0xcd, 16);
    id<MTLCommandBuffer> cb = [g_q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
    [e setComputePipelineState:pipeline]; [e setTexture:t atIndex:0]; [e setBytes:&layer length:sizeof layer atIndex:0]; [e setBuffer:b offset:0 atIndex:1];
    [e dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    CHECK(cb.status == MTLCommandBufferStatusCompleted && !cb.error, "the GPU reads the fitted view");
    memcpy(out, b.contents, 16);
}
static int same(const float v[4], NSUInteger slice) {
    for (int c = 0; c < 4; c++) if (fabsf(v[c] - texel(slice, c) / 255.0f) > 1e-4f) return 0;
    return 1;
}
int main(void) { @autoreleasepool {
    mtl_init(); NSError *error = nil;
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void rd(texture2d_array<float> t [[texture(0)]], constant uint& layer [[buffer(0)]], device float4* out [[buffer(1)]]) { out[0] = t.read(uint2(1, 2), layer); }\n";
    id<MTLLibrary> library = [g_dev newLibraryWithSource:source options:nil error:&error];
    id<MTLComputePipelineState> pipeline = library ? [g_dev newComputePipelineStateWithFunction:[library newFunctionWithName:@"rd"] error:&error] : nil;
    if (!pipeline) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 2; }
    id<MTLTexture> cube = filled(MTLTextureTypeCube, 1), cubes = filled(MTLTextureTypeCubeArray, 2);
    os_unfair_lock_lock(&g_rmu);
    g_treg = calloc(TID + 2, sizeof *g_treg); g_ntreg = TID + 2;
    uint64_t rid = 0, rid2 = 0, rid3 = 0;
    id<MTLTexture> fit = tex_fit(TID, cube, MTLTextureType2DArray, &rid);
    id<MTLTexture> again = tex_fit(TID, cube, MTLTextureType2DArray, &rid2);
    id<MTLTexture> fit2 = tex_fit(TID + 1, cubes, MTLTextureType2DArray, &rid3);
    os_unfair_lock_unlock(&g_rmu);
    CHECK(fit && fit.textureType == MTLTextureType2DArray && fit.arrayLength == 6, "a cube read as a 2D array: a six-layer view");
    CHECK(fit.parentTexture == cube, "made from the cube");
    CHECK(rid == fit.gpuResourceID._impl && again == fit && rid2 == rid, "kept for the next binding of the same texture");
    CHECK(fit2 && fit2.textureType == MTLTextureType2DArray && fit2.arrayLength == 12, "a cube array of two read as a 2D array: twelve layers");
    float v[4];
    for (uint32_t l = 0; l < 6; l++) { read_layer(pipeline, fit, l, v); CHECK(same(v, l), "layer l of the cube's view is face l"); }
    read_layer(pipeline, fit2, 7, v); CHECK(same(v, 7), "layer 7 of the cube array's view is the second cube's face 1");
    read_layer(pipeline, fit2, 11, v); CHECK(same(v, 11), "layer 11 of the cube array's view is the second cube's face 5");
    printf("tex_fit cube faces as 2D array layers: %d checks, %d failed\n", checks, failed); return failed != 0;
} }
