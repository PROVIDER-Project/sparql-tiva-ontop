"""Real DuckDB fixture test using the project's JDBC jar; no Docker required."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
JAVA = shutil.which('java')
JARS = sorted((ROOT / 'jdbc').glob('duckdb_jdbc-*.jar'))


class AreaMembershipTests(unittest.TestCase):
    @unittest.skipUnless(JAVA and JARS, 'requires Java 11+ and a DuckDB JDBC jar in jdbc/')
    def test_fixture_and_transaction_failures(self):
        result = subprocess.run(
            [JAVA, '--class-path', str(JARS[-1]),
             str(ROOT / 'tests/TestAreaMembership.java'), str(ROOT)],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
