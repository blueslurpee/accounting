import std/[times, math, strformat]
import decimal/decimal

import nimharu
import ../types
import ../account

const MARGIN: Real = 60
const DATE_OFFSET: Real = 60
const EXPENSE_OFFSET: Real = 120;
const ACCOUNT_OFFSET: Real = 240;
const CURRENCY_OFFSET: Real = 400;
const ENTRIES_PER_PAGE = 67

proc writeTitle(pdf: DocHandle, page: PageHandle, pageTitle: string, pageSubtitle: string, y: cfloat) = 
    let pageTitle = cstring(pageTitle)
    let pageSubtitle = cstring(pageSubtitle)
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


proc writeColumn(pdf: DocHandle, page: PageHandle, entries: seq[string], offset: Real, y: Real) = 
    let font = pdf.getFont("Helvetica", nil)

    page.setFontAndSize(font, 8)
    page.beginText()
    page.moveTextPos(offset, y)

    for index, entry in entries.pairs:
        page.showText(cstring(entry))
        page.moveTextPos(0, -10)
    
    page.endText()


proc writeRightJustifiedColumn(pdf: DocHandle, page: PageHandle, entries: seq[string], targetX: Real, y: Real) = 
    let font = pdf.getFont("Helvetica", nil)

    page.setFontAndSize(font, 8)

    for i, entry in entries.pairs:
        let textWidth = page.getTextWidth(cstring(entry))

        page.beginText()
        page.moveTextPos(targetX - textWidth, y - (cfloat(i) * 10))
        page.showText(cstring(entry))
        page.endText()


proc generateExpenseReport*(ledger: Ledger, filename: string) = 
    let filenameWithSuffix: string = filename & ".pdf"

    var i = 0
    var dates: seq[seq[string]] = @[]
    var expenseNames: seq[seq[string]] = @[]
    var accountNames: seq[seq[string]] = @[]
    var currencies: seq[seq[string]] = @[]
    var amounts: seq[seq[string]] = @[]
    var total: DecimalType = newDecimal("0.00")

    for transaction in ledger.transactions:
        for record in transaction.records:
            if record.kind == AccountKind.Expense:
                let lIndex = floor(i / ENTRIES_PER_PAGE).toInt

                if i mod ENTRIES_PER_PAGE == 0:
                    dates.add(@[transaction.date.format("yyyy-MM-dd")])
                    expenseNames.add(@[transaction.payee])
                    accountNames.add(@[record.accountKey.trimKey(1)])
                    currencies.add(@[record.convertedCurrencyKey])
                    amounts.add(@[record.convertedAmount.toAccountingString])
                    total += record.convertedAmount
                else:
                    dates[lIndex].add(transaction.date.format("yyyy-MM-dd"))
                    expenseNames[lIndex].add(transaction.payee)
                    accountNames[lIndex].add(record.accountKey.trimKey(1))
                    currencies[lIndex].add(record.convertedCurrencyKey)
                    amounts[lIndex].add(record.convertedAmount.toAccountingString)
                    total += record.convertedAmount

                i += 1

    # zero-indexed
    let pageNumber = dates.len - 1
    
    proc handle_error(error_no: clong, detail_no: clong, user_data: UserData) = 
        discard

    let error_handler: ErrorHandler = handle_error
    let user_data: HPDF_OBJECT = HPDF_OBJECT()
    let pdf: DocHandle = new(error_handler, addr user_data)

    for i in countup(0, pageNumber):
        let page: PageHandle = pdf.addPage()
        page.setSize(PageSize.A4, PageOrientation.Portrait)
    
        let width = page.getWidth()
        let height = page.getHeight()
        let columnStart = if i == 0: height - 116 else: height - 50
        
        if i == 0:
            pdf.writeTitle(page, ledger.entity, &"CONSOLIDATED EXPENSE REPORT - FISCAL YEAR {$ledger.fiscalYear}", height - 50)
            pdf.writeTableHeaders(page, height - 100)

        let dateSeq = dates[i]
        let expenseNameSeq = expenseNames[i]
        let accountNameSeq = accountNames[i]
        let currencySeq = currencies[i]
        let amountSeq = amounts[i]

        let pageRecordAmount = dateSeq.len

        pdf.writeColumn(page, dateSeq, DATE_OFFSET, columnStart)
        pdf.writeColumn(page, expenseNameSeq, EXPENSE_OFFSET, columnStart)
        pdf.writeColumn(page, accountNameSeq, ACCOUNT_OFFSET, columnStart)
        pdf.writeColumn(page, currencySeq, CURRENCY_OFFSET, columnStart)
        pdf.writeRightJustifiedColumn(page, amountSeq, width - MARGIN, columnStart)

        if i == pageNumber:
            # Underline
            let lineY = columnStart - ((pageRecordAmount - 1) * 10).toFloat
            page.moveTo(MARGIN, lineY - 4)
            page.lineTo(width - MARGIN, lineY - 4)
            page.stroke()

            let font = pdf.getFont("Helvetica-Bold", nil)
            page.setFontAndSize(font, 8)

            let totalText = "Total: " & total.toAccountingString
            let textWidth = page.getTextWidth(cstring(totalText))
            let totalY = columnStart - ((pageRecordAmount * 10) + 4).toFloat

            page.beginText()
            page.moveTextPos(width - MARGIN - textWidth, totalY)
            page.showText(cstring(totalText))            
            page.endText()
            
            # TODO: add logic if the last page were completely filled and a new page were needed



    pdf.saveToFile(cstring(filenameWithSuffix))
    pdf.free()