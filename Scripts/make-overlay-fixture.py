#!/usr/bin/env python3
"""A document with a table near the bottom of a 1200x900 window and plenty of text below it, so positions beyond the viewport are estimated."""
import sys
out = ["# Title here", "", "Paragraph with a {==comment==}{>>@sebo: note<<} in it and some more words so that it wraps once at the measure.", ""]
for i in range(1, 6): out += [f"- item {i} of the list, long enough to need a second line when the column is narrow or so"]
out += ["", "A paragraph between the list and the table, with a [link](x.md) and `code`.", "",
        "| Metric | Budget | Measured | Status |", "|---|---:|---:|:---:|",
        "| Cold launch to first paint | 200 ms | 180 ms | ok |", "| External change to paint | 50 ms | 44 ms | ok |", "| Open 1 MB file | 500 ms | 250 ms | ok |", "",
        "> quote with {==anchor==}{>>@claude: card<<} below the table", ""]
for i in range(40): out += [f"Filler paragraph {i} measure merge comment file sans speed viewport newsreader comment theme caret margin truth change diff file heading truth mono change.", ""]
open(sys.argv[1], "w").write("\n".join(out))
