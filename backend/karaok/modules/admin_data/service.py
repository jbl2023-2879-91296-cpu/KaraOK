"""Schema-aware, bounded database operations for the admin console."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
import re
from typing import Any

from ...config import ADMIN_DB_CONFIG
from ...infrastructure.database import get_admin_db
from .policy import TABLE_POLICIES, TablePolicy, table_policy


IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$")
TEXT_TYPES = {"char", "varchar", "text", "tinytext", "mediumtext", "longtext", "enum", "set"}
BINARY_TYPES = {"binary", "varbinary", "blob", "tinyblob", "mediumblob", "longblob"}
NUMERIC_TYPES = {"tinyint", "smallint", "mediumint", "int", "bigint", "decimal", "numeric", "float", "double", "real"}


def quote_identifier(value: str) -> str:
    if not IDENTIFIER_RE.fullmatch(value):
        raise ValueError("Invalid database identifier")
    return f"`{value}`"


def database_name() -> str:
    return str(ADMIN_DB_CONFIG["database"])


def _connection():
    return get_admin_db()


def _columns(cursor, table: str) -> list[dict[str, Any]]:
    cursor.execute(
        """SELECT COLUMN_NAME AS name, ORDINAL_POSITION AS position,
                  COLUMN_DEFAULT AS default_value, IS_NULLABLE AS nullable,
                  DATA_TYPE AS data_type, COLUMN_TYPE AS column_type,
                  CHARACTER_MAXIMUM_LENGTH AS max_length,
                  COLUMN_KEY AS column_key, EXTRA AS extra,
                  COLLATION_NAME AS collation
           FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s
           ORDER BY ORDINAL_POSITION""",
        (database_name(), table),
    )
    return list(cursor.fetchall())


def health() -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute("SELECT VERSION() AS server_version, DATABASE() AS database_name")
        result = cursor.fetchone()
        cursor.execute(
            "SELECT COUNT(*) AS table_count FROM information_schema.TABLES WHERE TABLE_SCHEMA = %s",
            (database_name(),),
        )
        result["table_count"] = int(cursor.fetchone()["table_count"])
        result["status"] = "ok"
        result["connection"] = "data_administration_api"
        return result
    finally:
        cursor.close()
        connection.close()


def catalog() -> list[dict[str, Any]]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT TABLE_NAME AS name, TABLE_TYPE AS type, ENGINE AS engine,
                      TABLE_ROWS AS estimated_rows, DATA_LENGTH AS data_bytes,
                      INDEX_LENGTH AS index_bytes, TABLE_COLLATION AS collation,
                      CREATE_TIME AS created_at, UPDATE_TIME AS updated_at
               FROM information_schema.TABLES
               WHERE TABLE_SCHEMA = %s ORDER BY TABLE_NAME""",
            (database_name(),),
        )
        rows = []
        for row in cursor.fetchall():
            policy = TABLE_POLICIES.get(row["name"])
            if policy is None:
                continue
            row["label"] = policy.label or row["name"]
            row["primary_key"] = policy.primary_key
            row["capabilities"] = {
                "read": policy.readable,
                "create": policy.creatable,
                "update": policy.updatable,
                "delete": policy.deletable,
            }
            rows.append(row)
        return rows
    finally:
        cursor.close()
        connection.close()


def table_details(table: str) -> dict[str, Any]:
    policy = table_policy(table)
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        columns = _columns(cursor, table)
        for column in columns:
            name = column["name"]
            column["hidden"] = name in policy.hidden_fields
            column["editable"] = name in policy.update_fields
            column["creatable"] = name in policy.create_fields
        cursor.execute(
            """SELECT INDEX_NAME AS name, NON_UNIQUE AS non_unique,
                      SEQ_IN_INDEX AS sequence, COLUMN_NAME AS column_name,
                      CARDINALITY AS cardinality, INDEX_TYPE AS index_type
               FROM information_schema.STATISTICS
               WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s
               ORDER BY INDEX_NAME, SEQ_IN_INDEX""",
            (database_name(), table),
        )
        indexes = list(cursor.fetchall())
        return {
            "table": table,
            "label": policy.label,
            "primary_key": policy.primary_key,
            "capabilities": {
                "read": policy.readable,
                "create": policy.creatable,
                "update": policy.updatable,
                "delete": policy.deletable,
            },
            "columns": columns,
            "indexes": indexes,
        }
    finally:
        cursor.close()
        connection.close()


def relationships() -> list[dict[str, Any]]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT k.CONSTRAINT_NAME AS name, k.TABLE_NAME AS child_table,
                      k.COLUMN_NAME AS child_column,
                      k.REFERENCED_TABLE_NAME AS parent_table,
                      k.REFERENCED_COLUMN_NAME AS parent_column,
                      r.UPDATE_RULE AS update_rule, r.DELETE_RULE AS delete_rule
               FROM information_schema.KEY_COLUMN_USAGE k
               LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS r
                 ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
                AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
               WHERE k.TABLE_SCHEMA = %s AND k.REFERENCED_TABLE_NAME IS NOT NULL
               ORDER BY k.TABLE_NAME, k.CONSTRAINT_NAME, k.ORDINAL_POSITION""",
            (database_name(),),
        )
        return list(cursor.fetchall())
    finally:
        cursor.close()
        connection.close()


def records(table: str, query: dict[str, Any]) -> dict[str, Any]:
    policy = table_policy(table)
    if not policy.readable:
        raise PermissionError("Records in this security-sensitive table are not exposed")
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        columns = _columns(cursor, table)
        visible = [column for column in columns if column["name"] not in policy.hidden_fields]
        names = {column["name"] for column in visible}
        page = max(1, _integer(query.get("page"), 1))
        page_size = _integer(query.get("page_size"), 25)
        if page_size not in {25, 50, 100}:
            page_size = 25
        params: list[Any] = []
        where: list[str] = []
        search = str(query.get("search", "")).strip()
        if search:
            cursor.execute(
                "SELECT COALESCE(TABLE_ROWS, 0) AS estimated_rows FROM information_schema.TABLES WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s",
                (database_name(), table),
            )
            estimated_rows = int(cursor.fetchone()["estimated_rows"])
            if estimated_rows >= 100_000 and str(query.get("confirm_search", "")) != "1":
                raise ValueError("Confirm the large-table search before running it")
            searchable = [c for c in visible if c["data_type"] in TEXT_TYPES][:8]
            if searchable:
                where.append("(" + " OR ".join(f"{quote_identifier(c['name'])} LIKE %s" for c in searchable) + ")")
                params.extend([f"%{search}%"] * len(searchable))
        filter_column = str(query.get("filter_column", ""))
        filter_value = query.get("filter_value")
        if filter_column or filter_value not in (None, ""):
            if filter_column not in names:
                raise ValueError("Invalid filter column")
            operator = "=" if query.get("filter_operator") == "equals" else "LIKE"
            where.append(f"{quote_identifier(filter_column)} {operator} %s")
            params.append(filter_value if operator == "=" else f"%{filter_value}%")
        select_parts = []
        for column in visible:
            quoted = quote_identifier(column["name"])
            if column["data_type"] in BINARY_TYPES:
                select_parts.append(f"OCTET_LENGTH({quoted}) AS {quoted}")
            else:
                select_parts.append(quoted)
        base = f" FROM {quote_identifier(table)}"
        if where:
            base += " WHERE " + " AND ".join(where)
        cursor.execute("SELECT COUNT(*) AS total" + base, tuple(params))
        total = int(cursor.fetchone()["total"])
        sort = str(query.get("sort", policy.primary_key))
        if sort not in names:
            sort = policy.primary_key
        direction = "DESC" if str(query.get("direction", "DESC")).upper() == "DESC" else "ASC"
        offset = (page - 1) * page_size
        sql = (
            "SELECT " + ", ".join(select_parts) + base
            + f" ORDER BY {quote_identifier(sort)} {direction} LIMIT %s OFFSET %s"
        )
        cursor.execute(sql, tuple(params + [page_size, offset]))
        rows = [_json_safe(row) for row in cursor.fetchall()]
        return {
            "table": table,
            "primary_key": policy.primary_key,
            "capabilities": {
                "create": policy.creatable,
                "update": policy.updatable,
                "delete": policy.deletable,
            },
            "columns": visible,
            "rows": rows,
            "pagination": {
                "page": page,
                "page_size": page_size,
                "total": total,
                "pages": max(1, (total + page_size - 1) // page_size),
            },
        }
    finally:
        cursor.close()
        connection.close()


def create_record(table: str, payload: dict[str, Any]) -> dict[str, Any]:
    policy = table_policy(table)
    if not policy.creatable:
        raise PermissionError("Create is not permitted for this table")
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        columns = _columns(cursor, table)
        values = _validated_values(payload, policy.create_fields, columns, require_all=True)
        names = list(values)
        cursor.execute(
            f"INSERT INTO {quote_identifier(table)} ({', '.join(quote_identifier(name) for name in names)}) "
            f"VALUES ({', '.join(['%s'] * len(names))})",
            tuple(values[name] for name in names),
        )
        record_id = cursor.lastrowid
        connection.commit()
        return {"id": record_id, "message": "Record created"}
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def update_record(table: str, record_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    policy = table_policy(table)
    if not policy.updatable:
        raise PermissionError("Update is not permitted for this table")
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        columns = _columns(cursor, table)
        values = _validated_values(payload, policy.update_fields, columns, require_all=False)
        if not values:
            raise ValueError("At least one editable field is required")
        cursor.execute(
            f"UPDATE {quote_identifier(table)} SET "
            + ", ".join(f"{quote_identifier(name)} = %s" for name in values)
            + f" WHERE {quote_identifier(policy.primary_key)} = %s LIMIT 1",
            tuple(values.values()) + (record_id,),
        )
        if cursor.rowcount != 1:
            cursor.execute(
                f"SELECT 1 AS found FROM {quote_identifier(table)} "
                f"WHERE {quote_identifier(policy.primary_key)} = %s LIMIT 1",
                (record_id,),
            )
            if cursor.fetchone() is None:
                connection.rollback()
                raise LookupError("Record was not found")
        connection.commit()
        return {"id": record_id, "message": "Record updated or already matched the submitted values"}
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def delete_record(table: str, record_id: str, confirmation: str) -> dict[str, Any]:
    policy = table_policy(table)
    if not policy.deletable:
        raise PermissionError("Delete is not permitted for this table")
    if confirmation != f"DELETE {table}:{record_id}":
        raise ValueError("Exact deletion confirmation is required")
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        owner_user_id = None
        if table == "assessment":
            cursor.execute(
                "SELECT user_id FROM assessment WHERE assessment_id = %s FOR UPDATE",
                (record_id,),
            )
            assessment = cursor.fetchone()
            if assessment is None:
                connection.rollback()
                raise LookupError("Record was not found")
            owner_user_id = int(assessment["user_id"])
        cursor.execute(
            f"DELETE FROM {quote_identifier(table)} WHERE {quote_identifier(policy.primary_key)} = %s LIMIT 1",
            (record_id,),
        )
        if cursor.rowcount != 1:
            connection.rollback()
            raise LookupError("Record was not found")
        connection.commit()
        return {"id": record_id, "owner_user_id": owner_user_id, "message": "Record deleted"}
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def analytics() -> dict[str, Any]:
    connection = _connection()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.execute(
            """SELECT COUNT(*) AS total_users,
                      SUM(is_active = TRUE) AS active_users,
                      SUM(email_verified_at IS NULL) AS unverified_users,
                      SUM(role = 'admin') AS admin_users
               FROM user"""
        )
        users = _json_safe(cursor.fetchone())
        cursor.execute(
            """SELECT assessment_status AS status, COUNT(*) AS total
               FROM assessment GROUP BY assessment_status ORDER BY assessment_status"""
        )
        assessment_statuses = [_json_safe(row) for row in cursor.fetchall()]
        cursor.execute(
            """SELECT DATE(assessment_date) AS day, COUNT(*) AS total
               FROM assessment
               WHERE assessment_date >= UTC_TIMESTAMP() - INTERVAL 30 DAY
               GROUP BY DATE(assessment_date) ORDER BY day"""
        )
        daily_assessments = [_json_safe(row) for row in cursor.fetchall()]
        cursor.execute(
            """SELECT COUNT(*) AS completed_results,
                      ROUND(AVG(quality_score), 2) AS average_quality_score
               FROM audio_analysis_result WHERE quality_score IS NOT NULL"""
        )
        quality = _json_safe(cursor.fetchone())
        cursor.execute(
            """SELECT COUNT(*) AS requests_24h,
                      ROUND(AVG(duration_ms), 2) AS average_duration_ms,
                      SUM(status_code >= 500) AS server_errors_24h
               FROM api_request_log
               WHERE created_at >= UTC_TIMESTAMP() - INTERVAL 1 DAY"""
        )
        requests = _json_safe(cursor.fetchone())
        return {
            "users": users,
            "assessment_statuses": assessment_statuses,
            "daily_assessments": daily_assessments,
            "quality": quality,
            "requests": requests,
        }
    finally:
        cursor.close()
        connection.close()


def _validated_values(
    payload: dict[str, Any], allowed: tuple[str, ...], columns: list[dict[str, Any]], *, require_all: bool
) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValueError("JSON object required")
    unexpected = set(payload) - set(allowed)
    if unexpected:
        raise ValueError("Unsupported fields: " + ", ".join(sorted(unexpected)))
    if require_all:
        missing = set(allowed) - set(payload)
        if missing:
            raise ValueError("Missing required fields: " + ", ".join(sorted(missing)))
    metadata = {column["name"]: column for column in columns}
    return {name: _validated_value(value, metadata[name]) for name, value in payload.items()}


def _validated_value(value: Any, column: dict[str, Any]) -> Any:
    if value is None:
        if column["nullable"] == "YES":
            return None
        raise ValueError(f"{column['name']} cannot be null")
    data_type = column["data_type"]
    if data_type == "tinyint" and column["column_type"].startswith("tinyint(1)"):
        return 1 if value in (True, 1, "1", "true", "on") else 0
    if data_type in NUMERIC_TYPES:
        try:
            number = float(value) if data_type in {"float", "double", "real", "decimal", "numeric"} else int(value)
        except (TypeError, ValueError) as error:
            raise ValueError(f"{column['name']} must be numeric") from error
        if column["name"] in {"volume", "bass", "treble", "loudness", "sharpness", "flatness", "max_allowable_noise", "max_allowable_distortion", "min_quality_score"} and not 0 <= number <= 100:
            raise ValueError(f"{column['name']} must be between 0 and 100")
        return number
    text = str(value).strip()
    if not text:
        raise ValueError(f"{column['name']} is required")
    max_length = column.get("max_length")
    if max_length and len(text) > int(max_length):
        raise ValueError(f"{column['name']} is too long")
    if data_type == "enum":
        options = re.findall(r"'((?:[^'\\]|\\.)*)'", column["column_type"])
        if text not in options:
            raise ValueError(f"{column['name']} has an invalid option")
    return text


def _integer(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (bytes, bytearray)):
        return f"[binary: {len(value)} bytes]"
    return value
