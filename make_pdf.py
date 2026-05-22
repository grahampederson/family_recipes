#!/usr/bin/env python3
"""
make_pdf.py — Converts a week's recipe markdown files + grocery list into a
single printable PDF. Looks in OUTPUT_DIR for the most recent week's files,
or accepts a date prefix via DATE env var (e.g. DATE=2026-05-21).
"""

import os
import re
import sys
import glob
from datetime import datetime

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak,
    HRFlowable, ListFlowable, ListItem
)
from reportlab.lib.enums import TA_LEFT, TA_CENTER

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

OUTPUT_DIR = os.environ.get('OUTPUT_DIR', os.path.join(os.getcwd(), 'recipes'))
DATE_PREFIX = os.environ.get('DATE', None)  # e.g. "2026-05-21"

# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_week_files(output_dir, date_prefix):
    """Return (day_files_sorted, grocery_file) for the given week."""
    if date_prefix:
        day_files = sorted(glob.glob(os.path.join(output_dir, f"{date_prefix}_*.md")))
        # Exclude grocery list from day files
        day_files = [f for f in day_files if 'grocery' not in os.path.basename(f)]
        grocery_files = glob.glob(os.path.join(output_dir, f"{date_prefix}_grocery_list.md"))
    else:
        # Find most recent week by looking at all dated grocery lists
        grocery_files = sorted(glob.glob(os.path.join(output_dir, '*_grocery_list.md')))
        if not grocery_files:
            print("ERROR: No grocery list found in", output_dir)
            sys.exit(1)
        latest_grocery = grocery_files[-1]
        # Extract date prefix from filename e.g. "2026-05-21_grocery_list.md"
        date_prefix = os.path.basename(latest_grocery)[:10]
        day_files = sorted(glob.glob(os.path.join(output_dir, f"{date_prefix}_*.md")))
        day_files = [f for f in day_files if 'grocery' not in os.path.basename(f)]
        grocery_files = [latest_grocery]

    grocery_file = grocery_files[0] if grocery_files else None
    return day_files, grocery_file, date_prefix

# ---------------------------------------------------------------------------
# Markdown → ReportLab flowables
# ---------------------------------------------------------------------------

def build_styles():
    base = getSampleStyleSheet()

    styles = {
        'h1': ParagraphStyle(
            'H1', parent=base['Normal'],
            fontSize=20, leading=26, spaceBefore=0, spaceAfter=10,
            textColor=colors.HexColor('#1a1a2e'),
            fontName='Helvetica-Bold',
        ),
        'h2': ParagraphStyle(
            'H2', parent=base['Normal'],
            fontSize=14, leading=18, spaceBefore=14, spaceAfter=4,
            textColor=colors.HexColor('#16213e'),
            fontName='Helvetica-Bold',
        ),
        'h3': ParagraphStyle(
            'H3', parent=base['Normal'],
            fontSize=12, leading=16, spaceBefore=10, spaceAfter=3,
            textColor=colors.HexColor('#0f3460'),
            fontName='Helvetica-Bold',
        ),
        'body': ParagraphStyle(
            'Body', parent=base['Normal'],
            fontSize=10, leading=14, spaceBefore=2, spaceAfter=2,
            fontName='Helvetica',
        ),
        'bullet': ParagraphStyle(
            'Bullet', parent=base['Normal'],
            fontSize=10, leading=14, spaceBefore=1, spaceAfter=1,
            fontName='Helvetica',
            leftIndent=16,
        ),
        'cover_title': ParagraphStyle(
            'CoverTitle', parent=base['Normal'],
            fontSize=28, leading=36, alignment=TA_CENTER,
            textColor=colors.HexColor('#1a1a2e'),
            fontName='Helvetica-Bold',
            spaceAfter=12,
        ),
        'cover_sub': ParagraphStyle(
            'CoverSub', parent=base['Normal'],
            fontSize=13, leading=18, alignment=TA_CENTER,
            textColor=colors.HexColor('#555555'),
            fontName='Helvetica',
        ),
    }
    return styles

def escape_xml(text):
    """Escape characters that break ReportLab's XML parser."""
    text = text.replace('&', '&amp;')
    text = text.replace('<', '&lt;')
    text = text.replace('>', '&gt;')
    return text

def inline_format(text):
    """Convert markdown inline bold/italic to ReportLab XML tags."""
    text = escape_xml(text)
    # Bold+italic ***text***
    text = re.sub(r'\*\*\*(.+?)\*\*\*', r'<b><i>\1</i></b>', text)
    # Bold **text**
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    # Italic *text*
    text = re.sub(r'\*(.+?)\*', r'<i>\1</i>', text)
    # Inline code `text`
    text = re.sub(r'`(.+?)`', r'<font name="Courier">\1</font>', text)
    return text

def markdown_to_flowables(md_text, styles):
    """Parse markdown lines into ReportLab flowables."""
    flowables = []
    lines = md_text.splitlines()
    i = 0
    in_list = False
    list_items = []

    def flush_list():
        nonlocal in_list, list_items
        if list_items:
            flowables.append(
                ListFlowable(
                    [ListItem(Paragraph(t, styles['bullet']), leftIndent=20, bulletColor=colors.HexColor('#0f3460'))
                     for t in list_items],
                    bulletType='bullet',
                    leftIndent=16,
                    spaceBefore=2,
                    spaceAfter=6,
                )
            )
        in_list = False
        list_items = []

    while i < len(lines):
        line = lines[i].rstrip()

        # Blank line
        if not line.strip():
            flush_list()
            flowables.append(Spacer(1, 4))
            i += 1
            continue

        # Headings
        if line.startswith('### '):
            flush_list()
            flowables.append(Paragraph(inline_format(line[4:]), styles['h3']))
            i += 1
            continue
        if line.startswith('## '):
            flush_list()
            flowables.append(Paragraph(inline_format(line[3:]), styles['h2']))
            flowables.append(HRFlowable(width='100%', thickness=0.5,
                                         color=colors.HexColor('#cccccc'), spaceAfter=4))
            i += 1
            continue
        if line.startswith('# '):
            flush_list()
            flowables.append(Paragraph(inline_format(line[2:]), styles['h1']))
            flowables.append(HRFlowable(width='100%', thickness=1.5,
                                         color=colors.HexColor('#1a1a2e'), spaceAfter=6))
            i += 1
            continue

        # Horizontal rule
        if re.match(r'^[-*_]{3,}$', line.strip()):
            flush_list()
            flowables.append(HRFlowable(width='100%', thickness=0.5,
                                         color=colors.HexColor('#cccccc')))
            i += 1
            continue

        # Bullet list items (-, *, +)
        bullet_match = re.match(r'^[\-\*\+]\s+(.*)', line)
        if bullet_match:
            in_list = True
            list_items.append(inline_format(bullet_match.group(1)))
            i += 1
            continue

        # Numbered list items
        num_match = re.match(r'^\d+\.\s+(.*)', line)
        if num_match:
            in_list = True
            list_items.append(inline_format(num_match.group(1)))
            i += 1
            continue

        # Regular paragraph
        flush_list()
        flowables.append(Paragraph(inline_format(line), styles['body']))
        i += 1

    flush_list()
    return flowables

# ---------------------------------------------------------------------------
# Cover page
# ---------------------------------------------------------------------------

def cover_page(date_prefix, num_recipes, styles):
    flowables = []
    flowables.append(Spacer(1, 2 * inch))

    try:
        dt = datetime.strptime(date_prefix, '%Y-%m-%d')
        date_str = dt.strftime('Week of %B %-d, %Y')
    except Exception:
        date_str = date_prefix

    flowables.append(Paragraph("Weekly Family Meal Plan", styles['cover_title']))
    flowables.append(Spacer(1, 0.15 * inch))
    flowables.append(HRFlowable(width='60%', thickness=2,
                                  color=colors.HexColor('#0f3460'),
                                  hAlign='CENTER', spaceAfter=16))
    flowables.append(Paragraph(date_str, styles['cover_sub']))
    flowables.append(Spacer(1, 0.1 * inch))
    flowables.append(Paragraph(f"{num_recipes} dinners &amp; grocery list", styles['cover_sub']))
    flowables.append(PageBreak())
    return flowables

# ---------------------------------------------------------------------------
# Page numbering
# ---------------------------------------------------------------------------

def make_page_template(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(colors.HexColor('#888888'))
    canvas.drawCentredString(letter[0] / 2, 0.5 * inch, f"Page {doc.page}")
    canvas.restoreState()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    day_files, grocery_file, date_prefix = find_week_files(OUTPUT_DIR, DATE_PREFIX)

    if not day_files and not grocery_file:
        print(f"ERROR: No recipe files found in {OUTPUT_DIR}")
        sys.exit(1)

    pdf_path = os.path.join(OUTPUT_DIR, f"{date_prefix}_meal_plan.pdf")
    print(f"Building PDF: {pdf_path}")
    print(f"  Found {len(day_files)} recipe file(s)" + (", grocery list" if grocery_file else ""))

    styles = build_styles()
    doc = SimpleDocTemplate(
        pdf_path,
        pagesize=letter,
        leftMargin=0.85 * inch,
        rightMargin=0.85 * inch,
        topMargin=0.9 * inch,
        bottomMargin=0.75 * inch,
        title=f"Family Meal Plan — {date_prefix}",
        author="Meal Planner",
    )

    story = []

    # Cover
    story.extend(cover_page(date_prefix, len(day_files), styles))

    # Recipes — one page break between each
    for idx, filepath in enumerate(day_files):
        with open(filepath, encoding='utf-8') as f:
            md = f.read()
        story.extend(markdown_to_flowables(md, styles))
        story.append(PageBreak())

    # Grocery list
    if grocery_file:
        with open(grocery_file, encoding='utf-8') as f:
            md = f.read()
        story.extend(markdown_to_flowables(md, styles))

    doc.build(story, onFirstPage=make_page_template, onLaterPages=make_page_template)
    print(f"Done! PDF saved to: {pdf_path}")

if __name__ == '__main__':
    main()