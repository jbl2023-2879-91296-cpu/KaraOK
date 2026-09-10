"""Report arithmetic tests on disposable SQLite data, plus real Flask auth tests.

The adapter translates only MySQL scalar/date syntax; joins, grouping, bounds,
window functions and pagination are executed rather than mocked. Production
MySQL dialect still requires a staging smoke test before deployment.
"""
import calendar
from contextlib import contextmanager
from datetime import date, datetime, timedelta
import re
import sqlite3
import unittest
from unittest.mock import patch

from tests import test_admin_data_api as existing
from karaok.modules.admin_data import reports
from mysql.connector import Error


class Cursor:
    def __init__(self, db): self.db = db
    def execute(self, sql, params=()):
        sql = sql.replace('%s', '?')
        sql = re.sub(r'TIMESTAMPDIFF\((YEAR|SECOND),', r"TIMESTAMPDIFF('\1',", sql)
        sql = sql.replace('LEFT(u.email,1)', 'SUBSTR(u.email,1,1)').replace('RIGHT(u.phone_number,2)', 'SUBSTR(u.phone_number,-2)')
        self.result = self.db.execute(sql, tuple(str(v) if isinstance(v,date) else v for v in params))
    def fetchall(self): return [dict(r) for r in self.result.fetchall()]


class ReportTests(unittest.TestCase):
    def setUp(self):
        class FixedDateTime(datetime):
            @classmethod
            def now(cls, tz=None): return cls(2026,9,10,tzinfo=tz)
        clock = patch.object(reports, 'datetime', FixedDateTime)
        clock.start(); self.addCleanup(clock.stop)
        self.db = sqlite3.connect(':memory:'); self.db.row_factory = sqlite3.Row
        self.addCleanup(self.db.close)
        self.db.create_function('TIMESTAMPDIFF',3,lambda unit,a,b: None if a is None or b is None else (reports.age_on(date.fromisoformat(a[:10]),date.fromisoformat(b[:10])) if unit=='YEAR' else (datetime.fromisoformat(b)-datetime.fromisoformat(a)).total_seconds()))
        for name, index in [('YEAR',0),('MONTH',1),('DAY',2)]:
            self.db.create_function(name,1,lambda v,i=index: int(v[:10].split('-')[i]) if v else None)
        self.db.create_function('LAST_DAY',1,lambda v: str(date(int(v[:4]),int(v[5:7]),calendar.monthrange(int(v[:4]),int(v[5:7]))[1])) if v and int(v[5:7]) else None)
        self.db.create_function('WEEKDAY',1,lambda v: date.fromisoformat(v[:10]).weekday())
        self.db.create_function('CONCAT',-1,lambda *args: ''.join(str(a) for a in args))
        self.db.create_function('SUBSTRING_INDEX',3,lambda s,sep,n:s.split(sep)[-1])
        self.db.executescript('''
        CREATE TABLE user(user_id INTEGER PRIMARY KEY,username TEXT,first_name TEXT,last_name TEXT,email TEXT,phone_number TEXT,birthday TEXT,country TEXT,city TEXT,created_at TEXT,role TEXT,is_active INTEGER,email_verified_at TEXT);
        CREATE TABLE assessment(assessment_id INTEGER PRIMARY KEY,user_id INTEGER,assessment_date TEXT,assessment_status TEXT,processing_time REAL,duration_seconds INTEGER,analysis_purpose TEXT);
        CREATE TABLE audio_analysis_result(assessment_id INTEGER UNIQUE,quality_score REAL);
        CREATE TABLE audio_upload(assessment_id INTEGER UNIQUE,genre_name TEXT);
        CREATE TABLE api_request_log(created_at TEXT,status_code INTEGER,duration_ms REAL);
        CREATE TABLE audit_log(audit_log_id INTEGER,action TEXT,resource_type TEXT,resource_id INTEGER,result TEXT,created_at TEXT);
        INSERT INTO user VALUES(1,'ada','Ada','A','ada@example.test','123456789','2000-09-10','PH','Manila','2026-08-01','user',1,'2026-08-01');
        INSERT INTO user VALUES(2,'ben','Ben','B','ben@example.test','987654321',NULL,'PH','Cebu','2026-09-02','user',0,NULL);
        INSERT INTO user VALUES(3,'admin','Admin','A','admin@example.test','1234','1980-01-01','PH','Manila','2026-09-01','admin',1,NULL);
        INSERT INTO user VALUES(4,'cy','Cy','C','cy@example.test','5432','2010-01-01','US','Boston','2026-09-03','user',1,NULL);
        INSERT INTO assessment VALUES(1,1,'2026-08-31','Completed',4,20,'quality_evaluation');
        INSERT INTO assessment VALUES(2,1,'2026-09-01','Completed',2,20,'quality_evaluation');
        INSERT INTO assessment VALUES(3,1,'2026-09-02','Completed',8,20,'quality_evaluation');
        INSERT INTO assessment VALUES(4,2,'2026-09-03','Failed',3,20,'quality_evaluation');
        INSERT INTO assessment VALUES(5,3,'2026-09-03','Completed',1,20,'quality_evaluation');
        INSERT INTO assessment VALUES(6,1,'2026-09-08','Completed',6,20,'quality_evaluation');
        INSERT INTO audio_analysis_result VALUES(1,50),(2,0),(3,80),(5,100),(6,90);
        INSERT INTO audio_upload VALUES(1,'Pop'),(2,'Pop'),(3,'Rock'),(4,NULL),(5,'Pop');
        ''')
        for field in ['noise_level','distortion_level','bass','treble','loudness','sharpness','flatness','empirical_status','worst_feature_status','worst_features','empirical_details','scoring_algorithm_version','quality_profile_version','reference_recording_count']:
            self.db.execute('ALTER TABLE audio_analysis_result ADD COLUMN '+field)
        self.db.execute('ALTER TABLE assessment ADD COLUMN result_status TEXT')
        self.db.executescript('''CREATE TABLE amplifier_profile(amplifier_profile_id INTEGER,user_id INTEGER,name TEXT,scale_min REAL,scale_max REAL,scale_step REAL,last_positions TEXT,created_at TEXT,updated_at TEXT);
        CREATE TABLE settings_recommendation(recommendation_id INTEGER,user_id INTEGER,assessment_id INTEGER,parent_recommendation_id INTEGER,genre TEXT,original_score REAL,verification_score REAL,overall_confidence TEXT,algorithm_version TEXT,genre_profile_version TEXT,recommendation_status TEXT,created_at TEXT,recommended_positions TEXT,scale_min REAL,scale_max REAL);
        INSERT INTO amplifier_profile VALUES(1,1,'Fixture amplifier',0,10,1,'{"volume":5,"bass":4,"treble":6,"sharpness":5,"flatness":5}','2026-08-01','2026-09-01');
        INSERT INTO settings_recommendation VALUES(1,1,2,NULL,'Pop',40,60,'provisional','v1','v1','verified','2026-09-02','{"volume":5,"bass":4,"treble":6,"sharpness":5,"flatness":5}',0,10);
        INSERT INTO settings_recommendation VALUES(2,1,3,1,'Pop',40,60,'provisional','v1','v1','generated','2026-09-03','{"volume":5,"bass":4,"treble":6,"sharpness":5,"flatness":5}',0,10);''')
        self.db.create_function('JSON_UNQUOTE',1,lambda value: value)
        @contextmanager
        def reader(): yield Cursor(self.db)
        p=patch.object(reports,'reader',reader);p.start();self.addCleanup(p.stop)
        self.query={'start':'2026-09-01','end':'2026-09-07'}

    def test_overview_does_not_multiply_joins_and_excludes_admin_and_end_boundary(self):
        data=reports.report('overview',self.query)
        self.assertEqual(data['metrics']['assessments'],3)
        self.assertEqual(data['metrics']['assessment_active_users'],2)
        self.assertEqual(data['metrics']['average_audio_quality_score'],40)
        self.assertEqual(data['metrics']['median_processing_seconds'],5)
        self.assertEqual(data['metrics']['completion_rate_percent'],66.67)
        self.assertEqual(data['lifetime']['registered_users'],3)
        self.assertEqual(data['metrics']['new_registrations'],2)
        self.assertEqual(data['previous']['assessments'],1)

    def test_empty_counts_zero_but_averages_and_rates_null(self):
        data=reports.report('overview',{'start':'2025-01-01','end':'2025-01-07'})
        self.assertEqual(data['metrics']['assessments'],0)
        self.assertIsNone(data['metrics']['average_audio_quality_score'])
        self.assertIsNone(data['metrics']['completion_rate_percent'])
        self.assertIsNone(data['metrics']['median_processing_seconds'])

    def test_participation_and_registration_conversion(self):
        data=reports.report('usage',self.query)
        self.assertEqual(data['conversion']['registrations'],2)
        self.assertEqual(data['conversion']['converted_users'],1)
        self.assertEqual(data['conversion']['conversion_percent'],50)
        self.assertEqual(data['conversion']['mean_hours_to_first_assessment'],24)
        self.assertEqual({r['assessor_type']:r['users'] for r in data['assessors']},{'First-time':1,'Returning':1})
        self.assertEqual(data['metrics']['assessments_per_participant'],1.5)

    def test_demographics_denominator_includes_unknown(self):
        data=reports.report('demographics',self.query)
        self.assertEqual(sum(r['users'] for r in data['ages']),3)
        self.assertEqual(sum(r['participants'] for r in data['ages']),2)
        unknown=next(r for r in data['ages'] if r['age_group']=='Unknown/invalid')
        self.assertEqual(unknown['users'],1)
        self.assertEqual(unknown['percent'],33.33)

    def test_directory_filters_masking_and_pagination(self):
        data=reports.directory('users',dict(self.query,status='deactivated',verified='no',country='PH'))
        self.assertEqual(data['total'],1)
        self.assertEqual(data['rows'][0]['email'],'b***@example.test')
        self.assertEqual(data['rows'][0]['phone'],'***21')
        self.assertNotIn('birthday',data['rows'][0])
        self.assertEqual(reports.directory('users',dict(self.query,page='2'))['rows'],[])
        self.assertEqual(reports.directory('users',dict(self.query,age_min='100'))['total'],0)
        self.assertEqual(reports.directory('users',dict(self.query,search="' OR 1=1 --"))['total'],0)

    def test_quality_null_and_zero_distinct(self):
        data=reports.report('quality',self.query)
        self.assertEqual({r['score_band']:r['assessments'] for r in data['scores']},{'0–19':1,'80–100':1,'Not scored':1})

    def test_invalid_parameters_rejected(self):
        for changes in [{'sort':'password'},{'page':'0'},{'direction':'DROP'},{'age_min':'-1'},{'status':'admin'},{'search':'x'*101}]:
            with self.subTest(changes=changes),self.assertRaises(ValueError): reports.directory('users',dict(self.query,**changes))

    def test_linked_verification_counted_once_and_knobs_normalized(self):
        with patch.object(reports,'SETTINGS_RECOMMENDATIONS_ENABLED',True):
            data=reports.report('amplifiers',self.query)
        self.assertEqual(len(data['verified']),1)
        self.assertEqual(data['verified'][0]['verification_assessment_id'],3)
        self.assertEqual(data['verified'][0]['recorded_difference'],20)
        volume=next(row for row in data['positions'] if row['control']=='volume')
        self.assertEqual(volume['normalized_percent_bucket'],50)
        self.assertEqual(volume['recommendations'],2)

    def test_detail_is_owner_scoped_and_has_no_secret_fields(self):
        self.assertEqual(reports.detail('assessments','2',self.query)['profile']['quality_score'],0)
        with self.assertRaises(LookupError): reports.detail('assessments','5',self.query)
        with self.assertRaises(LookupError): reports.detail('users','3',self.query)
        data=reports.detail('users','1',self.query)
        self.assertNotIn('birthday',data['profile'])
        self.assertNotIn('password',data['profile'])

    def test_feature_disabled_returns_no_recommendation_data(self):
        with patch.object(reports,'SETTINGS_RECOMMENDATIONS_ENABLED',False):
            self.assertEqual(set(reports.report('amplifiers',self.query)),{'meta','enabled'})

    def test_sql_age_rule_rejects_invalid_dates_and_observes_birthday(self):
        cases = [('2008-09-10',18),('2008-09-11',17),('0000-00-00',None),
                 ('2000-02-31',None),('2027-01-01',None),('1800-01-01',None)]
        for birthday, expected in cases:
            with self.subTest(birthday=birthday):
                self.db.execute('UPDATE user SET birthday=? WHERE user_id=1',(birthday,))
                data=reports.directory('users',{'start':'2026-08-01','end':'2026-09-07','user_id':'1'})
                self.assertEqual(data['rows'][0]['age'],expected)

    def test_age_boundaries_and_leap_day(self):
        for age in [18,25,35,45,55,65]:
            birthday=date(2026-age,9,10)
            self.assertEqual(reports.age_on(birthday,date(2026,9,9)),age-1)
            self.assertEqual(reports.age_on(birthday,date(2026,9,10)),age)
        self.assertEqual(reports.age_on(date(2004,2,29),date(2025,2,28)),20)
        self.assertEqual(reports.age_on(date(2004,2,29),date(2025,3,1)),21)
        self.assertIsNone(reports.age_on(date(2027,1,1),date(2026,1,1)))
        self.assertIsNone(reports.age_on(None,date(2026,1,1)))
        self.assertIsNone(reports.age_on(date(1800,1,1),date(2026,1,1)))

    def test_date_presets_and_invalid_ranges(self):
        for days in [7,30,90]:
            start,end=reports.window({'days':str(days)},date(2026,9,10))
            self.assertEqual((end-start).days,days)
            self.assertEqual(end,date(2026,9,10))
        self.assertEqual(reports.window({'days':'custom','start':'2026-09-01','end':'2026-09-03'},date(2026,9,10)),(date(2026,9,1),date(2026,9,4)))
        for q in [{'days':'custom'}, {'start':'bad'}, {'days':'9'}, {'start':'2026-09-09','end':'2026-09-01'}, {'end':'2026-09-10'}, {'start':'2020-01-01','end':'2026-01-01'}]:
            with self.subTest(q=q),self.assertRaises(ValueError): reports.window(q,date(2026,9,10))


class ReportRouteTests(unittest.TestCase):
    setUp = existing.AdminDataApiTests.setUp
    def test_new_endpoints_require_authentication(self):
        for url in ['/reports/overview','/directory/users','/directory/users/1']:
            self.assertEqual(self.client.get('/api/admin/data'+url).status_code,401)

    def test_failures_do_not_return_fabricated_reports(self):
        with patch.object(reports,'report',side_effect=Error('private database message')):
            response=self.client.get('/api/admin/data/reports/overview',headers=self.headers)
        self.assertEqual(response.status_code,500)
        self.assertEqual(response.get_json(),{'error':'Database operation failed'})

    def test_report_query_is_passed_and_invalid_dates_return_400(self):
        response=self.client.get('/api/admin/data/reports/overview?start=invalid',headers=self.headers)
        self.assertEqual(response.status_code,400)


if __name__=='__main__': unittest.main()
