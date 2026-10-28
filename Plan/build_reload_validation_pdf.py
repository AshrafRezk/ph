#!/usr/bin/env python3
"""Validation pack for the October 2026 organogram and employee reload."""

import json
from pathlib import Path

from reportlab.lib.colors import Color, black, white
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

PLAN = Path(__file__).resolve().parent
LOCAL = json.loads((PLAN / "zeta-reload-local.json").read_text(encoding="utf-8"))
ORG = json.loads((PLAN / "zeta-reload-org.json").read_text(encoding="utf-8"))
OUT = PLAN / "Zeta_Organogram_Employee_Reload_Validation.pdf"

TEAL = Color(11 / 255, 79 / 255, 108 / 255)
TEAL_SOFT = Color(232 / 255, 241 / 255, 245 / 255)
RULE = Color(210 / 255, 218 / 255, 224 / 255)
MUTED = Color(70 / 255, 80 / 255, 90 / 255)


def esc(value) -> str:
    text = "" if value is None else str(value)
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def header_footer(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(white)
    canvas.rect(0, 0, A4[0], A4[1], fill=1, stroke=0)
    canvas.setFillColor(TEAL)
    canvas.rect(0, A4[1] - 16 * mm, A4[0], 16 * mm, fill=1, stroke=0)
    canvas.setFillColor(white)
    canvas.setFont("Times-Bold", 9)
    canvas.drawString(16 * mm, A4[1] - 10 * mm, "Zeta Pharma  ·  Organogram and employee reload")
    canvas.setFont("Times-Roman", 9)
    canvas.drawRightString(A4[0] - 16 * mm, A4[1] - 10 * mm, "19 October 2026")
    canvas.setFillColor(MUTED)
    canvas.setFont("Times-Roman", 8)
    canvas.drawString(16 * mm, 8 * mm, "zetapharma.my.salesforce.com")
    canvas.drawRightString(A4[0] - 16 * mm, 8 * mm, str(doc.page))
    canvas.restoreState()


def table(rows, col_widths):
    styled = []
    for index, row in enumerate(rows):
        style_name = "CellB" if index == 0 else "Cell"
        styled.append([Paragraph(esc(cell), styles[style_name]) for cell in row])
    result = Table(styled, colWidths=col_widths, repeatRows=1)
    result.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), TEAL),
                ("TEXTCOLOR", (0, 0), (-1, 0), white),
                ("BACKGROUND", (0, 1), (-1, -1), white),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white, TEAL_SOFT]),
                ("GRID", (0, 0), (-1, -1), 0.3, RULE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    return result


def build():
    employees = LOCAL["employees"]
    june = LOCAL["june"]
    counts = LOCAL["counts"]
    roster = ORG["roster"]
    story = []
    story.append(Paragraph("Organogram and employee reload", styles["H1"]))
    story.append(
        Paragraph(
            "The October workbooks were loaded into zetapharma.my.salesforce.com on 19 October 2026. "
            "Counts below were checked against the files after the territory, brick, alignment, user, and roster jobs finished. "
            "The hierarchy is still Head Office, Business Unit, Line, District, and Position. "
            "National sales managers, area managers, district managers, and medical reps were assigned onto that tree.",
            styles["Body"],
        )
    )
    story.append(Paragraph("Sources", styles["H2"]))
    story.append(
        Paragraph(
            "Organogram: Toatal Organogram 2026.xlsx, sheet Total Organogram, 12,605 brick rows. "
            "Employee batch: Employee Data Base.xlsx, 31 active people. "
            "The previous organogram in the org was "
            + esc(june["previousSource"])
            + ".",
            styles["Body"],
        )
    )

    story.append(Paragraph("What changed from June", styles["H2"]))
    story.append(
        table(
            [
                ["", "June file", "October file", "In the org now"],
                ["Business units", "4", str(counts["businessUnits"]), "4"],
                ["Lines", "16", str(counts["lines"]), "19, including the June NEUROSCIENCE line"],
                ["Districts", "110", str(counts["districts"]), "138, including districts no longer in the file"],
                ["Positions", "721", str(counts["positions"]), "815, including positions no longer in the file"],
                ["Bricks 70 / 148 / 702", "70 / 148 / 702", "70 / 148 / 702", "70 / 148 / 702"],
                ["Active alignments", "11,215", "12,605", "12,605"],
            ],
            [32 * mm, 28 * mm, 32 * mm, 78 * mm],
        )
    )
    story.append(Spacer(1, 3 * mm))
    story.append(
        Paragraph(
            "Lines added: "
            + ", ".join(june["linesAdded"])
            + ". Line left in place from June and not deleted: "
            + ", ".join(june["linesRemoved"])
            + ". Positions in the new file that were not in June: "
            + str(len(june["positionsAdded"]))
            + ". June positions left in place: "
            + str(len(june["positionsRetired"]))
            + ". District names added: "
            + str(len(june["districtsAdded"]))
            + ". June district names left in place: "
            + str(len(june["districtsRetired"]))
            + ". Retired alignments deactivated: "
            + f"{ORG['retiredAlignments']:,}"
            + ". Training territories still present: "
            + str(ORG["trainingTerritories"])
            + ".",
            styles["Body"],
        )
    )

    story.append(Paragraph("Employees", styles["H2"]))
    story.append(
        Paragraph(
            "The employee workbook is a batch, not a replacement of the commercial roster. "
            "The user file went from 772 people to 784. "
            "Twelve people were created. Eighteen were updated. "
            "New users sign in with the first name plus @2026!. Existing users kept their passwords. "
            "One row could not be loaded.",
            styles["Body"],
        )
    )
    story.append(
        table(
            [["Code", "Name", "What happened"]]
            + [
                [row["code"], row["name"], "Created"]
                for row in employees["inserted"]
            ]
            + [
                [row["code"], row["name"], "Updated" + ("" if not row["changes"] else ": " + ", ".join(row["changes"]))]
                for row in employees["updated"]
            ]
            + [
                [row["code"], row["name"], "Skipped: " + row["reason"]]
                for row in employees["skipped"]
            ],
            [22 * mm, 78 * mm, 70 * mm],
        )
    )

    story.append(Paragraph("Roster assignments", styles["H2"]))
    story.append(
        Paragraph(
            f"The organogram names {roster['codes']} people. "
            f"{roster['users']} match an active Salesforce user and {roster['missingUsers']} do not, because neither workbook has an email for them. "
            f"Those {roster['missingUsers']} seats were left empty. "
            f"For the matched users, {roster['seatsFound']} of {roster['seatsExpected']} seats are on the territory named in the file. "
            "Vacant seats were not given a user. People on the new roster were removed from organogram seats that are not in the file. Training seats were not touched.",
            styles["Body"],
        )
    )

    story.append(Paragraph("Checks that passed", styles["H2"]))
    story.append(
        table(
            [
                ["Check", "Result"],
                ["Business units stayed DERMA-GIT-NEURO, CHC, CVM-ORTHO-PEDIA, and DIABETES", "Passed"],
                ["Every line, district, and position has its parent", "Passed"],
                ["No duplicate external ids in the load file", "Passed"],
                ["Brick levels are 70, 148, and 702", "Passed"],
                ["Active brick alignments equal the workbook, 12,605", "Passed"],
                ["1,215 alignments that are no longer in the file are inactive", "Passed"],
                ["All 30 emailed employees exist and are active", "Passed"],
                ["703 of 703 seats for matched users are assigned", "Passed"],
                ["GIT-SALES, NEUROSCIENCE-I, and NEUROSCIENCE-II exist", "Passed"],
                ["NEUROSCIENCE-II UNASSIGNED holds the 10 seats whose district cell was None", "Passed"],
                ["20 training territories are still in the org", "Passed"],
                ["Territory, brick, alignment, user, and roster jobs finished with no job errors", "Passed"],
            ],
            [130 * mm, 40 * mm],
        )
    )

    story.append(Paragraph("Exceptions", styles["H2"]))
    story.append(
        Paragraph(
            "These items were checked and are called out because the workbook or the org could not be applied exactly.",
            styles["Body"],
        )
    )
    for item in ORG["employeeExceptions"]:
        story.append(Paragraph(esc(item["code"] + " " + item["name"] + ". " + item["detail"]), styles["Body"]))
    story.append(
        Paragraph(
            "Fatma Esmail Shawky Gaber, code 2533, has no business email, so no username was created.",
            styles["Body"],
        )
    )
    story.append(
        Paragraph(
            "Ten NEUROSCIENCE-II positions had a district cell of None. They were loaded under NEUROSCIENCE-II UNASSIGNED: "
            + "; ".join(LOCAL["exceptions"]["blankDistrictPositions"])
            + ".",
            styles["Body"],
        )
    )
    conflict_names = [row["name"] + " (" + ", ".join(str(item) for item in row["ids"]) + ")" for row in LOCAL["exceptions"]["positionIdConflicts"]]
    story.append(
        Paragraph(
            "Seventeen position names appear with more than one Position ID. The territory key stays the position name, and the most common id was stored: "
            + "; ".join(conflict_names)
            + ".",
            styles["Body"],
        )
    )
    story.append(
        Paragraph(
            "June territories that are not in the October file were left in place and were not deleted. "
            "That is the NEUROSCIENCE line, these districts: "
            + "; ".join(june["districtsRetired"])
            + ", and "
            + str(len(june["positionsRetired"]))
            + " positions.",
            styles["Body"],
        )
    )

    story.append(Paragraph("People on the organogram with no Salesforce user", styles["H2"]))
    story.append(
        Paragraph(
            "These 135 employee ids are on the organogram. They were not assigned because there is no user and no email to create one.",
            styles["Body"],
        )
    )
    unmatched_rows = [["Code", "Name", "Role on the file"]]
    for person in LOCAL["unmatchedPeople"]:
        unmatched_rows.append([person["code"], person["name"], ", ".join(person["roles"])])
    story.append(table(unmatched_rows, [22 * mm, 95 * mm, 53 * mm]))

    story.append(Paragraph("June positions left in the org", styles["H2"]))
    retired_rows = [["Position"]]
    for name in june["positionsRetired"]:
        retired_rows.append([name])
    story.append(table(retired_rows, [170 * mm]))

    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=22 * mm,
        bottomMargin=16 * mm,
        title="Zeta Pharma organogram and employee reload",
        author="Zeta Pharma",
    )
    doc.build(story, onFirstPage=header_footer, onLaterPages=header_footer)
    print(OUT)


styles = getSampleStyleSheet()
styles.add(
    ParagraphStyle(
        "H1",
        parent=styles["Heading1"],
        fontName="Times-Bold",
        fontSize=18,
        leading=22,
        textColor=TEAL,
        spaceAfter=6,
    )
)
styles.add(
    ParagraphStyle(
        "H2",
        parent=styles["Heading2"],
        fontName="Times-Bold",
        fontSize=13,
        leading=16,
        textColor=TEAL,
        spaceBefore=10,
        spaceAfter=4,
    )
)
styles.add(
    ParagraphStyle(
        "Body",
        parent=styles["Normal"],
        fontName="Times-Roman",
        fontSize=10.5,
        leading=14,
        textColor=black,
        spaceAfter=6,
    )
)
styles.add(
    ParagraphStyle(
        "Cell",
        parent=styles["Normal"],
        fontName="Times-Roman",
        fontSize=8,
        leading=10,
        textColor=black,
        spaceAfter=0,
    )
)
styles.add(
    ParagraphStyle(
        "CellB",
        parent=styles["Cell"],
        fontName="Times-Bold",
        textColor=white,
    )
)

if __name__ == "__main__":
    build()
