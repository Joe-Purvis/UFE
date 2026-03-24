\# Prototype X2 Scope — Improved Receiver Signal Chain



\## Goal

Improve robustness and detectability of the ultrasound echo envelope for range-gated operation.



\## What changes in X2

\- Rework the receiver analogue chain to produce a clean unipolar/envelope signal suitable for thresholding.

\- Improve gain distribution and headroom to prevent clipping.

\- Provide a stable bias/VMID strategy for single-supply stages.

\- Make the comparator input well-defined (filtered/integrated) with controlled recovery/reset behaviour.



\## Acceptance checks

\- No clipping for expected echo amplitude range at the gain stage outputs.

\- Full-wave/envelope path produces correct polarity and consistent amplitude.

\- Range-gated detection is stable (no false triggers in the receive window).

\- Recovery/reset allows fast reacquisition between bursts.



\## Notes

\- X1 is the imported baseline (tag: X1).

\- X2 is the first receiver-chain redesign milestone.

