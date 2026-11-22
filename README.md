# Factory — vertical slice

A first-person, headless-testable factory builder set in a procedural valley. Mine and process resources, route items on belts, manage power, and deliver components to the Ascent Spire.

## Run

Open the project in Godot 4.3 and press **F6/F5** to run the main scene/project. To start with a sample production line for a demo, run with `-- --demo-factory`.

## Controls

- **WASD**, **Shift**, **Space**, mouse — move, sprint, jump, and look
- **E** — interact; hold on a resource node to hand-mine
- **B** — open build menu; **1–9**, **Q/0**, and the scroll wheel select buildings
- **R** — rotate; click start/end cells to route a belt
- **F** — hold to dismantle; **X** — dismantle mode, then click
- **Tab** — inventory and hand crafting; **F5/F9** — save/load; **Esc** — pause/menu; **H** — help

## Headless tests

```sh
~/bin/godot --headless --path . -s tests/run_tests.gd
```
