"""Opt-in real endpoint checks; no host data mounts or container network access.

Build first, then set TIVA_ENDPOINT_IMAGE to enable these tests.
"""
import json
import os
import shutil
import subprocess
import time
import unittest
from urllib.parse import urlencode

IMAGE = os.environ.get('TIVA_ENDPOINT_IMAGE')


@unittest.skipUnless(IMAGE and shutil.which('docker'),
                     'Set TIVA_ENDPOINT_IMAGE to test a built endpoint with Docker')
class EndpointImageTests(unittest.TestCase):
    @classmethod
    def docker(cls, *args):
        return subprocess.run(['docker', *args], capture_output=True, text=True,
                              check=True, timeout=180).stdout.strip()

    @classmethod
    def setUpClass(cls):
        cls.container = cls.docker('run', '-d', '--network', 'none', IMAGE)
        cls.addClassCleanup(subprocess.run, ['docker', 'rm', '-f', '-v', cls.container],
                            capture_output=True, check=False, timeout=30)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            state = json.loads(cls.docker('inspect', '--format', '{{json .State}}', cls.container))
            if state.get('Health', {}).get('Status') == 'healthy':
                return
            if not state['Running']:
                break
            time.sleep(2)
        raise RuntimeError('Endpoint did not become healthy: ' + cls.docker('logs', cls.container)[-12000:])

    def query(self, sparql):
        url = 'http://localhost:8080/sparql?' + urlencode({'query': sparql})
        response = self.docker('exec', self.container, 'wget', '-qO-',
                               '--header=Accept: application/sparql-results+json', url)
        return json.loads(response)['results']['bindings']

    def test_unbounded_spo_can_be_stopped_after_ten_rows(self):
        url = 'http://localhost:8080/sparql?' + urlencode({'query': 'SELECT * { ?s ?p ?o }'})
        prefix = self.docker(
            'exec', self.container, 'sh', '-c',
            'wget -qO- --header=Accept:text/tab-separated-values "$1" | head -n 11',
            'sh', url)
        lines = prefix.splitlines()
        self.assertEqual(len(lines), 11)
        self.assertEqual(set(lines[0].split('\t')), {'?s', '?p', '?o'})

    def test_observation_count_and_year(self):
        rows = self.query('SELECT (COUNT(*) AS ?n) WHERE { ?o a <http://purl.org/linked-data/cube#Observation> }')
        self.assertGreater(int(rows[0]['n']['value']), 0)
        if os.environ.get('EXPECTED_OBSERVATIONS'):
            self.assertEqual(int(rows[0]['n']['value']), int(os.environ['EXPECTED_OBSERVATIONS']))
        rows = self.query('SELECT DISTINCT ?year WHERE { ?o <http://purl.org/linked-data/sdmx/2009/dimension#refPeriod> ?year }')
        self.assertEqual({r['year']['value'] for r in rows}, {'2022'})

    def test_country_links(self):
        rows = self.query('SELECT (COUNT(*) AS ?n) WHERE { ?area <https://example.org/tiva/vocab/hasCountry> ?country }')
        self.assertGreater(int(rows[0]['n']['value']), 0)
        if os.environ.get('EXPECTED_COUNTRY_LINKS'):
            self.assertEqual(int(rows[0]['n']['value']), int(os.environ['EXPECTED_COUNTRY_LINKS']))

    def test_fixed_subject_and_literal_types(self):
        rows = self.query('SELECT ?o ?v WHERE { ?o a <http://purl.org/linked-data/cube#Observation>; <http://purl.org/linked-data/sdmx/2009/measure#obsValue> ?v } LIMIT 1')
        self.assertEqual(len(rows), 1)
        iri = rows[0]['o']['value']
        self.assertTrue(iri.startswith('https://example.org/tiva/observation/'))
        fixed = self.query('SELECT ?v ?year WHERE { <' + iri + '> <http://purl.org/linked-data/sdmx/2009/measure#obsValue> ?v; <http://purl.org/linked-data/sdmx/2009/dimension#refPeriod> ?year }')
        self.assertEqual(len(fixed), 1)
        self.assertEqual(fixed[0]['v'], rows[0]['v'])
        self.assertEqual(fixed[0]['v']['datatype'], 'http://www.w3.org/2001/XMLSchema#double')
        self.assertEqual(fixed[0]['year']['datatype'], 'http://www.w3.org/2001/XMLSchema#gYear')

    def test_self_contained_read_only_database(self):
        info = json.loads(self.docker('inspect', self.container))[0]
        self.assertEqual(info['HostConfig']['NetworkMode'], 'none')
        self.assertFalse(any(mount['Type'] == 'bind' for mount in info['Mounts']))
        self.assertEqual(info['Config']['User'], 'ontop')
        self.docker('exec', self.container, 'sh', '-c',
                    'test -r /data/tiva.duckdb && test ! -w /data/tiva.duckdb')
        labels = info['Config']['Labels']
        self.assertTrue(labels['org.aksw.tiva.artifact.version'])
        self.assertEqual(labels['org.aksw.tiva.artifact.checksum.algorithm'], 'SHA-1')
        for name in ('tiva.duckdb.zst.sha1', 'duckdb_jdbc.jar.sha1'):
            digest = self.docker('exec', self.container, 'cat', '/opt/ontop/input/' + name)
            self.assertRegex(digest, r'^[0-9a-fA-F]{40}$')


if __name__ == '__main__':
    unittest.main()
