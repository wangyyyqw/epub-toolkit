"""Compare real EPUB shaping/outlines before and after subsetting.

Requires fontTools and uharfbuzz. The EPUB never leaves the local machine.
Checks every document, horizontal and vertical, plus every shared cmap entry.
"""

import argparse
import hashlib
import io
import json
import zipfile
import xml.etree.ElementTree as ET

import uharfbuzz as hb
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont


class Font:
    def __init__(self, data):
        self.tt = TTFont(io.BytesIO(data))
        self.glyphs = self.tt.getGlyphSet()
        self.order = self.tt.getGlyphOrder()
        self.cache = {}
        self.hb = hb.Font(hb.Face(data))
        hb.ot_font_set_funcs(self.hb)

    def outline(self, gid):
        if gid not in self.cache:
            pen = DecomposingRecordingPen(self.glyphs)
            self.glyphs[self.order[gid]].draw(pen)
            self.cache[gid] = hashlib.sha256(repr(pen.value).encode()).hexdigest()
        return self.cache[gid]

    def shape(self, text, vertical):
        buffer = hb.Buffer()
        buffer.add_str(text)
        buffer.guess_segment_properties()
        buffer.language = "zh"
        if vertical:
            buffer.direction = "ttb"
        hb.shape(self.hb, buffer)
        return [
            (self.outline(g.codepoint), g.cluster,
             p.x_advance, p.y_advance, p.x_offset, p.y_offset)
            for g, p in zip(buffer.glyph_infos, buffer.glyph_positions)
        ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original")
    parser.add_argument("processed")
    parser.add_argument("--output")
    args = parser.parse_args()
    report = []
    with zipfile.ZipFile(args.original) as source, zipfile.ZipFile(args.processed) as target:
        texts = []
        for name in source.namelist():
            if name.endswith((".xhtml", ".html")):
                root = ET.fromstring(source.read(name))
                texts.append((name, "".join(root.itertext())))
        for name in source.namelist():
            if not name.endswith((".otf", ".ttf")):
                continue
            before, after = Font(source.read(name)), Font(target.read(name))
            errors = []
            # Validate unencoded layout glyphs too by comparing actual shaped
            # outlines, not glyph IDs, which legitimately change in a subset.
            for doc, text in texts:
                for vertical in (False, True):
                    if before.shape(text, vertical) != after.shape(text, vertical):
                        errors.append({"document": doc, "vertical": vertical})
            common = set(before.tt.getBestCmap()) & set(after.tt.getBestCmap())
            probe = "".join(map(chr, sorted(common)))
            for vertical in (False, True):
                if before.shape(probe, vertical) != after.shape(probe, vertical):
                    errors.append({"document": "all-retained-codepoints", "vertical": vertical})
            report.append({
                "font": name,
                "documents": len(texts),
                "shaping_runs": (len(texts) + 1) * 2,
                "retained_codepoints": len(common),
                "compared_source_glyph_outlines": len(before.cache),
                "compared_subset_glyph_outlines": len(after.cache),
                "mismatches": errors,
            })
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    print(rendered)
    if args.output:
        with open(args.output, "w") as handle:
            handle.write(rendered + "\n")
    if any(row["mismatches"] for row in report):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
