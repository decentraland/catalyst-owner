"""TLS regression tests; real OpenSSL fixtures, no Docker daemon or ACME calls."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOST = 'peer-testing.decentraland.org'
INIT = (ROOT / 'init.sh').read_text()
FUNCTIONS = INIT.split('##\n# Main program\n##', 1)[0]
TWO_DAYS_AGO = time.time() - 2 * 86400


class CertificateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = tempfile.TemporaryDirectory()
        cls.fixture_dir = Path(cls.fixtures.name)
        for name, subject, host, key, days in [
                ('ec', HOST, HOST, 'ec', 90),
                ('other', 'other.example.org', 'other.example.org', 'ec', 90),
                ('rsa', HOST, HOST, 'rsa:2048', 90),
                ('weak', HOST, HOST, 'rsa:1024', 90),
                ('expiring', HOST, HOST, 'ec', 2),
                # Self-signed, so the issuer carries the staging name too.
                ('staging', '(STAGING) Ersatz Edamame E1', HOST, 'ec', 90)]:
            directory = cls.fixture_dir / name
            directory.mkdir()
            args = ['openssl', 'req', '-x509', '-nodes', '-newkey', key]
            if key == 'ec':
                args += ['-pkeyopt', 'ec_paramgen_curve:prime256v1']
            subprocess.run(args + ['-days', str(days), '-subj', f'/CN={subject}',
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
        self.le = self.root / 'letsencrypt'
        (self.le / 'live').mkdir(parents=True)
        (self.le / 'renewal').mkdir()

    def shell(self, code, **extra):
        env = dict(os.environ, TEST_ROOT=str(self.root), LE_DIR=str(self.le),
                   DOMAIN=HOST, RENEW_DAYS='30', **extra)
        return subprocess.run(['bash', '-c', FUNCTIONS + '\n' + code], cwd=ROOT,
                              env=env, text=True, capture_output=True)

    def lineage(self, name, fixture='ec', renewal=True, recent=False):
        directory = self.le / 'live' / name
        shutil.copytree(self.fixture_dir / fixture, directory)
        if not recent:
            for pem in directory.iterdir():
                os.utime(pem, (TWO_DAYS_AGO, TWO_DAYS_AGO))
        if renewal:
            (self.le / 'renewal' / f'{name}.conf').write_text('renewal settings')
        return directory

    def state(self):
        # The same script init.sh runs inside the certbot container.
        result = self.shell('sh -c "$cert_state_script"')
        self.assertEqual(result.returncode, 0, result.stderr)
        return tuple(result.stdout.split())

    def test_select_existing_numbered_lineage(self):
        self.lineage(HOST + '-0001')
        self.assertEqual(self.state(), (HOST + '-0001', 'valid'))

    def test_prefer_exact_name(self):
        self.lineage(HOST)
        self.lineage(HOST + '-0001')
        self.assertEqual(self.state(), (HOST, 'valid'))

    def test_skip_empty_base_directory(self):
        (self.le / 'live' / HOST).mkdir()
        self.lineage(HOST + '-0001')
        self.assertEqual(self.state(), (HOST + '-0001', 'valid'))

    def test_skip_wrong_host_and_incomplete_lineages(self):
        self.lineage(HOST + '-0001', 'other')
        incomplete = self.lineage(HOST + '-0002')
        (incomplete / 'privkey.pem').unlink()
        self.lineage(HOST + '-0003')
        self.assertEqual(self.state(), (HOST + '-0003', 'valid'))

    def test_skip_lineage_certbot_does_not_manage(self):
        # e.g. a dummy certificate left in live/ by older versions of init.sh
        self.lineage(HOST, renewal=False)
        self.assertEqual(self.state(), (HOST, 'missing'))

    def test_skip_non_numbered_suffix(self):
        self.lineage(HOST + '-backup')
        self.lineage(HOST + '-dry-run')
        self.assertEqual(self.state(), (HOST, 'missing'))

    def test_new_install_uses_host(self):
        self.assertEqual(self.state(), (HOST, 'missing'))

    def test_key_strength_accounts_for_algorithm(self):
        for fixture, expected in [('ec', 'valid'), ('rsa', 'valid'), ('weak', 'weak-key')]:
            with self.subTest(fixture=fixture):
                shutil.rmtree(self.le / 'live')
                (self.le / 'live').mkdir()
                self.lineage(HOST, fixture)
                self.assertEqual(self.state(), (HOST, expected))

    def test_staging_certificate_is_replaced(self):
        self.lineage(HOST, 'staging')
        self.assertEqual(self.state(), (HOST, 'staging'))

    def test_certificate_close_to_expiry(self):
        self.lineage(HOST, 'expiring')
        self.assertEqual(self.state(), (HOST, 'expiring'))

    def test_recently_issued_certificate(self):
        self.lineage(HOST, recent=True)
        self.assertEqual(self.state(), (HOST, 'recent'))

    def test_render_https_config_uses_selected_lineage(self):
        config = self.root / 'nginx.conf'
        result = self.shell(
            'renderHttpsConfig "$DOMAIN" "/etc/letsencrypt/live/$DOMAIN-0001" '
            '"$nginx_server_template_https" "$CONFIG"', CONFIG=str(config))
        self.assertEqual(result.returncode, 0, result.stderr)
        text = config.read_text()
        self.assertIn(f'server_name {HOST};', text)
        self.assertIn(f'/live/{HOST}-0001/fullchain.pem;', text)
        self.assertIn(f'/live/{HOST}-0001/privkey.pem;', text)
        self.assertNotIn('$certificate_path', text)

    def issue(self, fail_on=''):
        # Exercise the real issuance function, substituting only external commands.
        return self.shell('''
nginx_url="$DOMAIN"
EMAIL=ops@example.org
cert_failure_file="$TEST_ROOT/failed"
waitForAcmeChallenge () { :; }
waitForCertbotService () { :; }
certbotRun () {
  printf '%s\\n' "$*" >> "$TEST_ROOT/certbot-calls"
  case "$*" in *"$FAIL_ON"*) [ -n "$FAIL_ON" ] && return 1 ;; esac
  return 0
}
issueCert "$DOMAIN-0001"
''', FAIL_ON=fail_on)

    def calls(self):
        path = self.root / 'certbot-calls'
        return path.read_text().splitlines() if path.exists() else []

    def test_issuance_renews_the_selected_lineage_in_place(self):
        result = self.issue()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        dry_run, real = self.calls()
        self.assertIn(f'--cert-name {HOST}-0001-dry-run --dry-run', dry_run)
        self.assertIn(f'--cert-name {HOST}-0001 --force-renewal', real)
        self.assertNotIn('--dry-run', real)
        self.assertFalse((self.root / 'failed').exists())

    def test_failed_dry_run_skips_the_real_request(self):
        result = self.issue(fail_on='--dry-run')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertTrue((self.root / 'failed').exists())

    def test_failed_issuance_backs_off(self):
        result = self.issue(fail_on='--force-renewal')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 2)
        result = self.issue()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not trying again yet', result.stdout)
        self.assertEqual(len(self.calls()), 2)


if __name__ == '__main__':
    unittest.main()
