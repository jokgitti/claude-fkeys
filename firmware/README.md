# Firmware images and how to get back to normal

Two `.bin` files, both for a **GMMK Pro ANSI rev 1** (USB `0x320F:0x5044`). Do not
flash either to an ISO board or a rev 2.

| File | What it is | What you get |
|---|---|---|
| `gmmk_pro_rev1_ansi_fkeys.bin` | This project's firmware | Normal typing. All RGB is off except F-keys bound to a Claude session, which show its state colour (the waiting state pulses from fully dark to full colour every 700 ms by default; period and floor are set from `palette.json`, not by reflashing). Without a running `fkeysd` the whole keyboard is dark. |
| `gmmk_pro_rev1_ansi_default.bin` | QMK's stock keymap for this board | Normal keyboard, normal RGB. No Claude integration. Nothing from this project. |

## Getting Glorious's own firmware back

Glorious's stock image is their proprietary firmware and is **not included here**
— it is not ours to redistribute. Fetch it and verify it:

    curl -fLO 'https://gloriouscore.nyc3.digitaloceanspaces.com/Glorious_Core/%28QMK%29GMMK%20_PRO_US_2021_04_07_V0035_DFU_FW.bin'
    shasum -a 256 '(QMK)GMMK _PRO_US_2021_04_07_V0035_DFU_FW.bin'
    # expect 40c0114269e62891aba8ee959b708498b9fb176573b8d88980218ebf2fb0c33f

That checksum is from the file as downloaded on 2026-09-29. Check it before
flashing — a vendor URL can change contents without changing its path.

The link comes from
<https://glorious.ladesk.com/385785-GMMK-PRO---Reverting-to-default-Glorious-CORE-Firmware>.
That page's text mentions v0045 for rev 1 while the file it actually links is
V0035; the URL above is the file it links. **ANSI rev 1 only** — the same page
has different files for ISO and rev 2.

If that URL ever dies, `gmmk_pro_rev1_ansi_default.bin` here still restores a
fully working keyboard; you only lose Glorious Core, which is Windows-only.

## Which one do you want

- **The keyboard is misbehaving and you want it normal again, today**:
  `gmmk_pro_rev1_ansi_default.bin`. Built from QMK source on this machine, so it
  is known to work on this board — it is the same build that produced the fkeys
  image, minus this project's keymap.
- **You want Glorious Core back, or you are selling the board**: the Glorious
  image, downloaded as above.
- Glorious Core is Windows-only. On macOS the stock image buys you nothing over
  QMK's default keymap.

## Entering DFU

The keyboard must be in DFU (bootloader) mode before anything can be written.

- **On this project's firmware, or any QMK firmware**: hold `Esc` while plugging
  the USB cable in.
- **On Glorious stock firmware**: hold `Space` + `B` while plugging the cable in.

You are in DFU when the keyboard goes dark and stops typing. Have another
keyboard available — the GMMK Pro will not type while in DFU.

Both sequences are from Glorious and QMK documentation and were **not verified on
this unit**. If neither works, the PCB has a physical reset button: unscrew the
backplate and hold it while connecting.

Confirm before flashing:

    dfu-util -l | grep -i 'Found DFU'

## Flashing

    dfu-util -a 0 -d 0483:df11 -s 0x08000000:leave -D <file>.bin

`0483:df11` is the STM32 DFU bootloader, not the keyboard's normal USB id.
`0x08000000` is the start of flash on an STM32F303. `:leave` makes the keyboard
restart into the new firmware when the write finishes.

Do not unplug mid-write. If you do, the keyboard stays in DFU and you flash
again — see below.

QMK Toolbox works too if you prefer a GUI: <https://github.com/qmk/qmk_toolbox/releases>.

## If a flash fails

The STM32 bootloader lives in ROM and cannot be erased by anything you flash. A
failed, interrupted or wrong write leaves the keyboard in DFU mode, still
writable. Re-enter DFU and flash a known-good image from this directory.

There is no sequence here that bricks the board.

## Rebuilding from source

The two QMK images can be rebuilt. You need an ARM cross-compiler and a QMK
checkout — neither is installed by this project's `make install`:

    # ARM's official toolchain, no sudo, removable with rm -rf
    mkdir -p ~/.local/arm-toolchain && cd ~/.local/arm-toolchain
    curl -fLO 'https://gitlab.arm.com/api/v4/projects/tooling%2Fgnu-toolchains-for-arm/packages/generic/gnu-toolchain/15.3.rel1/arm-gnu-toolchain-15.3.rel1-darwin-arm64-arm-none-eabi.tar.xz'
    tar -xf arm-gnu-toolchain-*.tar.xz

    # QMK's CLI is a Python package; its build also shells out to dfu-suffix
    python3 -m venv ~/.local/arm-toolchain/qmkvenv
    ~/.local/arm-toolchain/qmkvenv/bin/pip install qmk
    brew install dfu-util

    git clone --depth 1 --recurse-submodules https://github.com/qmk/qmk_firmware.git ~/qmk_firmware
    ~/.local/arm-toolchain/qmkvenv/bin/qmk config user.qmk_home="$HOME/qmk_firmware"

    export PATH="$HOME/.local/arm-toolchain/qmkvenv/bin:$HOME/.local/arm-toolchain/arm-gnu-toolchain-15.3.rel1-darwin-arm64-arm-none-eabi/bin:$PATH"
    cp -R qmk/keymaps/fkeys ~/qmk_firmware/keyboards/gmmk/pro/rev1/ansi/keymaps/fkeys
    cd ~/qmk_firmware
    make gmmk/pro/rev1/ansi:fkeys      # this project
    make gmmk/pro/rev1/ansi:default    # QMK stock

Glorious's image cannot be rebuilt — it is closed-source, which is why a copy is
kept here.

## What reverting does and does not undo

Flashing `default` or the Glorious image removes the F-row lighting. It does
**not** touch anything on the Mac. The daemon, the hook and the LaunchAgent are
separate:

    cd ~/dev/claude-fkeys && make uninstall

and remove the `fkey-status.sh` entries from `~/.claude/settings.json`.

With this project's firmware flashed but no daemon running, the keyboard types
normally and every LED is off. The same holds 10 seconds after the last report
from the daemon, and on any computer that is not running `fkeysd`.

The `Fn`-layer `RM_*` RGB keys are still in the keymap. QMK's `rgb_matrix_task`
runs the indicator callback (`rgb_matrix_indicators_advanced`) only while an
effect is active. So the RGB toggle key probably stops the F-row lights too:
toggling RGB off would leave the board dark until it is toggled on again. This
is from reading QMK's source and has not been confirmed on hardware. The other
`RM_*` keys change the effect underneath, which is fully overpainted, so they
have no visible result. For normal RGB, flash `gmmk_pro_rev1_ansi_default.bin`.
