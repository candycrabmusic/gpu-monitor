# GPU Monitor (Omarchy bar-widget)

NVIDIA GPU monitoring for the Omarchy shell bar: utilization, temperature,
VRAM, clocks, power draw and fan speed at a glance, with a click-to-open
details panel showing throttling reasons and the processes using the GPU.

**Read-only.** This plugin only monitors — it never changes fan speed, clocks,
power limits, or GPU state. Fan control on NVIDIA needs NV-CONTROL via an X
display with Coolbits, which a Wayland bar widget cannot reach; by design this
plugin doesn't attempt it.

## Features

- **Bar label** — `37° 12%` by default (temperature + utilization). Right-click
  cycles between `Both` / `Temp` / `Usage`; the choice persists to shell.json.
  The label flips to the bar's urgent color above the configured thresholds.
- **Details panel** (left-click, or `omarchy-shell shell show vichu.gpu-monitor`):
  - Utilization, temperature, fan speed, VRAM, power draw/limit, graphics and
    memory clocks with their maxes.
  - A VRAM-used bar with a warning threshold.
  - Throttling reasons (HW/sw thermal slowdown, power brake, hw slowdown,
    sync boost, GPU idle).
  - Processes currently using the GPU (PID, name, VRAM).
  - Escape closes it; `g` / `r` inside the panel forces a refresh.

## Install

```sh
omarchy plugin validate ~/.config/omarchy/plugins/vichu.gpu-monitor
omarchy plugin enable vichu.gpu-monitor left
omarchy-shell shell rescanPlugins
```

Then place it in the bar if it did not appear:

```sh
omarchy bar move vichu.gpu-monitor --section left
```

## Settings

Per-widget settings live in the inline shell.json entry for the widget
(`omarchy bar set vichu.gpu-monitor <key> <value>` or the config UI, or
right-click the widget for `displayMode`):

| key             | default | meaning                    |
|-----------------|---------|----------------------------|
| `updateInterval`| 2000    | poll interval (ms)         |
| `tempThreshold` | 80      | temperature warning (°C)   |
| `utilThreshold` | 90      | utilization warning (%)    |
| `memThreshold`  | 90      | VRAM used warning (%)      |
| `displayMode`   | Both    | bar label: `Both`/`Temp`/`Usage` |

## Data source

Everything comes from `nvidia-smi` (part of `nvidia-utils`, already on PATH):

- GPU stats: one `nvidia-smi --query-gpu=... --format=csv,noheader,nounits`
  call per poll (utilization, temps, fan %, power draw/limit, graphics/SM/mem
  clocks + maxes, VRAM used/free/total, throttle reasons, P-state, driver).
- Processes: `nvidia-smi --query-compute-apps=pid,process_name,used_memory`,
  polled on alternate ticks.

No privileges, no root helpers, no system changes. If `nvidia-smi` is missing
or no NVIDIA GPU is present, the widget shows `GPU —` and the panel shows a
"no GPU detected" notice instead of crashing.

## Requirements

- NVIDIA GPU + `nvidia-smi` (any NVIDIA proprietary open/closed driver)
- Omarchy shell (Quickshell)
- Nerd Font for the bar (already the Omarchy default)

## Notes

- Single-GPU only: when several NVIDIA GPUs are present the plugin reports the
  first one.
- `fan.speed` reads 0 on cards with zero-RPM idle fans (like this RTX 3060 at
  the desktop); under load it reports the actual speed.
- `temperature.memory` is N/A on some cards (the panel reports it via the fan
  and tile numbers that the card does expose).

## License

MIT