# Report material: Stage 1

Raw material for the CSE 3120 report. Line numbers refer to [stage1.asm](../stage1/stage1.asm).

## 1. Architecture

### Why MASM + Win32 rather than Irvine32

Irvine32 is built around console programs: text output, keyboard input and character-cell positioning. This game needs pixel-level mouse positions, a graphical window and drawing, which come from `user32` and `gdi32`. Calling them directly removes a dependency. It still uses the course's core material: procedures, `INVOKE`/`PROTO`, `STRUCT`, addressing modes and conditional jumps.

### Layers

```
              Windows (mouse, keyboard, paint and close messages)
                                   |
                                   v
   main: message loop  --->  WndProc: routes each message
                                   |
        +--------------------------+--------------------------+
        v                          v                          v
   INPUT                      GAME LOGIC                 RENDERING
   HandleMouseMove            gameState                  RenderScene
   HandleClick                StartRun                   DrawMaze, DrawHud
   WM_MOUSELEAVE              EnterCrash                 ShowErrorScreen
   WM_KEYDOWN (Esc)           RestartLevel               ShowLevelComplete
        |                          ^                          |
        v                          |                          v
   COLLISION                       |                     Back buffer (memory DC)
   TraceMousePath  ----------------+                          |
   TestPixel                                                  v
   CheckCollision, CheckFinish                           WM_PAINT: BitBlt
        |                                                to the window
        v
   GetTileAtPixel --> GetTileAtCell --> level1Map (shared by DrawMaze too)
```

### Key design decisions

| Decision | Reason |
|---|---|
| One ASCII tile map (40 x 28, 20 px per tile) | Drawing and collision read the same bytes, so they can't disagree. The map in the source looks like the maze. |
| Assembly-time size check (line 111) | `IF ($ - level1Map) NE (MAP_W * MAP_H)` stops the build if a row has the wrong length. |
| Explicit state variable (`gameState`) | Each message's meaning depends on the state, so the mouse is only dangerous during a run. |
| Back buffer | Scenes are drawn off-screen and copied in one `BitBlt`, which prevents flicker. |
| Redraw only on state changes | Mouse movement doesn't trigger a redraw, so tracking stays cheap. |
| Native crosshair cursor | Its hotspot is its center, so the collision point is visible. The game doesn't need to draw a cursor. |
| Neon edge drawn inside wall tiles | Every lit edge pixel is deadly, so the visible boundary is the true boundary. |
| No `ClipCursor` or `SetCapture` | The mouse is never trapped. |

### State machine

| From | Event | To |
|---|---|---|
| READY | Click on START | PLAY |
| PLAY | Path meets a wall, or cursor leaves the window | CRASH (crash counter + 1) |
| PLAY | Path reaches FINISH | WON |
| PLAY | Esc, or the window loses focus | READY (no crash counted) |
| CRASH | RETRY | READY |
| WON | PLAY AGAIN | READY |
| Any | EXIT, title-bar X, or Esc outside a run | Program closes |

## 2. Collision algorithm

**Collision point:** the cursor hotspot, one pixel at the crosshair's center. Windows reports it in `lParam` of `WM_MOUSEMOVE`.

**The problem:** Windows sends position samples, not a report of every pixel crossed. A fast flick can produce two samples on opposite sides of a wall, with both positions in safe corridor. Checking only the newest sample would let the player pass straight through.

**The solution:** `TraceMousePath` (line 511) treats each pair of samples as a line segment and tests every pixel along it, using Bresenham's integer line algorithm:

1. Keep the last checked position in `lastX`, `lastY`. A run starts at the exact point clicked on START.
2. On each `WM_MOUSEMOVE`, walk from `(lastX, lastY)` to the new position.
3. At each pixel, `TestPixel` converts the pixel to a tile: `col = x / 20`, `row = (y - 40) / 20`, `index = row * 40 + col`.
4. The first wall or FINISH tile met ends the walk. Order along the path decides the result, so a flick through a wall onto FINISH is a crash.
5. If the whole segment is clear, the new position becomes `(lastX, lastY)`.

**Edge cases:**

| Case | Handling |
|---|---|
| Moving diagonally between two walls that touch only at a corner | X and Y are stepped and tested separately, so there is never a diagonal jump |
| Coordinates off the maze, including negatives | Treated as wall. Negatives are rejected before dividing, because `IDIV` truncates toward zero and -5 / 20 would otherwise give tile 0 |
| Leaving the window and re-entering past a wall | `TrackMouseEvent` requests `WM_MOUSELEAVE`, which counts as a crash |
| Alt-Tab during a run | The run is cancelled with no crash counted, and the player must click START again |

**Cost:** a segment takes at most about `|dx| + |dy|` tests, each a few array and arithmetic operations. The window limits that to about 1,400 tests per sample, and most segments are only a few pixels long.

### Evidence that the sweep matters

Two builds were run through the same test script. The only source difference is the arguments to `TraceMousePath`:

| Test | Full sweep | Newest position only (sabotaged) |
|---|---|---|
| Fast flick across a wall crashes | PASS | **FAIL** |
| Flick onto FINISH is a crash, not a win | PASS | **FAIL** |
| Other 19 tests | PASS | PASS |

The sabotaged build was temporary and is not included in the project. It was made just before the two final failure-screen fixes in section 5, which don't touch collision code.

In [screenshot 05](screenshots/stage1/05_crash_flick_fault_at_y140.png), the cursor jumped in one move from (90, 110) to (90, 250), which is safe floor. The game reports the fault at **Y=140**, the first wall pixel on that line.

## 3. Assembly instruction examples

Each is taken from the source. Good topics for the report's discussion:

| Concept | Instruction | Line | Purpose |
|---|---|---|---|
| Two-dimensional array indexing | `imul edx, MAP_W` | 411 | `index = row * MAP_W + col` into the byte map |
| Zero extension | `movzx eax, BYTE PTR [edx]` | 414 | Reads a one-byte tile into a 32-bit register |
| Sign extension | `movsx eax, WORD PTR lParam` | 1097 | Extracts a possibly negative X from the message |
| Signed division | `cdq` then `idiv ebx` | 430 | Converts pixels to tiles |
| Flags to a value | `sete al` | 454 | Turns the `cmp` result into a 0 or 1 return value |
| Shift as multiplication | `shl ebx, 1` | 556 | Computes `2 * errTerm` in Bresenham's loop |
| Absolute value with flags | `jns` / `neg eax` | 521 | Computes the line's length and sets its direction |
| Indexed table of pointers | `mov eax, crashHeads[esi*TYPE crashHeads]` | 995 | Selects a failure message |
| Remainder from `DIV` | `div ecx`, then `mov crashMsg, edx` | 624 | `crashCount MOD 5` cycles the messages |
| Struct access through a pointer | `cmp ecx, (RECT PTR [ebx]).left` | 714 | Button hit-testing |
| `PROTO` / `INVOKE` / `LOCAL` / `USES` | Throughout | 229 onward | Stack frames and register preservation |
| Win32 callback | `WndProc PROC hWin, uMsg, wParam, lParam` | 1071 | Windows calls our code with stdcall |
| Assembly-time expression | `IF ($ - level1Map) NE ...` | 111 | Validates the data while building |
| Macro function | `RGBCOLOR MACRO r, g, b` | 46 | Builds a Windows color value |

Check these line numbers against the final source before submitting, since they will shift as code is added.

### Annotated excerpt: tile lookup (`GetTileAtCell`)

```asm
    imul edx, MAP_W                 ; index = row * MAP_W + col
    add  edx, ecx
    add  edx, pCurrentMap           ; EDX = address of that tile
    movzx eax, BYTE PTR [edx]       ; EAX = tile character
```

### Annotated excerpt: one Bresenham step (`TraceMousePath`)

```asm
    mov  ebx, errTerm               ; EBX = 2 * errTerm, decides the steps
    shl  ebx, 1
    cmp  ebx, deltaY                ; if 2*err >= deltaY, step in X
    jl   TryY
    mov  eax, deltaY
    add  errTerm, eax
    add  esi, stepX
    INVOKE TestPixel, esi, edi      ; every intermediate pixel is tested
    test eax, eax
    jnz  Finished
```

## 4. Screenshots of each stage

All images were captured from the running program at 800 x 600. The system cursor isn't included.

| File | Shows |
|---|---|
| [01_ready.png](screenshots/stage1/01_ready.png) | Maze waiting for START, with level, progress and crash count |
| [02_playing.png](screenshots/stage1/02_playing.png) | Run in progress |
| [03_level_complete.png](screenshots/stage1/03_level_complete.png) | FINISH reached |
| [04_crash_wall.png](screenshots/stage1/04_crash_wall.png) | Wall touched at the exact boundary pixel (Y=140) |
| [05_crash_flick_fault_at_y140.png](screenshots/stage1/05_crash_flick_fault_at_y140.png) | Fast flick caught at the first wall pixel |
| [06_crash_left_window.png](screenshots/stage1/06_crash_left_window.png) | Cursor left the window |

Stages 2 and 3 will add their own folders.

The CPU Debugger box on the failure screen is fictional and says so on screen. On a wall crash its coordinates and tile value are real, but the instructions listed are an illustration, not the instructions the program ran.

## 5. Stage 1 test results

Automated run on Windows 11 with MASM 14.44, using real cursor movement and screen pixels. The final source passed **21 of 21** when built with `build_stage1.bat` and again when built with `asm_CSE3120.bat`. The Native Tools commands were checked to assemble and link, but that executable wasn't run through the tests.

| Area | Checks |
|---|---|
| Window | Client area is exactly 800 x 600 |
| Rendering | No drawn pixel in the 448,000-pixel maze area disagrees with the map on floor versus wall (START and FINISH labels excluded) |
| READY state | Walls are harmless, and clicking a wall doesn't start a run |
| Valid play | A slow walk along the true path survives and reaches FINISH |
| Boundary | y=139 is safe and y=140 crashes |
| Swept path | Flick across a wall crashes; flick onto FINISH crashes; long flick inside a corridor is safe |
| Leaving | Leaving the window crashes; focus loss cancels the run |
| Resources | GDI object count stays at 16 over 20 crash cycles |
| Exits | Esc, EXIT and the title-bar X all exit with code 0 |

**What these tests don't cover:**
- Nobody has played it by hand, so how it feels and how difficult it is remain unjudged.
- Focus loss was simulated by posting `WM_ACTIVATEAPP`, not by a real Alt-Tab.
- It was only tested on one PC, at 1920 x 1200.
- Automated cursor moves can't reproduce a physical mouse's timing exactly.
- The Visual Studio IDE steps in the README were not tried.

**Bugs found during development:**

| Bug | Found by | Fix |
|---|---|---|
| `INVOKE` of later procedures failed to assemble | MASM (A2006) | Added a `PROTO` block |
| `bh` used as a parameter name | MASM (A2008) | Renamed to `boxH` |
| Window-exit crash displayed the previous run's coordinates | Reading the screenshot; the pixel tests missed it | `StartRun` now resets `hitX`, `hitY` |
| Window-exit trace showed `tile = '.'` followed by a taken `JE` | Reading the screenshot | Separate trace for that crash type |

## 6. Roadmap

| Stage | Adds |
|---|---|
| 1 (done) | One maze, mouse, swept collision, failure and level-complete screens |
| 2 | Title screen, 10 distinct maps with a level table, `NextLevel`, a path check for every map, final victory screen |
| 3 | Register collectibles, elapsed-time stats, secret ending |
