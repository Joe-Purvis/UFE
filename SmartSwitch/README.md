\# SmartSwitch\_2.0 (Circuit Design)



This repository contains \*\*only circuit-design artifacts\*\* for SmartSwitch\_2.0

(KiCad schematic/PCB and LTspice simulations).



Scope is intentionally limited — MATLAB and FPGA code live in separate repositories.



\## Repository layout



\- `kicad/`   — KiCad projects (schematic + PCB)

\- `ltspice/` — LTspice schematics, symbols, models

\- `docs/`    — design notes, BOM notes, decisions, screenshots

\- `exports/` — generated outputs (Gerbers, drill, PDFs). Not version-controlled.



\## Notes



\- Keep `exports/` for generated files only.

\- Commit KiCad source files (`.kicad\_sch`, `.kicad\_pcb`, project files) and LTspice source (`.asc`, models).

