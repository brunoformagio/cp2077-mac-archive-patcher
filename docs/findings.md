# Findings

Native macOS Cyberpunk 2077 loads the official `archive/Mac` RDAR archives. Loose Windows-style PC mod archives are not enough for every tested archive-only mod, especially when the mod tries to override resources that already exist in official Mac archives.

The successful approach:

1. Choose a loaded Mac target archive.
2. Append source compressed segments from the PC mod archive.
3. Replace or insert file records by FNV-1a 64-bit depot path hash.
4. Append segment table entries.
5. Preserve dependency table bytes.
6. Recompute the RDAR index CRC64.
7. Align the rewritten index and final file size to 4096 bytes.
8. Apply mods sequentially so the desired override wins last.

For multi-archive mod stacks, load order still matters. Applying shared dependency archives first and then applying the intended final override archive last fixed cases where partial resources loaded but dependent meshes or appearances did not.
