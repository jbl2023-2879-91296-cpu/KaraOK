"""Execution implementation."""

from __future__ import annotations

from .summary import _score_analyzer_output
from .visualizations import _visualization_paths
from datetime import datetime
from datetime import timezone
from karaok.core.config import ALLOWED_ANALYSIS_PURPOSES
from karaok.core.config import ANALYSIS_OUTPUT_DIR
from karaok.core.config import ANALYZER_COMPLETED_EXIT_CODES
from karaok.core.config import AUDIO_ANALYSIS_TIMEOUT_SECONDS
from karaok.core.config import AUDIO_ANALYZER_PATH
from karaok.core.config import AUDIO_ANALYZER_SETTINGS_PATH
from karaok.core.artifacts import _analysis_directory
from karaok.core.runtime import app
from karaok.core.paths import ensure_within_root
from pathlib import Path
from typing import Any
import json
import os
import shutil
import signal
import subprocess
import sys
import time


class AudioAnalyzerExecutionError(RuntimeError):
    def __init__(self, message: str, dump: dict[str, Any]):
        super().__init__(message)
        self.dump = dump


def _process_text(value: str | bytes | None, limit: int = 20_000) -> str:
    if value is None:
        return ""
    text = value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value
    return text[-limit:]


def _execute_analyzer_command(
    command: list[str],
    *,
    cwd: str,
    environment: dict[str, str],
    timeout_seconds: int,
) -> subprocess.CompletedProcess[str]:
    process_options: dict[str, Any] = {}
    if os.name == "nt":
        process_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        process_options["start_new_session"] = True
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
        **process_options,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                capture_output=True,
                text=True,
                check=False,
            )
        else:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            stdout, stderr = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
        error.output = stdout
        error.stderr = stderr
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def _run_audio_analyzer(
    audio_path: str,
    *,
    user_id: int,
    assessment_id: int,
    original_name: str,
    analysis_purpose: str,
) -> dict[str, Any]:
    """Run the standalone analyzer and return its transient structured output."""
    if analysis_purpose not in ALLOWED_ANALYSIS_PURPOSES:
        raise ValueError("analysis_purpose is invalid")
    if not os.path.isfile(AUDIO_ANALYZER_PATH):
        raise RuntimeError("audio_analyzer.py is unavailable")
    if not os.path.isfile(AUDIO_ANALYZER_SETTINGS_PATH):
        raise RuntimeError("audio analyzer settings are unavailable")

    destination = _analysis_directory(user_id, assessment_id)
    command = [
        sys.executable,
        AUDIO_ANALYZER_PATH,
        audio_path,
        "--output-dir",
        str(destination),
        "--settings",
        AUDIO_ANALYZER_SETTINGS_PATH,
        "--no-save-csv",
    ]
    started_at = datetime.now(timezone.utc)
    started_clock = time.monotonic()
    environment = os.environ.copy()
    environment["MPLBACKEND"] = "Agg"
    environment["PYTHONUNBUFFERED"] = "1"
    runtime_cache = Path(ANALYSIS_OUTPUT_DIR).resolve() / "_runtime_cache"
    matplotlib_cache = runtime_cache / "matplotlib"
    numba_cache = runtime_cache / "numba"
    matplotlib_cache.mkdir(parents=True, exist_ok=True)
    numba_cache.mkdir(parents=True, exist_ok=True)
    environment["MPLCONFIGDIR"] = str(matplotlib_cache)
    environment["NUMBA_CACHE_DIR"] = str(numba_cache)

    exit_code: int | None = None
    stdout = ""
    stderr = ""
    process_error: str | None = None
    try:
        completed = _execute_analyzer_command(
            command,
            cwd=os.path.dirname(AUDIO_ANALYZER_PATH),
            environment=environment,
            timeout_seconds=AUDIO_ANALYSIS_TIMEOUT_SECONDS,
        )
        exit_code = completed.returncode
        stdout = _process_text(completed.stdout)
        stderr = _process_text(completed.stderr)
    except subprocess.TimeoutExpired as error:
        stdout = _process_text(error.stdout)
        stderr = _process_text(error.stderr)
        process_error = (
            f"Audio analysis exceeded {AUDIO_ANALYSIS_TIMEOUT_SECONDS} seconds."
        )
    except OSError as error:
        process_error = f"Audio analyzer could not be started: {error}"

    analyzer_output: dict[str, Any] | None = None
    if exit_code in ANALYZER_COMPLETED_EXIT_CODES:
        result_files = sorted(
            destination.glob("*_analysis.json"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if result_files:
            try:
                with result_files[0].open("r", encoding="utf-8") as handle:
                    loaded = json.load(handle)
                if isinstance(loaded, dict):
                    analyzer_output = loaded
            except (OSError, json.JSONDecodeError) as error:
                process_error = f"Analyzer JSON could not be read: {error}"
        else:
            process_error = "Analyzer completed without producing a JSON result."
    elif process_error is None:
        process_error = f"Audio analyzer exited with code {exit_code}."

    empirical_quality: dict[str, Any] | None = None
    if analyzer_output is not None and process_error is None:
        try:
            empirical_quality = _score_analyzer_output(analyzer_output)
        except ValueError as error:
            process_error = f"Empirical quality scoring failed: {error}"

    visualizations: dict[str, str] | None = None
    if analyzer_output is not None and process_error is None:
        try:
            visualizations = _visualization_paths(destination)
        except (OSError, RuntimeError) as error:
            process_error = str(error)

    duration_seconds = round(time.monotonic() - started_clock, 3)
    analysis_completed = (
        analyzer_output is not None
        and empirical_quality is not None
        and process_error is None
    )
    dump: dict[str, Any] = {
        "dump_schema_version": 1,
        "analysis_status": "completed" if analysis_completed else "failed",
        "analysis_purpose": analysis_purpose,
        "upload": {
            "assessment_id": assessment_id,
            "original_file_name": original_name,
        },
        "analyzer_process": {
            "started_at_utc": started_at.isoformat(),
            "duration_seconds": duration_seconds,
            "exit_code": exit_code,
            "quality_thresholds_failed": exit_code == 3,
            "stdout": stdout,
            "stderr": stderr,
        },
        "analysis": analyzer_output,
        "empirical_quality": empirical_quality,
        "visualizations": visualizations,
    }
    if process_error is not None:
        dump["error"] = process_error
    if not analysis_completed:
        raise AudioAnalyzerExecutionError(process_error or "Audio analysis failed", dump)
    return dump


def run_audio_analyzer(
    audio_path: str,
    *,
    user_id: int,
    assessment_id: int,
    original_name: str,
    analysis_purpose: str,
) -> dict[str, Any]:
    """Analyze an upload and retain only its two report visualizations."""
    dump: dict[str, Any] | None = None
    try:
        dump = _run_audio_analyzer(
            audio_path,
            user_id=user_id,
            assessment_id=assessment_id,
            original_name=original_name,
            analysis_purpose=analysis_purpose,
        )
        return dump
    finally:
        root = Path(ANALYSIS_OUTPUT_DIR).resolve()
        destination = (root / str(user_id) / str(assessment_id)).resolve()
        if os.path.commonpath((str(root), str(destination))) != str(root):
            app.logger.error("Refused to clean an invalid analyzer working path")
        elif destination.is_dir():
            visualizations = dump.get("visualizations") if dump else None
            keep = {
                ensure_within_root(root, root / relative_path)
                for relative_path in (
                    visualizations.values()
                    if isinstance(visualizations, dict)
                    else ()
                )
                if isinstance(relative_path, str)
            }
            if not keep:
                shutil.rmtree(destination, ignore_errors=True)
            else:
                for artifact in destination.iterdir():
                    if artifact.is_file() and artifact.resolve() not in keep:
                        artifact.unlink(missing_ok=True)
