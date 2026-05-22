#!/usr/bin/env python3

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WRITE_RUNTIME_ENV = REPO_ROOT / "scripts" / "write-runtime-env.py"
WRITE_WEBKIT_FLAGS = REPO_ROOT / "scripts" / "write-webkit-feature-flags.py"


class WriteRuntimeEnvCliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> None:
        subprocess.run(
            [sys.executable, str(WRITE_RUNTIME_ENV), *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_writes_comments_and_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "nested" / "runtime.conf"
            self.run_cli(
                str(output),
                "--comment",
                "first comment",
                "--comment",
                "second comment",
                "--entry",
                "LD_LIBRARY_PATH",
                "/opt/lib",
                "--entry",
                "FOO",
                "bar",
                "--optional-entry",
                "LD_PRELOAD",
                "libegl-stubs.so",
                "--optional-entry",
                "EMPTY_SHOULD_SKIP",
                "",
            )

            self.assertEqual(
                output.read_text(encoding="utf-8"),
                "# first comment\n"
                "# second comment\n"
                "LD_LIBRARY_PATH=/opt/lib\n"
                "FOO=bar\n"
                "LD_PRELOAD=libegl-stubs.so\n",
            )

    def test_empty_input_still_writes_newline(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "empty.conf"
            self.run_cli(str(output))
            self.assertEqual(output.read_text(encoding="utf-8"), "\n")


class WriteWebkitFeatureFlagsCliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> None:
        subprocess.run(
            [sys.executable, str(WRITE_WEBKIT_FLAGS), *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_reads_flags_from_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            cache = Path(temp_dir) / "WebKitBuild" / "Release" / "CMakeCache.txt"
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(
                "ENABLE_GPU_PROCESS:BOOL=ON\n"
                "ENABLE_WEBGL:BOOL=ON\n"
                "USE_GBM:STRING=1\n"
                "ENABLE_BUBBLEWRAP_SANDBOX:BOOL=OFF\n"
                "UNRELATED_KEY:STRING=value\n",
                encoding="utf-8",
            )
            output = Path(temp_dir) / "feature-flags.txt"

            self.run_cli(
                str(cache),
                str(output),
                "2.52.3",
                "--source-dir",
                "/tmp/src",
                "--build-dir",
                "/tmp/build",
            )

            self.assertEqual(
                output.read_text(encoding="utf-8"),
                "WPE WebKit version: 2.52.3\n"
                "Source dir: /tmp/src\n"
                "Build dir: /tmp/build\n"
                "\n"
                "ENABLE_GPU_PROCESS=ON\n"
                "ENABLE_WEBGL=ON\n"
                "ENABLE_WEBGPU=<not found>\n"
                "USE_GBM=1\n"
                "ENABLE_BUBBLEWRAP_SANDBOX=OFF\n",
            )

    def test_missing_cache_uses_not_found_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            cache = Path(temp_dir) / "missing" / "CMakeCache.txt"
            output = Path(temp_dir) / "feature-flags.txt"

            self.run_cli(str(cache), str(output), "2.52.3")

            self.assertEqual(
                output.read_text(encoding="utf-8"),
                "WPE WebKit version: 2.52.3\n"
                f"Build dir: {cache.parent}\n"
                "\n"
                "ENABLE_GPU_PROCESS=<not found>\n"
                "ENABLE_WEBGL=<not found>\n"
                "ENABLE_WEBGPU=<not found>\n"
                "USE_GBM=<not found>\n"
                "ENABLE_BUBBLEWRAP_SANDBOX=<not found>\n",
            )


if __name__ == "__main__":
    unittest.main()
