"""Generate original geometric CFF/GSUB test fonts, without third-party artwork."""

from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.t2CharStringPen import T2CharStringPen


def build(cff):
    names = [".notdef", "space", "A", "B", "lig", "vertical", "unused"]
    builder = FontBuilder(1000, isTTF=not cff)
    builder.setupGlyphOrder(names)
    builder.setupCharacterMap({32: "space", 65: "A", 66: "B", 67: "unused"})
    outlines = {}
    for index, name in enumerate(names):
        pen = T2CharStringPen(600, None) if cff else TTGlyphPen(None)
        if name != "space":
            pen.moveTo((0, 0))
            pen.lineTo((200 + index * 20, 500))
            pen.lineTo((400, 0))
            pen.closePath()
        outlines[name] = pen.getCharString() if cff else pen.glyph()
    if cff:
        builder.setupCFF("OriginalComplexProbe", {}, outlines, {})
    else:
        builder.setupGlyf(outlines)
    builder.setupHorizontalMetrics({name: (600, 0) for name in names})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({
        "familyName": "Original Complex Probe",
        "styleName": "Regular",
        "uniqueFontIdentifier": "epub-toolkit-complex-regression",
        "fullName": "Original Complex Probe",
        "psName": "OriginalComplexProbe",
    })
    builder.setupOS2()
    builder.setupPost()
    builder.setupMaxp()
    addOpenTypeFeaturesFromString(builder.font, """
        languagesystem DFLT dflt;
        feature liga { sub A B by lig; } liga;
        feature vert {
            sub A by vertical;
            pos unused <0 20 0 0>;
        } vert;
        feature ss01 { sub B by vertical; } ss01;
    """)
    builder.save(Path("test/fixtures") / ("complex_probe.otf" if cff else "complex_probe.ttf"))


if __name__ == "__main__":
    build(False)
    build(True)
