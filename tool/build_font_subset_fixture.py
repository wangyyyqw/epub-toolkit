"""Generate an original geometric TrueType fixture; requires fontTools."""

from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def main():
    names = [".notdef", "A", "unused", "B", "component", "extra"]
    glyphs = {}
    for name in names:
        pen = TTGlyphPen(None)
        pen.moveTo((0, 0))
        pen.lineTo((200, 500))
        pen.lineTo((400, 0))
        pen.closePath()
        glyphs[name] = pen.glyph()
    pen = TTGlyphPen(glyphs)
    pen.addComponent("A", (1, 0, 0, 1, 0, 0))
    pen.addComponent("component", (0.5, 0, 0, 0.5, 200, 0))
    glyphs["B"] = pen.glyph()
    font = FontBuilder(1000, isTTF=True)
    font.setupGlyphOrder(names)
    font.setupCharacterMap({65: "A", 66: "B", 0x20000: "B"})
    font.setupGlyf(glyphs)
    font.setupHorizontalMetrics({name: (500, 0) for name in names})
    font.setupHorizontalHeader(ascent=800, descent=-200)
    font.setupNameTable({
        "familyName": "Original Subset Test", "styleName": "Regular",
        "uniqueFontIdentifier": "epub-toolkit-regression",
        "fullName": "Original Subset Test", "psName": "OriginalSubsetTest",
    })
    font.setupOS2()
    font.setupPost()
    font.setupMaxp()
    destination = Path("test/fixtures/subset_probe.ttf")
    destination.parent.mkdir(parents=True, exist_ok=True)
    font.save(destination)


if __name__ == "__main__":
    main()
