"""Real DuckDB fixture test using the project's JDBC jar; no Docker required."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
JAVA = shutil.which('java')
JAR = Path(os.environ.get('DUCKDB_JDBC_JAR', ROOT / 'target/test-dependencies/duckdb_jdbc-1.5.6.0.jar'))


class AreaMembershipTests(unittest.TestCase):
    @unittest.skipUnless(JAVA and JAR.is_file(), 'requires Java 11+ and a DuckDB JDBC jar (DUCKDB_JDBC_JAR)')
    def test_fixture_and_transaction_failures(self):
        result = subprocess.run(
            [JAVA, '--class-path', str(JAR),
             str(ROOT / 'tests/TestAreaMembership.java'), str(ROOT)],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
