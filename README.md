# STACK OVERFLOW: Escape the CPU

A mouse-controlled maze game for Windows, written in 32-bit MASM using the Win32 API.

**Status: Stage 1 of 3.** One maze, mouse tracking, swept collision detection, failure screen and level-complete screen. Levels 2-10, the menus and the special features are not built yet.

## Folder layout

```
README.md               this file
stage1/
  stage1.asm            all game code and data
  win32.inc             Win32 constants, structures and prototypes
  build_stage1.bat      one-step GUI build
tests/
  test_stage1.ps1       automated test tool (not part of the game)
docs/
  REPORT_NOTES.md       material for the report
  screenshots/stage1/   screenshots captured from the running game
```

Irvine32 is not used. The game calls `kernel32`, `user32` and `gdi32` directly.

## Build and run

Pick any one method. Methods A, B and C were run on this machine with MASM 14.44; method D was not.

### A. The included batch file (recommended)

This produces a true GUI program, so no console window appears.

```bash
stage1\build_stage1.bat
```

```bash
stage1\stage1.exe
```

### B. Your `asm_CSE3120.bat`

Run it from inside `stage1`, because it looks for the `.asm` file in the current folder. Pass the file name only.

```bash
cd stage1
```

```bash
C:\Users\madis\Documents\Assembly\Project32_VS2022\asm_CSE3120.bat stage1.asm
```

```bash
stage1.exe
```

This batch file links with `/SUBSYSTEM:CONSOLE`, so Windows creates a console first. The game calls `FreeConsole` on startup to detach from it. The script also links `irvine32.lib` and other libraries, which is harmless because the game doesn't use them.

### C. x86 Native Tools Command Prompt for VS 2022

Open that prompt from the Start menu, `cd` into `stage1`, then run:

```bash
ml /c /coff /W3 stage1.asm
```

```bash
link /SUBSYSTEM:WINDOWS stage1.obj kernel32.lib user32.lib gdi32.lib
```

```bash
stage1.exe
```

### D. Visual Studio 2022 IDE (not tested)

1. Create an **Empty Project (C++)**, and set the platform to **x86**.
2. Right-click the project, then **Build Dependencies > Build Customizations**, and tick **masm**.
3. Add `stage1.asm` and `win32.inc` to the project.
4. In **Project > Properties > Linker > System**, set **SubSystem** to **Windows**.
5. In **Linker > Input > Additional Dependencies**, add `kernel32.lib;user32.lib;gdi32.lib`.
6. Build and run with **Ctrl+F5**.

## How to play

1. Click the blue **START** block.
2. Move through the green corridor without touching a wall. The neon cyan edge counts as wall.
3. Reach the yellow **FINISH** block.

The crosshair's center is the collision point. Esc cancels a run in progress, and exits from any other screen. The title-bar X always works.

## Run the tests

This moves the real cursor for about 30 seconds, so leave the mouse alone while it runs. Close any open copy of the game first.

```bash
powershell -ExecutionPolicy Bypass -File tests\test_stage1.ps1
```

## Troubleshooting

| Message | Likely cause | Fix |
|---|---|---|
| `A2006: undefined symbol` on an `INVOKE` | The procedure is defined later in the file and has no `PROTO` | Add a `PROTO` above its first use |
| `A2008: syntax error` on a parameter or local | The name is reserved, such as `bh`, `dx` or `cx` | Rename it, as with `boxH` here |
| `A2006` on a name that differs only in case | `option casemap:none` makes names case-sensitive | Match the exact Win32 spelling |
| `A2070: invalid instruction operands` | Two memory operands, such as `mov hitX, px` | Go through a register: `mov eax, px`, then `mov hitX, eax` |
| The `level1Map must be exactly...` error | A map row isn't exactly 40 characters | Fix the row length |
| `LNK2001: unresolved external symbol` | A library is missing, or a `PROTO` has the wrong argument count (stdcall names include the byte count, as in `_FillRect@12`) | Add the library, or correct the `PROTO` |
| `LNK1104: cannot open file 'kernel32.lib'` | The SDK path isn't set | Use the Native Tools prompt or one of the batch files |
| `LNK1168: cannot open stage1.exe for writing` | The game is still running | Close it and rebuild |
| `'ml' is not recognized` | Plain command prompt with no toolchain on `PATH` | Use method A, B or C above |
| Batch file can't find the `.asm` | `asm_CSE3120.bat` was run from another folder | `cd stage1` first |
| Batch file paths fail after a VS update | `14.44.35207` is hard-coded and has changed | Update the version in the batch file |
