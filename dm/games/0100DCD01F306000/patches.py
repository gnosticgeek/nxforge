# Mina the Hollower (0100DCD01F306000): the rewriter's patches of this game's own builds. dm/tools/patch_nso.py loads every profile's patches.py and applies those of a module's NSO build ID;
# CUTS, OBS and FRAME_STEP as described there ("Registered patches"). Patches of Nintendo SDK module builds are in dm/tools/sdk_patches.py
CUTS = {
  # Mina the Hollower 1.0.5 (v262144) main. With virtual address memory the game reserves more address space than the 5 GB block holds, which the Switch's 64 GB alias region allows:
  # - nninitStartup (main+0x103d90) initializes malloc, a StandardAllocator, over 16 GB (main+0x875c20: Initialize(nullptr, size, false)); CentralHeap::Init fails and the SDK aborts (sdk+0x141b98)
  # - nnMain sets up two engine heaps (main+0x6d8b8 and +0x6dc18 → main+0xdda90), each with a first segment of 4 GB of address space (AllocateAddressRegion at main+0x1089b0), 16 MB committed
  #   at a time; a heap adds another segment when one is full (its list at +0x40). When the alias region had no room, AllocateAddressRegion returned 0 and the game stored through it (main+0xddc1c).
  #   A third heap (main+0x73f508) takes 64 MB segments and is left as it is
  # All of them commit pages as they go, so the address space bounds only what they can reserve: 2 GB for malloc and 1 GB first segments, with the 62 MB node area (sdk_patches.py), fit a
  # 4.375 GB alias region. Malloc needs the larger share: the game reads its 601 MB sound bank (default.sndbnk.yc) into one malloc block through the engine heap's large-block path (main+0xde0c0),
  # which a 1 GB malloc could not give (a null block, then a crash at main+0xde154)
  '2bc484524f0c86bc7c2228d6fbfb0817': [
    (0x103d9c, '8100c0d2', '0100b0d2', 'nninitStartup: malloc StandardAllocator address space mov x1,#0x400000000 → mov x1,#0x80000000 (16 GB → 2 GB)'),
    (0x6d8ac, '2100c0d2', '0100a8d2', 'nnMain: first engine heap, first segment mov x1,#0x100000000 → mov x1,#0x40000000 (4 GB → 1 GB)'),
    (0x6dc0c, '2100c0d2', '0100a8d2', 'nnMain: second engine heap, first segment mov x1,#0x100000000 → mov x1,#0x40000000 (4 GB → 1 GB)'),
  ],
}
