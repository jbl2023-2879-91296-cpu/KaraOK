from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
from datetime import datetime
import hashlib
import os

app = Flask(__name__)
CORS(app)

# ── Database config ────────────────────────────────────────────────────────────
DB_CONFIG = {
    'host': 'localhost',
    'database': 'karaok_db',
    'user': 'root',
    'password': '12345678',
    'port': 3306,
}

def get_db():
    """Return a new MySQL connection."""
    conn = mysql.connector.connect(**DB_CONFIG)
    return conn

def hash_password(password: str) -> str:
    """SHA-256 hash the password with a fixed salt for simplicity."""
    salt = 'karaok_salt_2025'
    return hashlib.sha256(f'{salt}{password}'.encode()).hexdigest()


# ── Health check ───────────────────────────────────────────────────────────────
@app.route('/api/health', methods=['GET'])
def health():
    try:
        conn = get_db()
        conn.close()
        return jsonify({'status': 'ok', 'db': 'connected'}), 200
    except Error as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ══════════════════════════════════════════════════════════════════════════════
# AUTH
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/auth/register', methods=['POST'])
def register():
    data      = request.get_json()
    name      = data.get('name', '').strip()
    email     = data.get('email', '').strip().lower()
    password  = data.get('password', '')
    user_type = data.get('user_type', 'technician')

    if not name or not email or not password:
        return jsonify({'error': 'name, email and password are required'}), 400
    if user_type not in ('technician', 'owner'):
        return jsonify({'error': 'user_type must be technician or owner'}), 400

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    # Check duplicate email
    cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
    if cursor.fetchone():
        cursor.close(); conn.close()
        return jsonify({'error': 'Email already registered'}), 409

    pw_hash = hash_password(password)
    cursor.execute(
        "INSERT INTO users (name, email, password_hash, user_type) VALUES (%s, %s, %s, %s)",
        (name, email, pw_hash, user_type)
    )
    conn.commit()
    user_id = cursor.lastrowid
    cursor.close(); conn.close()
    return jsonify({
        'id': user_id, 'name': name,
        'email': email, 'user_type': user_type
    }), 201


@app.route('/api/auth/login', methods=['POST'])
def login():
    data     = request.get_json()
    email    = data.get('email', '').strip().lower()
    password = data.get('password', '')

    if not email or not password:
        return jsonify({'error': 'email and password are required'}), 400

    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        "SELECT id, name, email, user_type, password_hash FROM users WHERE email = %s",
        (email,)
    )
    user = cursor.fetchone()
    cursor.close(); conn.close()

    if not user or user['password_hash'] != hash_password(password):
        return jsonify({'error': 'Invalid email or password'}), 401

    return jsonify({
        'id':        user['id'],
        'name':      user['name'],
        'email':     user['email'],
        'user_type': user['user_type'],
    }), 200


# ══════════════════════════════════════════════════════════════════════════════
# USERS
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/users', methods=['GET'])
def get_users():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, name, user_type, created_at FROM users")
    rows = cursor.fetchall()
    cursor.close(); conn.close()
    return jsonify(rows), 200


@app.route('/api/users', methods=['POST'])
def create_user():
    data = request.get_json()
    name      = data.get('name')
    user_type = data.get('user_type')  # 'technician' | 'owner'
    if not name or not user_type:
        return jsonify({'error': 'name and user_type required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO users (name, user_type) VALUES (%s, %s)",
        (name, user_type)
    )
    conn.commit()
    user_id = cursor.lastrowid
    cursor.close(); conn.close()
    return jsonify({'id': user_id, 'name': name, 'user_type': user_type}), 201


# ══════════════════════════════════════════════════════════════════════════════
# AUDIO TESTS  (Technician)
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/audio-tests', methods=['GET'])
def get_audio_tests():
    user_id = request.args.get('user_id')
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    if user_id:
        cursor.execute(
            "SELECT * FROM audio_tests WHERE user_id = %s ORDER BY created_at DESC",
            (user_id,)
        )
    else:
        cursor.execute("SELECT * FROM audio_tests ORDER BY created_at DESC")
    rows = cursor.fetchall()
    cursor.close(); conn.close()
    return jsonify(rows), 200


@app.route('/api/audio-tests/<int:test_id>', methods=['GET'])
def get_audio_test(test_id):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM audio_tests WHERE id = %s", (test_id,))
    row = cursor.fetchone()
    cursor.close(); conn.close()
    if not row:
        return jsonify({'error': 'Not found'}), 404
    return jsonify(row), 200


@app.route('/api/audio-tests', methods=['POST'])
def create_audio_test():
    data        = request.get_json()
    user_id     = data.get('user_id')
    test_name   = data.get('test_name')
    score       = data.get('score')
    noise_level = data.get('noise_level')
    distortion  = data.get('distortion_level')
    status      = data.get('status', 'Acceptable')
    duration_s  = data.get('duration_seconds', 0)

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO audio_tests
           (user_id, test_name, score, noise_level, distortion_level, status, duration_seconds)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (user_id, test_name, score, noise_level, distortion, status, duration_s)
    )
    conn.commit()
    test_id = cursor.lastrowid
    cursor.close(); conn.close()
    return jsonify({'id': test_id, 'test_name': test_name, 'score': score}), 201


@app.route('/api/audio-tests/<int:test_id>', methods=['DELETE'])
def delete_audio_test(test_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM audio_tests WHERE id = %s", (test_id,))
    conn.commit()
    cursor.close(); conn.close()
    return jsonify({'message': 'Deleted'}), 200


# ══════════════════════════════════════════════════════════════════════════════
# GENRE SETTINGS  (Owner)
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/genre-settings', methods=['GET'])
def get_genre_settings():
    genre = request.args.get('genre')
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    if genre:
        cursor.execute(
            "SELECT * FROM genre_settings WHERE genre = %s ORDER BY updated_at DESC LIMIT 1",
            (genre,)
        )
        row = cursor.fetchone()
        cursor.close(); conn.close()
        if not row:
            return jsonify({'error': 'No settings for this genre'}), 404
        return jsonify(row), 200
    else:
        cursor.execute("SELECT * FROM genre_settings ORDER BY genre")
        rows = cursor.fetchall()
        cursor.close(); conn.close()
        return jsonify(rows), 200


@app.route('/api/genre-settings', methods=['POST'])
def save_genre_settings():
    data      = request.get_json()
    user_id   = data.get('user_id')
    genre     = data.get('genre')
    volume    = data.get('volume', 75)
    bass      = data.get('bass', 55)
    treble    = data.get('treble', 65)
    flatness  = data.get('flatness', 70)
    sharpness = data.get('sharpness', 90)

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO genre_settings
           (user_id, genre, volume, bass, treble, flatness, sharpness)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (user_id, genre, volume, bass, treble, flatness, sharpness)
    )
    conn.commit()
    setting_id = cursor.lastrowid
    cursor.close(); conn.close()
    return jsonify({'id': setting_id, 'genre': genre}), 201


# ══════════════════════════════════════════════════════════════════════════════
# AUDIO UPLOADS  (Owner)
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/api/audio-uploads', methods=['GET'])
def get_audio_uploads():
    user_id = request.args.get('user_id')
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    if user_id:
        cursor.execute(
            "SELECT * FROM audio_uploads WHERE user_id = %s ORDER BY created_at DESC",
            (user_id,)
        )
    else:
        cursor.execute("SELECT * FROM audio_uploads ORDER BY created_at DESC")
    rows = cursor.fetchall()
    cursor.close(); conn.close()
    return jsonify(rows), 200


@app.route('/api/audio-uploads', methods=['POST'])
def create_audio_upload():
    data      = request.get_json()
    user_id   = data.get('user_id')
    file_name = data.get('file_name')
    genre     = data.get('genre')
    score     = data.get('score')
    status    = data.get('status', 'Acceptable')

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO audio_uploads (user_id, file_name, genre, score, status)
           VALUES (%s, %s, %s, %s, %s)""",
        (user_id, file_name, genre, score, status)
    )
    conn.commit()
    upload_id = cursor.lastrowid
    cursor.close(); conn.close()
    return jsonify({'id': upload_id, 'file_name': file_name, 'genre': genre}), 201


# ══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
