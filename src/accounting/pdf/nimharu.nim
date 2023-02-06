when defined(Windows):
  const libName* = "libhpdf.dll"
elif defined(Linux):
  const libName* = "libhpdf.so"
elif defined(MacOsX):
  const libName* = "libhpdf.dylib"

type
    PageSize* = enum
        A4 = 3
    PageOrientation* = enum
        Portrait, Landscape

type
    HPDF_OBJECT* = object
    Status* = culong
    Real* = cfloat
    DocHandle* = ptr HPDF_OBJECT
    PageHandle* = ptr HPDF_OBJECT
    FontHandle* = ptr HPDF_OBJECT
    UserData* = ptr HPDF_OBJECT
    ErrorHandler* = proc(error_no: clong, detail_no: clong, user_data: UserData): void


proc new*(user_error_fn: ErrorHandler, user_data: UserData): DocHandle {.importc:  "HPDF_New", dynlib: libName.}

proc getFont*(pdf: DocHandle, font_name: cstring, encoding_name: cstring): FontHandle {.importc: "HPDF_GetFont", dynlib: libName.}
proc addPage*(pdf: DocHandle): PageHandle {.importc: "HPDF_AddPage", dynlib: libName.}
proc saveToFile*(pdf: DocHandle, fname: cstring): void {.importc: "HPDF_SaveToFile", dynlib: libName.}
proc free*(pdf: DocHandle): void {.importc: "HPDF_Free", dynlib: libName.} 

proc setSize*(page: PageHandle, size: PageSize, orientation: PageOrientation): void {.importc: "HPDF_Page_SetSize", dynlib: libName.}
proc getWidth*(page: PageHandle): cfloat {.importc: "HPDF_Page_GetWidth", dynlib: libName.}
proc getHeight*(page: PageHandle): cfloat {.importc: "HPDF_Page_GetHeight", dynlib: libName.}
proc getTextWidth*(page: PageHandle, text: cstring): cfloat {.importc: "HPDF_Page_TextWidth", dynlib: libName.}
proc setFontAndSize*(page: PageHandle, font: FontHandle, size: cfloat): void {.importc: "HPDF_Page_SetFontAndSize", dynlib: libName.}
proc beginText*(page: PageHandle): Status {.importc: "HPDF_Page_BeginText", dynlib: libName, discardable.}
proc moveTextPos*(page: PageHandle, x: Real, y: Real): Status {.importc: "HPDF_Page_MoveTextPos", dynlib: libName, discardable.}
proc textOut*(page: PageHandle, xPos: Real, yPos: Real, text: cstring): Status {.importc: "HPDF_Page_TextOut", dynlib: libName, discardable.}
proc showText*(page: PageHandle, text: cstring): Status {.importc: "HPDF_Page_ShowText", dynlib: libName, discardable.}
proc endText*(page: PageHandle): Status {.importc: "HPDF_Page_EndText", dynlib: libName, discardable.}
proc moveTo*(page: PageHandle, x: Real, y: Real): Status {.importc: "HPDF_Page_MoveTo", dynlib: libName, discardable.}
proc lineTo*(page: PageHandle, x: Real, y: Real): Status {.importc: "HPDF_Page_LineTo", dynlib: libName, discardable.}
proc stroke*(page: PageHandle): Status {.importc: "HPDF_Page_Stroke", dynlib: libName, discardable.}