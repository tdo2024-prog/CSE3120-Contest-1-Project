; win32.inc - The small slice of the Windows API this game needs.
; Written by hand (no windows.h, no MASM32) so that every constant,
; structure and prototype the game depends on can be read in one place.
; All functions use the STDCALL convention except wsprintfA (C / variable args).

;----------------------------- Structures -----------------------------
POINT STRUCT
    ptX     SDWORD ?
    ptY     SDWORD ?
POINT ENDS

RECT STRUCT
    left    SDWORD ?
    top     SDWORD ?
    right   SDWORD ?
    bottom  SDWORD ?
RECT ENDS

MSG STRUCT
    hwnd    DWORD ?
    message DWORD ?
    wParam  DWORD ?
    lParam  DWORD ?
    time    DWORD ?
    pt      POINT <>
MSG ENDS

WNDCLASSEXA STRUCT
    cbSize        DWORD ?
    style         DWORD ?
    lpfnWndProc   DWORD ?
    cbClsExtra    DWORD ?
    cbWndExtra    DWORD ?
    hInstance     DWORD ?
    hIcon         DWORD ?
    hCursor       DWORD ?
    hbrBackground DWORD ?
    lpszMenuName  DWORD ?
    lpszClassName DWORD ?
    hIconSm       DWORD ?
WNDCLASSEXA ENDS

PAINTSTRUCT STRUCT
    hdc         DWORD ?
    fErase      DWORD ?
    rcPaint     RECT <>
    fRestore    DWORD ?
    fIncUpdate  DWORD ?
    rgbReserved BYTE 32 DUP(?)
PAINTSTRUCT ENDS

TRACKMOUSEEVENT STRUCT
    cbSize      DWORD ?
    dwFlags     DWORD ?
    hwndTrack   DWORD ?
    dwHoverTime DWORD ?
TRACKMOUSEEVENT ENDS

;----------------------------- Constants ------------------------------
; Window messages
WM_DESTROY      EQU 0002h
WM_PAINT        EQU 000Fh
WM_ERASEBKGND   EQU 0014h
WM_ACTIVATEAPP  EQU 001Ch
WM_KEYDOWN      EQU 0100h
WM_MOUSEMOVE    EQU 0200h
WM_LBUTTONDOWN  EQU 0201h
WM_MOUSELEAVE   EQU 02A3h

; Window styles and creation
WS_OVERLAPPED   EQU 00000000h
WS_CAPTION      EQU 00C00000h
WS_SYSMENU      EQU 00080000h
WS_MINIMIZEBOX  EQU 00020000h
CW_USEDEFAULT   EQU 80000000h
CS_HREDRAW      EQU 0002h
CS_VREDRAW      EQU 0001h
SW_SHOWNORMAL   EQU 1
SM_CXSCREEN     EQU 0
SM_CYSCREEN     EQU 1

; Cursor, keys, mouse tracking
IDC_CROSS       EQU 32515
IDI_APPLICATION EQU 32512
VK_ESCAPE       EQU 1Bh
TME_LEAVE       EQU 00000002h

; GDI
TRANSPARENT_BK  EQU 1
TA_LEFT         EQU 0
TA_CENTER       EQU 6
SRCCOPY         EQU 00CC0020h
NULL_PEN        EQU 8
FW_NORMAL       EQU 400
FW_BOLD         EQU 700
FIXED_PITCH_MODERN EQU 31h          ; FIXED_PITCH OR FF_MODERN

;----------------------------- kernel32 -------------------------------
ExitProcess      PROTO :DWORD
FreeConsole      PROTO
GetModuleHandleA PROTO :DWORD
lstrlenA         PROTO :DWORD

;------------------------------ user32 --------------------------------
AdjustWindowRect  PROTO :DWORD, :DWORD, :DWORD
BeginPaint        PROTO :DWORD, :DWORD
CreateWindowExA   PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, \
                        :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
DefWindowProcA    PROTO :DWORD, :DWORD, :DWORD, :DWORD
DestroyWindow     PROTO :DWORD
DispatchMessageA  PROTO :DWORD
EndPaint          PROTO :DWORD, :DWORD
FillRect          PROTO :DWORD, :DWORD, :DWORD
GetDC             PROTO :DWORD
GetMessageA       PROTO :DWORD, :DWORD, :DWORD, :DWORD
GetSystemMetrics  PROTO :DWORD
InvalidateRect    PROTO :DWORD, :DWORD, :DWORD
LoadCursorA       PROTO :DWORD, :DWORD
LoadIconA         PROTO :DWORD, :DWORD
PostQuitMessage   PROTO :DWORD
RegisterClassExA  PROTO :DWORD
ReleaseDC         PROTO :DWORD, :DWORD
SetProcessDPIAware PROTO
ShowWindow        PROTO :DWORD, :DWORD
TrackMouseEvent   PROTO :DWORD
TranslateMessage  PROTO :DWORD
UpdateWindow      PROTO :DWORD
wsprintfA         PROTO C :DWORD, :DWORD, :VARARG

;------------------------------- gdi32 --------------------------------
BitBlt            PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, \
                        :DWORD, :DWORD, :DWORD, :DWORD
CreateCompatibleBitmap PROTO :DWORD, :DWORD, :DWORD
CreateCompatibleDC PROTO :DWORD
CreateFontA       PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, \
                        :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
CreateSolidBrush  PROTO :DWORD
DeleteDC          PROTO :DWORD
DeleteObject      PROTO :DWORD
GetStockObject    PROTO :DWORD
Polygon           PROTO :DWORD, :DWORD, :DWORD
SelectObject      PROTO :DWORD, :DWORD
SetBkMode         PROTO :DWORD, :DWORD
SetTextAlign      PROTO :DWORD, :DWORD
SetTextColor      PROTO :DWORD, :DWORD
TextOutA          PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
