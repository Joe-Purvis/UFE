Fabrication Notes – SmartSwitch (Rev X2)

Project: Solid State Smart Switch
Revision: X2 (Prototype)
Quantity: 2 boards
Tool: KiCad EDA 9.0.4
Designer: Joe Purvis
Institution: University of Glasgow – James Watt School of Engineering

--------------------------------------------------------------------
1. Files Provided
--------------------------------------------------------------------
This fabrication package contains:
- Gerber files (RS-274X / Gerber X2)
- Excellon drill files:
  * *-PTH.drl  (plated through holes)
  * *-NPTH.drl (non-plated through holes)
- Gerber drill map files (visual reference only)
- Gerber job file (*.gbrjob)

Notes:
- Excellon drill files are authoritative
- Drill map files are for reference only

--------------------------------------------------------------------
2. PCB Stackup
--------------------------------------------------------------------
Nominal 4-layer FR-4 stackup.
Fabricator may substitute an equivalent standard stackup.

L1: Top copper – 1 oz
Prepreg
L2: Inner copper – 0.5 oz (GND plane)
Core FR-4, Tg ≥ 150 °C
L3: Inner copper – 0.5 oz (power / signals)
Prepreg
L4: Bottom copper – 1 oz

Total finished board thickness: 1.6 mm ±10 %

Surface finish: ENIG (preferred). Lead-free HASL acceptable if ENIG unavailable.

No controlled impedance requirements.
Dielectric thicknesses may be per fabricator standard.

--------------------------------------------------------------------
3. Board Outline & Mechanical
--------------------------------------------------------------------
- Board outline defined exclusively by Edge.Cuts
- No internal slots or cut-outs unless visible in Gerbers
- No controlled-depth milling
- Gerbers are authoritative over drawings

--------------------------------------------------------------------
4. Drilling
--------------------------------------------------------------------
- PTH and NPTH drills provided as separate files
- Units: millimetres
- Format: Excellon
- Zero format: decimal
- Origin: absolute

Plating:
- All holes in *-PTH.drl are plated
- All holes in *-NPTH.drl are non-plated

--------------------------------------------------------------------
5. Soldermask & Silkscreen
--------------------------------------------------------------------
- Soldermask on top and bottom sides
- Soldermask openings generated from pad geometry
- Soldermask subtraction from silkscreen enabled
- Top silkscreen only; no bottom silkscreen required
- Silkscreen clipping at board edge acceptable

--------------------------------------------------------------------
6. Assembly Notes
--------------------------------------------------------------------
- Hand-assembled prototype
- DNP markings present on fabrication layers
- No panelisation required
- No fiducials required

--------------------------------------------------------------------
7. Electrical Notes
--------------------------------------------------------------------
- Board contains multiple isolated domains
- ISO reference nets are not system ground
- Dedicated test points provided for isolated mid-points

--------------------------------------------------------------------
8. BOM Notes
--------------------------------------------------------------------
- µ and Ω symbols are intentional and expected
- Manufacturer substitutions acceptable if approved.
- Passive component tolerances per BOM unless otherwise stated

--------------------------------------------------------------------
9. General
--------------------------------------------------------------------
- Gerbers are authoritative
- Fabricator discretion permitted where not constrained
- Prototype / research use only

--------------------------------------------------------------------
10. Contact
--------------------------------------------------------------------
Joe Purvis
University of Glasgow – James Watt School of Engineering
email j.purvis.1@research.gla.ac.uk
