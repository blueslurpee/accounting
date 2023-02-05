when defined(Windows):
  const libName* = "libhpdf.dll"
elif defined(Linux):
  const libName* = "libhpdf.so"
elif defined(MacOsX):
  const libName* = "libhpdf.dylib"

type
    PageSize = enum
        A4 = 3
    PageOrientation = enum
        Portrait, Landscape

type
    HPDF_OBJECT = object
    Status* = culong
    Real* = cfloat
    DocHandle* = ptr HPDF_OBJECT
    PageHandle* = ptr HPDF_OBJECT
    FontHandle* = ptr HPDF_OBJECT
    UserData* = ptr HPDF_OBJECT
    ErrorHandler* = proc(error_no: clong, detail_no: clong, user_data: UserData): void


proc new(user_error_fn: ErrorHandler, user_data: UserData): DocHandle {.importc:  "HPDF_New", dynlib: libName.}
proc getFont(pdf: DocHandle, font_name: cstring, encoding_name: cstring): FontHandle {.importc: "HPDF_GetFont", dynlib: libName.}
proc addPage(pdf: DocHandle): PageHandle {.importc: "HPDF_AddPage", dynlib: libName.}
proc saveToFile(pdf: DocHandle, fname: cstring): void {.importc: "HPDF_SaveToFile", dynlib: libName.}
proc free(pdf: DocHandle): void {.importc: "HPDF_Free", dynlib: libName.} 

proc setSize(page: PageHandle, size: PageSize, orientation: PageOrientation): void {.importc: "HPDF_Page_SetSize", dynlib: libName.}
proc getWidth(page: PageHandle): cfloat {.importc: "HPDF_Page_GetWidth", dynlib: libName.}
proc getHeight(page: PageHandle): cfloat {.importc: "HPDF_Page_GetHeight", dynlib: libName.}
proc getTextWidth(page: PageHandle, text: cstring): cfloat {.importc: "HPDF_Page_TextWidth", dynlib: libName.}
proc setFontAndSize(page: PageHandle, font: FontHandle, size: cfloat): void {.importc: "HPDF_Page_SetFontAndSize", dynlib: libName.}
proc beginText(page: PageHandle): Status {.importc: "HPDF_Page_BeginText", dynlib: libName, discardable.}
proc moveTextPos(page: PageHandle, x: Real, y: Real): Status {.importc: "HPDF_Page_MoveTextPos", dynlib: libName, discardable.}
proc textOut(page: PageHandle, xPos: Real, yPos: Real, text: cstring): Status {.importc: "HPDF_Page_TextOut", dynlib: libName, discardable.}
proc showText(page: PageHandle, text: cstring): Status {.importc: "HPDF_Page_ShowText", dynlib: libName, discardable.}
proc endText(page: PageHandle): Status {.importc: "HPDF_Page_EndText", dynlib: libName, discardable.}
proc moveTo(page: PageHandle, x: Real, y: Real): Status {.importc: "HPDF_Page_MoveTo", dynlib: libName, discardable.}
proc lineTo(page: PageHandle, x: Real, y: Real): Status {.importc: "HPDF_Page_LineTo", dynlib: libName, discardable.}
proc stroke(page: PageHandle): Status {.importc: "HPDF_Page_Stroke", dynlib: libName, discardable.}

# Implementation

const PAGE_TITLE = "ACME HOLDINGS LLC"
const PAGE_SUBTITLE = "CONSOLIDATED EXPENSE REPORT - FISCAL YEAR 2022"
const MARGIN: Real = 60
const DATE_OFFSET: Real = 60
const EXPENSE_OFFSET: Real = 120;
const ACCOUNT_OFFSET: Real = 240;
const CURRENCY_OFFSET: Real = 400;

const dates: seq[cstring] = @[
    "2022-02-17",
    "2022-02-18",
    "2022-02-19",
]
const expenseNames: seq[cstring] = @[
    "METRO January",
    "CSSA Expenses",
    "GCP Cloud Servers"
]
const accountNames: seq[cstring] = @[
    "Transportation",
    "Education",
    "Cloud Services",
]
const currencies: seq[cstring] = @[
    "USD",
    "USD",
    "CHF",
]
const amounts: seq[cstring] = @[
    "32.33",
    "438.21",
    "3.57",
]


proc writeTitle(pdf: DocHandle, page: PageHandle, pageTitle: cstring, pageSubtitle: cstring, y: cfloat) = 
    let pageWidth = page.getWidth()
    var font = pdf.getFont("Helvetica-Bold", nil)
    page.setFontAndSize(font, 10)

    let titleWidth = page.getTextWidth(pageTitle)
    page.beginText()
    page.textOut((pageWidth - titleWidth) / 2, y, pageTitle)
    page.endText()

    font = pdf.getFont("Helvetica", nil)
    page.setFontAndSize(font, 9)

    let subtitleWidth = page.getTextWidth(pageSubtitle)
    let delta = subtitleWidth - titleWidth
    page.beginText()
    page.textOut(((pageWidth - titleWidth) / 2) - (delta / 2), y - 10, pageSubtitle)
    page.endText()


proc writeTableHeaders(pdf: DocHandle, page: PageHandle, y: cfloat) = 
    let pageWidth = page.getWidth()

    # Set font
    let font = pdf.getFont("Helvetica", nil)
    page.setFontAndSize(font, 8)

    # Headers
    page.beginText()
    page.moveTextPos(DATE_OFFSET, y)
    page.showText("DATE")
    page.endText()
    
    page.beginText()
    page.moveTextPos(EXPENSE_OFFSET, y)
    page.showText("EXPENSE")
    page.endText()

    page.beginText()
    page.moveTextPos(ACCOUNT_OFFSET, y)
    page.showText("ACCOUNT")
    page.endText()

    page.beginText()
    page.moveTextPos(CURRENCY_OFFSET, y)
    page.showText("CURRENCY")
    page.endText()

    # Right justified
    let textWidth = page.getTextWidth("AMOUNT")
    page.beginText()
    page.moveTextPos(pageWidth - MARGIN - textWidth, y)
    page.showText("AMOUNT")
    page.endText()

    # Underline
    page.moveTo(MARGIN, y - 4)
    page.lineTo(pageWidth - MARGIN, y - 4)
    page.stroke()


proc writeColumn(pdf: DocHandle, page: PageHandle, entries: seq[cstring], offset: Real, y: Real) = 
    let font = pdf.getFont("Helvetica", nil)

    page.setFontAndSize(font, 8)
    page.beginText()
    page.moveTextPos(offset, y)

    for entry in entries:
        page.showText(entry)
        page.moveTextPos(0, -10)
    
    page.endText()


proc writeRightJustifiedColumn(pdf: DocHandle, page: PageHandle, entries: seq[cstring], targetX: Real, y: Real) = 
    let font = pdf.getFont("Helvetica", nil)

    page.setFontAndSize(font, 8)

    for i, entry in entries.pairs:
        let textWidth = page.getTextWidth(entry)

        page.beginText()
        page.moveTextPos(targetX - textWidth, y - (cfloat(i) * 10))
        page.showText(entry)
        page.endText()


if isMainModule:
    proc handle_error(error_no: clong, detail_no: clong, user_data: UserData) = 
        discard

    let error_handler: ErrorHandler = handle_error
    let user_data: HPDF_OBJECT = HPDF_OBJECT()

    let pdf: DocHandle = new(error_handler, addr user_data)
    let page: PageHandle = pdf.addPage()
    
    page.setSize(PageSize.A4, PageOrientation.Portrait)

    let width = page.getWidth()
    let height = page.getHeight()
    let columnStart = height - 116

    pdf.writeTitle(page, PAGE_TITLE, PAGE_SUBTITLE, height - 50)
    pdf.writeTableHeaders(page, height - 100)
    pdf.writeColumn(page, dates, DATE_OFFSET, columnStart)
    pdf.writeColumn(page, expenseNames, EXPENSE_OFFSET, columnStart)
    pdf.writeColumn(page, accountNames, ACCOUNT_OFFSET, columnStart)
    pdf.writeColumn(page, currencies, CURRENCY_OFFSET, columnStart)
    pdf.writeRightJustifiedColumn(page, amounts, width - MARGIN, columnStart)

    pdf.saveToFile("test.pdf")
    pdf.free()

    echo "Success"