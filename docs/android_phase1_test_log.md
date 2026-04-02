# Android Phase 1 Test Log

Last updated: 2026-04-02

## Results

| Date | Area | Scenario | Status | Notes |
| --- | --- | --- | --- | --- |
| 2026-04-02 | Counselor Live Routing | Counselor `Live` now stays inside the same counselor workspace shell on Android | Fixed in code | The counselor live route now lives inside the shared counselor shell route, so switching from Dashboard, Sessions, or Availability into Live no longer swaps to a separate shell or causes a full workspace refresh feel. |
| 2026-04-02 | Counselor Availability Mobile Layout | Slot feed header no longer overflows on narrow Android widths | Fixed in code | The slot-feed heading/actions row now switches to a stacked compact layout on smaller widths, and the compact copy uses fewer words so the Android UI fits without the `RenderFlex overflowed by 23 pixels on the right` error. |
| 2026-04-02 | Counselor Appointments Mobile Layout | Counselor appointments no longer overflow in short Android lanes | Fixed in code | The appointments body now becomes internally scrollable only when the route transition or embedded shell gives it a bounded height, preventing the `RenderFlex overflowed by 622 pixels on the bottom` error while keeping the normal layout on larger canvases. |
