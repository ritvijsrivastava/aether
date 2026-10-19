#!/usr/bin/env python3
"""Generates the git-ignored test PDFs that need no third-party content.

  python3 tool/make_test_pdfs.py

Writes into test/fixtures/generated/:
  rotated.pdf   7 pages with the line "Hello rotation test": /Rotate 0, 90,
                180, 270 (text upright on screen), a page with a CropBox that
                does not start at the origin, and /Rotate 90 and 180 with the
                text left as drawn (sideways and upside down on screen)
  scanned.pdf   one page that is only a picture of text (no text layer)

Needs: python3 with PIL, and pdftoppm + ImageMagick `magick` for scanned.pdf.
"""
import os, subprocess, sys

out = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures', 'generated')
os.makedirs(out, exist_ok=True)


def pdf(objects):
    """objects: list of bytes bodies, object n is objects[n-1]."""
    buf = bytearray(b'%PDF-1.4\n')
    offsets = []
    for i, body in enumerate(objects, 1):
        offsets.append(len(buf))
        buf += b'%d 0 obj\n' % i + body + b'\nendobj\n'
    xref = len(buf)
    buf += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)
    for o in offsets:
        buf += b'%010d 00000 n \n' % o
    buf += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    return bytes(buf)


def rotated():
    # (rotate, text matrix, cropbox). The "upright" pages draw their text
    # turned so that it reads upright on screen after the page's /Rotate,
    # which is how real rotated pages are made. The two "sideways" pages
    # leave the text as drawn, so it reads sideways / upside down on screen.
    # The baseline starts 72 pt from the left and 150 pt from the top of what
    # is displayed.
    pages = [
        (0,   b'1 0 0 1 72 642',        None),                  # 0 upright
        (90,  b'0 1 -1 0 150 72',       None),                  # 1 upright after /Rotate 90
        (180, b'-1 0 0 -1 540 150',     None),                  # 2 upright after /Rotate 180
        (270, b'0 -1 1 0 462 720',      None),                  # 3 upright after /Rotate 270
        (0,   b'1 0 0 1 72 642',        (50, 50, 562, 742)),    # 4 crop box, origin not at 0,0
        (90,  b'1 0 0 1 72 700',        None),                  # 5 sideways on screen
        (180, b'1 0 0 1 72 700',        None),                  # 6 upside down on screen
    ]
    objs = [None, None, b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    kids = []
    for rot, tm, crop in pages:
        content = b'BT /F1 24 Tf ' + tm + b' Tm (Hello rotation test) Tj ET'
        pid = len(objs) + 1
        cid = len(objs) + 2
        extra = b' /Rotate %d' % rot if rot else b''
        if crop:
            extra += b' /CropBox [%d %d %d %d]' % crop
        objs.append(
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]' + extra +
            b' /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>' % cid)
        objs.append(b'<< /Length %d >>\nstream\n' % len(content) + content + b'\nendstream')
        kids.append(b'%d 0 R' % pid)
    objs[0] = b'<< /Type /Catalog /Pages 2 0 R >>'
    objs[1] = b'<< /Type /Pages /Kids [' + b' '.join(kids) + b'] /Count %d >>' % len(kids)
    with open(os.path.join(out, 'rotated.pdf'), 'wb') as f:
        f.write(pdf(objs))


def scanned():
    src = os.path.join(out, 'plain.pdf')
    if not os.path.exists(src):
        src = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures', 'mapreduce', 'mapreduce.pdf')
    if not os.path.exists(src):
        print('scanned.pdf skipped: no mapreduce.pdf to photograph', file=sys.stderr)
        return
    png = os.path.join(out, 'scan_page')
    subprocess.check_call(['pdftoppm', '-r', '110', '-f', '1', '-l', '1', '-png', '-singlefile', src, png])
    subprocess.check_call(['magick', png + '.png', '-colorspace', 'Gray', '-units', 'PixelsPerInch',
                           '-density', '110', os.path.join(out, 'scanned.pdf')])
    os.remove(png + '.png')


rotated()
scanned()
print('wrote', sorted(f for f in os.listdir(out) if f in ('rotated.pdf', 'scanned.pdf')))
