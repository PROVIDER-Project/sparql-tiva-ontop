"""Namespace rendering checks; no database or Docker required."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ONTOP = Path(__file__).resolve().parents[1] / 'ontop'
PROJECT = 'tiva'

@unittest.skipUnless(shutil.which('envsubst'), 'Requires envsubst (gettext)')
class NamespaceTests(unittest.TestCase):
    def render(self, text, overrides=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith('NS_')}
        env.update(overrides or {})
        return subprocess.run(['sh', str(ONTOP / 'expand.sh')], input=text,
                              capture_output=True, text=True, check=True,
                              cwd='/', env=env).stdout

    def test_defaults_and_complete_mapping(self):
        text = self.render((ONTOP / (PROJECT + '.r2rml.ttl.in')).read_text())
        self.assertNotIn('${NS_', text)
        self.assertNotIn('https://example.org/', text)
        self.assertIn('https://schema.projekt-provider.de/' + PROJECT + '#', text)
        self.assertIn('https://data.projekt-provider.de/' + PROJECT + '/observation/', text)
        self.assertIn('o:hasCountry', text)
        self.assertIn('https://data.projekt-provider.de/country/{COUNTRY_CODE}', text)
        self.assertIn('{OBSERVATION_LOCAL_NAME}', text)

    def test_override_and_unrelated_dollar_expressions(self):
        variable = 'NS_' + PROJECT.upper() + '_R'
        text = '${' + variable + '}observation/{ID} $OTHER ${OTHER} $(SQL)'
        self.assertEqual(self.render(text, {variable: 'https://staging.example/', 'OTHER': 'changed'}),
                         'https://staging.example/observation/{ID} $OTHER ${OTHER} $(SQL)')

    def test_empty_override_uses_default(self):
        variable = 'NS_' + PROJECT.upper() + '_O'
        self.assertEqual(self.render('${' + variable + '}', {variable: ''}),
                         'https://schema.projekt-provider.de/' + PROJECT + '#')

    def test_all_namespace_overrides(self):
        variables = ['NS_GLOBAL_O', 'NS_GLOBAL_R', 'NS_' + PROJECT.upper() + '_O', 'NS_' + PROJECT.upper() + '_R']
        values = {v: 'https://override.example/' + v + '/' for v in variables}
        self.assertEqual(self.render(' '.join('${' + v + '}' for v in variables), values),
                         ' '.join(values[v] for v in variables))

    def test_shell_syntax(self):
        for name in ('namespaces.sh', 'expand.sh', 'start.sh'):
            subprocess.run(['sh', '-n', str(ONTOP / name)], check=True)
