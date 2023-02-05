/*
 * << Haru Free PDF Library 2.0.0 >> -- font_demo.c
 *
 * Copyright (c) 1999-2006 Takeshi Kanno <takeshi_kanno@est.hi-ho.ne.jp>
 *
 * Permission to use, copy, modify, distribute and sell this software
 * and its documentation for any purpose is hereby granted without fee,
 * provided that the above copyright notice appear in all copies and
 * that both that copyright notice and this permission notice appear
 * in supporting documentation.
 * It is provided "as is" without express or implied warranty.
 *
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
#include "hpdf.h"

jmp_buf env;

#ifdef HPDF_DLL
void __stdcall
#else
void
#endif

    error_handler(HPDF_STATUS error_no,
                  HPDF_STATUS detail_no,
                  void *user_data)
{
    printf("ERROR: error_no=%04X, detail_no=%u\n",
           (HPDF_UINT)error_no,
           (HPDF_UINT)detail_no);
    longjmp(env, 1);
}

const char *dates[] = {
    "2022-02-16",
    "2022-02-17",
    "2022-02-18",
    NULL};

const char *expense_names[] = {
    "\"GA January\"",
    "\"ICU Expenses\"",
    "\"GCP Servers\"",
    NULL};

const char *account_names[] = {
    "Transportation",
    "Education",
    "Cloud Services",
    NULL};

const char *currencies[] = {
    "USD",
    "USD",
    "CHF",
    NULL};

const char *amounts[] = {
    "32.33",
    "438.21",
    "3.57",
    NULL};

const HPDF_REAL MARGIN = 60;
const HPDF_REAL DATE_OFFSET = 60;
const HPDF_REAL EXPENSE_OFFSET = 120;
const HPDF_REAL ACCOUNT_OFFSET = 240;
const HPDF_REAL CURRENCY_OFFSET = 400;

void write_title(HPDF_Doc pdf, HPDF_Page page, char *page_title, char *page_subtitle, float y)
{
    HPDF_REAL page_width = HPDF_Page_GetWidth(page);

    /* Title */
    HPDF_Font font = HPDF_GetFont(pdf, "Helvetica-Bold", NULL);
    HPDF_Page_SetFontAndSize(page, font, 10);
    HPDF_REAL tw = HPDF_Page_TextWidth(page, page_title);

    HPDF_Page_BeginText(page);
    HPDF_Page_TextOut(page, (page_width - tw) / 2, y, page_title);
    HPDF_Page_EndText(page);

    /* Subtitle */
    font = HPDF_GetFont(pdf, "Helvetica", NULL);
    HPDF_Page_SetFontAndSize(page, font, 9);
    HPDF_REAL stw = HPDF_Page_TextWidth(page, page_subtitle);
    HPDF_REAL d = stw - tw;

    HPDF_Page_BeginText(page);
    HPDF_Page_TextOut(page, ((page_width - tw) / 2) - (d / 2), y - 10, page_subtitle);
    HPDF_Page_EndText(page);
}

void write_table_headers(HPDF_Doc pdf, HPDF_Page page, float y)
{
    HPDF_REAL page_width = HPDF_Page_GetWidth(page);

    // Set font
    HPDF_Font font = HPDF_GetFont(pdf, "Helvetica", NULL);
    HPDF_Page_SetFontAndSize(page, font, 8);

    // Headers
    HPDF_Page_BeginText(page);
    HPDF_Page_MoveTextPos(page, DATE_OFFSET, y);
    HPDF_Page_ShowText(page, "DATE");
    HPDF_Page_EndText(page);

    HPDF_Page_BeginText(page);
    HPDF_Page_MoveTextPos(page, EXPENSE_OFFSET, y);
    HPDF_Page_ShowText(page, "EXPENSE");
    HPDF_Page_EndText(page);

    HPDF_Page_BeginText(page);
    HPDF_Page_MoveTextPos(page, ACCOUNT_OFFSET, y);
    HPDF_Page_ShowText(page, "ACCOUNT");
    HPDF_Page_EndText(page);

    HPDF_Page_BeginText(page);
    HPDF_Page_MoveTextPos(page, CURRENCY_OFFSET, y);
    HPDF_Page_ShowText(page, "CURRENCY");
    HPDF_Page_EndText(page);

    // Right justified
    HPDF_REAL text_width = HPDF_Page_TextWidth(page, "AMOUNT");
    HPDF_Page_BeginText(page);
    HPDF_Page_MoveTextPos(page, page_width - MARGIN - text_width, y);
    HPDF_Page_ShowText(page, "AMOUNT");
    HPDF_Page_EndText(page);

    // Underline
    HPDF_Page_MoveTo(page, MARGIN, y - 4);
    HPDF_Page_LineTo(page, page_width - MARGIN, y - 4);
    HPDF_Page_Stroke(page);
}

void write_column(HPDF_Doc pdf, HPDF_Page page, char **entries, HPDF_REAL offset, HPDF_REAL y)
{
    char *text_buffer;
    HPDF_Font font = HPDF_GetFont(pdf, "Helvetica", NULL);

    HPDF_Page_SetFontAndSize(page, font, 8);
    HPDF_Page_BeginText(page);
    HPDF_Page_MoveTextPos(page, offset, y);

    HPDF_UINT i = 0;
    while (entries[i])
    {
        text_buffer = entries[i];
        HPDF_Page_ShowText(page, text_buffer);
        HPDF_Page_MoveTextPos(page, 0, -10);

        i++;
    }

    HPDF_Page_EndText(page);
}

void write_right_justified_column(HPDF_Doc pdf, HPDF_Page page, char **entries, HPDF_REAL target_x, HPDF_REAL y)
{
    char *text_buffer;
    HPDF_Font font = HPDF_GetFont(pdf, "Helvetica", NULL);
    HPDF_Page_SetFontAndSize(page, font, 8);

    HPDF_UINT i = 0;
    while (entries[i])
    {
        text_buffer = entries[i];
        HPDF_REAL text_width = HPDF_Page_TextWidth(page, text_buffer);

        HPDF_Page_BeginText(page);
        HPDF_Page_MoveTextPos(page, target_x - text_width, y - (i * 10));
        HPDF_Page_ShowText(page, text_buffer);
        HPDF_Page_EndText(page);

        i++;
    }
}

int main(int argc, char **argv)
{
    HPDF_Doc pdf;
    HPDF_Page page;
    HPDF_REAL width;
    HPDF_REAL height;

    const char *page_title = "ACME HOLDINGS LLC";
    const char *page_subtitle = "CONSOLIDATED EXPENSE REPORT - FISCAL YEAR 2022";
    char fname[256];

    strcpy(fname, argv[0]);
    strcat(fname, ".pdf");

    pdf = HPDF_New(error_handler, NULL);
    if (!pdf)
    {
        printf("error: cannot create PdfDoc object\n");
        return 1;
    }

    if (setjmp(env))
    {
        HPDF_Free(pdf);
        return 1;
    }

    /* Initialise page */
    page = HPDF_AddPage(pdf);
    HPDF_Page_SetSize(page, HPDF_PAGE_SIZE_A4, HPDF_PAGE_PORTRAIT);

    width = HPDF_Page_GetWidth(page);
    height = HPDF_Page_GetHeight(page);

    /* Title & subtitle */
    write_title(pdf, page, page_title, page_subtitle, height - 50);

    /* Table headers */
    write_table_headers(pdf, page, height - 100);

    /* Output records */
    HPDF_REAL column_start = height - 116;
    write_column(pdf, page, dates, DATE_OFFSET, column_start);
    write_column(pdf, page, expense_names, EXPENSE_OFFSET, column_start);
    write_column(pdf, page, account_names, ACCOUNT_OFFSET, column_start);
    write_column(pdf, page, currencies, CURRENCY_OFFSET, column_start);
    write_right_justified_column(pdf, page, amounts, width - MARGIN, column_start);

    /* Save & clean up*/
    HPDF_SaveToFile(pdf, fname);
    HPDF_Free(pdf);

    return 0;
}