// NXForge: included by front_mac_front_end.inc (so front_mac.m meets no new line). The Mac's thermal state, Low Power Mode and power source.
// nxnative's host asks for the first two through dm_thermal_now and dm_low_power_now, whose weak defaults (hle_nvn.c) answer -1 and 0 without a
// front end that knows: a Mac log's power and on-screen lines then say "thermal -1", and the frame step tries 60 fps again in Low Power Mode,
// where macOS holds the clocks down and the try can only fail. These are the strong definitions, as front_ios.m has them. thermalState: 0 nominal,
// 1 fair, 2 serious, 3 critical. Every change is logged with its time, and the start says whether the Mac runs on its battery, so a slow session
// can be told from a slow build.
// The thermal cap (hle_nvn.c thermal_capped: 30 fps while the state is serious or worse) was measured on iPhones only, so it stays off on the
// Mac unless DM_THERMAL_CAP=1 asks for it.
#include <IOKit/ps/IOPowerSources.h>
int dm_thermal_now(void) { return (int)NSProcessInfo.processInfo.thermalState; }
int dm_low_power_now(void) { return NSProcessInfo.processInfo.lowPowerModeEnabled; }
static const char *nxf_power_source(void) {
    CFStringRef s = IOPSGetProvidingPowerSourceType(NULL);   // a constant string, not ours to release
    return !s ? "unknown" : CFEqual(s, CFSTR(kIOPMBatteryPowerKey)) ? "battery" : CFEqual(s, CFSTR(kIOPMUPSPowerKey)) ? "UPS" : "mains";
}
static void nxf_power_init(void) {
    static int done; if (done) return; done = 1;
    setenv("DM_THERMAL_CAP", "0", 0);
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; LOG("front end: thermal state → %d (%.0f s after launch, on %s)", dm_thermal_now(), CFAbsoluteTimeGetCurrent() - t0, nxf_power_source()); }];
    [nc addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; LOG("front end: Low Power Mode → %s (%.0f s after launch, on %s)", dm_low_power_now() ? "on" : "off", CFAbsoluteTimeGetCurrent() - t0, nxf_power_source()); }];
    LOG("front end: thermal state %d, Low Power Mode %s, running on %s", dm_thermal_now(), dm_low_power_now() ? "on" : "off", nxf_power_source());
}
