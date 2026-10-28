#!/usr/bin/env python3
"""SFE steps, Abdullah's login, and console screenshots."""

from reportlab.lib.colors import Color, white, black
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
)

OUT = "/Users/ashrafrezk/Salesforce Projects/Zeta Pharma/ph/Plan/SFE_Validation_Steps.pdf"
SHOTS = "/Users/ashrafrezk/Salesforce Projects/Zeta Pharma/ph/Plan/sfe-steps-shots"

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
    canvas.drawString(16 * mm, A4[1] - 10 * mm, "Zeta Pharma  ·  SFE validation steps")
    canvas.setFont("Times-Roman", 9)
    canvas.drawRightString(A4[0] - 16 * mm, A4[1] - 10 * mm, "19 October 2026")
    canvas.setFillColor(MUTED)
    canvas.setFont("Times-Roman", 8)
    canvas.drawString(16 * mm, 8 * mm, "zetapharma.my.salesforce.com")
    canvas.drawRightString(A4[0] - 16 * mm, 8 * mm, str(doc.page))
    canvas.restoreState()


def shot(path, width):
    image = Image(path, width=width, height=width * 929 / 1152)
    image.hAlign = "CENTER"
    return image


def build():
    styles = getSampleStyleSheet()
    h1 = ParagraphStyle(
        "H1",
        parent=styles["Heading1"],
        fontName="Times-Bold",
        fontSize=18,
        leading=22,
        textColor=TEAL,
        spaceAfter=6,
    )
    h2 = ParagraphStyle(
        "H2",
        parent=styles["Heading2"],
        fontName="Times-Bold",
        fontSize=13,
        leading=16,
        textColor=TEAL,
        spaceBefore=8,
        spaceAfter=4,
    )
    body = ParagraphStyle(
        "Body",
        parent=styles["Normal"],
        fontName="Times-Roman",
        fontSize=10.5,
        leading=14,
        textColor=black,
        spaceAfter=5,
    )
    caption = ParagraphStyle(
        "Caption",
        parent=body,
        fontName="Times-Italic",
        fontSize=9,
        leading=12,
        textColor=MUTED,
        spaceBefore=2,
        spaceAfter=4,
    )
    cell = ParagraphStyle("Cell", parent=body, fontSize=10, leading=13, spaceAfter=0)
    cell_b = ParagraphStyle("CellB", parent=cell, fontName="Times-Bold", textColor=TEAL)

    content_width = A4[0] - 32 * mm
    story = []
    story.append(Paragraph("How an SFE checks the October load", h1))
    story.append(
        Paragraph(
            "Sign in, open SFE Co-pilot, and check the territory tree and the people. "
            "The screenshots were taken in the live org on 19 October 2026.",
            body,
        )
    )

    story.append(Paragraph("Abdullah's login", h2))
    story.append(
        Paragraph(
            "This is Ahmed Abdullah ElShahat AbdelSamad AbdelNaby, SFE Manager, System Administrator. "
            "A temporary password was set for this check. His previous password no longer works.",
            body,
        )
    )
    rows = [
        [Paragraph("Site", cell_b), Paragraph("https://zetapharma.my.salesforce.com", cell)],
        [Paragraph("Username", cell_b), Paragraph("ahmed.abdullah@zeta-pharma.com", cell)],
        [Paragraph("Password", cell_b), Paragraph("Abdullah@2026!", cell)],
        [Paragraph("Profile", cell_b), Paragraph("System Administrator", cell)],
        [Paragraph("Title", cell_b), Paragraph("SFE Manager, SFE &amp; CRM", cell)],
    ]
    table = Table(rows, colWidths=[32 * mm, content_width - 32 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), TEAL_SOFT),
                ("GRID", (0, 0), (-1, -1), 0.4, RULE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(table)
    story.append(Spacer(1, 3 * mm))

    story.append(Paragraph("Steps", h2))
    steps = [
        "Open the site above and sign in with Abdullah's username and password.",
        "Click the app launcher (the nine dots, top left) and open <b>SFE Co-pilot</b>.",
        "Stay on the <b>Admin Console</b> tab. The modules are under Setup / Modules.",
        "Open <b>Territory Management</b>, then the <b>Territories</b> tab. This is the loaded tree: Head Office, the four business units, lines, districts, and positions. Each row shows the assigned person, or Vacant.",
        "Open the <b>Users</b> tab in the same window. Search a name or email. The row shows username, title, profile, and Active. Edit opens the profile. OTP Password sets a new password for that person.",
        "To see the Salesforce user record, click the gear, then Setup, then Administration, Users, Users. Abdullah's own record is the example below.",
        "Login As is not on the user record yet. Under Setup, Security, Login Access Policies, check <b>Administrators Can Log in as Any User</b> and save. A Login button then appears on each user record.",
    ]
    for index, text in enumerate(steps, start=1):
        story.append(Paragraph(f"{index}. {text}", body))

    story.append(Paragraph("What to expect", h2))
    story.append(
        Paragraph(
            "The Territories tab is the organogram check. The Users tab is the people check. "
            "Bricks Management shows the same territory tree. The brick list beside it is empty, so the 12,605 brick alignments are not visible on that screen.",
            body,
        )
    )
    story.append(
        Paragraph(
            "Sample Logistics now shows a package icon on its Admin Console tile.",
            body,
        )
    )

    pages = [
        (
            "01-admin-console.png",
            "1. SFE Co-pilot, Admin Console. Open Territory Management to check the tree and the people. Sample Logistics is the orange package tile.",
        ),
        (
            "02-territories.png",
            "2. Territory Management, Territories tab. Head Office, business units, and lines, with the assigned person or Vacant.",
        ),
        (
            "03-users.png",
            "3. Territory Management, Users tab. Search a person, then Edit or OTP Password.",
        ),
        (
            "04-abdullah-user.png",
            "4. Setup, Users, Users. Abdullah's record: ahmed.abdullah@zeta-pharma.com, SFE Manager, System Administrator, Active.",
        ),
        (
            "05-login-access.png",
            "5. Setup, Security, Login Access Policies. Check Administrators Can Log in as Any User, then save. The Login button appears on the user record after that.",
        ),
    ]
    for filename, text in pages:
        story.append(PageBreak())
        story.append(Paragraph(text, caption))
        story.append(shot(f"{SHOTS}/{filename}", content_width))

    doc = SimpleDocTemplate(
        OUT,
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=22 * mm,
        bottomMargin=16 * mm,
        title="SFE validation steps",
        author="Zeta Pharma",
    )
    doc.build(story, onFirstPage=header_footer, onLaterPages=header_footer)
    print(OUT)


if __name__ == "__main__":
    build()
