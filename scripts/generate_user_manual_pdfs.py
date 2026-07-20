#!/usr/bin/env python3
"""Generate the two employee-facing ERP manuals from their Markdown sources."""

from __future__ import annotations

import html
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
GUIDES = ROOT / "docs" / "user-guides"
ASSET_OUTPUT = ROOT / "assets" / "manuals"
PUBLIC_OUTPUT = ROOT / "output" / "pdf"

NAVY = colors.HexColor("#0A3C66")
BLUE = colors.HexColor("#1976D2")
TEAL = colors.HexColor("#0F8F7B")
ORANGE = colors.HexColor("#C96521")
INK = colors.HexColor("#17212B")
MUTED = colors.HexColor("#5E6B78")
LINE = colors.HexColor("#DCE4EC")
SOFT = colors.HexColor("#F4F7FA")
SOFT_BLUE = colors.HexColor("#EAF2F9")
WHITE = colors.white


@dataclass(frozen=True)
class ManualSpec:
    source: str
    output: str
    short_title: str
    section_label: str
    accent: colors.Color


SPECS = (
    ManualSpec(
        source="JOBS_TABLE_USER_GUIDE.md",
        output="manual_jobs_table.pdf",
        short_title="Jobs Table",
        section_label="TALLER",
        accent=ORANGE,
    ),
    ManualSpec(
        source="WEBSITE_ONLINE_SALES_USER_GUIDE.md",
        output="manual_sitio_web_ventas_online.pdf",
        short_title="Sitio Web y venta online",
        section_label="CANAL WEB",
        accent=TEAL,
    ),
)


def register_fonts() -> None:
    fonts = ROOT / "assets" / "fonts"
    pdfmetrics.registerFont(TTFont("Barlow", fonts / "Barlow-Regular.ttf"))
    pdfmetrics.registerFont(
        TTFont("BarlowMedium", fonts / "Barlow-Medium.ttf")
    )
    pdfmetrics.registerFont(
        TTFont("BarlowSemiBold", fonts / "Barlow-SemiBold.ttf")
    )
    pdfmetrics.registerFont(TTFont("BarlowBold", fonts / "Barlow-Bold.ttf"))
    pdfmetrics.registerFont(TTFont("Oswald", fonts / "Oswald-wght.ttf"))


def inline_markup(value: str) -> str:
    escaped = html.escape(value.strip())
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(
        r"`(.+?)`", r'<font name="BarlowSemiBold" color="#0A3C66">\1</font>', escaped
    )
    return escaped


def styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "ManualTitle",
            parent=base["Title"],
            fontName="Oswald",
            fontSize=25,
            leading=29,
            textColor=WHITE,
            alignment=TA_LEFT,
            spaceAfter=0,
        ),
        "metadata": ParagraphStyle(
            "ManualMetadata",
            parent=base["Normal"],
            fontName="BarlowMedium",
            fontSize=8.6,
            leading=11,
            textColor=colors.HexColor("#D6E3EF"),
            spaceAfter=0,
        ),
        "h2": ParagraphStyle(
            "ManualH2",
            parent=base["Heading2"],
            fontName="Oswald",
            fontSize=15.2,
            leading=18,
            textColor=NAVY,
            spaceBefore=12,
            spaceAfter=6,
            keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "ManualH3",
            parent=base["Heading3"],
            fontName="BarlowBold",
            fontSize=10.8,
            leading=14,
            textColor=INK,
            spaceBefore=9,
            spaceAfter=4,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "ManualBody",
            parent=base["BodyText"],
            fontName="Barlow",
            fontSize=9.4,
            leading=13,
            textColor=INK,
            spaceAfter=6,
        ),
        "bullet": ParagraphStyle(
            "ManualBullet",
            parent=base["BodyText"],
            fontName="Barlow",
            fontSize=9.2,
            leading=12.4,
            textColor=INK,
            leftIndent=13,
            firstLineIndent=-8,
            bulletIndent=1,
            spaceAfter=3.5,
        ),
        "number": ParagraphStyle(
            "ManualNumber",
            parent=base["BodyText"],
            fontName="Barlow",
            fontSize=9.2,
            leading=12.4,
            textColor=INK,
            leftIndent=16,
            firstLineIndent=-12,
            bulletIndent=0,
            spaceAfter=3.5,
        ),
        "callout": ParagraphStyle(
            "ManualCallout",
            parent=base["BodyText"],
            fontName="BarlowMedium",
            fontSize=9.3,
            leading=12.5,
            textColor=NAVY,
            spaceAfter=0,
        ),
        "table_header": ParagraphStyle(
            "ManualTableHeader",
            parent=base["Normal"],
            fontName="BarlowBold",
            fontSize=8.2,
            leading=10.5,
            textColor=WHITE,
            alignment=TA_LEFT,
        ),
        "table_body": ParagraphStyle(
            "ManualTableBody",
            parent=base["Normal"],
            fontName="Barlow",
            fontSize=8.2,
            leading=10.8,
            textColor=INK,
            alignment=TA_LEFT,
        ),
    }


class FlowDiagram(Flowable):
    def __init__(self, labels: Iterable[str], accent: colors.Color):
        super().__init__()
        self.labels = [label.strip() for label in labels if label.strip()]
        self.accent = accent
        row_size = 5 if len(self.labels) <= 5 else 4
        self.rows = [
            self.labels[index : index + row_size]
            for index in range(0, len(self.labels), row_size)
        ]
        # Keep multi-step diagrams compact enough to remain paired with the
        # explanation that follows. The previous 53 mm two-row block pushed a
        # three-line explanation onto a new page and left an orphan diagram.
        self.row_height = 18 * mm
        self.row_gap = 3 * mm
        self.box_height = 13.5 * mm
        self.height = (
            len(self.rows) * self.row_height
            + max(0, len(self.rows) - 1) * self.row_gap
        )

    def wrap(self, available_width: float, available_height: float) -> tuple[float, float]:
        self.width = available_width
        return available_width, self.height

    def draw(self) -> None:
        canvas = self.canv
        row_height = self.row_height
        row_gap = self.row_gap
        for row_index, row in enumerate(self.rows):
            count = len(row)
            arrow_gap = 8 * mm
            box_width = (self.width - arrow_gap * max(0, count - 1)) / max(1, count)
            box_height = self.box_height
            y = (
                self.height
                - (row_index + 1) * row_height
                - row_index * row_gap
                + 2.2 * mm
            )
            for index, label in enumerate(row):
                x = index * (box_width + arrow_gap)
                canvas.setFillColor(SOFT)
                canvas.setStrokeColor(LINE)
                canvas.roundRect(x, y, box_width, box_height, 2.4 * mm, fill=1, stroke=1)
                canvas.setFillColor(self.accent)
                canvas.roundRect(x, y, 2.6 * mm, box_height, 2.4 * mm, fill=1, stroke=0)
                canvas.setFillColor(INK)
                canvas.setFont("BarlowSemiBold", 8.2)
                lines = _wrap_canvas_text(label, "BarlowSemiBold", 8.2, box_width - 10 * mm)
                line_height = 9.6
                start_y = y + box_height / 2 + (len(lines) - 1) * line_height / 2 - 3
                for line_index, line in enumerate(lines[:3]):
                    canvas.drawCentredString(
                        x + box_width / 2 + 1.3 * mm,
                        start_y - line_index * line_height,
                        line,
                    )
                if index < count - 1:
                    arrow_x1 = x + box_width + 1.5 * mm
                    arrow_x2 = x + box_width + arrow_gap - 1.5 * mm
                    arrow_y = y + box_height / 2
                    canvas.setStrokeColor(self.accent)
                    canvas.setFillColor(self.accent)
                    canvas.setLineWidth(1.2)
                    canvas.line(arrow_x1, arrow_y, arrow_x2, arrow_y)
                    canvas.line(arrow_x2, arrow_y, arrow_x2 - 3, arrow_y + 2.2)
                    canvas.line(arrow_x2, arrow_y, arrow_x2 - 3, arrow_y - 2.2)
            if row_index < len(self.rows) - 1:
                current_last_x = (count - 1) * (box_width + arrow_gap) + box_width / 2
                next_count = len(self.rows[row_index + 1])
                next_box_width = (
                    self.width - arrow_gap * max(0, next_count - 1)
                ) / max(1, next_count)
                next_first_x = next_box_width / 2
                y1 = y - 0.8 * mm
                y2 = y - row_gap - 1.2 * mm
                canvas.setStrokeColor(self.accent)
                canvas.setLineWidth(1.1)
                canvas.line(current_last_x, y1, current_last_x, y2)
                canvas.line(current_last_x, y2, next_first_x, y2)
                canvas.line(next_first_x, y2, next_first_x, y2 - 1.7 * mm)
                canvas.line(
                    next_first_x,
                    y2 - 1.7 * mm,
                    next_first_x - 2.2,
                    y2 - 1.7 * mm + 3,
                )
                canvas.line(
                    next_first_x,
                    y2 - 1.7 * mm,
                    next_first_x + 2.2,
                    y2 - 1.7 * mm + 3,
                )


def _wrap_canvas_text(text: str, font: str, size: float, max_width: float) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if not current or pdfmetrics.stringWidth(candidate, font, size) <= max_width:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines or [text]


class ManualDocTemplate(BaseDocTemplate):
    def __init__(self, path: Path, spec: ManualSpec):
        super().__init__(
            str(path),
            pagesize=A4,
            leftMargin=17 * mm,
            rightMargin=17 * mm,
            topMargin=17 * mm,
            bottomMargin=23 * mm,
            title=f"Manual de usuario - {spec.short_title}",
            author="Viña Bike",
            subject="Guía operativa para el equipo Viña Bike",
        )
        self.spec = spec
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        self.addPageTemplates(
            PageTemplate(id="manual", frames=[frame], onPage=self._draw_page)
        )

    def _draw_page(self, canvas, document) -> None:
        canvas.saveState()
        page_number = canvas.getPageNumber()
        if page_number > 1:
            canvas.setFillColor(NAVY)
            canvas.rect(0, A4[1] - 11 * mm, A4[0], 11 * mm, fill=1, stroke=0)
            canvas.setFillColor(WHITE)
            canvas.setFont("Oswald", 9.5)
            canvas.drawString(17 * mm, A4[1] - 7.2 * mm, "VIÑA BIKE")
            canvas.setFont("BarlowMedium", 8.2)
            canvas.drawRightString(
                A4[0] - 17 * mm,
                A4[1] - 7.2 * mm,
                self.spec.short_title,
            )
        canvas.setStrokeColor(LINE)
        canvas.line(17 * mm, 12 * mm, A4[0] - 17 * mm, 12 * mm)
        canvas.setFillColor(MUTED)
        canvas.setFont("Barlow", 7.5)
        canvas.drawString(17 * mm, 7.5 * mm, "Manual interno · Viña Bike ERP")
        canvas.drawRightString(
            A4[0] - 17 * mm, 7.5 * mm, f"Página {page_number}"
        )
        canvas.restoreState()


def title_banner(title: str, metadata: str, spec: ManualSpec, style_map) -> Table:
    label = Paragraph(
        f'<font name="BarlowBold" size="8" color="#FFFFFF">{spec.section_label}</font>',
        style_map["metadata"],
    )
    title_p = Paragraph(inline_markup(title), style_map["title"])
    metadata_p = Paragraph(inline_markup(metadata), style_map["metadata"])
    table = Table(
        [[label], [title_p], [metadata_p]],
        colWidths=[176 * mm],
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), NAVY),
                ("LEFTPADDING", (0, 0), (-1, -1), 9 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9 * mm),
                ("TOPPADDING", (0, 0), (0, 0), 7 * mm),
                ("BOTTOMPADDING", (0, 0), (0, 0), 1.5 * mm),
                ("TOPPADDING", (0, 1), (0, 1), 1.5 * mm),
                ("BOTTOMPADDING", (0, 1), (0, 1), 2.5 * mm),
                ("TOPPADDING", (0, 2), (0, 2), 1 * mm),
                ("BOTTOMPADDING", (0, 2), (0, 2), 7 * mm),
                ("LINEBELOW", (0, 0), (0, 0), 2, spec.accent),
            ]
        )
    )
    return table


def callout(text: str, spec: ManualSpec, style_map) -> Table:
    table = Table(
        [[Paragraph(inline_markup(text), style_map["callout"])]],
        colWidths=[176 * mm],
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SOFT_BLUE),
                ("LINEBEFORE", (0, 0), (0, -1), 3, spec.accent),
                ("LEFTPADDING", (0, 0), (-1, -1), 5 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5 * mm),
                ("TOPPADDING", (0, 0), (-1, -1), 4 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4 * mm),
            ]
        )
    )
    return table


def markdown_table(rows: list[list[str]], style_map) -> Table:
    columns = len(rows[0])
    if columns == 2:
        widths = [53 * mm, 123 * mm]
    elif columns == 3:
        widths = [37 * mm, 55 * mm, 84 * mm]
    else:
        widths = [176 * mm / columns] * columns
    vertical_padding = 1.4 * mm if columns == 2 else 2.6 * mm
    data = []
    for row_index, row in enumerate(rows):
        style = style_map["table_header"] if row_index == 0 else style_map["table_body"]
        data.append([Paragraph(inline_markup(value), style) for value in row])
    table = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), vertical_padding),
        ("BOTTOMPADDING", (0, 0), (-1, -1), vertical_padding),
        ("LINEBELOW", (0, 0), (-1, -1), 0.45, LINE),
        ("BOX", (0, 0), (-1, -1), 0.6, LINE),
    ]
    for row_index in range(1, len(data)):
        commands.append(
            (
                "BACKGROUND",
                (0, row_index),
                (-1, row_index),
                WHITE if row_index % 2 else SOFT,
            )
        )
    table.setStyle(TableStyle(commands))
    return table


def parse_manual(source: Path, spec: ManualSpec) -> list[Flowable]:
    style_map = styles()
    lines = source.read_text(encoding="utf-8").splitlines()
    story: list[Flowable] = []
    index = 0
    title = ""
    metadata = ""

    if lines and lines[0].startswith("# "):
        title = lines[0][2:].strip()
        index = 1
    while index < len(lines) and not lines[index].strip():
        index += 1
    if index < len(lines) and lines[index].startswith("**Versión:**"):
        metadata = lines[index].replace("**", "")
        index += 1
    story.extend(
        [title_banner(title, metadata, spec, style_map), Spacer(1, 6 * mm)]
    )

    paragraph_lines: list[str] = []

    def flush_paragraph() -> None:
        if not paragraph_lines:
            return
        story.append(
            KeepTogether(
                [
                    Paragraph(
                        inline_markup(" ".join(paragraph_lines)),
                        style_map["body"],
                    )
                ]
            )
        )
        paragraph_lines.clear()

    while index < len(lines):
        raw = lines[index]
        line = raw.strip()
        if not line:
            flush_paragraph()
            index += 1
            continue
        if line == "<!-- pagebreak -->":
            flush_paragraph()
            story.append(PageBreak())
            index += 1
            continue
        if line.startswith("## "):
            flush_paragraph()
            story.append(Paragraph(inline_markup(line[3:]), style_map["h2"]))
            index += 1
            continue
        if line.startswith("### "):
            flush_paragraph()
            story.append(Paragraph(inline_markup(line[4:]), style_map["h3"]))
            index += 1
            continue
        if line == "```flow":
            flush_paragraph()
            index += 1
            flow_lines: list[str] = []
            while index < len(lines) and lines[index].strip() != "```":
                flow_lines.append(lines[index].strip())
                index += 1
            labels = " ".join(flow_lines).split("->")
            story.extend([FlowDiagram(labels, spec.accent), Spacer(1, 2 * mm)])
            index += 1
            continue
        if line.startswith(">"):
            flush_paragraph()
            callout_lines = [line[1:].strip()]
            index += 1
            while index < len(lines) and lines[index].strip().startswith(">"):
                callout_lines.append(lines[index].strip()[1:].strip())
                index += 1
            story.extend(
                [callout(" ".join(callout_lines), spec, style_map), Spacer(1, 3 * mm)]
            )
            continue
        if line.startswith("|"):
            flush_paragraph()
            table_lines: list[str] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                table_lines.append(lines[index].strip())
                index += 1
            parsed_rows = [
                [cell.strip() for cell in table_line.strip("|").split("|")]
                for table_line in table_lines
            ]
            rows = [
                row
                for row in parsed_rows
                if not all(re.fullmatch(r":?-{3,}:?", cell) for cell in row)
            ]
            story.extend([markdown_table(rows, style_map), Spacer(1, 3 * mm)])
            continue
        if line.startswith("- "):
            flush_paragraph()
            item_lines = [line[2:].strip()]
            index += 1
            while (
                index < len(lines)
                and lines[index].strip()
                and lines[index] != lines[index].lstrip()
            ):
                item_lines.append(lines[index].strip())
                index += 1
            story.append(
                KeepTogether(
                    [
                        Paragraph(
                            inline_markup(" ".join(item_lines)),
                            style_map["bullet"],
                            bulletText="•",
                        )
                    ]
                )
            )
            continue
        number_match = re.match(r"^(\d+)\.\s+(.+)$", line)
        if number_match:
            flush_paragraph()
            item_lines = [number_match.group(2)]
            index += 1
            while (
                index < len(lines)
                and lines[index].strip()
                and lines[index] != lines[index].lstrip()
            ):
                item_lines.append(lines[index].strip())
                index += 1
            story.append(
                KeepTogether(
                    [
                        Paragraph(
                            inline_markup(" ".join(item_lines)),
                            style_map["number"],
                            bulletText=f"{number_match.group(1)}.",
                        )
                    ]
                )
            )
            continue
        paragraph_lines.append(line)
        index += 1

    flush_paragraph()
    # A trailing layout spacer can overflow an otherwise full last page and
    # create a blank page that contains only header/footer furniture.
    while story and isinstance(story[-1], Spacer):
        story.pop()
    return story


def build_manual(spec: ManualSpec) -> Path:
    source = GUIDES / spec.source
    output = ASSET_OUTPUT / spec.output
    doc = ManualDocTemplate(output, spec)
    doc.build(parse_manual(source, spec))
    shutil.copy2(output, PUBLIC_OUTPUT / spec.output)
    return output


def main() -> None:
    register_fonts()
    ASSET_OUTPUT.mkdir(parents=True, exist_ok=True)
    PUBLIC_OUTPUT.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        output = build_manual(spec)
        print(f"generated {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
