# 1966 GTO — MSD 6AL Ultra + Blaster SS Coil + Bulkhead Connector Install Plan

Project notes for converting a 1966 Pontiac GTO (1967 Pontiac 400 engine) from a Pertronix
ignition to a full MSD setup, plus a full firewall bulkhead connector replacement.

> Disclaimer: this is a planning checklist, not a substitute for the printed MSD instructions
> shipped with each part or the 1966 Pontiac chassis service manual. Always cross-check
> wire colors against the instruction sheet that came in the box — MSD has reused color
> codes across decades but the position of the trigger plug, harness length, and the
> presence of the white "points/AC trigger" wire vary by part number.

---

## 1. Parts already installed

- [x] MSD Pro-Billet distributor for Pontiac V8 350–455 (vacuum-advance)
- [x] MSD Super Conductor 8.5 mm spark plug wires, multi-angle HEI boots

## 2. Parts to install in this phase

- MSD 6AL Ultra ignition control box
- MSD Blaster SS ignition coil (black)
- New firewall bulkhead connector pins/terminals (full bulkhead)

## 3. Known answers (recorded so we don't re-decide)

| Decision | Answer | Implication |
|----------|--------|-------------|
| Tachometer | Aftermarket | Use the 6AL **gray** tach output; no MSD 8920 adapter needed |
| Resistor wire status | **Unknown** | Section 6 includes a multimeter test before any new wiring is run |
| Bulkhead scope | **Full connector** | Plan covers both engine-bay and interior sides |
| Plan format | Markdown + checklists | This document |

## 4. Tools and consumables to gather before starting

### Hand tools

- [ ] 10 mm, 7/16", 1/2", 9/16" sockets and combo wrenches
- [ ] Phillips and small flat-blade screwdrivers (the small flat is the bulkhead pin-release tool)
- [ ] Wire stripper, ratcheting crimper for insulated and non-insulated terminals
- [ ] Heat gun for adhesive-lined heat shrink
- [ ] Soldering iron (40 W minimum) and rosin-core electronics solder
- [ ] Test light and a digital multimeter (DMM)
- [ ] Timing light (inductive, dial-back preferred)
- [ ] Vacuum pump or a vacuum-cap kit (to plug the distributor advance line during initial timing)
- [ ] Torque wrench for the distributor hold-down

### Electrical consumables

- [ ] 12 AWG red wire, ~10 ft, for the new switched-12 V feed to the 6AL
- [ ] 10 AWG red and 10 AWG black, ~6 ft each, for the heavy 6AL battery leads (only if your harness needs them — the box ships with leads, but they may be too short)
- [ ] 16 AWG twisted pair (or shielded pair) for distributor-pickup extension if the factory pigtail is short
- [ ] Heat-shrink tubing (adhesive-lined, multiple sizes)
- [ ] Crimp ring terminals sized for battery posts and ground stud
- [ ] Inline ATC fuse holder + 20 A fuse for the new 12 V feed
- [ ] Loom / convoluted tubing and tie-downs

### Bulkhead-specific

- [ ] 1966 GTO chassis service manual wiring diagram (or NPD reproduction laminated diagram) — printed and on hand
- [ ] Bulkhead connector pin/terminal kit. Options, in order of fidelity:
  - American Autowire **GM bulkhead terminal kit** (matches GM Packard 56-series female terminals on the dash side and male terminals on the engine side)
  - Painless Performance terminal kit
  - Lectric Limited replacement terminals (correct repro for 1964–67 GTO if originality matters)
- [ ] Replacement bulkhead **connector shells** (only if the plastic shells are cracked — most installs reuse them)
- [ ] Pin-release tool sized for GM Packard 56 (a thin flat-blade often works, but the proper tool prevents tang damage)
- [ ] Dielectric grease for the reassembled bulkhead

### Mechanical

- [ ] M5/M6 stainless hardware to mount the 6AL box (the box has its own bracket; you supply mounting screws)
- [ ] Anti-seize for spark plug threads (already used in prior phase)

## 5. Pre-flight: take notes before disturbing anything

1. [ ] **Disconnect the battery negative cable first.** Tape the terminal so it can't fall back on the post.
2. [ ] Photograph the engine bay from multiple angles in good light.
   Specifically capture the coil bracket, the existing Pertronix wiring at the coil, the bulkhead engine-side, and the ignition switch wiring.
3. [ ] With a label maker or masking tape + Sharpie, label every wire at the existing coil,
   every wire at the bulkhead engine-side, and every wire at the bulkhead interior-side **before** disassembly.
4. [ ] Note the current static timing: rotate the engine to TDC #1 compression and mark the rotor position on the distributor housing with a paint pen.
   (You have a new MSD distributor, so this is for reference only — but if anything goes sideways during the bulkhead work you have a known-good reference.)
5. [ ] Save the box and instruction sheet from the 6AL Ultra and the Blaster SS — refer to them for warranty and the wire color sheet.

## 6. Diagnose the existing ignition feed (resistor wire test)

The 1966 GTO uses a factory **pink resistor wire** from the ignition switch to the coil "+" terminal.
With the key in **RUN**, this wire drops voltage from ~12 V down to ~6–9 V to protect the original points coil.
The MSD 6AL **must see a full switched 12 V** on its small red wire — a resistor wire will cause hard starting,
weak spark, or trigger a "low voltage" fault on the Ultra.

Do this test **before** running any new wires:

1. [ ] Reconnect the battery negative.
2. [ ] Set the DMM to DC volts, 20 V range. Black probe to a clean engine ground.
3. [ ] Back-probe the wire currently feeding the coil "+" terminal (the wire that fed the Pertronix). Key **OFF** — should read 0 V.
4. [ ] Key to **RUN** (engine not cranking), record voltage.
    - **~12.0–12.6 V** → resistor wire was already bypassed during the Pertronix install. You can reuse this feed for the 6AL's small red wire.
    - **~6–9 V** → resistor wire is still in circuit. **Do not reuse it.** Plan to run a new 12 AWG fused feed (Section 9.2).
5. [ ] Have a helper crank the engine briefly, watch the meter.
    - Voltage should not collapse below ~9.5 V at the new feed point. If it does, the source is too weak for the 6AL — pick a different switched source.
6. [ ] Disconnect the battery negative again before any further work.

Record the result here:

```text
Coil-feed voltage at RUN: ______ V
Coil-feed voltage at CRANK: ______ V
Conclusion (circle one):  RESISTOR WIRE IN CIRCUIT  /  ALREADY BYPASSED
```

## 7. Mount the 6AL Ultra box

The 6AL is a CD ignition with internal high-voltage switching — it needs a location that is:

- **Cool.** Not on the engine, intake, header heat shield, or anywhere it sees direct exhaust radiation.
- **Vibration-isolated by metal-to-metal mounting** (no rubber; the 6AL chassis is also its heat sink and EMI shield).
- **Reachable** for the trigger plug, coil leads (≤ ~24" run is ideal), and battery cables.
- **Dry.** Above the inner fender lip, not in a wheel-well splash zone.

Recommended location for a 1966 GTO: **driver-side inner fender, vertical orientation**, fins out, behind the radiator support and ahead of the brake booster. The passenger-side inner fender is also acceptable.

Steps:

1. [ ] Trial-fit the box and confirm trigger plug, coil leads, and battery cables all reach without strain.
2. [ ] Mark and drill four mounting holes through the inner fender. Deburr.
3. [ ] Bolt the box solidly with stainless hardware. Do **not** use rubber isolators — the chassis is a ground/EMI path.
4. [ ] Confirm the heavy black battery-ground lead can reach the battery negative post or a clean chassis ground bolted directly to the negative cable.

## 8. Wire the coil

Critical rule: when an MSD 6AL is installed, the coil is driven by the 6AL **only**.
The original ignition feed wire (resistor wire or otherwise) must **not** terminate at the coil —
that wire now goes to the 6AL's small red wire instead.

Blaster SS wiring with the 6AL:

| 6AL wire | Color | Goes to |
|----------|-------|---------|
| Coil + output | **Orange** | Coil **positive (+)** terminal |
| Coil − output | **Black with white tracer** (some models stripe varies — verify on the printed sheet) | Coil **negative (−)** terminal |

Steps:

1. [ ] Mount the Blaster SS coil to the existing bracket (or a new bracket on the intake/inner fender). Coil mounting orientation does not matter electrically, but keep terminals away from header heat.
2. [ ] Crimp ring terminals on the orange and black/tracer leads from the 6AL. Use heat-shrink.
3. [ ] Connect orange to **(+)** and black/tracer to **(−)**.
4. [ ] Cap and tape the ends of any wire that previously fed the coil — those will be re-purposed in Section 9 if voltage testing showed a usable 12 V feed, or abandoned if it was the resistor wire.

## 9. Wire the 6AL Ultra

### 9.1 Heavy battery leads

1. [ ] Heavy **red** lead from the 6AL → **battery positive post**, with an **inline fuse** (20 A ATC, mounted within 12" of the battery).
2. [ ] Heavy **black** lead from the 6AL → **battery negative post** (preferred), or to a clean,
   paint-free chassis ground bolt that itself has a heavy strap to the battery negative.
3. [ ] Verify a separate **engine-to-chassis** ground strap exists and is clean.
   The MSD instructions are explicit about this — without it, ignition noise on the tach signal and intermittent triggering are common.

### 9.2 Switched 12 V feed (small red wire)

If Section 6 showed the resistor wire was still in circuit, run a new feed:

1. [ ] Pick a switched 12 V source. Best options, in order:
   - A spare fused circuit on the fuse block that is hot in **RUN** and **START** (not just RUN).
   - A new relay, coil energized by the original ignition-switch feed, with the relay's load contact fed from the battery through a fuse.
     This is the cleanest solution and isolates the 6AL from voltage drop in the old harness.
2. [ ] Run 12 AWG red wire from that source, through the firewall via an existing grommet, to the small red wire on the 6AL.
   Inline fuse near the source, **20 A**.
3. [ ] Connect via crimp + heat shrink, or solder + heat shrink. Avoid scotch-locks and twist caps.

If Section 6 showed full 12 V already at the old coil feed, you may reuse that wire —
extend it cleanly to the 6AL location with 12 AWG, retain the same circuit protection.

### 9.3 Small black wire (signal ground)

1. [ ] Connect the small black wire to a clean, paint-free chassis ground point local to the 6AL mounting location.
   This is the signal ground for internal logic — it must be solid, but the heavy black lead in 9.1 carries the actual ignition current.

### 9.4 Magnetic pickup from the distributor

The MSD Pro-Billet for Pontiac uses a 2-pin pigtail. Standard MSD convention:

- **Violet** = pickup positive (+)
- **Green** = pickup negative (−)

Steps:

1. [ ] Mate the distributor's 2-pin connector to the 6AL's matching 2-pin trigger plug. This is keyed — it only goes one way.
   **Do not** cut and splice unless absolutely necessary; if you must extend, use a twisted pair (and shield the extension if you have noise issues).
2. [ ] Route the pickup wires **away from** spark plug wires, the coil, and the heavy 6AL battery leads.
   Route along the firewall or down the driver-side valve cover edge, not across the intake.
3. [ ] If polarity is reversed (engine starts but timing wanders or backfires under load), swap violet ↔ green and re-test.
   The Pro-Billet will run either polarity but timing is only correct in one orientation.

### 9.5 Tach output (gray wire)

1. [ ] Route the **gray** wire to the aftermarket tach's signal input.
   Confirm the tach is a 12 V negative-trigger style — most modern aftermarket tachs are; some early-2000s units need a tach adapter.
2. [ ] If the tach is mounted in the cabin, route the gray wire through an existing firewall grommet,
   **not** the same path as the pickup wires (keep tach signal away from the magnetic pickup pair).

### 9.6 Unused wires

- [ ] **White wire** (points / shift-light input on some 6AL variants): cap with heat shrink and tape back. Do not ground it.
- [ ] Any other harness wires not used per the printed instruction sheet: cap and tape.

## 10. Replace the firewall bulkhead connector

The 1966 GTO uses GM's pre-1968 bulkhead arrangement (often called "first design"),
which is **physically different** from the 1968+ "second design" connector that most aftermarket harness kits standardize on.
Confirm which design your car has before ordering terminals — original 1966 should be first design,
but a previous owner may have swapped to a later harness.

### 10.1 Plan and document

1. [ ] Print the 1966 GTO chassis manual wiring diagram. Highlight every wire that passes through the bulkhead.
2. [ ] On the engine side, label each wire at the connector with masking tape + circuit name (IGN, BAT, START, ACC, TACH, headlight high/low, horn relay, etc.). Cross-reference to the diagram.
3. [ ] Photograph the back of the connector before removing terminals.

### 10.2 Disassemble

1. [ ] Battery negative disconnected — confirm again before touching the bulkhead.
2. [ ] Unbolt the connector halves from the firewall. Pull the engine-side connector through enough to work on it.
3. [ ] One wire at a time: insert the pin-release tool into the front of the connector to disengage the locking tang, pull the wire and old terminal out the back. Lay the wire flat with its label visible.
4. [ ] Repeat on the interior side.

### 10.3 Reterminate

For each wire, in this order to avoid losing track:

1. [ ] Cut off the old terminal just behind the crimp.
2. [ ] Strip back ~3/16" of insulation. Inspect the copper — if it's discolored more than ~1" back, cut further and add a butt-splice extension with a short jumper of correct-gauge wire.
3. [ ] Crimp the new GM Packard 56 terminal. Use a proper crimper (not pliers) — a bad crimp here is what caused the original failure.
4. [ ] Tug-test the crimp.
5. [ ] Insert into the **same cavity** the original wire occupied. Listen/feel for the click of the locking tang.
6. [ ] Tug the wire from the back — it must not pull out.

Repeat for every wire. Do interior-side and engine-side as separate sessions if needed.

### 10.4 Reassemble

1. [ ] Apply a thin film of dielectric grease to the engine-side terminals.
2. [ ] Mate the two halves through the firewall, ensure the gasket/seal is in place, bolt them together.
3. [ ] Visually verify no wires are pinched.

### 10.5 Special note: the ignition feed

If you ran a **new** 12 AWG switched feed in Section 9.2 directly from a relay or fuse block,
that wire does **not** go through the bulkhead — it's a standalone circuit.
The original pink resistor wire that used to feed the coil through the bulkhead can be capped and abandoned at both ends, or removed entirely.

If you reused the original ignition feed (because Section 6 showed it was already 12 V), then it still passes through the bulkhead and gets a new terminal like any other wire.

## 11. First start

1. [ ] Final visual check: every connection insulated, no exposed conductors, no wires touching the exhaust or fan, all terminals tight at battery, coil, and 6AL.
2. [ ] Verify spark plug wire firing order on the new distributor: Pontiac V8 = **1-8-4-3-6-5-7-2**, **clockwise** rotor rotation. Confirm rotor points to #1 tower at TDC compression.
3. [ ] Reconnect battery negative.
4. [ ] Key to RUN (do not crank yet). Check for any smoke, hot wires, blown fuses. The 6AL Ultra has a status LED — note its behavior per the printed sheet.
5. [ ] Crank with the throttle slightly open. Engine should fire promptly. If it starts and dies, suspect pickup polarity (Section 9.4) or a misrouted plug wire.
6. [ ] Let it warm up briefly, watch for fuel/oil/coolant leaks (unrelated to ignition but always check after any engine-bay work).

## 12. Set timing

The MSD setup will be more aggressive than the Pertronix because spark energy is higher. Re-check timing after install — don't assume the prior setting is still correct.

1. [ ] Warm engine to operating temp.
2. [ ] **Disconnect and plug** the vacuum advance line at the distributor.
3. [ ] With timing light on #1, set initial timing to **~12° BTDC** as a starting point for a 1967 Pontiac 400 with iron heads and pump gas.
   Adjust by ear and detonation behavior — most 400s like 10–14° initial.
4. [ ] Bring engine to ~3000 rpm steady, verify total mechanical advance is **~34–36° BTDC** all-in.
   If it overshoots, the MSD distributor's mechanical advance bushings/springs need swapping (kit comes with the distributor).
5. [ ] Reconnect vacuum advance. Cruise vacuum advance should add ~10–15° on top of mechanical at light load — verify no part-throttle ping on a road test.
6. [ ] Lock the distributor hold-down. Recheck initial timing one last time.

## 13. Validation

- [ ] Idle quality smooth, no miss
- [ ] No backfire on decel (a small pop on hard decel is normal; sharp backfire = pickup polarity or firing order)
- [ ] Tach reads correctly across RPM range — no jumping at idle, no stuck at zero
- [ ] No detonation at WOT in 2nd/3rd gear under load
- [ ] 6AL box stays cool to the touch after a 15-min drive
- [ ] No new "phantom" loads on charging system (alternator output not pegged at idle)
- [ ] Bulkhead connector cool to the touch after a long drive (a hot connector means a marginal terminal — pull and redo it)

## 14. Things that commonly go wrong (and the fix)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| No spark, 6AL LED indicates no trigger | Pickup wires reversed or open | Confirm violet/green continuity from distributor to 6AL plug |
| Engine starts, runs, but timing wanders | Pickup polarity reversed | Swap violet ↔ green |
| Engine cuts out at high RPM | Loose coil terminal, weak switched 12 V feed, or marginal chassis ground | Re-torque coil terminals; verify ≥ 11.5 V at the small red wire under load; re-check engine-to-chassis strap |
| Tach reads zero or erratic | Tach signal routed near pickup wires; or tach needs an adapter | Re-route gray wire on a different path; verify tach type |
| Hot bulkhead pin | Bad crimp on the new terminal | Pull it, redo the crimp with the correct tool, re-test |
| Engine cranks but won't start, fuel and timing both check out | Spark wires off by one tower (HEI cap rotation differs from the old distributor) | Re-verify firing order against the rotor's TDC position |
| 6AL fuse blows immediately on key-on | Coil leads reversed at the box, or coil internally shorted | Verify orange = coil (+), black/tracer = coil (−); meg-test the coil |

## 15. References

These are starting points — always confirm against the printed instruction sheet that ships in your specific 6AL Ultra and Blaster SS boxes, since MSD has revised harness colors across part-number revisions.

- MSD 6 Series installation instructions (covers 6A, 6AL, 6T, 6BTM, 6TN — wire colors are consistent across the family)
- MSD wiring manual / tech notes (general MSD wiring reference)
- MSD Tech Bulletin: distributor magnetic pickups (covers polarity, troubleshooting)
- American Autowire 1964–67 GTO Classic Update Series instructions (bulkhead connector design notes)
- 1966 Pontiac Tempest/GTO Chassis Service Manual (factory wiring diagrams)
- GTO Forum and PY Online Forums (community reference for 1966 bulkhead specifics)

## 16. Open questions to confirm before the wrenches come out

- [ ] Is the bulkhead the original "first design" or has it been converted to "second design"? Determines which terminal kit to order.
- [ ] Confirm the exact part number of the 6AL Ultra (6AL-2, 6AL Ultra, etc.) and verify the harness color sheet matches Section 8/9 above.
- [ ] Is the aftermarket tach a 12 V negative-trigger type, or does its installation manual call for a tach adapter? If unclear, capture the make/model so we can verify before final wiring.
- [ ] Does the existing under-hood circuit have a working engine-to-chassis ground strap and a chassis-to-battery-negative strap? If not, add both before powering up the 6AL.
