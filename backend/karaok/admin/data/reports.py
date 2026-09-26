"""Read-only product reports. Every timestamp is evaluated in UTC.

Only stored assessments belonging to role=user count as activity. Each join
uses a unique assessment key; no request log is used as a user event.
"""
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone

from . import service
from ...core.config import SETTINGS_RECOMMENDATIONS_ENABLED


AGE = """CASE WHEN u.birthday IS NULL OR YEAR(u.birthday) = 0
 OR MONTH(u.birthday) = 0 OR DAY(u.birthday) = 0
 OR DAY(u.birthday) > DAY(LAST_DAY(u.birthday))
 OR u.birthday > %s OR TIMESTAMPDIFF(YEAR,u.birthday,%s) > 120
 THEN NULL ELSE TIMESTAMPDIFF(YEAR,u.birthday,%s) END"""
AGE_GROUP = """CASE WHEN age IS NULL THEN 'Unknown/invalid' WHEN age < 18 THEN 'Under 18'
 WHEN age < 25 THEN '18–24' WHEN age < 35 THEN '25–34' WHEN age < 45 THEN '35–44'
 WHEN age < 55 THEN '45–54' WHEN age < 65 THEN '55–64' ELSE '65+' END"""
BASE = " FROM assessment a JOIN user u ON u.user_id=a.user_id LEFT JOIN audio_analysis_result r ON r.assessment_id=a.assessment_id LEFT JOIN audio_upload f ON f.assessment_id=a.assessment_id "


def window(query, today=None):
    today = today or datetime.now(timezone.utc).date()
    try:
        custom = query.get('days') == 'custom'
        if custom and not (query.get('start') and query.get('end')):
            raise ValueError()
        days = 30 if custom else int(query.get('days', 30))
        if days not in (7, 30, 90):
            raise ValueError()
        end = date.fromisoformat(query['end']) if query.get('end') else today - timedelta(days=1)
        start = date.fromisoformat(query['start']) if query.get('start') else end - timedelta(days=days-1)
    except (ValueError, TypeError):
        raise ValueError('Use valid ISO dates and a 7, 30 or 90 day preset') from None
    if start > end or (end-start).days >= 366 or end >= today:
        raise ValueError('Select 1–366 complete UTC days ending before today')
    return start, end + timedelta(days=1)


def age_on(birthday, reference):
    """Reference implementation for the SQL age rule, including leap birthdays."""
    if not isinstance(birthday, date) or birthday > reference:
        return None
    age = reference.year-birthday.year-((reference.month, reference.day) < (birthday.month, birthday.day))
    return age if age <= 120 else None


@contextmanager
def reader():
    connection = service._connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute("SET time_zone = '+00:00'")
        # Consistent snapshot across each report; never retain connections in cache.
        connection.start_transaction(consistent_snapshot=True, readonly=True)
        yield cursor
    finally:
        connection.rollback()
        cursor.close()
        connection.close()


def rows(cursor, sql, params=()):
    cursor.execute(sql, tuple(params))
    return [service._json_safe(row) for row in cursor.fetchall()]


def one(cursor, sql, params=()):
    return rows(cursor, sql, params)[0]


def report(section, query):
    if section not in ('overview', 'demographics', 'usage', 'quality', 'amplifiers', 'operations'):
        raise ValueError('Unknown report')
    start, end = window(query)
    reference = datetime.now(timezone.utc).date()
    args = (start, end)
    where = " WHERE u.role='user' AND a.assessment_date >= %s AND a.assessment_date < %s "
    result = {'meta': {'start': start.isoformat(), 'end': (end-timedelta(days=1)).isoformat(),
        'timezone': 'UTC', 'age_reference': reference.isoformat(),
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'coverage': 'Stored assessments of registered non-administrator users only. Guest assessments stay device-local.',
        'window': 'Inclusive dates; complete UTC days. Lifetime metrics are explicitly labelled.'}}
    with reader() as c:
        if section == 'overview':
            result['lifetime'] = one(c, """SELECT COUNT(*) registered_users,
                COALESCE(SUM(is_active=1),0) enabled_accounts, COALESCE(SUM(is_active=0),0) deactivated_accounts,
                COALESCE(SUM(email_verified_at IS NOT NULL),0) verified_accounts,
                COALESCE(SUM(email_verified_at IS NULL),0) unverified_accounts FROM user WHERE role='user'""")
            def metrics(bounds):
                m = one(c, """SELECT COUNT(*) assessments, COUNT(DISTINCT a.user_id) assessment_active_users,
                    COALESCE(SUM(a.assessment_status='Completed'),0) completed,
                    COALESCE(SUM(a.assessment_status='Failed'),0) failed,
                    ROUND(100.0*SUM(a.assessment_status='Completed')/NULLIF(COUNT(*),0),2) completion_rate_percent,
                    ROUND(AVG(CASE WHEN a.assessment_status='Completed' THEN r.quality_score END),2) average_audio_quality_score,
                    COUNT(CASE WHEN a.assessment_status='Completed' THEN r.quality_score END) scored_completed_assessments
                    """ + BASE + where, bounds)
                m.update(one(c, "SELECT COUNT(*) new_registrations FROM user WHERE role='user' AND created_at >= %s AND created_at < %s", bounds))
                m.update(one(c, """SELECT ROUND(AVG(processing_time),3) median_processing_seconds FROM (
                    SELECT a.processing_time, ROW_NUMBER() OVER (ORDER BY a.processing_time) n, COUNT(*) OVER () total
                    FROM assessment a JOIN user u ON u.user_id=a.user_id
                    WHERE u.role='user' AND a.assessment_date >= %s AND a.assessment_date < %s
                    AND a.assessment_status='Completed' AND a.processing_time >= 0
                    ) p WHERE n IN (FLOOR((total+1)/2),FLOOR((total+2)/2))""", bounds))
                return m
            result['metrics'] = metrics(args)
            result['previous'] = metrics((start-(end-start), start))
            result['registrations'] = rows(c, "SELECT DATE(created_at) day,COUNT(*) total FROM user WHERE role='user' AND created_at >= %s AND created_at < %s GROUP BY day ORDER BY day", args)
            result['trend'] = rows(c, "SELECT DATE(a.assessment_date) day,COUNT(*) total"+BASE+where+" GROUP BY day ORDER BY day", args)
            result['statuses'] = rows(c, "SELECT a.assessment_status status,COUNT(*) total"+BASE+where+" GROUP BY a.assessment_status ORDER BY total DESC", args)
            result['genres'] = rows(c, "SELECT COALESCE(NULLIF(f.genre_name,''),'Not collected') genre,COUNT(*) total"+BASE+where+" GROUP BY genre ORDER BY total DESC LIMIT 20", args)
            result['recent'] = rows(c, "SELECT a.assessment_id,a.user_id,u.username,a.assessment_date,a.assessment_status,r.quality_score"+BASE+where+" ORDER BY a.assessment_date DESC,a.assessment_id DESC LIMIT 10", args)
        elif section == 'demographics':
            users = "SELECT u.user_id,u.country,u.city,"+AGE+" age FROM user u WHERE u.role='user'"
            age_args = (reference,)*3
            result['ages'] = rows(c, "SELECT "+AGE_GROUP+" age_group,COUNT(*) users, ROUND(100.0*COUNT(*)/NULLIF(SUM(COUNT(*)) OVER (),0),2) percent, SUM(EXISTS(SELECT 1 FROM assessment a WHERE a.user_id=d.user_id AND a.assessment_date >= %s AND a.assessment_date < %s)) participants FROM ("+users+") d GROUP BY age_group ORDER BY MIN(COALESCE(age,999))", args+age_args)
            age_rows = {row['age_group']: row for row in result['ages']}
            denominator = sum(row['users'] for row in age_rows.values())
            result['ages'] = [age_rows.get(label, {'age_group': label, 'users': 0,
                'percent': 0 if denominator else None, 'participants': 0})
                for label in ('Under 18', '18–24', '25–34', '35–44', '45–54', '55–64', '65+', 'Unknown/invalid')]
            for field in ('country','city'):
                result[field] = rows(c, "SELECT COALESCE(NULLIF("+field+",''),'Unknown') location,COUNT(*) users,ROUND(100.0*COUNT(*)/NULLIF(SUM(COUNT(*)) OVER (),0),2) percent FROM user WHERE role='user' GROUP BY location ORDER BY users DESC,location LIMIT 25")
        elif section == 'usage':
            result['metrics'] = one(c, "SELECT COUNT(DISTINCT a.user_id) participating_users, ROUND(1.0*COUNT(*)/NULLIF(COUNT(DISTINCT a.user_id),0),2) assessments_per_participant"+BASE+where, args)
            for label, days in [('daily',1),('weekly',7),('monthly',30)]:
                result['metrics'][label+'_active_users'] = one(c, "SELECT COUNT(DISTINCT a.user_id) total FROM assessment a JOIN user u ON u.user_id=a.user_id WHERE u.role='user' AND a.assessment_date >= %s AND a.assessment_date < %s", (end-timedelta(days=days),end))['total']
            # Aggregate assessor classifications in SQL, not by downloading user history.
            result['assessors'] = rows(c, """SELECT assessor_type,COUNT(*) users FROM (SELECT CASE WHEN MIN(a.assessment_date) >= %s THEN 'First-time' ELSE 'Returning' END assessor_type FROM assessment a JOIN user u ON u.user_id=a.user_id WHERE u.role='user' AND a.assessment_date < %s GROUP BY a.user_id HAVING MAX(a.assessment_date) >= %s) d GROUP BY assessor_type""", (start,end,start))
            result['conversion'] = one(c, """SELECT COUNT(*) registrations,COUNT(first_date) converted_users,
                ROUND(100.0*COUNT(first_date)/NULLIF(COUNT(*),0),2) conversion_percent,
                ROUND(AVG(TIMESTAMPDIFF(SECOND,created_at,first_date))/3600,2) mean_hours_to_first_assessment
                FROM (SELECT u.created_at,(SELECT MIN(a.assessment_date) FROM assessment a WHERE a.user_id=u.user_id AND a.assessment_date >= u.created_at AND a.assessment_date < %s) first_date FROM user u WHERE u.role='user' AND u.created_at >= %s AND u.created_at < %s) d""", (end,start,end))
            result['weekdays'] = rows(c,"SELECT WEEKDAY(a.assessment_date) weekday,COUNT(*) assessments"+BASE+where+" GROUP BY weekday ORDER BY weekday",args)
            result['daily'] = rows(c,"SELECT DATE(a.assessment_date) day,COUNT(DISTINCT a.user_id) active_users"+BASE+where+" GROUP BY day ORDER BY day",args)
        elif section == 'quality':
            result['scores'] = rows(c,"SELECT CASE WHEN r.quality_score IS NULL THEN 'Not scored' WHEN r.quality_score < 0 OR r.quality_score > 100 THEN 'Outside 0–100' WHEN r.quality_score < 20 THEN '0–19' WHEN r.quality_score < 40 THEN '20–39' WHEN r.quality_score < 60 THEN '40–59' WHEN r.quality_score < 80 THEN '60–79' ELSE '80–100' END score_band,COUNT(*) assessments"+BASE+where+" GROUP BY score_band ORDER BY score_band",args)
            result['trend'] = rows(c,"SELECT DATE(a.assessment_date) day,ROUND(AVG(r.quality_score),2) average_score,COUNT(r.quality_score) scored_assessments"+BASE+where+" AND a.assessment_status='Completed' GROUP BY day ORDER BY day",args)
            result['genres'] = rows(c,"SELECT COALESCE(NULLIF(f.genre_name,''),'Not collected') genre,COUNT(*) assessments,COUNT(CASE WHEN a.assessment_status='Completed' THEN r.quality_score END) scored,ROUND(AVG(CASE WHEN a.assessment_status='Completed' THEN r.quality_score END),2) average_score,ROUND(100.0*SUM(a.assessment_status='Failed')/NULLIF(COUNT(*),0),2) failure_percent"+BASE+where+" GROUP BY genre ORDER BY assessments DESC LIMIT 25",args)
        elif section == 'amplifiers':
            result['enabled'] = SETTINGS_RECOMMENDATIONS_ENABLED
            if result['enabled']:
                result['metrics'] = one(c,"SELECT COUNT(*) saved_profiles_lifetime FROM amplifier_profile p JOIN user u ON u.user_id=p.user_id WHERE u.role='user'")
                result['statuses'] = rows(c,"SELECT s.recommendation_status status,COUNT(*) recommendations FROM settings_recommendation s JOIN user u ON u.user_id=s.user_id WHERE u.role='user' AND s.created_at >= %s AND s.created_at < %s GROUP BY s.recommendation_status",args)
                result['genres'] = rows(c,"SELECT s.genre,COUNT(*) recommendations FROM settings_recommendation s JOIN user u ON u.user_id=s.user_id WHERE u.role='user' AND s.created_at >= %s AND s.created_at < %s GROUP BY s.genre ORDER BY recommendations DESC LIMIT 25",args)
                result['versions'] = rows(c,"SELECT s.algorithm_version,s.genre_profile_version,s.overall_confidence,COUNT(*) recommendations FROM settings_recommendation s JOIN user u ON u.user_id=s.user_id WHERE u.role='user' AND s.created_at >= %s AND s.created_at < %s GROUP BY s.algorithm_version,s.genre_profile_version,s.overall_confidence ORDER BY recommendations DESC LIMIT 50",args)
                result['verified'] = rows(c,"SELECT s.recommendation_id,child.assessment_id verification_assessment_id,s.original_score,child.verification_score,ROUND(child.verification_score-s.original_score,2) recorded_difference FROM settings_recommendation s JOIN settings_recommendation child ON child.parent_recommendation_id=s.recommendation_id AND child.user_id=s.user_id JOIN user u ON u.user_id=s.user_id WHERE u.role='user' AND child.created_at >= %s AND child.created_at < %s AND child.verification_score IS NOT NULL ORDER BY child.created_at DESC LIMIT 50",args)
                result['positions'] = []
                for knob in ('volume','bass','treble','sharpness','flatness'):
                    result['positions'] += rows(c,"SELECT %s control, FLOOR(10*(CAST(JSON_UNQUOTE(JSON_EXTRACT(s.recommended_positions,'$."+knob+"')) AS DECIMAL(10,3))-s.scale_min)/NULLIF(s.scale_max-s.scale_min,0))*10 normalized_percent_bucket,COUNT(*) recommendations FROM settings_recommendation s JOIN user u ON u.user_id=s.user_id WHERE u.role='user' AND s.created_at >= %s AND s.created_at < %s AND JSON_EXTRACT(s.recommended_positions,'$."+knob+"') IS NOT NULL GROUP BY normalized_percent_bucket ORDER BY normalized_percent_bucket",(knob,)+args)
        else:
            result['metrics'] = one(c,"SELECT COUNT(*) requests,COALESCE(SUM(status_code BETWEEN 400 AND 599),0) errors,ROUND(100.0*SUM(status_code BETWEEN 400 AND 599)/NULLIF(COUNT(*),0),2) error_percent,ROUND(AVG(duration_ms),2) mean_latency_ms FROM api_request_log WHERE created_at >= %s AND created_at < %s",args)
            result['attention'] = rows(c,"SELECT a.assessment_id,a.user_id,u.username,a.assessment_date,a.assessment_status"+BASE+where+" AND a.assessment_status IN ('Failed','Pending','Processing') ORDER BY a.assessment_date DESC LIMIT 50",args)
            result['audit'] = rows(c,"SELECT audit_log_id,action,resource_type,resource_id,result,created_at FROM audit_log WHERE created_at >= %s AND created_at < %s ORDER BY created_at DESC,audit_log_id DESC LIMIT 50",args)
    return result


def directory(kind, query):
    if kind not in ('users','assessments'):
        raise ValueError('Unknown directory')
    start,end = window(query)
    reference = datetime.now(timezone.utc).date()
    try:
        page = int(query.get('page',1))
        if not 1 <= page <= 10000: raise ValueError()
    except (ValueError,TypeError):
        raise ValueError('Invalid page') from None
    size = 100 if query.get('export') == '1' else 25
    params = []
    clauses = ["u.role='user'"]
    field = 'u.created_at' if kind == 'users' else 'a.assessment_date'
    clauses += [field+' >= %s',field+' < %s']
    params += [start,end]
    search = str(query.get('search','')).strip()
    if len(search) > 100: raise ValueError('Search is limited to 100 characters')
    if search:
        search_fields = ['u.username', 'u.first_name', 'u.last_name', 'CAST(u.user_id AS CHAR)']
        if kind == 'assessments':
            search_fields += ['CAST(a.assessment_id AS CHAR)', 'a.analysis_purpose']
        clauses.append('(' + ' OR '.join(f + ' LIKE %s' for f in search_fields) + ')')
        params += ['%' + search + '%'] * len(search_fields)
    for f in ('country','city'):
        if query.get(f):
            clauses.append('u.'+f+' = %s'); params.append(str(query[f])[:100])
    if query.get('verified') in ('yes','no'):
        clauses.append('u.email_verified_at IS '+('NOT NULL' if query['verified']=='yes' else 'NULL'))
    if query.get('status'):
        allowed = ('enabled','deactivated') if kind=='users' else ('Pending','Processing','Completed','Failed')
        if query['status'] not in allowed: raise ValueError('Invalid status')
        clauses.append('u.is_active = %s' if kind=='users' else 'a.assessment_status = %s')
        params.append(int(query['status']=='enabled') if kind=='users' else query['status'])
    for f,op in [('age_min','>='),('age_max','<=')]:
        if query.get(f) not in (None,''):
            try:
                age=int(query[f])
                if not 0<=age<=120: raise ValueError()
            except (ValueError,TypeError): raise ValueError('Age must be between 0 and 120') from None
            clauses.append('('+AGE+') '+op+' %s'); params += [reference]*3+[age]
    if query.get('age_min') not in (None, '') and query.get('age_max') not in (None, '') and int(query['age_min']) > int(query['age_max']):
        raise ValueError('Minimum age must not exceed maximum age')
    if query.get('user_id'):
        if not str(query['user_id']).isdigit(): raise ValueError('Invalid user ID')
        clauses.append('u.user_id=%s');params.append(int(query['user_id']))
    if query.get('genre') and kind=='assessments':
        clauses.append('f.genre_name=%s');params.append(str(query['genre'])[:50])
    sorts = {'date':field,'username':'u.username','id':'u.user_id' if kind=='users' else 'a.assessment_id'}
    if kind=='assessments': sorts['score']='r.quality_score'
    sort = sorts.get(query.get('sort','date'))
    if not sort: raise ValueError('Invalid sort')
    direction = str(query.get('direction','DESC')).upper()
    if direction not in ('ASC','DESC'): raise ValueError('Invalid direction')
    base = ' FROM user u ' if kind=='users' else BASE
    base += ' WHERE '+' AND '.join(clauses)
    with reader() as c:
        total = one(c,'SELECT COUNT(*) total'+base,params)['total']
        if kind=='users':
            select = """u.user_id,u.username,u.first_name,u.last_name,CONCAT(LEFT(u.email,1),'***@',SUBSTRING_INDEX(u.email,'@',-1)) email,
            CONCAT('***',RIGHT(u.phone_number,2)) phone,u.city,u.country,u.created_at,
            (u.email_verified_at IS NOT NULL) verified,u.is_active,"""+AGE+""" age,
            (SELECT COUNT(*) FROM assessment a WHERE a.user_id=u.user_id) assessment_count_lifetime,
            (SELECT MAX(a.assessment_date) FROM assessment a WHERE a.user_id=u.user_id) last_assessment_lifetime"""
            select_params = [reference]*3
        else:
            select = 'a.assessment_id,a.user_id,u.username,a.assessment_date,a.analysis_purpose,f.genre_name,a.assessment_status,r.quality_score,a.duration_seconds,a.processing_time'
            select_params=[]
        data = rows(c,'SELECT '+select+base+' ORDER BY '+sort+' '+direction+', '+('u.user_id' if kind=='users' else 'a.assessment_id')+' '+direction+' LIMIT %s OFFSET %s',select_params+params+[size,(page-1)*size if size==25 else 0])
    return {'rows':data,'total':total,'page':page,'page_size':size,'pages':max(1,(total+size-1)//size), 'age_reference':reference.isoformat()}


def detail(kind, record_id, query):
    if kind not in ('users','assessments') or not str(record_id).isdigit():
        raise ValueError('Invalid detail request')
    start,end=window(query)
    with reader() as c:
        if kind=='users':
            reference=datetime.now(timezone.utc).date()
            profile=rows(c,"SELECT u.user_id,u.username,u.first_name,u.last_name,u.city,u.country,u.created_at,u.is_active,(u.email_verified_at IS NOT NULL) verified,CONCAT(LEFT(u.email,1),'***@',SUBSTRING_INDEX(u.email,'@',-1)) email,CONCAT('***',RIGHT(u.phone_number,2)) phone,"+AGE+" age FROM user u WHERE u.role='user' AND u.user_id=%s",(reference,reference,reference,record_id))
            if not profile: raise LookupError('User not found')
            data={'profile':profile[0], 'age_reference':reference.isoformat(), 'meta':{'start':start.isoformat(),'end':(end-timedelta(days=1)).isoformat()}}
            data['scores']=rows(c,"SELECT DATE(a.assessment_date) day,ROUND(AVG(r.quality_score),2) average_score,COUNT(r.quality_score) scored_assessments"+BASE+" WHERE u.role='user' AND a.user_id=%s AND a.assessment_date >= %s AND a.assessment_date < %s AND a.assessment_status='Completed' GROUP BY day ORDER BY day",(record_id,start,end))
            data['genres']=rows(c,"SELECT COALESCE(f.genre_name,'Not collected') genre,COUNT(*) assessments"+BASE+" WHERE u.role='user' AND a.user_id=%s AND a.assessment_date >= %s AND a.assessment_date < %s GROUP BY genre ORDER BY assessments DESC LIMIT 25",(record_id,start,end))
            data['profiles']=rows(c,"SELECT amplifier_profile_id,name,scale_min,scale_max,scale_step,last_positions,created_at,updated_at FROM amplifier_profile WHERE user_id=%s ORDER BY updated_at DESC LIMIT 50",(record_id,)) if SETTINGS_RECOMMENDATIONS_ENABLED else []
        else:
            found=rows(c,"SELECT a.assessment_id,a.user_id,u.username,a.assessment_date,a.analysis_purpose,a.assessment_status,a.duration_seconds,a.processing_time,a.result_status,f.genre_name,r.quality_score,r.noise_level,r.distortion_level,r.bass,r.treble,r.loudness,r.sharpness,r.flatness,r.empirical_status,r.worst_feature_status,r.worst_features,r.empirical_details,r.scoring_algorithm_version,r.quality_profile_version,r.reference_recording_count"+BASE+" WHERE u.role='user' AND a.assessment_id=%s",(record_id,))
            if not found: raise LookupError('Assessment not found')
            data={'profile':found[0]}
    return data
