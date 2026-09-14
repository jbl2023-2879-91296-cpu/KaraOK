"""Deterministic diagrams of the checked-in KaraOK application.

Run with the Codex bundled Python (reportlab, pypdf, pypdfium2, Pillow).
All coordinates use a top-left origin. No application services are started.
"""
from pathlib import Path
import hashlib
import json
import re
from xml.sax.saxutils import escape

from reportlab.graphics.shapes import Drawing, Rect, Line, Polygon, String
from reportlab.graphics import renderPDF, renderSVG
from reportlab.lib.colors import HexColor, Color
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen.canvas import Canvas

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
PDF = ROOT / 'output' / 'pdf' / 'karaok-application-diagrams.pdf'
INK = '#18332E'
MUTED = '#52645F'
ACCENT = '#176D58'
PALE = '#EAF3EF'
PAPER = '#FFFFFF'
LINE = '#75877F'
RULE = '#D4DFD9'
TABLES = {
    'D1': 'user', 'D2': 'assessment', 'D3': 'audio_upload',
    'D4': 'audio_analysis_result', 'D5': 'amplifier_profile',
    'D6': 'settings_recommendation', 'D7': 'registration_otp',
    'D8': 'refresh_token', 'D9': 'revoked_access_token',
    'D10': 'audit_log', 'D11': 'api_request_log',
}


class Diagram:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.d = Drawing(w, h)
        self.labels = []
        self.rect(0, 0, w, h, fill=PAPER, stroke=None)

    def rect(self, x, y, w, h, fill=PAPER, stroke=LINE, r=0, dashed=False):
        self.d.add(Rect(x, self.h-y-h, w, h, rx=r, ry=r,
                        fillColor=HexColor(fill) if fill else None,
                        strokeColor=HexColor(stroke) if stroke else None,
                        strokeWidth=1.5, strokeDashArray=[6, 5] if dashed else None))

    def text(self, x, y, value, size=18, bold=False, color=INK,
             anchor='start', leading=None, max_width=None):
        font = 'Helvetica-Bold' if bold else 'Helvetica'
        leading = leading or size*1.3
        for i, line in enumerate(value.split('\n')):
            if max_width is not None:
                assert stringWidth(line, font, size) <= max_width, (line, max_width)
            self.d.add(String(x, self.h-y-i*leading-size*.78, line,
                              fontName=font, fontSize=size,
                              fillColor=HexColor(color), textAnchor=anchor))
            self.labels.append(line)

    def line(self, x1, y1, x2, y2, color=LINE, width=1.5, dashed=False):
        self.d.add(Line(x1, self.h-y1, x2, self.h-y2,
                        strokeColor=HexColor(color), strokeWidth=width,
                        strokeDashArray=[5, 4] if dashed else None))

    def arrow(self, points, color=ACCENT, width=1.6, dashed=False):
        for p, q in zip(points, points[1:]):
            self.line(*p, *q, color=color, width=width, dashed=dashed)
        (x0, y0), (x, y) = points[-2:]
        dx, dy = x-x0, y-y0
        n = (dx*dx+dy*dy)**.5
        ux, uy = dx/n, dy/n
        a, b = 8, 3.4
        coords = [x, self.h-y,
                  x-a*ux+b*uy, self.h-(y-a*uy-b*ux),
                  x-a*ux-b*uy, self.h-(y-a*uy+b*ux)]
        self.d.add(Polygon(coords, fillColor=HexColor(color), strokeColor=None))

    def box(self, x, y, w, h, title, body='', title_size=24, body_size=18,
            fill=PAPER, dashed=False):
        self.rect(x, y, w, h, fill=fill, r=10, dashed=dashed)
        self.text(x+22, y+22, title, title_size, True, max_width=w-44)
        if body:
            self.text(x+22, y+title_size+42, body, body_size,
                      leading=body_size*1.45, max_width=w-44)

    def header(self, index, title, subtitle):
        self.text(45, 28, 'KaraOK  /  CURRENT APPLICATION', 16, True, ACCENT)
        self.text(45, 64, title, 39, True)
        self.text(45, 118, subtitle, 18, color=MUTED)
        self.text(self.w-45, 37, index, 22, True, ACCENT, anchor='end')
        self.line(45, 155, self.w-45, 155, color=RULE)

    def save(self, name):
        renderSVG.drawToFile(self.d, str(OUT / (name+'.svg')))
        (OUT / (name+'.labels.txt')).write_text('\n'.join(self.labels)+'\n', encoding='utf-8')


def architecture():
    g = Diagram(2200, 1280)
    g.header('01', 'Client-server architecture',
             'Flutter and the local PHP Admin Console use the Flask API; the API owns access to MySQL and analysis files.')
    # Physical / responsibility boundaries.
    g.rect(45, 185, 540, 940, fill='#F7FAF8', stroke=RULE)
    g.text(65, 203, 'CLIENT DEVICES', 18, True, ACCENT)
    g.rect(835, 185, 570, 940, fill='#F7FAF8', stroke=RULE)
    g.text(855, 203, 'APPLICATION SERVER', 18, True, ACCENT)
    g.text(1650, 203, 'DATA & SUPPORTING SERVICES', 18, True, ACCENT)

    g.box(70, 245, 490, 240, 'Flutter application',
          'Guest and registered-user workflows\nRecord / select audio; view quality reports\nAccount, history and amplifier settings*\nHTTP API client; bearer tokens when signed in', 26, 19)
    g.box(70, 545, 490, 172, 'App-private device storage',
          'Secure session-token storage\nGuest records, report images and profiles*\nPer-user history and downloaded-image cache', 23, 18, PALE)
    g.arrow([(210, 485), (210, 545)])
    g.arrow([(430, 545), (430, 485)])
    g.text(227, 508, 'local reads / writes', 16, color=MUTED)

    g.box(70, 760, 490, 100, 'Administrator browser',
          'Local console pages and forms', 24, 18)
    g.arrow([(170, 860), (170, 915)])
    g.arrow([(455, 915), (455, 860)])
    g.text(196, 878, 'loopback HTTP / HTML', 16, color=MUTED)
    g.box(70, 915, 490, 185, 'Local PHP Admin Console',
          'Server-side API client and local sign-in\nAnalytics, schema and allowed record edits\nLocal credentials, sessions, logs and cache', 24, 18)

    g.box(860, 245, 520, 113, 'HTTP entry point',
          'Repository deployment: Nginx -> Gunicorn\nDevelopment: Flask server', 24, 18)
    g.arrow([(1120, 358), (1120, 403)])
    g.box(860, 403, 520, 346, 'Flask API',
          'Authentication, verification and user profiles\nAudio evaluation, assessment history, reports\nAmplifier profiles and recommendations*\nData Administration API and table policies\nJWT / admin-key checks; request and audit logs', 28, 19)
    g.box(860, 819, 520, 184, 'Local analysis & recommendation code',
          'Python audio analyzer subprocess\nAudio measurements and empirical scoring\nMatplotlib waveform / spectrogram generation\nBounded settings recommendations*', 22, 18)
    g.arrow([(985, 749), (985, 819)])
    g.arrow([(1245, 819), (1245, 749)])
    g.text(1003, 775, 'audio / analysis output', 16, color=MUTED)
    g.text(880, 1040, 'One backend codebase; analysis executes locally.\nSettings output is applied physically by the user.', 18, color=MUTED)

    # Client request and return paths, separated from the boxes.
    g.arrow([(560, 306), (860, 306)])
    g.text(710, 260, 'HTTP(S) /api', 19, True, anchor='middle')
    g.text(710, 284, 'JSON + multipart audio', 16, anchor='middle')
    g.arrow([(860, 446), (710, 446), (710, 414), (560, 414)])
    g.text(711, 365, 'JSON results / tokens', 16, anchor='middle')
    g.text(711, 388, 'report image bytes', 16, anchor='middle')
    g.arrow([(560, 970), (747, 970), (747, 660), (860, 660)])
    g.text(704, 713, 'HTTP(S)', 18, True, anchor='middle')
    g.text(704, 741, '/api/admin/data', 17, anchor='middle')
    g.text(704, 767, 'server-side API key', 16, anchor='middle')
    g.arrow([(860, 705), (785, 705), (785, 1045), (560, 1045)])
    g.text(664, 1060, 'JSON data / reports', 16, anchor='middle')

    g.box(1650, 245, 505, 286, 'MySQL  /  karaok_db',
          'user  |  registration_otp\nrefresh_token  |  revoked_access_token\nassessment  |  audio_upload\naudio_analysis_result  |  amplifier_profile\nsettings_recommendation\naudit_log  |  api_request_log', 27, 19, PALE)
    g.arrow([(1380, 470), (1650, 470)])
    g.text(1515, 412, 'SQL queries / changes', 17, anchor='middle')
    g.arrow([(1650, 507), (1380, 507)])
    g.text(1515, 526, 'rows / query results', 17, anchor='middle')
    g.text(1515, 561, 'Separate application and', 14, color=MUTED, anchor='middle')
    g.text(1515, 582, 'data-admin DB identities', 14, color=MUTED, anchor='middle')

    g.box(1650, 620, 505, 171, 'Server filesystem',
          'Temporary uploaded audio: removed after use\nSigned-in analysis artifacts: retained\nWaveform / spectrogram paths stored in MySQL', 25, 18, PALE)
    g.arrow([(1380, 626), (1530, 626), (1530, 671), (1650, 671)])
    g.arrow([(1650, 751), (1490, 751), (1490, 705), (1380, 705)])
    g.text(1515, 687, 'files / image bytes', 16, anchor='middle')
    g.box(1650, 844, 505, 135, 'Versioned reference JSON',
          'Quality thresholds, genre profiles, control priors\nPlus checked-in analyzer configuration', 24, 18, PALE)
    g.arrow([(1650, 925), (1380, 925)])
    g.text(1515, 883, 'reference measurements', 16, anchor='middle')
    g.text(1515, 906, 'and configuration', 16, anchor='middle')

    g.box(1650, 1030, 505, 95, 'SMTP email service',
          'Registration OTP and temporary-password email', 24, 17)
    # An explicit API port follows the narrow right-hand server boundary.
    g.arrow([(1380, 735), (1394, 735), (1394, 1090), (1650, 1090)])
    g.text(1515, 1013, 'SMTP + STARTTLS', 17, anchor='middle')

    g.line(45, 1161, 2155, 1161, color=RULE)
    g.text(45, 1180, '* Implemented behind a settings feature flag (default: off). Deployment boxes describe checked-in configuration; live deployment was not queried.', 17, color=MUTED)
    g.text(45, 1208, 'Guest assessment data and report images stay device-local; the API still analyzes guest audio and records request / audit metadata.', 17, color=MUTED)
    g.text(45, 1237, 'Source: current repository b74ceb8, database/schema.sql and implementation files. Detailed evidence: docs/diagrams/evidence.md.', 16, color=MUTED)
    return g


def dfd():
    g = Diagram(2400, 1800)
    g.header('02', 'Level 1 data-flow diagram',
             'Scope: KaraOK server-side application. E1 = Flutter client; E2 = local Admin Console; E3 = SMTP email service.')
    g.text(45, 173, 'Six numbered processes. Store IDs repeat to avoid crossing lines; a repeated ID always denotes the same store.', 17, color=MUTED)

    def panel(x, y, num, title, desc, actor, input_label, output_label, stores,
              note='', email=False, logs=False):
        w, h = 1138, 451
        g.rect(x, y, w, h, stroke=RULE)
        g.text(x+17, y+16, title, 22, True)
        # Gane-Sarson rounded process, deliberately tall so each store has a port.
        px, py, pw, ph = x+355, y+72, 235, 325
        g.rect(px, py, pw, ph, fill=PALE, stroke=ACCENT, r=13)
        g.line(px, py+41, px+pw, py+41, color=ACCENT)
        g.text(px+pw/2, py+12, num, 23, True, ACCENT, anchor='middle')
        g.text(px+pw/2, py+137, desc, 20, True, anchor='middle', leading=27, max_width=pw-20)

        if logs:
            for i, p in enumerate(['1.0', '2.0', '3.0', '4.0', '5.0']):
                ey = y+83+i*58
                g.rect(x+22, ey, 166, 40, fill=PALE, stroke=ACCENT, r=8)
                g.text(x+105, ey+12, 'Process '+p+' (repeat)', 14, True, anchor='middle')
                g.arrow([(x+188, ey+20), (x+302, ey+20), (x+302, y+260)], color=LINE)
            g.arrow([(x+302, y+260), (px, y+260)])
            g.text(x+219, y+91, 'API request', 13, color=MUTED)
            g.text(x+219, y+110, 'metadata;', 13, color=MUTED)
            g.text(x+219, y+129, 'audit events', 13, color=MUTED)
            g.text(x+22, y+392, 'Only audit-instrumented actions emit audit events.', 13, color=MUTED)
        else:
            ax, ay, aw, ah = x+22, y+195, 174, 85
            g.rect(ax, ay, aw, ah, stroke=INK)
            g.text(ax+aw/2, ay+20, actor, 17, True, anchor='middle', leading=23, max_width=aw-12)
            g.arrow([(ax+aw, ay+17), (px, ay+17)])
            g.text((ax+aw+px)/2, ay-43, input_label, 12.5, anchor='middle', leading=17, max_width=156)
            g.arrow([(px, ay+68), (ax+aw, ay+68)])
            g.text((ax+aw+px)/2, ay+83, output_label, 12.5, anchor='middle', leading=17, max_width=156)
        # One open-ended symbol per actual table / file store.
        n = len(stores)
        weights = [1.6 if write and read else 1 for _, _, write, read in stores]
        unit = min(45, 319/sum(weights))
        heights = [unit*weight for weight in weights]
        sy = y+78 + (319-sum(heights))/2
        for idx, (sid, label, write, read) in enumerate(stores):
            spacing = heights[idx]
            cy = sy+sum(heights[:idx])+spacing/2
            sx, sw = x+824, 292
            sh = min(43, spacing-4)
            top = cy-sh/2
            g.line(sx, top, sx+sw, top, color=INK)
            g.line(sx, top+sh, sx+sw, top+sh, color=INK)
            g.line(sx, top, sx, top+sh, color=INK)
            g.line(sx+39, top, sx+39, top+sh, color=INK)
            g.text(sx+19.5, cy-6, sid, 12, True, anchor='middle')
            g.text(sx+49, cy-6, label, 13.5, max_width=sw-50)
            mid = (px+pw+sx)/2
            if write and read:
                g.arrow([(px+pw, cy-5), (sx, cy-5)])
                g.text(mid, cy-19, write, 10.5, anchor='middle', max_width=225)
                g.arrow([(sx, cy+8), (px+pw, cy+8)], color=LINE)
                g.text(mid, cy+12, read, 10.5, anchor='middle', max_width=225)
            elif write:
                g.arrow([(px+pw, cy), (sx, cy)])
                g.text(mid, cy-17, write, 11.5, anchor='middle', max_width=225)
            elif read:
                g.arrow([(sx, cy), (px+pw, cy)], color=LINE)
                g.text(mid, cy-17, read, 11.5, anchor='middle', max_width=225)
        if email:
            g.rect(x+22, y+355, 174, 64, stroke=INK)
            g.text(x+109, y+367, 'E3  SMTP\nemail service', 16, True, anchor='middle', leading=20)
            g.arrow([(px, y+365), (x+250, y+365), (x+250, y+387), (x+196, y+387)])
            g.text(x+265, y+334, 'OTP / recovery email', 12, anchor='middle')
        if note:
            g.text(x+17, y+425, note, 12.5, color=MUTED, max_width=w-34)

    panel(45, 214, '1.0', 'Identity, verification and sessions',
          'Manage accounts\nand sessions', 'E1  Flutter client\nGuest / signed in',
          'Credentials, OTP,\nprofile, session token', 'Account state,\nprofile, tokens', [
              ('D1', 'user', 'account / profile updates', 'identity / security state'),
              ('D7', 'registration_otp', 'hashed OTP / attempts / deletion', 'pending verification'),
              ('D8', 'refresh_token', 'token hash / rotation / revocation', 'refresh-session state'),
              ('D9', 'revoked_access_token', 'revoked JWT identifier', 'revocation state'),
          ], email=True)

    panel(1217, 214, '2.0', 'Audio assessment and optional settings generation',
          'Evaluate playback;\ngenerate / verify\nrecommendations*', 'E1  Flutter client\nGuest / signed in',
          'Audio + metadata;\ngenre / controls*', 'Scores, reports;\nrecommendations*', [
              ('D2', 'assessment', 'assessment / processing status', None),
              ('D3', 'audio_upload', 'upload metadata / score / status', None),
              ('D4', 'audio_analysis_result', 'measurements / provenance / paths', None),
              ('D5', 'amplifier_profile', None, 'owned scale / positions*'),
              ('D6', 'settings_recommendation', 'result / verification linkage*', 'parent recommendation*'),
              ('F1', 'Analysis artifacts (files)', 'working files / retained PNGs', 'analyzer output / PNG bytes'),
              ('F2', 'Reference JSON files', None, 'analyzer config / quality / genre'),
          ], note='D2-D6 business persistence is for signed-in users. Guest output is returned to E1; server artifacts are temporary.')

    panel(45, 694, '3.0', 'Amplifier profiles and applied-settings state*',
          'Manage profiles;\nrecord settings\napplied by user*', 'E1  Flutter client\nSigned-in user',
          'Scale, positions,\nprofile / apply data*', 'Profiles, metadata,\napplied status*', [
              ('D5', 'amplifier_profile', 'profile CRUD / last positions', 'owned profiles / scale'),
              ('D6', 'settings_recommendation', 'applied status / timestamp', 'owned recommendation'),
              ('F2', 'Reference JSON files', None, 'profile metadata / control prior'),
          ], note='Profile metadata also has a public endpoint. Applying settings records confirmation; the user moves the controls.')

    panel(1217, 694, '4.0', 'Assessment history and visual reports',
          'Manage records\nand reports', 'E1  Flutter client\nSigned-in user',
          'Record / report ID;\nrecord data / deletion', 'History, record,\nimage / status', [
              ('D2', 'assessment', 'record create / delete', 'owned assessment history'),
              ('D3', 'audio_upload', None, 'owned upload metadata'),
              ('D4', 'audio_analysis_result', 'result for record-create endpoint', 'stored measurements / paths'),
              ('D5', 'amplifier_profile', None, 'linked amplifier profile'),
              ('D6', 'settings_recommendation', None, 'linked recommendation'),
              ('F1', 'Analysis artifacts (files)', 'assessment artifact deletion', 'waveform / spectrogram bytes'),
              ('F2', 'Reference JSON files', None, 'quality-reference provenance'),
          ], note='Assessment deletion cascades to D3, D4 and D6 through the database foreign keys.')

    panel(45, 1174, '5.0', 'Administration and operational reporting',
          'Inspect data;\nperform allowed\nadministration', 'E2  Local Admin\nConsole',
          'API key, queries,\nallowed edit / delete', 'Reports, schema,\nrows, change status', [
              ('D1', 'user', 'active-status update', 'permitted account data'),
              ('D2', 'assessment', 'status update / deletion', 'assessment records'),
              ('D3', 'audio_upload', None, 'upload metadata'),
              ('D4', 'audio_analysis_result', None, 'analysis results'),
              ('D5', 'amplifier_profile', None, 'amplifier profiles'),
              ('D6', 'settings_recommendation', None, 'recommendation records'),
              ('D10', 'audit_log', None, 'audit entries'),
              ('D11', 'api_request_log', None, 'request metadata'),
              ('F1', 'Analysis artifacts (files)', 'deleted-assessment cleanup', None),
              ('S1', 'MySQL information_schema', None, 'table / column / FK metadata'),
          ], note='D7-D9 record contents are blocked by admin policy; schema metadata remains inspectable.')

    panel(1217, 1174, '6.0', 'Audit and request recording',
          'Record audit\nand API activity', None, None, None, [
              ('D10', 'audit_log', 'security / business audit event', None),
              ('D11', 'api_request_log', 'sanitized request metadata', None),
          ], logs=True, note='Bodies, credentials, OTPs and uploaded audio bytes are excluded from api_request_log.')

    g.line(45, 1649, 2355, 1649, color=RULE)
    g.text(45, 1666, 'Notation: square = external entity; rounded rectangle = process; open-ended store = data store; arrows = named data flows.', 17, color=MUTED)
    g.text(45, 1694, 'D1-D11 exactly match database/schema.sql. F1-F2 are filesystem stores; S1 is MySQL system metadata. These are not additional ERD tables.', 17, color=MUTED)
    g.text(45, 1722, '* Conditional settings feature (default: off). Shared authentication checks for protected requests reuse process 1.0. E1 owns device-local guest history.', 17, color=MUTED)
    g.text(45, 1750, 'Source: repository b74ceb8. Flow details and explicit limitations: docs/diagrams/evidence.md. This is a code-derived model, not a live-server inventory.', 16, color=MUTED)
    return g


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PDF.parent.mkdir(parents=True, exist_ok=True)
    actual = set(re.findall(r'CREATE TABLE IF NOT EXISTS\s+(\w+)', (ROOT/'database/schema.sql').read_text()))
    assert set(TABLES.values()) == actual, (actual, TABLES)
    diagrams = [('client-server-architecture', architecture()), ('dfd-level-1', dfd())]
    page_w, page_h = 1683.78, 1190.55  # A2 landscape; useful at print scale.
    c = Canvas(str(PDF), pagesize=(page_w, page_h))
    c.setTitle('KaraOK - Current Application Architecture and Level 1 DFD')
    c.setAuthor('KaraOK project documentation')
    for name, diagram in diagrams:
        diagram.save(name)
        scale = min(page_w/diagram.w, page_h/diagram.h)
        c.saveState()
        c.translate((page_w-diagram.w*scale)/2, (page_h-diagram.h*scale)/2)
        c.scale(scale, scale)
        renderPDF.draw(diagram.d, c, 0, 0)
        c.restoreState()
        c.showPage()
    c.save()
    # Render the actual PDF pages for inspection and shareable PNGs.
    import pypdfium2 as pdfium
    from pypdf import PdfReader
    reader = PdfReader(str(PDF))
    assert len(reader.pages) == 2
    pdf_text = '\n'.join(page.extract_text() for page in reader.pages)
    for table in actual:
        assert table in pdf_text, table
    document = pdfium.PdfDocument(str(PDF))
    for index, (name, diagram) in enumerate(diagrams):
        page = document[index]
        bitmap = page.render(scale=1.65)
        picture = bitmap.to_pil()
        picture.save(OUT/(name+'.png'))
        bitmap.close()
        page.close()
    document.close()
    # Machine-readable store dictionary and receipt; detailed evidence is separate.
    (OUT/'store-dictionary.json').write_text(json.dumps(TABLES, indent=2)+'\n')
    paths = [PDF] + [OUT/(name+ext) for name, _ in diagrams for ext in ['.svg','.png']]
    receipt = {
        'basis': 'Checked-in code at b74ceb8 and authoritative 11-table schema; live services not queried.',
        'method': 'Deterministic reportlab vector geometry; PDFium rasterization of final PDF.',
        'skill': 'editorial-infographics; pdf',
        'pdf_pages': len(reader.pages),
        'database_tables_verified': sorted(actual),
        'assets': [{'path': str(p.relative_to(ROOT)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths],
    }
    (OUT/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps({'pdf': str(PDF), 'pages': 2, 'exact_schema_table_match': True, 'assets': [str(p) for p in paths]}, indent=2))


if __name__ == '__main__':
    main()
