#!/usr/bin/env python3
"""One-off builder for the SFE validation PDF. Run from anywhere."""

from reportlab.lib.colors import Color, white, black
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Image,
    Table,
    TableStyle,
    PageBreak,
    KeepTogether,
    ListFlowable,
    ListItem,
)

OUT = "/Users/ashrafrezk/Salesforce Projects/Zeta Pharma/ph/Plan/SFE_Admin_Console_Validation.pdf"
SHOTS = "/Users/ashrafrezk/Salesforce Projects/Zeta Pharma/ph/Plan/sfe-validation-shots"

TEAL = Color(11 / 255, 79 / 255, 108 / 255)
TEAL_SOFT = Color(232 / 255, 241 / 255, 245 / 255)
RULE = Color(210 / 255, 218 / 255, 224 / 255)
MUTED = Color(70 / 255, 80 / 255, 90 / 255)


def header_footer(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(white)
    canvas.rect(0, 0, A4[0], A4[1], fill=1, stroke=0)
    canvas.setFillColor(TEAL)
    canvas.rect(0, A4[1] - 16 * mm, A4[0], 16 * mm, fill=1, stroke=0)
    canvas.setFillColor(white)
    canvas.setFont("Times-Bold", 9)
    canvas.drawString(16 * mm, A4[1] - 10 * mm, "Zeta Pharma  ·  SFE validation pack")
    canvas.setFont("Times-Roman", 9)
    canvas.drawRightString(A4[0] - 16 * mm, A4[1] - 10 * mm, "15 October 2026")
    canvas.setFillColor(MUTED)
    canvas.setFont("Times-Roman", 8)
    canvas.drawString(16 * mm, 8 * mm, "zetapharma.my.salesforce.com")
    canvas.drawRightString(A4[0] - 16 * mm, 8 * mm, str(doc.page))
    canvas.restoreState()


def build():
    styles = getSampleStyleSheet()
    h1 = ParagraphStyle(
        "h1",
        parent=styles["Heading1"],
        fontName="Times-Bold",
        fontSize=18,
        leading=22,
        textColor=TEAL,
        spaceAfter=6,
        spaceBefore=0,
    )
    h2 = ParagraphStyle(
        "h2",
        parent=styles["Heading2"],
        fontName="Times-Bold",
        fontSize=13,
        leading=16,
        textColor=TEAL,
        spaceBefore=10,
        spaceAfter=4,
    )
    body = ParagraphStyle(
        "body",
        parent=styles["Normal"],
        fontName="Times-Roman",
        fontSize=10.5,
        leading=14,
        textColor=black,
        spaceAfter=6,
    )
    small = ParagraphStyle(
        "small",
        parent=body,
        fontSize=9,
        leading=12,
        textColor=MUTED,
    )
    cell = ParagraphStyle(
        "cell",
        parent=body,
        fontSize=8.5,
        leading=11,
        spaceAfter=0,
    )
    cell_b = ParagraphStyle(
        "cellb",
        parent=cell,
        fontName="Times-Bold",
        textColor=white,
    )
    caption = ParagraphStyle(
        "cap",
        parent=small,
        fontName="Times-Italic",
        spaceBefore=2,
        spaceAfter=8,
    )

    story = []
    story.append(Paragraph("Sign in and check the Admin Console", h1))
    story.append(
        Paragraph(
            "This pack is for the SFE and CRM team. It shows what is in the Zeta Pharma org today, how to sign in, and which screens to open. Screenshots were taken on 15 October 2026 in Field Co-pilot.",
            body,
        )
    )

    story.append(Paragraph("How to sign in", h2))
    story.append(
        Paragraph(
            "Open <b>https://zetapharma.my.salesforce.com</b>. The username is the business email. The password is the first word of the English name, letters only, followed by <b>@2026!</b>. Example: Mayar Ashraf Mohamed Ibrahim signs in as mayar.ashraf@zeta-pharma.com with Mayar@2026!.",
            body,
        )
    )
    story.append(
        Paragraph(
            "After sign-in, open the app launcher and choose <b>Field Co-pilot</b>. Click <b>Admin Console</b>. The six SFE and CRM people below already have System Administrator access, so the console opens for them.",
            body,
        )
    )

    headers = [
        Paragraph(h, cell_b) for h in ["Name", "Title", "Username", "Password"]
    ]
    sfe_rows = [
        ["Ahmed Abdullah ElShahat", "SFE Manager", "ahmed.abdullah@zeta-pharma.com", "Ahmed@2026!"],
        ["Ahmed Mohamed Hamid", "Business Excellence Manager", "ahmed.hamid@zeta-pharma.com", "Ahmed@2026!"],
        ["Aya Adel Abdelwahab", "Senior Analyst CRM", "aya.adel@zeta-pharma.com", "Aya@2026!"],
        ["David Ayman Badie", "CRM &amp; SFE Specialist", "david.badie@zeta-pharma.com", "David@2026!"],
        ["Hamsa DiaaElDin Sayed", "CRM &amp; SFE Specialist", "hamsa.diaaeldin@zeta-pharma.com", "Hamsa@2026!"],
        ["Manar Saleh Aly", "CRM Specialist", "manar.saleh@zeta-pharma.com", "Manar@2026!"],
    ]
    data = [headers]
    for row in sfe_rows:
        data.append([Paragraph(col, cell) for col in row])
    table = Table(data, colWidths=[42 * mm, 42 * mm, 62 * mm, 32 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), TEAL),
                ("TEXTCOLOR", (0, 0), (-1, 0), white),
                ("BACKGROUND", (0, 1), (-1, -1), TEAL_SOFT),
                ("GRID", (0, 0), (-1, -1), 0.3, RULE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    story.append(table)
    story.append(Spacer(1, 3 * mm))
    story.append(
        Paragraph(
            "Every other commercial employee uses the same rule. Username is the business email. New field users are Standard User, so they can sign in and confirm the password, and they do not see this console until a field permission set is assigned.",
            small,
        )
    )

    story.append(Paragraph("What was loaded on 15 October", h2))
    story.append(
        Paragraph(
            "The commercial employee file was loaded into Salesforce. 772 people are active. Welcome email was not sent. 663 have the direct manager from the sheet. 39 rows have no manager code. 70 rows point at a manager code that is not in this file, so those manager links are still open. People who already had a Salesforce login kept their existing profile.",
            body,
        )
    )
    story.append(
        Paragraph(
            "A spot check: Mayar Ashraf, mayar.ashraf@zeta-pharma.com, title Act as Field Force Supervisor, manager Mohamed Shaaban Mohamed Elsafty, profile Standard User, status Active.",
            body,
        )
    )
    story.append(
        Paragraph(
            "June 2026 distributor withdrawals were already in the org before this user load: 120,905 rows, about 1.32 million units, tied to 28,958 pharmacies and 90 products. Sources are IbnSina, POS, Elezaby, Egydrug, Sofico, and a thin Direct set of 460 rows. The brick on every row is blank.",
            body,
        )
    )

    story.append(Paragraph("What to try in the Admin Console", h2))
    story.append(
        Paragraph(
            "The console has 15 modules. Use them to look and confirm. Do not run a wipe in Account Management. Sales Data can show the June withdrawals. Territory contribution, ceilings, chain shares, the bulk split, and original and buffer targets have not been calculated from those rows.",
            body,
        )
    )

    modules = [
        "Territory Management, Users tab. Search your own name, then search mayar.ashraf. Confirm Active, title, email, and manager.",
        "Territory Management, Product Lines. Confirm CHC, DIAB-I through DIAB-IV, GIT-I through GIT-III, PEDIA, ORTHO, CVM, DERMA, and NEUROSCIENCE are present.",
        "Meetings Setup. Confirm the meeting types, who can create them, and the approval sequence. Reps still create meetings from this setup. The request-only change is not live yet.",
        "Sales Data. Open June 2026 and confirm IbnSina, POS, Elezaby, Egydrug, and Sofico rows. Do not upload the same files again.",
        "Products Manager and Bricks Management. Browse. Product and brick alignment for the new users is not part of this load.",
    ]
    story.append(
        ListFlowable(
            [ListItem(Paragraph(item, body), leftIndent=8) for item in modules],
            bulletType="1",
            start="1",
            leftIndent=14,
            bulletFontName="Times-Roman",
            bulletFontSize=10,
        )
    )

    def shot(filename, title, note):
        path = f"{SHOTS}/{filename}"
        img = Image(path, width=175 * mm, height=98 * mm, kind="proportional")
        img.hAlign = "CENTER"
        return KeepTogether(
            [
                Paragraph(title, h2),
                img,
                Paragraph(note, caption),
            ]
        )

    story.append(PageBreak())
    story.append(Paragraph("Screens from the org", h1))
    story.append(
        shot(
            "01-admin-console.png",
            "Admin Console home",
            "Field Co-pilot, Admin Console. Fifteen modules. This is the first screen after sign-in for an administrator.",
        )
    )
    story.append(
        shot(
            "02-territory-management.png",
            "Territory Management, product lines",
            "Product lines already in the org, with brand, detail, sample, and product counts on each card.",
        )
    )
    story.append(PageBreak())
    story.append(
        shot(
            "03-users.png",
            "Territory Management, users",
            "Commercial employees as loaded. Status Active, profile Standard User, username equal to the business email. Search from the box at the top left.",
        )
    )
    story.append(
        shot(
            "04-distributors.png",
            "Distributors Management",
            "Import screen for a new distributor Excel. June withdrawals are already stored. This screen is for the next file, with Max rows still at 200.",
        )
    )
    story.append(PageBreak())
    story.append(
        shot(
            "05-meetings.png",
            "Meetings Setup",
            "Meeting types live in the console: KOL Roundtable, Speaker Meeting, Advisory Board, Seminar, Webinar, Conference, Symposium, and L&amp;D Training.",
        )
    )

    later = [
        "Territory sales contribution, chain brick shares, ceilings, and the bulk split. The June rows are loaded; they are not digested.",
        "Original and buffer targets per position and item.",
        "Assigning each new user to an organogram position.",
        "CLM decks aligned to products and territories. One presentation is in the org today.",
        "A real classification and physician-movement history. The APM numbers in the org today are a demo seed: penetration is filled, sales volume is filled on 1,952 rows across 226 accounts, and classification is about 1,520 rows split almost evenly across A1 to C3. Rating snapshots repeat 12,708 accounts across 12 months and do not store a class.",
    ]
    story.append(Paragraph("Still to come, so do not mark these as done", h2))
    story.append(
        ListFlowable(
            [ListItem(Paragraph(item, body), leftIndent=8) for item in later],
            bulletType="bullet",
            leftIndent=14,
            bulletFontName="Times-Roman",
            bulletFontSize=10,
        )
    )
    story.append(Paragraph("Please send back", h2))
    story.append(
        Paragraph(
            "A short note is enough: which login worked, which user record looked wrong, and which console module did not open. June withdrawal totals can be checked. Do not treat APM, classification, or territory contribution as finished. Do not deactivate users or wipe accounts during this pass.",
            body,
        )
    )

    doc = SimpleDocTemplate(
        OUT,
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=22 * mm,
        bottomMargin=16 * mm,
        title="Zeta Pharma SFE validation pack",
        author="Zeta Pharma",
    )
    doc.build(story, onFirstPage=header_footer, onLaterPages=header_footer)
    print(OUT)


if __name__ == "__main__":
    build()
