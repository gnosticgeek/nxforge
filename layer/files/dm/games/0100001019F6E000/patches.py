# Horizon Chase 2 (0100001019F6E000): the rewriter's patches of this game's own builds (dm/tools/patch_nso.py, "Registered patches")

# The online subsystem falls back to Switch, not NULL. The game's default online service is Epic Online Services, whose SDK (rom:/nro/EOSSDK-Switch-Shipping.nro) the host never
# loads (docs/reference/services.md, Online SDKs in NROs are never loaded), so it fails. Unreal's FOnlineSubsystemModule::LoadDefaultSubsystem then tries "NULL", which this game does
# not ship, and IOnlineSubsystem::Get() stays null. The game's own code calls it without a check (17 sites in main, the first at main+0x14f71dc 0.8 s after boot: SIGSEGV at address 0).
# The fallback's name is pointed at "Switch" instead (the UTF-16 tail of a string in ro), so the game gets Unreal's Switch online subsystem, which it ships and which plays offline.
CUTS = {
  # 1.6.9 (v524288) main: adrp x0, "NULL"; add x0, x0; mov w1, #4  →  adrp x0, "Switch"; add x0, x0; mov w1, #6 (FName's length argument)
  'e13f632fc2a66eebf39cb8e1a57fa417': [
    (0x1195798, '20d502f000c8279181008052', 'a0d402f000280d91c1008052', 'online subsystem: the fallback after the default service fails is Switch, not NULL (EOS is never loaded)'),
  ],
}

BINDING = [
    {'what': 'online subsystem: the fallback after the default service fails is Switch, not NULL', 'now': 'build', 'goal': 'engine',
     'purpose': 'runtime', 'why': "Unreal's own fallback names an online subsystem this game does not ship; any Unreal game whose default service is EOS and that lacks NULL would need the same, so an engine_patches.py rule could hold it",
     'checked': 'one build (1.6.9): the bytes at the site, and a boot on the Mac'},
]
