"""Local-only visual QA API. Synthetic test data; never opens a MySQL connection.
Run from backend: python -m tests.admin_preview_api
"""
from flask import Flask, jsonify, request
from tests.test_admin_reports import ReportTests
from karaok.modules.admin_data import reports

app = Flask(__name__)
fixture = ReportTests()
fixture.setUp()

@app.before_request
def key():
    if request.headers.get('Authorization') != 'Bearer fixture-key-only-not-a-real-machine-key':
        return jsonify(error='Unauthorized'), 401

@app.get('/api/admin/data/reports/<section>')
def report(section):
    result = reports.report(section, request.args.to_dict())
    result['meta']['coverage'] = 'SYNTHETIC QA FIXTURE — not production data. ' + result['meta']['coverage']
    return jsonify(result)

@app.get('/api/admin/data/directory/<kind>')
def directory(kind):
    return jsonify(reports.directory(kind, request.args.to_dict()))

@app.get('/api/admin/data/directory/<kind>/<record_id>')
def detail(kind, record_id):
    return jsonify(reports.detail(kind, record_id, request.args.to_dict()))

@app.errorhandler(ValueError)
def invalid(error): return jsonify(error=str(error)), 400

@app.errorhandler(Exception)
def failed(error): return jsonify(error='QA fixture endpoint unavailable'), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8092, threaded=False, use_reloader=False)
