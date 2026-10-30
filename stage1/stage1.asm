TITLE STACK OVERFLOW - ESCAPE THE CPU : Stage 1 prototype     (stage1.asm)

; One maze, real mouse control, swept-path collision detection, and an
; in-window failure screen, in 32-bit MASM calling only the Win32 API.
;
; Stage 1 contains exactly one level. The level data, the collision code and
; the state machine are written so that Stage 2 can add levels 2-10 and the
; extra screens without changing how collision works.

.386
.model flat, stdcall
option casemap:none
.stack 4096

include win32.inc

;======================================================================
; CONSTANTS
;======================================================================
WINDOW_W    EQU 800         ; client area size in pixels
WINDOW_H    EQU 600
HUD_H       EQU 40          ; status bar height, above the maze
CELL_SIZE   EQU 20          ; one map tile = 20 x 20 pixels
MAP_W       EQU 40          ; tiles per row    (40 * 20 = 800)
MAP_H       EQU 28          ; rows of tiles    (28 * 20 + 40 = 600)
GLOW        EQU 2           ; thickness of the neon wall edge in pixels

; Tile types. They are ASCII so the map below can be read as a picture.
TILE_WALL   EQU '#'
TILE_PATH   EQU '.'
TILE_START  EQU 'S'
TILE_FINISH EQU 'F'

; Game states. WndProc behaves differently depending on which one is active.
STATE_READY EQU 0           ; waiting for a click on START
STATE_PLAY  EQU 1           ; run in progress, collisions are live
STATE_CRASH EQU 2           ; failure screen showing
STATE_WON   EQU 3           ; level complete screen showing

; Results returned by TestPixel and TraceMousePath
PATH_CLEAR  EQU 0
PATH_WALL   EQU 1
PATH_FINISH EQU 2

; Windows colors are stored as 00BBGGRRh, so this macro builds one from R,G,B.
RGBCOLOR MACRO r:REQ, g:REQ, b:REQ
    EXITM <((b) SHL 16) OR ((g) SHL 8) OR (r)>
ENDM

COL_BG      = RGBCOLOR(  4,   8,  14)
COL_WALL    = RGBCOLOR(  8,  20,  28)
COL_DOT     = RGBCOLOR( 20,  60,  70)
COL_GLOW    = RGBCOLOR(  0, 255, 255)
COL_PATH    = RGBCOLOR(  0, 150,  80)
COL_START   = RGBCOLOR(  0, 190, 255)
COL_FINISH  = RGBCOLOR(255, 215,   0)
COL_HUD     = RGBCOLOR(  0,  30,  30)
COL_GREEN   = RGBCOLOR( 57, 255,  20)
COL_CYAN    = RGBCOLOR(  0, 255, 255)
COL_DIM     = RGBCOLOR( 20,  70,  60)
COL_WHITE   = RGBCOLOR(235, 245, 245)
COL_BLACK   = RGBCOLOR(  0,   0,   0)
COL_RED_BG  = RGBCOLOR(120,   0,   0)
COL_RED_HI  = RGBCOLOR(255,  70,  70)
COL_YELLOW  = RGBCOLOR(255, 215,   0)
COL_WON_BG  = RGBCOLOR(  0,  70,  40)
COL_BUTTON  = RGBCOLOR( 10,  20,  24)

;======================================================================
; DATA
;======================================================================
.data
className   BYTE "StackOverflowEscape",0
windowTitle BYTE "STACK OVERFLOW - Escape the CPU (Stage 1)",0
fontName    BYTE "Consolas",0

; Level 1 map. This one table is the only maze geometry in the program:
; DrawMaze paints it and CheckCollision reads it, so what you see on screen
; and what kills you can never disagree.
level1Map LABEL BYTE
    BYTE "########################################"   ; row 0
    BYTE "########################################"
    BYTE "##SSSS..............................####"
    BYTE "##SSSS..............................####"
    BYTE "##SSSS..............................####"
    BYTE "################################....####"   ; row 5
    BYTE "################################....####"
    BYTE "################################....####"
    BYTE "################################....####"
    BYTE "####................................####"
    BYTE "####................................####"   ; row 10
    BYTE "####................................####"
    BYTE "####....################################"
    BYTE "####....################################"
    BYTE "####....################################"
    BYTE "####....################################"   ; row 15
    BYTE "####................................####"
    BYTE "####................................####"
    BYTE "####................................####"
    BYTE "################################....####"
    BYTE "################################....####"   ; row 20
    BYTE "################################....####"
    BYTE "################################....####"
    BYTE "##FFFF..............................####"
    BYTE "##FFFF..............................####"
    BYTE "##FFFF..............................####"   ; row 25
    BYTE "########################################"
    BYTE "########################################"

; Stops the build if a row above has the wrong length.
IF ($ - level1Map) NE (MAP_W * MAP_H)
    .ERR <level1Map must be exactly MAP_W * MAP_H bytes>
ENDIF

levelName   BYTE "MOV",0

; Failure messages. crashHeads and crashSubs are parallel tables of pointers;
; the crash counter picks the entry. Entry 5 is used when the cursor leaves
; the window rather than touching a wall.
head0 BYTE "SEGMENTATION FAULT",0
sub0  BYTE "Skill issue detected.",0
head1 BYTE "STACK OVERFLOW",0
sub1  BYTE "Too many bad decisions.",0
head2 BYTE "INVALID OPCODE",0
sub2  BYTE "Walls are not optional.",0
head3 BYTE "ACCESS DENIED",0
sub3  BYTE "You cannot MOV through walls.",0
head4 BYTE "CPU EXCEPTION",0
sub4  BYTE "Try debugging your mouse.",0
head5 BYTE "GENERAL PROTECTION FAULT",0
sub5  BYTE "The cursor left its address space.",0
crashHeads DWORD head0, head1, head2, head3, head4, head5
crashSubs  DWORD sub0,  sub1,  sub2,  sub3,  sub4,  sub5
NUM_WALL_MESSAGES EQU 5
LEFT_WINDOW_MSG   EQU 5

; Static text
fmtLevel    BYTE "LEVEL %02d/10  %s",0
fmtCrashes  BYTE "CRASHES: %d",0
fmtFault    BYTE "FAULT ADDRESS  X=%d  Y=%d  TILE=(%d,%d)",0
fmtCmp      BYTE "CMP  map[%d][%d], WALL   ; tile = '%c'",0
txtReady    BYTE "CLICK START TO BEGIN - ESC EXITS",0
txtPlaying  BYTE "AVOID THE WALLS - ESC ABORTS",0
txtDone     BYTE "CHOOSE AN OPTION BELOW",0
txtStart    BYTE "START",0
txtFinish   BYTE "FINISH",0
txtBang     BYTE "!",0
txtRetry    BYTE "RETRY",0
txtAgain    BYTE "PLAY AGAIN",0
txtExit     BYTE "EXIT",0
txtTrace0   BYTE "CPU DEBUGGER - illustrative, not the code actually run",0
txtTrace1   BYTE "MOV  EAX, cursorPosition",0
txtTrace3   BYTE "JE   GAME_OVER           ; branch taken",0
txtCmpLeft  BYTE "CMP  cursorPosition, WINDOW_BOUNDS",0
txtTrace3Left BYTE "JA   GAME_OVER           ; branch taken",0
txtWonHead  BYTE "ACCESS GRANTED",0
txtWonSub   BYTE "Level 01 complete. You reached FINISH safely.",0

; Buttons shared by the failure and level-complete panels
btnPrimary  RECT <180, 432, 380, 482>
btnExit     RECT <420, 432, 620, 482>

; Warning triangle on the failure panel, drawn with GDI's Polygon
warnTriangle POINT <400, 100>, <366, 158>, <434, 158>

; Handles
hInstance   DWORD ?
hMainWnd    DWORD ?
hBackDC     DWORD ?     ; memory device context holding the back buffer
hBackBmp    DWORD ?     ; bitmap selected into hBackDC
hOldBmp     DWORD ?
hFontLarge  DWORD ?
hFontMedium DWORD ?
hFontSmall  DWORD ?

; Game state
gameState   DWORD STATE_READY
pCurrentMap DWORD ?     ; address of the map currently being played
crashCount  DWORD 0
lastX       SDWORD 0    ; last checked cursor position (the start of the
lastY       SDWORD 0    ;   next path segment to test)
hitX        SDWORD 0    ; pixel where the last path test stopped
hitY        SDWORD 0
crashMsg    DWORD 0     ; index into crashHeads / crashSubs
startCol    DWORD 0     ; first START and FINISH tiles, for their labels
startRow    DWORD 0
finishCol   DWORD 0
finishRow   DWORD 0
textBuffer  BYTE 128 DUP(?)

;======================================================================
; CODE
;======================================================================
.code

; INVOKE can only call a procedure it has already seen, so procedures defined
; later in this file are declared here.
InitializeGame    PROTO
CreateGameWindow  PROTO
LoadLevel         PROTO :DWORD
GetTileAtCell     PROTO :SDWORD, :SDWORD
GetTileAtPixel    PROTO :SDWORD, :SDWORD
CheckCollision    PROTO :SDWORD, :SDWORD
CheckFinish       PROTO :SDWORD, :SDWORD
TestPixel         PROTO :SDWORD, :SDWORD
TraceMousePath    PROTO :SDWORD, :SDWORD, :SDWORD, :SDWORD
HandleMouseMove   PROTO :SDWORD, :SDWORD
ChooseWallMessage PROTO
EnterCrash        PROTO
HandleClick       PROTO :SDWORD, :SDWORD
StartRun          PROTO :SDWORD, :SDWORD
RestartLevel      PROTO
PointInRect       PROTO :DWORD, :SDWORD, :SDWORD
RenderScene       PROTO
FillBox           PROTO :SDWORD, :SDWORD, :SDWORD, :SDWORD, :DWORD
PutText           PROTO :SDWORD, :SDWORD, :DWORD, :DWORD, :DWORD
PutTextCentered   PROTO :SDWORD, :SDWORD, :DWORD, :DWORD, :DWORD
DrawButton        PROTO :DWORD, :DWORD, :DWORD
DrawMaze          PROTO
DrawHud           PROTO
ShowErrorScreen   PROTO
ShowLevelComplete PROTO
ReleaseGame       PROTO
WndProc           PROTO :DWORD, :DWORD, :DWORD, :DWORD

;----------------------------------------------------------------------
; main - program entry point: set up, then run the Windows message loop.
;----------------------------------------------------------------------
main PROC
    LOCAL msgData:MSG

    INVOKE FreeConsole              ; asm_CSE3120.bat links as a console app;
                                    ; this detaches the unwanted console
    INVOKE SetProcessDPIAware       ; 1 pixel in our math = 1 pixel on screen
    INVOKE InitializeGame
    INVOKE CreateGameWindow
    test eax, eax
    jz   Quit

MessageLoop:
    INVOKE GetMessageA, ADDR msgData, 0, 0, 0
    cmp  eax, 0                     ; 0 = WM_QUIT, -1 = error: stop on either
    jle  Quit
    INVOKE TranslateMessage, ADDR msgData
    INVOKE DispatchMessageA, ADDR msgData
    jmp  MessageLoop

Quit:
    INVOKE ExitProcess, 0
    ret                             ; never reached; ExitProcess does not return
main ENDP

;----------------------------------------------------------------------
; InitializeGame - create the fonts and load the first level.
;----------------------------------------------------------------------
InitializeGame PROC
    INVOKE GetModuleHandleA, 0
    mov  hInstance, eax
    INVOKE CreateFontA, 34, 0, 0, 0, FW_BOLD, 0, 0, 0, 0, 0, 0, 0, \
           FIXED_PITCH_MODERN, ADDR fontName
    mov  hFontLarge, eax
    INVOKE CreateFontA, 20, 0, 0, 0, FW_BOLD, 0, 0, 0, 0, 0, 0, 0, \
           FIXED_PITCH_MODERN, ADDR fontName
    mov  hFontMedium, eax
    INVOKE CreateFontA, 16, 0, 0, 0, FW_NORMAL, 0, 0, 0, 0, 0, 0, 0, \
           FIXED_PITCH_MODERN, ADDR fontName
    mov  hFontSmall, eax
    INVOKE LoadLevel, OFFSET level1Map
    ret
InitializeGame ENDP

;----------------------------------------------------------------------
; CreateGameWindow - register the class, create a fixed-size centered
; window and its back buffer.
; Returns: EAX = window handle, or 0 on failure
;----------------------------------------------------------------------
CreateGameWindow PROC USES ebx
    LOCAL wc:WNDCLASSEXA, frame:RECT, winW:DWORD, winH:DWORD, hdcWin:DWORD
    GAME_STYLE EQU WS_OVERLAPPED OR WS_CAPTION OR WS_SYSMENU OR WS_MINIMIZEBOX

    mov  wc.cbSize, SIZEOF WNDCLASSEXA
    mov  wc.style, CS_HREDRAW OR CS_VREDRAW
    mov  wc.lpfnWndProc, OFFSET WndProc
    mov  wc.cbClsExtra, 0
    mov  wc.cbWndExtra, 0
    mov  eax, hInstance
    mov  wc.hInstance, eax
    INVOKE LoadIconA, 0, IDI_APPLICATION
    mov  wc.hIcon, eax
    mov  wc.hIconSm, eax
    ; The crosshair's hotspot is its exact center, which makes it obvious
    ; which single pixel is the collision reference point.
    INVOKE LoadCursorA, 0, IDC_CROSS
    mov  wc.hCursor, eax
    mov  wc.hbrBackground, 0        ; we paint every pixel ourselves
    mov  wc.lpszMenuName, 0
    mov  wc.lpszClassName, OFFSET className
    INVOKE RegisterClassExA, ADDR wc
    test eax, eax
    jz   Failed

    ; Ask Windows how large the frame must be for an 800x600 client area.
    mov  frame.left, 0
    mov  frame.top, 0
    mov  frame.right, WINDOW_W
    mov  frame.bottom, WINDOW_H
    INVOKE AdjustWindowRect, ADDR frame, GAME_STYLE, 0
    mov  eax, frame.right
    sub  eax, frame.left
    mov  winW, eax
    mov  eax, frame.bottom
    sub  eax, frame.top
    mov  winH, eax

    ; Centered X in EBX, centered Y in EAX.
    INVOKE GetSystemMetrics, SM_CXSCREEN
    sub  eax, winW
    sar  eax, 1
    mov  ebx, eax
    INVOKE GetSystemMetrics, SM_CYSCREEN
    sub  eax, winH
    sar  eax, 1

    INVOKE CreateWindowExA, 0, ADDR className, ADDR windowTitle, GAME_STYLE, \
           ebx, eax, winW, winH, 0, 0, hInstance, 0
    test eax, eax
    jz   Failed
    mov  hMainWnd, eax

    ; Back buffer: draw off-screen, then copy to the window in one step.
    INVOKE GetDC, hMainWnd
    mov  hdcWin, eax
    INVOKE CreateCompatibleDC, hdcWin
    mov  hBackDC, eax
    INVOKE CreateCompatibleBitmap, hdcWin, WINDOW_W, WINDOW_H
    mov  hBackBmp, eax
    INVOKE SelectObject, hBackDC, hBackBmp
    mov  hOldBmp, eax
    INVOKE ReleaseDC, hMainWnd, hdcWin
    INVOKE SetBkMode, hBackDC, TRANSPARENT_BK

    INVOKE RenderScene
    INVOKE ShowWindow, hMainWnd, SW_SHOWNORMAL
    INVOKE UpdateWindow, hMainWnd
    mov  eax, hMainWnd
    ret
Failed:
    xor  eax, eax
    ret
CreateGameWindow ENDP

;----------------------------------------------------------------------
; LoadLevel - make a map current and find its START and FINISH labels.
; Receives: pMap = address of a MAP_W * MAP_H byte map
;----------------------------------------------------------------------
LoadLevel PROC USES esi edi, pMap:DWORD
    mov  eax, pMap
    mov  pCurrentMap, eax
    mov  startCol, -1
    mov  finishCol, -1
    xor  edi, edi                   ; EDI = row
RowLoop:
    xor  esi, esi                   ; ESI = column
ColLoop:
    INVOKE GetTileAtCell, esi, edi
    cmp  al, TILE_START
    jne  NotStart
    cmp  startCol, -1               ; only remember the first START tile
    jne  NextCol
    mov  startCol, esi
    mov  startRow, edi
    jmp  NextCol
NotStart:
    cmp  al, TILE_FINISH
    jne  NextCol
    cmp  finishCol, -1
    jne  NextCol
    mov  finishCol, esi
    mov  finishRow, edi
NextCol:
    inc  esi
    cmp  esi, MAP_W
    jb   ColLoop
    inc  edi
    cmp  edi, MAP_H
    jb   RowLoop
    ret
LoadLevel ENDP

;======================================================================
; COLLISION DETECTION
;======================================================================

;----------------------------------------------------------------------
; GetTileAtCell - read one tile from the current map.
; Receives: col, row (anything off the map counts as wall)
; Returns:  EAX = tile character
;----------------------------------------------------------------------
GetTileAtCell PROC col:SDWORD, row:SDWORD
    mov  eax, TILE_WALL
    mov  ecx, col
    mov  edx, row
    cmp  ecx, 0
    jl   Done
    cmp  ecx, MAP_W
    jge  Done
    cmp  edx, 0
    jl   Done
    cmp  edx, MAP_H
    jge  Done
    imul edx, MAP_W                 ; index = row * MAP_W + col
    add  edx, ecx
    add  edx, pCurrentMap
    movzx eax, BYTE PTR [edx]
Done:
    ret
GetTileAtCell ENDP

;----------------------------------------------------------------------
; GetTileAtPixel - convert a window pixel to a tile and read it.
; Receives: px, py in client coordinates
; Returns:  EAX = tile character (pixels off the maze count as wall)
;----------------------------------------------------------------------
GetTileAtPixel PROC USES ebx, px:SDWORD, py:SDWORD
    mov  ebx, CELL_SIZE

    mov  eax, px                    ; column = px / CELL_SIZE
    cmp  eax, 0                     ; reject negatives first: IDIV truncates
    jl   OffMap                     ;   toward zero, so -5 / 20 would give 0
    cdq
    idiv ebx
    mov  ecx, eax

    mov  eax, py                    ; row = (py - HUD_H) / CELL_SIZE
    sub  eax, HUD_H
    jl   OffMap
    cdq
    idiv ebx

    INVOKE GetTileAtCell, ecx, eax
    ret
OffMap:
    mov  eax, TILE_WALL
    ret
GetTileAtPixel ENDP

;----------------------------------------------------------------------
; CheckCollision - is this pixel solid?
; Returns: EAX = 1 if the pixel is wall or off the maze, otherwise 0
;----------------------------------------------------------------------
CheckCollision PROC px:SDWORD, py:SDWORD
    INVOKE GetTileAtPixel, px, py
    cmp  eax, TILE_WALL
    sete al
    movzx eax, al
    ret
CheckCollision ENDP

;----------------------------------------------------------------------
; CheckFinish - is this pixel on the FINISH zone?
; Returns: EAX = 1 if the pixel is a FINISH tile, otherwise 0
;----------------------------------------------------------------------
CheckFinish PROC px:SDWORD, py:SDWORD
    INVOKE GetTileAtPixel, px, py
    cmp  eax, TILE_FINISH
    sete al
    movzx eax, al
    ret
CheckFinish ENDP

;----------------------------------------------------------------------
; TestPixel - test one point on the cursor's path and record where it is.
; Returns: EAX = PATH_CLEAR, PATH_WALL or PATH_FINISH
;----------------------------------------------------------------------
TestPixel PROC px:SDWORD, py:SDWORD
    mov  eax, px
    mov  hitX, eax
    mov  eax, py
    mov  hitY, eax

    INVOKE CheckCollision, px, py
    test eax, eax
    jnz  HitWall
    INVOKE CheckFinish, px, py
    test eax, eax
    jnz  HitFinish
    mov  eax, PATH_CLEAR
    ret
HitWall:
    mov  eax, PATH_WALL
    ret
HitFinish:
    mov  eax, PATH_FINISH
    ret
TestPixel ENDP

;----------------------------------------------------------------------
; TraceMousePath - test every pixel between two cursor samples.
;
; Windows does not report every pixel the mouse crosses. A fast flick can
; produce samples far apart, with a wall between them. Testing only the new
; position would let that flick jump the wall, so we walk the straight line
; between the samples using Bresenham's line algorithm (integers only).
;
; X and Y are tested after separate steps, never diagonally in one step, so
; the walk also cannot slip between two walls that touch only at a corner.
;
; Returns: EAX = PATH_CLEAR, or the first PATH_WALL / PATH_FINISH met along
;          the line. hitX and hitY give the pixel where the walk stopped.
;----------------------------------------------------------------------
TraceMousePath PROC USES ebx esi edi, x0:SDWORD, y0:SDWORD, x1:SDWORD, y1:SDWORD
    LOCAL deltaX:SDWORD, deltaY:SDWORD, stepX:SDWORD, stepY:SDWORD, errTerm:SDWORD

    mov  esi, x0                    ; ESI, EDI = current point on the line
    mov  edi, y0

    ; deltaX = |x1 - x0|, stepX = direction of travel in X
    mov  stepX, 1
    mov  eax, x1
    sub  eax, x0
    jns  XPositive
    neg  eax
    mov  stepX, -1
XPositive:
    mov  deltaX, eax

    ; deltaY = -|y1 - y0| (negative by convention), stepY = direction in Y
    mov  stepY, 1
    mov  eax, y1
    sub  eax, y0
    jns  YPositive
    neg  eax
    mov  stepY, -1
YPositive:
    neg  eax
    mov  deltaY, eax

    ; errTerm tracks how far the current pixel is from the ideal line.
    add  eax, deltaX
    mov  errTerm, eax

    INVOKE TestPixel, esi, edi      ; the first point counts too
    test eax, eax
    jnz  Finished

WalkLoop:
    cmp  esi, x1                    ; reached the end of the line?
    jne  KeepWalking
    cmp  edi, y1
    jne  KeepWalking
    mov  eax, PATH_CLEAR
    jmp  Finished

KeepWalking:
    mov  ebx, errTerm               ; EBX = 2 * errTerm, decides the steps
    shl  ebx, 1

    cmp  ebx, deltaY                ; if 2*err >= deltaY, step in X
    jl   TryY
    mov  eax, deltaY
    add  errTerm, eax
    add  esi, stepX
    INVOKE TestPixel, esi, edi
    test eax, eax
    jnz  Finished

TryY:
    cmp  ebx, deltaX                ; if 2*err <= deltaX, step in Y
    jg   WalkLoop
    mov  eax, deltaX
    add  errTerm, eax
    add  edi, stepY
    INVOKE TestPixel, esi, edi
    test eax, eax
    jnz  Finished
    jmp  WalkLoop

Finished:
    ret
TraceMousePath ENDP

;======================================================================
; GAME LOGIC
;======================================================================

;----------------------------------------------------------------------
; HandleMouseMove - process a cursor sample during a run.
;----------------------------------------------------------------------
HandleMouseMove PROC px:SDWORD, py:SDWORD
    cmp  gameState, STATE_PLAY      ; the mouse is harmless in other states
    jne  Done

    INVOKE TraceMousePath, lastX, lastY, px, py
    cmp  eax, PATH_WALL
    je   Crashed
    cmp  eax, PATH_FINISH
    je   Won

    mov  eax, px                    ; clear: next segment starts here
    mov  lastX, eax
    mov  eax, py
    mov  lastY, eax
    jmp  Done

Crashed:
    INVOKE ChooseWallMessage
    INVOKE EnterCrash
    jmp  Done
Won:
    mov  gameState, STATE_WON
    INVOKE RenderScene
Done:
    ret
HandleMouseMove ENDP

;----------------------------------------------------------------------
; ChooseWallMessage - pick a message: crashMsg = crashCount MOD 5
;----------------------------------------------------------------------
ChooseWallMessage PROC
    mov  eax, crashCount
    xor  edx, edx
    mov  ecx, NUM_WALL_MESSAGES
    div  ecx
    mov  crashMsg, edx
    ret
ChooseWallMessage ENDP

;----------------------------------------------------------------------
; EnterCrash - count the failure and show the failure screen.
;----------------------------------------------------------------------
EnterCrash PROC
    inc  crashCount
    mov  gameState, STATE_CRASH
    INVOKE RenderScene
    ret
EnterCrash ENDP

;----------------------------------------------------------------------
; HandleClick - left button: START tile, or a button on a panel.
;----------------------------------------------------------------------
HandleClick PROC px:SDWORD, py:SDWORD
    cmp  gameState, STATE_READY
    je   ReadyClick
    cmp  gameState, STATE_PLAY      ; clicks do nothing during a run
    je   Done

    ; A panel is showing: check its two buttons.
    INVOKE PointInRect, ADDR btnPrimary, px, py
    test eax, eax
    jz   TryExit
    INVOKE RestartLevel
    jmp  Done
TryExit:
    INVOKE PointInRect, ADDR btnExit, px, py
    test eax, eax
    jz   Done
    INVOKE DestroyWindow, hMainWnd
    jmp  Done

ReadyClick:
    INVOKE GetTileAtPixel, px, py
    cmp  eax, TILE_START
    jne  Done
    INVOKE StartRun, px, py
Done:
    ret
HandleClick ENDP

;----------------------------------------------------------------------
; StartRun - begin a run from the clicked point on START.
;----------------------------------------------------------------------
StartRun PROC USES ebx, px:SDWORD, py:SDWORD
    LOCAL tme:TRACKMOUSEEVENT

    mov  eax, px                    ; the path begins exactly at the click
    mov  lastX, eax
    mov  hitX, eax                  ; also clears the previous run's fault point
    mov  eax, py
    mov  lastY, eax
    mov  hitY, eax
    mov  gameState, STATE_PLAY

    ; Ask Windows for WM_MOUSELEAVE, so the player can't exit the window and
    ; re-enter past a wall. The mouse itself is never captured or confined.
    mov  tme.cbSize, SIZEOF TRACKMOUSEEVENT
    mov  tme.dwFlags, TME_LEAVE
    mov  eax, hMainWnd
    mov  tme.hwndTrack, eax
    mov  tme.dwHoverTime, 0
    INVOKE TrackMouseEvent, ADDR tme

    INVOKE RenderScene
    ret
StartRun ENDP

;----------------------------------------------------------------------
; RestartLevel - return to the waiting state. Crashes stay counted.
;----------------------------------------------------------------------
RestartLevel PROC
    mov  gameState, STATE_READY
    INVOKE RenderScene
    ret
RestartLevel ENDP

;----------------------------------------------------------------------
; PointInRect - is (px, py) inside the rectangle?
; Returns: EAX = 1 if inside, otherwise 0
;----------------------------------------------------------------------
PointInRect PROC USES ebx, pRect:DWORD, px:SDWORD, py:SDWORD
    mov  ebx, pRect
    mov  ecx, px
    mov  edx, py
    xor  eax, eax
    cmp  ecx, (RECT PTR [ebx]).left
    jl   Done
    cmp  ecx, (RECT PTR [ebx]).right
    jge  Done
    cmp  edx, (RECT PTR [ebx]).top
    jl   Done
    cmp  edx, (RECT PTR [ebx]).bottom
    jge  Done
    mov  eax, 1
Done:
    ret
PointInRect ENDP

;======================================================================
; RENDERING - everything draws to the back buffer; WM_PAINT copies it.
;======================================================================

;----------------------------------------------------------------------
; RenderScene - redraw for the current state and request a repaint.
;----------------------------------------------------------------------
RenderScene PROC
    INVOKE DrawMaze
    INVOKE DrawHud
    cmp  gameState, STATE_CRASH
    jne  NotCrash
    INVOKE ShowErrorScreen
    jmp  Present
NotCrash:
    cmp  gameState, STATE_WON
    jne  Present
    INVOKE ShowLevelComplete
Present:
    INVOKE InvalidateRect, hMainWnd, 0, 0
    ret
RenderScene ENDP

;----------------------------------------------------------------------
; FillBox - fill a rectangle with a solid color.
;----------------------------------------------------------------------
FillBox PROC USES ebx, boxX:SDWORD, boxY:SDWORD, boxW:SDWORD, boxH:SDWORD, color:DWORD
    LOCAL box:RECT
    mov  eax, boxX
    mov  box.left, eax
    add  eax, boxW
    mov  box.right, eax
    mov  eax, boxY
    mov  box.top, eax
    add  eax, boxH
    mov  box.bottom, eax
    INVOKE CreateSolidBrush, color
    mov  ebx, eax
    INVOKE FillRect, hBackDC, ADDR box, ebx
    INVOKE DeleteObject, ebx        ; GDI objects must be freed or they leak
    ret
FillBox ENDP

;----------------------------------------------------------------------
; PutText - draw a string left-aligned at (tx, ty).
;----------------------------------------------------------------------
PutText PROC tx:SDWORD, ty:SDWORD, pStr:DWORD, color:DWORD, hFont:DWORD
    INVOKE SelectObject, hBackDC, hFont
    INVOKE SetTextColor, hBackDC, color
    INVOKE lstrlenA, pStr
    INVOKE TextOutA, hBackDC, tx, ty, pStr, eax
    ret
PutText ENDP

;----------------------------------------------------------------------
; PutTextCentered - draw a string centered horizontally on tx.
;----------------------------------------------------------------------
PutTextCentered PROC tx:SDWORD, ty:SDWORD, pStr:DWORD, color:DWORD, hFont:DWORD
    INVOKE SetTextAlign, hBackDC, TA_CENTER
    INVOKE PutText, tx, ty, pStr, color, hFont
    INVOKE SetTextAlign, hBackDC, TA_LEFT
    ret
PutTextCentered ENDP

;----------------------------------------------------------------------
; DrawButton - a framed button with a centered label.
;----------------------------------------------------------------------
DrawButton PROC USES ebx esi edi, pRect:DWORD, pLabel:DWORD, color:DWORD
    LOCAL boxW:SDWORD, boxH:SDWORD

    mov  ebx, pRect
    mov  esi, (RECT PTR [ebx]).left
    mov  edi, (RECT PTR [ebx]).top
    mov  eax, (RECT PTR [ebx]).right
    sub  eax, esi
    mov  boxW, eax
    mov  eax, (RECT PTR [ebx]).bottom
    sub  eax, edi
    mov  boxH, eax

    INVOKE FillBox, esi, edi, boxW, boxH, color ; border color

    lea  eax, [esi+3]                           ; inner face, 3 pixels smaller
    lea  ecx, [edi+3]
    mov  edx, boxW
    sub  edx, 6
    mov  ebx, boxH
    sub  ebx, 6
    INVOKE FillBox, eax, ecx, edx, ebx, COL_BUTTON

    mov  eax, boxW                              ; label at the button's center
    sar  eax, 1
    add  eax, esi
    mov  ecx, boxH
    sar  ecx, 1
    add  ecx, edi
    sub  ecx, 12
    INVOKE PutTextCentered, eax, ecx, pLabel, color, hFontMedium
    ret
DrawButton ENDP

;----------------------------------------------------------------------
; DrawMaze - paint the current map tile by tile.
; The neon edge is painted on the wall's side of the boundary, so every
; lit pixel is a pixel that will cause a crash.
;----------------------------------------------------------------------
DrawMaze PROC USES ebx esi edi
    LOCAL tileX:SDWORD, tileY:SDWORD

    xor  edi, edi                   ; EDI = row
RowLoop:
    xor  esi, esi                   ; ESI = column
ColLoop:
    mov  eax, esi                   ; tile's top-left pixel
    imul eax, CELL_SIZE
    mov  tileX, eax
    mov  eax, edi
    imul eax, CELL_SIZE
    add  eax, HUD_H
    mov  tileY, eax

    INVOKE GetTileAtCell, esi, edi
    cmp  al, TILE_WALL
    je   DrawWall
    mov  ebx, COL_PATH
    cmp  al, TILE_START
    jne  NotStart
    mov  ebx, COL_START
NotStart:
    cmp  al, TILE_FINISH
    jne  PaintFloor
    mov  ebx, COL_FINISH
PaintFloor:
    INVOKE FillBox, tileX, tileY, CELL_SIZE, CELL_SIZE, ebx
    jmp  NextCol

DrawWall:
    INVOKE FillBox, tileX, tileY, CELL_SIZE, CELL_SIZE, COL_WALL
    mov  eax, tileX                 ; small "circuit board" dot in the middle
    add  eax, CELL_SIZE/2 - 1
    mov  ecx, tileY
    add  ecx, CELL_SIZE/2 - 1
    INVOKE FillBox, eax, ecx, 2, 2, COL_DOT

    ; Light each side of this wall tile that faces open floor.
    lea  eax, [edi-1]
    INVOKE GetTileAtCell, esi, eax  ; tile above
    cmp  al, TILE_WALL
    je   CheckBelow
    INVOKE FillBox, tileX, tileY, CELL_SIZE, GLOW, COL_GLOW
CheckBelow:
    lea  eax, [edi+1]
    INVOKE GetTileAtCell, esi, eax
    cmp  al, TILE_WALL
    je   CheckLeft
    mov  eax, tileY
    add  eax, CELL_SIZE - GLOW
    INVOKE FillBox, tileX, eax, CELL_SIZE, GLOW, COL_GLOW
CheckLeft:
    lea  eax, [esi-1]
    INVOKE GetTileAtCell, eax, edi
    cmp  al, TILE_WALL
    je   CheckRight
    INVOKE FillBox, tileX, tileY, GLOW, CELL_SIZE, COL_GLOW
CheckRight:
    lea  eax, [esi+1]
    INVOKE GetTileAtCell, eax, edi
    cmp  al, TILE_WALL
    je   NextCol
    mov  eax, tileX
    add  eax, CELL_SIZE - GLOW
    INVOKE FillBox, eax, tileY, GLOW, CELL_SIZE, COL_GLOW

NextCol:
    inc  esi
    cmp  esi, MAP_W
    jb   ColLoop
    inc  edi
    cmp  edi, MAP_H
    jb   RowLoop

    ; Zone labels, placed from the positions LoadLevel found.
    mov  eax, startCol
    imul eax, CELL_SIZE
    add  eax, 14
    mov  ecx, startRow
    imul ecx, CELL_SIZE
    add  ecx, HUD_H + 18
    INVOKE PutText, eax, ecx, ADDR txtStart, COL_BLACK, hFontMedium
    mov  eax, finishCol
    imul eax, CELL_SIZE
    add  eax, 8
    mov  ecx, finishRow
    imul ecx, CELL_SIZE
    add  ecx, HUD_H + 18
    INVOKE PutText, eax, ecx, ADDR txtFinish, COL_BLACK, hFontMedium
    ret
DrawMaze ENDP

;----------------------------------------------------------------------
; DrawHud - status bar: level, progress out of 10, prompt, crash count.
;----------------------------------------------------------------------
DrawHud PROC USES ebx esi
    INVOKE FillBox, 0, 0, WINDOW_W, HUD_H, COL_HUD
    INVOKE FillBox, 0, HUD_H - 2, WINDOW_W, 2, COL_GREEN

    INVOKE wsprintfA, ADDR textBuffer, ADDR fmtLevel, 1, ADDR levelName
    INVOKE PutText, 12, 9, ADDR textBuffer, COL_GREEN, hFontMedium

    ; Ten progress segments; level 1 lights the first one.
    xor  ebx, ebx
SegmentLoop:
    mov  eax, ebx
    imul eax, 14
    add  eax, 190
    mov  esi, COL_DIM
    test ebx, ebx
    jnz  DrawSegment
    mov  esi, COL_GREEN
DrawSegment:
    INVOKE FillBox, eax, 12, 11, 14, esi
    inc  ebx
    cmp  ebx, 10
    jb   SegmentLoop

    ; The prompt depends on the state.
    mov  eax, OFFSET txtReady
    cmp  gameState, STATE_READY
    je   ShowPrompt
    mov  eax, OFFSET txtPlaying
    cmp  gameState, STATE_PLAY
    je   ShowPrompt
    mov  eax, OFFSET txtDone
ShowPrompt:
    INVOKE PutText, 345, 11, eax, COL_CYAN, hFontSmall

    INVOKE wsprintfA, ADDR textBuffer, ADDR fmtCrashes, crashCount
    INVOKE PutText, 660, 9, ADDR textBuffer, COL_RED_HI, hFontMedium
    ret
DrawHud ENDP

;----------------------------------------------------------------------
; ShowErrorScreen - the red failure panel with the CPU debugger trace.
; The trace is illustrative: it explains the crash in assembly terms, but
; it is not a record of the instructions the program actually executed.
;----------------------------------------------------------------------
ShowErrorScreen PROC USES ebx esi
    LOCAL hOldPen:DWORD, hOldBrush:DWORD, tileCol:DWORD, tileRow:DWORD, tileChar:DWORD

    INVOKE FillBox, 110, 84, 580, 412, COL_RED_HI       ; border
    INVOKE FillBox, 114, 88, 572, 404, COL_RED_BG       ; panel

    ; Warning triangle: Polygon uses the selected brush and pen.
    INVOKE CreateSolidBrush, COL_YELLOW
    mov  ebx, eax
    INVOKE SelectObject, hBackDC, ebx
    mov  hOldBrush, eax
    INVOKE GetStockObject, NULL_PEN
    INVOKE SelectObject, hBackDC, eax
    mov  hOldPen, eax
    INVOKE Polygon, hBackDC, ADDR warnTriangle, 3
    INVOKE SelectObject, hBackDC, hOldPen
    INVOKE SelectObject, hBackDC, hOldBrush
    INVOKE DeleteObject, ebx
    INVOKE PutTextCentered, 400, 120, ADDR txtBang, COL_BLACK, hFontLarge

    ; Look up this crash's message: table base + index * 4 bytes per pointer.
    mov  esi, crashMsg
    mov  eax, crashHeads[esi*TYPE crashHeads]
    INVOKE PutTextCentered, 400, 166, eax, COL_WHITE, hFontLarge
    mov  eax, crashSubs[esi*TYPE crashSubs]
    INVOKE PutTextCentered, 400, 206, eax, COL_YELLOW, hFontMedium

    ; Work out which tile the path stopped on, for the fault report.
    mov  ecx, CELL_SIZE
    mov  eax, hitX
    cdq
    idiv ecx
    mov  tileCol, eax
    mov  eax, hitY
    sub  eax, HUD_H
    cdq
    idiv ecx
    mov  tileRow, eax
    INVOKE GetTileAtPixel, hitX, hitY
    mov  tileChar, eax

    INVOKE wsprintfA, ADDR textBuffer, ADDR fmtFault, hitX, hitY, tileCol, tileRow
    INVOKE PutTextCentered, 400, 238, ADDR textBuffer, COL_WHITE, hFontSmall

    ; The debugger box
    INVOKE FillBox, 134, 266, 532, 116, COL_BLACK
    INVOKE PutText, 146, 274, ADDR txtTrace0, COL_CYAN, hFontSmall
    INVOKE PutText, 146, 300, ADDR txtTrace1, COL_GREEN, hFontSmall
    cmp  crashMsg, LEFT_WINDOW_MSG  ; no wall was touched: explain the exit
    jne  WallTrace
    INVOKE PutText, 146, 324, ADDR txtCmpLeft, COL_GREEN, hFontSmall
    INVOKE PutText, 146, 348, ADDR txtTrace3Left, COL_RED_HI, hFontSmall
    jmp  TraceDone
WallTrace:
    INVOKE wsprintfA, ADDR textBuffer, ADDR fmtCmp, tileRow, tileCol, tileChar
    INVOKE PutText, 146, 324, ADDR textBuffer, COL_GREEN, hFontSmall
    INVOKE PutText, 146, 348, ADDR txtTrace3, COL_RED_HI, hFontSmall
TraceDone:

    INVOKE wsprintfA, ADDR textBuffer, ADDR fmtCrashes, crashCount
    INVOKE PutTextCentered, 400, 396, ADDR textBuffer, COL_WHITE, hFontMedium

    INVOKE DrawButton, ADDR btnPrimary, ADDR txtRetry, COL_GREEN
    INVOKE DrawButton, ADDR btnExit, ADDR txtExit, COL_RED_HI
    ret
ShowErrorScreen ENDP

;----------------------------------------------------------------------
; ShowLevelComplete - the green panel shown after reaching FINISH.
;----------------------------------------------------------------------
ShowLevelComplete PROC
    INVOKE FillBox, 110, 150, 580, 346, COL_GREEN
    INVOKE FillBox, 114, 154, 572, 338, COL_WON_BG
    INVOKE PutTextCentered, 400, 210, ADDR txtWonHead, COL_GREEN, hFontLarge
    INVOKE PutTextCentered, 400, 268, ADDR txtWonSub, COL_WHITE, hFontMedium
    INVOKE wsprintfA, ADDR textBuffer, ADDR fmtCrashes, crashCount
    INVOKE PutTextCentered, 400, 320, ADDR textBuffer, COL_WHITE, hFontMedium
    INVOKE DrawButton, ADDR btnPrimary, ADDR txtAgain, COL_GREEN
    INVOKE DrawButton, ADDR btnExit, ADDR txtExit, COL_RED_HI
    ret
ShowLevelComplete ENDP

;----------------------------------------------------------------------
; ReleaseGame - free every GDI object before the program exits.
;----------------------------------------------------------------------
ReleaseGame PROC
    INVOKE SelectObject, hBackDC, hOldBmp
    INVOKE DeleteObject, hBackBmp
    INVOKE DeleteDC, hBackDC
    INVOKE DeleteObject, hFontLarge
    INVOKE DeleteObject, hFontMedium
    INVOKE DeleteObject, hFontSmall
    ret
ReleaseGame ENDP

;======================================================================
; WINDOW PROCEDURE - Windows calls this for every message to our window.
;======================================================================
WndProc PROC hWin:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL ps:PAINTSTRUCT, hdcPaint:DWORD

    mov  eax, uMsg
    cmp  eax, WM_MOUSEMOVE
    je   OnMouseMove
    cmp  eax, WM_LBUTTONDOWN
    je   OnClick
    cmp  eax, WM_MOUSELEAVE
    je   OnMouseLeave
    cmp  eax, WM_KEYDOWN
    je   OnKey
    cmp  eax, WM_ACTIVATEAPP
    je   OnActivate
    cmp  eax, WM_PAINT
    je   OnPaint
    cmp  eax, WM_ERASEBKGND
    je   OnErase
    cmp  eax, WM_DESTROY
    je   OnDestroy
    INVOKE DefWindowProcA, hWin, uMsg, wParam, lParam
    ret

OnMouseMove:
    ; lParam: low word = X, high word = Y. They are signed, because they can
    ; be negative when the mouse is captured or moves off the client area.
    movsx eax, WORD PTR lParam
    movsx edx, WORD PTR lParam+2
    INVOKE HandleMouseMove, eax, edx
    jmp  Handled

OnClick:
    movsx eax, WORD PTR lParam
    movsx edx, WORD PTR lParam+2
    INVOKE HandleClick, eax, edx
    jmp  Handled

OnMouseLeave:
    ; Leaving the window during a run counts as a crash, otherwise the player
    ; could go around a wall. hitX and hitY hold the last point tested.
    cmp  gameState, STATE_PLAY
    jne  Handled
    mov  crashMsg, LEFT_WINDOW_MSG
    INVOKE EnterCrash
    jmp  Handled

OnKey:
    cmp  wParam, VK_ESCAPE
    jne  Handled
    cmp  gameState, STATE_PLAY
    je   AbortRun
    INVOKE DestroyWindow, hWin      ; Esc on any other screen exits
    jmp  Handled
AbortRun:
    INVOKE RestartLevel             ; Esc mid-run cancels without a crash
    jmp  Handled

OnActivate:
    ; Alt-Tab during a run cancels it, again without a crash. The player must
    ; click START again, so switching away can't be used to skip walls.
    cmp  wParam, 0
    jne  Handled
    cmp  gameState, STATE_PLAY
    jne  Handled
    INVOKE RestartLevel
    jmp  Handled

OnPaint:
    INVOKE BeginPaint, hWin, ADDR ps
    mov  hdcPaint, eax
    INVOKE BitBlt, hdcPaint, 0, 0, WINDOW_W, WINDOW_H, hBackDC, 0, 0, SRCCOPY
    INVOKE EndPaint, hWin, ADDR ps
    jmp  Handled

OnErase:
    mov  eax, 1                     ; "already erased": WM_PAINT covers it all
    ret

OnDestroy:
    INVOKE ReleaseGame
    INVOKE PostQuitMessage, 0

Handled:
    xor  eax, eax
    ret
WndProc ENDP

END main
