<!--
SPDX-License-Identifier: GPL-2.0-only OR MIT
-->
# aic8800 - the board's WiFi/BT part, built out of tree

The Cubie A7S carries an AICSemi AIC8800D80 WiFi/Bluetooth part behind its
on-board USB hub. This directory holds our patches against Radxa's packaging of
the vendor driver (`radxa-pkg/aic8800`). The vendor source is **never committed
here**; the build fetches it from the pinned upstream commit
(`AIC8800_COMMIT` in `scripts/lib/aic8800.sh`), prepares it as Radxa ships it,
applies `patches/upstream/` and `patches/` (see [Patches](#patches)) and builds
the modules against the kernel tree of this recipe. `KERNEL-ID` names the commit.

## Why out of tree

There is no mainline driver for this part. An RFC series on linux-wireless
covers the SDIO variant only; there is no upstream support for USB yet.

The vendor driver is about 130 files, which we have not reviewed in full. It is
built out of tree as shipped, with only the delta in `patches/` applied, and
not imported as kernel patches.

## The pin

| | |
|---|---|
| Source | `radxa-pkg/aic8800`, tag `5.0+git20260123.5f7be68d-11` |
| Commit | `b6e136a9fe30a4babf0dde5ba9d02313e1c99c30` |
| Driver subdir | `src/USB/driver_fw/drivers/aic8800` (the part is a USB device on this board) |
| Modules built | `aic_load_fw` (firmware loader) and `aic8800_fdrv` (WiFi FullMAC) |
| Built against | Linux 6.18 |

`aic_btusb` is deliberately not built. It brings a private HCI stack and
exposes `/dev/aicbt_dev` instead of an `hci0`. The in-tree `btusb` driver binds
this part through its generic interface entry (class `e0/01/01`), so Bluetooth
costs no extra code.

Chip facts a maintainer needs: the USB id before firmware download is
`a69c:8d80`; after download the part re-enumerates as `a69c:8d81` with three
interfaces (two Bluetooth `e0/01/01`, one vendor-specific `ff/ff/ff`). The
loader reports `chip_id=7` and `chip_mcu_id=0` on the board.

## Firmware

The firmware is a vendor-supplied binary. This recipe does not fetch or ship
it. The image recipe
[a7s-build](https://github.com/DockSeed/a7s-build) fetches it from the same
upstream commit and verifies it against its own hashes.

The driver does not use `request_firmware()`; it opens
`/lib/firmware/aic8800_fw/USB/aic8800D80/<name>` directly (Radxa's
`fix-usb-firmware-path.patch`; overridable with the `aic_fw_path`
module parameter). It opens seven files on this part:

- `fw_adid_8800d80_u02.bin`
- `fw_patch_8800d80_u02.bin`
- `fw_patch_8800d80_u02_ext0.bin`
- `fw_patch_table_8800d80_u02.bin`
- `fmacfw_8800d80_u02.bin`
- `fmacfw_8800d80_h_u02.bin` (shipped although the non-H image is the one used
  here: the choice is made at runtime from `chip_id`)
- `aic_userconfig_8800d80.txt`

The vendor manifest (`src/firmware_version.md`) does not list
`aic_userconfig_8800d80.txt`.

## Patches

Applied in three steps; each step is made against the tree with the steps
before it applied.

**Radxa's package as shipped.** The files listed in `CRLF_FILES` of
`.github/local/Makefile.local` are converted to LF, then the 33 patches of the
pin's `debian/patches/series` are applied with `patch -p1 --fuzz=0`, as quilt
applies them. The 6.18 build fixes are part of this step; no compat patch of
ours is needed. Among them:

- `fix-Lower-the-debugging-log-level` - Feng Zhang (Radxa): the compiled-in
  `aicwf_dbg_level` is `LOGERROR`. Its PCIe and SDIO hunks change files this
  recipe does not build.
- `fix-usb-suspend-reboot-hang` - Jiali Chen (Radxa): a failed bulk-IN
  completion took a semaphore inside URB completion and left scanning
  returning `-EBUSY`; the handshake is removed from the completion path.

**Other projects' patches, unchanged** (`patches/upstream/`, in the order of
`patches/upstream/series`, which names each author and source). They are
applied byte for byte as published, with `patch -p1 --fuzz=0`; for a target
file with CRLF line ends the hunk lines get CRLF at apply time.

- radxa-pkg/aic8800 pull request 114 (N Oliver, PixnBits), 16 of its 17 patches: length,
  index and TID checks on the rx and firmware-message paths, `CAP_NET_ADMIN`
  for the private commands, allocation and parser fixes. Its SDIO hunks change
  files this recipe does not build. `fix-usb-rx-aggregate-length-checks` is not
  taken: it changes the same USB rx paths as nine of our patches (rx aggregate,
  bulk-in errors and refill, the loader's rx parser), which bound them.
- radxa-pkg/aic8800 pull request 106 (Pranav0-0Aggarwal),
  `fix-usb-drop-trace_printk`: the `trace_printk()` in the management tx-status
  path made every boot print the kernel's DEBUG-kernel notice.
- `bluetooth-fw-upload-fix-chip-mcu-id-needs-cache-mem-addr` - bnister,
  shenmintao/aic8800d80 pull request 35: on parts reporting an MCU id, bit 0 at
  `0x40100020` is set before the upload, or BT firmware load fails with `-110`.
  Applied from `src/USB/driver_fw`. Does not execute on the board
  (`chip_mcu_id=0`); kept for other parts.

**Ours** (`patches/series`):

1. `aic_load_fw-print-the-cache-address-when-its-read-fails` - the read-failure
   message of bnister's block prints the address that was read.
2. `aic_load_fw-match-only-the-vendor-interface` - the loader's table matched
   whole devices, so after download USB probed it on all three interfaces and
   each refusal was logged as an error. It now matches only `ff/ff/ff`, the
   interface its parser accepts.
3. `aic_load_fw-track-firmware-upload-per-part` - the "firmware already
   loaded" flag was one module-wide global; it is now kept per part, keyed by
   USB topology path, so two parts do not depend on enumeration order.
4. `regulatory-let-cfg80211-govern-the-radio` - the wiphy was self-managed
   (`custregd` compiled in as true, while the parameter text says the default
   is 0), so `regulatory.db` governed nothing. The default now matches the
   text: `custregd` is opt-in.
5. `aic8800_fdrv-keep-draining-rx-after-a-bad-aggregate` - after an aggregate
   header that claims more than the buffer holds, the rx consumer thread was
   not woken again and all rx URBs eventually failed to resubmit; the loop now
   breaks instead of returning with buffers queued.
6. `aic8800_fdrv-add-a-test-stimulus-for-failed-bulk-in-completions` -
   `rx_inject_urb_error` handles good bulk-IN completions as `-EPROTO`, to
   check `fix-usb-suspend-reboot-hang` on the board.
7. `aic_load_fw-bound-the-rx-parser-to-what-was-received` - the loader's rx
   parser did not bound frame headers against the buffer (endless loop with an
   skb leak, `memcpy` length); every header, pull and copy is now bounded. The
   handler-table index is checked by `fix-usb-fw-msg-index-checks`.
8. `aic8800_fdrv-do-not-advertise-monitor-mode` - monitor mode is removed from
   the supported interface modes: this build compiles the driver without its
   monitor-data support, the guard in `change_iface()` refuses monitor mode
   once a second vif exists, and the monitor paths were measured to oops, so
   a working monitor mode needs a series of its own.
9. `aic8800-give-the-boot-path-prints-a-log-level` - bare `printk()` lines of
   a normal boot (firmware paths, md5, upload progress) all came out at warn;
   they now have meaningful levels, text unchanged.
10. `aic_load_fw-no-rx-refill-after-the-bus-has-stopped` - a pending rx refill
    could run after the post-download bus stop and log `bus is not up` at error
    level on a working radio; the work is cancelled after the stop.
11. `aic8800-init-the-rx-refill-work-before-the-first-error-path` - a failed
    allocation in probe cancelled a work item that was never initialised;
    initialised first now, and `-ENOMEM` is returned as a negative errno.
12. `aic_load_fw-no-rx-urb-in-flight-after-the-bus-stop` - closes the remaining
    race where a refill submits an rx URB after the stop killed them and the
    error path frees the device under it.
13. `aic_load_fw-return-an-errno-from-a-failed-configuration-or-upload` - a
    failed configuration or firmware upload returned 0 from probe, leaving the
    interface "bound" and the radio dead until re-plug.
14. `aic_load_fw-a-timed-out-firmware-message-fails-and-is-freed` - a timed-out
    firmware message was reported as confirmed, leaked the command, and a killed
    wait freed it while still on the list; it now returns `-ETIMEDOUT`.
15. `aic8800_fdrv-count-received-data-frames-in-the-interface-statistics` -
    `rx_packets`/`rx_bytes` were only counted under `CONFIG_BR_SUPPORT`
    (disabled), so a station's receive counters did not follow its traffic.
16. `aic_load_fw-keep-the-driver-data-of-the-usb-device-alone` - the loader
    is a USB interface driver but kept its bus structure in the driver data of
    the USB device, which belongs to the driver bound to the device. With a
    device tree node on the hub port that is `onboard_usb_dev`, whose
    disconnect then took the freed bus structure for its own state. The bus
    handle is now the interface and the bus structure is reached through the
    interface's driver data.
17. `aic8800_fdrv-keep-the-driver-data-of-the-usb-device-alone` - the same
    for the WiFi module. The parent of the wiphy, the firmware-request and DMA
    device and the wakeup sources stay on the USB device.
18. `aic8800_fdrv-bound-the-a-msdu-subframe-length` - an A-MSDU subframe shorter
    than its LLC/SNAP head or past the frame ends the split.
19. `aic8800_fdrv-check-whole-rx-frames-and-messages-against-what-was-received` -
    every rx frame and message must fit in what was received.
20. `aic8800_fdrv-read-the-a-msdu-flag-before-the-split-frees-the-frame` - the
    A-MSDU flag is read before the split frees the frame.
21. `aic8800_fdrv-bound-the-firmware-assert-text-to-its-buffer` - the firmware
    assert text is bounded to its buffer.
22. `aic_load_fw-no-busy-wait-under-the-rx-pool-lock` - no `mdelay(10)` under
    the rx pool lock.
23. `aic8800_fdrv-retry-a-failed-rx-submit-later-instead-of-mdelay-100` - a
    failed rx submit is retried 100 ms later from process context.
24. `aic8800_fdrv-end-the-msg-in-refill-loop-when-a-submit-fails` - the msg-in
    refill loop ends on a failed submit.
25. `aic8800_fdrv-re-arm-the-bulk-in-urbs-after-a-transfer-error` - bulk-in URBs
    are re-armed after a transient transfer error.
26. `aic8800_fdrv-free-an-unsent-tx-frame-by-its-type-drop-it-on-copy-failure` -
    an unsent tx frame is freed by its type; a failed copy drops it.
27. `aic8800_fdrv-let-a-tx-frame-skip-the-tcp-ack-filter-if-allocation-fails` -
    a small tx frame skips the TCP ACK filter if its allocation fails.
28. `aic8800_fdrv-make-rx-defragmentation-safe-against-long-fragments-timeout` -
    rx defragmentation: atomic allocations, bounded fragments, safe timeout.
29. `aic8800_fdrv-free-a-msg-in-frame-whose-copy-cannot-be-allocated` - a msg-in
    frame whose copy fails is freed.
30. `aic8800_fdrv-clear-the-confirmation-slot-of-a-dropped-tx-frame` - a dropped
    tx frame clears its confirmation slot.
31. `aic8800_fdrv-bound-the-ap-entry-to-sta-flowctrl-in-sm-connect-ind` - the
    AP index of a connect indication is checked against `sta_table[]`, which is
    longer than `sta_flowctrl[]`; the pending count is read only for an index
    that `sta_flowctrl[]` holds.

New counter of 18-31: `rx_bad_frame_drops` (0444).

Several patches add small module parameters or counters under
`/sys/module/<module>/parameters/` to inject the failure they fix; they are
described in the patch headers.

## Licence

Releases carry the prepared driver source as `a7s-aic8800-dkms`, with a Debian
copyright file; the firmware is not in it. Our patches are GPL-2.0-only,
matching the code they modify; the patches in `patches/upstream/` keep the terms
of their projects.

The vendor source files carry no licence text. Radxa's `debian/copyright`
states GPL-2 for `src/`, and both modules declare `MODULE_LICENSE("GPL")`.
`aic_br_ext.c`/`.h` (Apache-2.0) are not built (`CONFIG_BR_SUPPORT = n`).
`rwnx_radar.c`, which is built, states that it is adapted from the ath driver
(Neratec Solutions AG); that code is ISC-licensed in the kernel. The firmware
has no licence and is not part of this recipe.

## Bumping the pin

1. Pick the new upstream tag and resolve its full commit id.
2. Update the tag and commit in `scripts/lib/aic8800.sh` and the table above;
   the image recipe moves its firmware pin to the same commit.
3. Re-derive the firmware list from the new tree: the load path in
   `aic_compat_8800d80.c` decides which files are opened.
4. Apply Radxa's `debian/patches/series`, then `patches/upstream/series` and
   `patches/series` in order. A patch that no longer applies fails the
   build; rebase it rather than loosening the match. Drop patches that upstream
   has absorbed.
5. Build, load the modules on the board, and check that the firmware md5 prints
   of the driver match the firmware files, WiFi associates and `hci0` comes up.
