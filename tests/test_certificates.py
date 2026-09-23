"""TLS regression tests; real OpenSSL fixtures, no Docker daemon or ACME calls."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOST = 'peer-testing.decentraland.org'
INIT = (ROOT / 'init.sh').read_text()
FUNCTIONS = INIT.split('##\n# Main program\n##', 1)[0]
HTTPS_SETUP = INIT.split('export nginx_url=', 1)[1].split('\nmatches=', 1)[0]
HTTPS_SETUP = 'export nginx_url=' + HTTPS_SETUP


class CertificateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = tempfile.TemporaryDirectory()
        cls.fixture_dir = Path(cls.fixtures.name)
        for name, host, key in [('ec', HOST, 'ec'), ('other', 'other.example.org', 'ec'),
                                ('rsa', HOST, 'rsa:2048'), ('weak', HOST, 'rsa:1024')]:
            directory = cls.fixture_dir / name
            directory.mkdir()
            args = ['openssl', 'req', '-x509', '-nodes', '-newkey', key]
            if key == 'ec':
                args += ['-pkeyopt', 'ec_paramgen_curve:prime256v1']
            subprocess.run(args + ['-days', '2', '-subj', f'/CN={host}',
                           '-addext', f'subjectAltName=DNS:{host}',
                           '-keyout', str(directory / 'privkey.pem'),
                           '-out', str(directory / 'fullchain.pem')],
                           check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.fixtures.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.live = self.root / 'conf/live'
        self.live.mkdir(parents=True)
        self.config = self.root / 'nginx.conf'

    def shell(self, code, **extra):
        env = dict(os.environ, TEST_ROOT=str(self.root), HOST=HOST,
                   FIXTURE=str(self.fixture_dir / 'ec'), **extra)
        return subprocess.run(['bash', '-c', FUNCTIONS + '\n' + code], cwd=ROOT,
                              env=env, text=True, capture_output=True)

    def lineage(self, name, fixture='ec'):
        directory = self.live / name
        shutil.copytree(self.fixture_dir / fixture, directory)
        return directory

    def select(self):
        result = self.shell('certificateNameForHost "$HOST" "$TEST_ROOT/conf/live"')
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_select_existing_numbered_lineage(self):
        self.lineage(HOST + '-0001')
        self.assertEqual(self.select(), HOST + '-0001')

    def test_prefer_exact_name(self):
        self.lineage(HOST)
        self.lineage(HOST + '-0001')
        self.assertEqual(self.select(), HOST)

    def test_skip_empty_base_directory(self):
        (self.live / HOST).mkdir()
        self.lineage(HOST + '-0001')
        self.assertEqual(self.select(), HOST + '-0001')

    def test_skip_wrong_host_and_incomplete_lineages(self):
        self.lineage(HOST + '-0001', 'other')
        incomplete = self.lineage(HOST + '-0002')
        (incomplete / 'privkey.pem').unlink()
        self.lineage(HOST + '-0003')
        self.assertEqual(self.select(), HOST + '-0003')

    def test_skip_non_numbered_suffix(self):
        self.lineage(HOST + '-backup')
        self.assertEqual(self.select(), HOST)

    def test_new_install_uses_host(self):
        self.assertEqual(self.select(), HOST)

    def test_key_strength_accounts_for_algorithm(self):
        for fixture, expected in [('ec', 1), ('rsa', 1), ('weak', 0)]:
            with self.subTest(fixture=fixture):
                result = self.shell('certificateNeedsRenewal "$CERT"',
                                    CERT=str(self.fixture_dir / fixture / 'fullchain.pem'))
                self.assertEqual(result.returncode, expected, result.stderr)

    def setup_script(self):
        return '''
data_path="$TEST_ROOT"
nginx_server_file="$TEST_ROOT/nginx.conf"
CATALYST_URL="https://$HOST"
REGENERATE=0
'''

    def test_existing_ec_lineage_is_reused_without_issuance(self):
        self.lineage(HOST + '-0001')
        result = self.shell(self.setup_script() + '''
leCertEmit () { echo 'Unexpected issuance' >&2; exit 99; }
''' + HTTPS_SETUP)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = self.config.read_text()
        self.assertIn(f'server_name {HOST};', config)
        self.assertIn(f'/live/{HOST}-0001/fullchain.pem;', config)
        self.assertIn(f'/live/{HOST}-0001/privkey.pem;', config)
        self.assertNotIn('$certificate_path', config)

    def test_localhost_still_uses_http(self):
        result = self.shell(self.setup_script() + '\nCATALYST_URL=http://localhost\n' + HTTPS_SETUP)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('ssl_certificate', self.config.read_text())

    def test_wrong_host_certificate_is_not_reused(self):
        self.lineage(HOST, 'other')
        result = self.shell(self.setup_script() + '''
leCertEmit () { echo 'Issuance required'; }
''' + HTTPS_SETUP)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Issuance required', result.stdout)

    def issue(self, name, fail=False):
        # Exercise the real issuance function, substituting only external commands.
        return self.shell(self.setup_script() + '''
nginx_url="$HOST"
certificate_name="$CERT_NAME"
CATALYST_OWNER_CHANNEL=stable
EMAIL=ops@example.org
downloadTlsFile () { touch "$2"; }
curl () { printf 200; }
sleep () { :; }
docker-compose () {
  printf '%s\\n' "$*" >> "$TEST_ROOT/docker-calls"
  case "$*" in
    *'openssl req'*)
      mkdir -p "$TEST_ROOT/conf/bootstrap/$HOST"
      cp "$FIXTURE/"*.pem "$TEST_ROOT/conf/bootstrap/$HOST/" ;;
    *'certbot certonly'*)
      [ "$FAIL_ISSUANCE" = 1 ] && return 1
      mkdir -p "$TEST_ROOT/conf/live/$certificate_name"
      cp "$FIXTURE/"*.pem "$TEST_ROOT/conf/live/$certificate_name/" ;;
    *'rm -Rf'*) echo 'Must not delete certificate lineages' >&2; return 99 ;;
    *'nginx -t'*)
      test -f "$TEST_ROOT/conf/live/$certificate_name/fullchain.pem" || return 1 ;;
  esac
  return 0
}
leCertEmit
''', CERT_NAME=name, FAIL_ISSUANCE='1' if fail else '0')

    def test_issuance_uses_explicit_name_and_preserves_existing_lineage(self):
        name = HOST + '-0001'
        self.lineage(name)
        renewal = self.root / f'conf/renewal/{name}.conf'
        renewal.parent.mkdir()
        renewal.write_text('existing renewal settings')
        result = self.issue(name)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = (self.root / 'docker-calls').read_text()
        self.assertEqual(calls.count(f"--cert-name '{name}'"), 2)
        self.assertNotIn('rm -Rf', calls)
        self.assertEqual(renewal.read_text(), 'existing renewal settings')
        self.assertIn(f'/live/{name}/fullchain.pem;', self.config.read_text())
        self.assertNotIn('/bootstrap/', self.config.read_text())

    def test_first_issuance_uses_requested_name(self):
        result = self.issue(HOST)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.live / HOST / 'fullchain.pem').is_file())
        self.assertIn(f'/live/{HOST}/fullchain.pem;', self.config.read_text())

    def test_failed_issuance_preserves_previous_certificate(self):
        name = HOST + '-0001'
        directory = self.lineage(name, 'rsa')
        before = (directory / 'fullchain.pem').read_bytes()
        result = self.issue(name, fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((directory / 'fullchain.pem').read_bytes(), before)
        self.assertNotIn('restart nginx', (self.root / 'docker-calls').read_text())
        self.assertIn(f'/bootstrap/{HOST}/fullchain.pem;', self.config.read_text())


if __name__ == '__main__':
    unittest.main()
