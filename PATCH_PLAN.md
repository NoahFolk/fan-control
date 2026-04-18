# Concrete Patch Plan

## Goal

Adapt this fork so it can safely control fans on the Proxmox host for a Supermicro X10SRL-F system while sourcing drive temperatures from a TrueNAS VM that owns the HBA.

## Working Assumptions

- Keep `defaults/fan-control.py` as the main controller instead of reviving `truenas-fanctl` as a separate service.
- Prefer SSH plus `smartctl` on the TrueNAS side over the earlier TrueNAS API/WebSocket idea.
- Treat the existing `fan-control` repo as the runtime project and `truenas-fanctl` as reference material for safer temp collection, fan characterization, and deployment notes.

## Patch Order

### 1. Replace the disk-temperature collection path

Primary files:

- `getdisktemp.sh`
- `temperature.sh`
- `defaults/fan-control.py`
- `config.toml`
- `defaults/gen-config.py.proxmox`

Changes:

- Remove the hard dependency on `qm guest exec` and the current one-disk-at-a-time SMART parse.
- Replace it with a single Proxmox-side helper that SSHes into TrueNAS and runs a safer collector similar to `truenas-fanctl/get_disk_temps.sh`.
- Return structured output for all disks in one call instead of spawning one remote call per disk.
- Parse multiple possible SMART temperature formats instead of assuming only one field layout.

Acceptance criteria:

- One command from the Proxmox side returns temperatures for all target disks.
- Standby, missing, or unparsable disks do not crash the controller.
- The Python loop can compute HDD average and max temperatures from the structured output.

### 2. Replace fragile disk naming with stable mapping

Primary files:

- `defaults/fan-control.py`
- `config.toml`
- `defaults/gen-config.py.proxmox`
- `README.md`

Changes:

- Stop treating `sda`, `sdb`, and similar names as the long-term identity for monitored drives.
- Add a config format that allows stable identifiers, ideally serial numbers or another persistent identifier exported by the TrueNAS-side helper.
- Make the temp collector return both a stable identifier and the current kernel device name so the controller can match disks safely.
- Document how to build and maintain the mapping using the workflow already outlined in `truenas-fanctl/drive-mapping.md`.

Acceptance criteria:

- Reordering Linux device names after reboot does not require patching the controller.
- A replaced or missing drive produces a warning and fallback behavior, not a hard failure.

### 3. Finish the two-zone behavior for the target board

Primary files:

- `defaults/fan-control.py`
- `config.toml`
- `defaults/gen-config.py.proxmox`
- `README.md`

Changes:

- Use the existing split-zone logic already present in `defaults/fan-control.py` instead of inventing a second controller.
- Configure the target deployment for `single_zone = False`.
- Confirm Zone 0 is the CPU/system fan group and Zone 1 is the HDD fan group for the X10SRL-F wiring layout.
- Convert the fan characterization data in `truenas-fanctl` into practical starter curves for CPU and HDD zones.

Acceptance criteria:

- CPU temperature only drives Zone 0.
- HDD temperature only drives Zone 1.
- The default suggested curves avoid the very low duty values that make Supermicro fans drop out or surge back to full speed.

### 4. Add explicit safe fallback behavior

Primary files:

- `defaults/fan-control.py`
- `defaults/fan-control.service`
- `README.md`

Changes:

- Define what happens when the controller cannot get valid HDD temperatures.
- Add a configurable safe fallback duty for the HDD zone instead of relying on incidental exception handling.
- Differentiate between temporary read failures, repeated communication failures, and total script failure.
- Keep or improve the current behavior that moves the platform to a safe state on unhandled exceptions.

Acceptance criteria:

- If TrueNAS is unreachable, the HDD zone moves to a documented safe speed.
- If a temp read fails once, the script logs it and keeps running.
- If repeated failures occur, the script escalates to the safe fallback without operator intervention.

### 5. Clean up configuration and install flow for the actual deployment target

Primary files:

- `config.toml`
- `defaults/gen-config.py.proxmox`
- `install.sh`
- `README.md`

Changes:

- Add configuration for SSH target, remote command path, timeouts, fallback duty, and stable disk identifiers.
- Remove or clearly de-emphasize install paths that are not relevant to the intended Proxmox plus TrueNAS setup.
- Make the README describe the current intended architecture instead of the inherited multi-platform archive story.

Acceptance criteria:

- A new install on Proxmox can be configured without reading the upstream repo history.
- The generated config matches the actual deployment model for this fork.

### 6. Validate the controller against real hardware behavior

Primary files:

- `README.md`
- Optional helper docs under the repo root

Changes:

- Use the characterization data from `truenas-fanctl/fan_sweep.py` and the CSV outputs to pick sensible minimum fan duty values.
- Record the chosen minimum stable duty values for each zone in the repo docs.
- Run a small manual validation matrix: idle, disk activity, CPU load, missing-disk simulation, and TrueNAS-unreachable simulation.

Acceptance criteria:

- No selected default duty value causes the fans to stall or jump back to board-controlled full speed.
- The documented validation steps are enough to re-check behavior after future edits.

## Suggested First Implementation Slice

If this work is split into smaller patches, the most valuable first slice is:

1. Introduce the new TrueNAS-over-SSH temp collector.
2. Switch HDD monitoring to stable identifiers.
3. Add HDD-zone fallback speed.

That slice should be enough to make the fork usable for the intended environment even before the rest of the cleanup lands.

## Deliberately Not First

- Rewriting the controller into a new architecture.
- Reintroducing the TrueNAS API/WebSocket path.
- Making the project broadly portable again across pfSense, TrueNAS CORE, and Proxmox before the Proxmox plus TrueNAS path is solid.

Those can wait until the target deployment works reliably.
