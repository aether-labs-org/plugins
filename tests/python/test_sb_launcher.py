import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from sb_helpers import PLUGIN

LAUNCHER = PLUGIN / "bin" / "sb-python"
MESSAGE = "sb: needs Python 3.9+ (tried python, python3)"


class LauncherBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        self.script = Path(self.tmp.name) / "probe.py"
        self.script.write_text("import sys\nprint('ran', sys.version_info[0])\n", encoding="utf-8")

    def real(self, name):
        (self.bin / name).symlink_to(sys.executable)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body, encoding="utf-8")
        path.chmod(0o755)

    def launch(self, *args, path=None):
        env = {"PATH": str(self.bin) if path is None else path}
        return subprocess.run(["/bin/sh", str(LAUNCHER), *args], capture_output=True, text=True, env=env)


class LauncherTests(LauncherBase):
    def test_only_python3_on_path(self):
        self.real("python3")
        done = self.launch(str(self.script))
        self.assertEqual((done.returncode, done.stdout.strip()), (0, "ran 3"), done.stderr)

    def test_only_python_on_path(self):
        self.real("python")
        done = self.launch(str(self.script))
        self.assertEqual((done.returncode, done.stdout.strip()), (0, "ran 3"), done.stderr)

    def test_arguments_reach_the_script(self):
        self.real("python3")
        self.script.write_text("import sys\nprint(sys.argv[1:])\n", encoding="utf-8")
        done = self.launch(str(self.script), "--vault", "a b")
        self.assertEqual(done.stdout.strip(), "['--vault', 'a b']")

    def test_python_is_preferred_when_both_work(self):
        for name in ("python", "python3"):
            self.stub(name, 'if [ "$1" = "-I" ]; then exit 0; fi\necho "ran %s"\n' % name)
        done = self.launch(str(self.script))
        self.assertEqual(done.stdout.strip(), "ran python")

    def test_broken_python_falls_back_to_python3(self):
        self.stub("python", "exit 1\n")
        self.real("python3")
        done = self.launch(str(self.script))
        self.assertEqual((done.returncode, done.stdout.strip()), (0, "ran 3"), done.stderr)

    def test_old_python_is_rejected(self):
        self.stub("python", 'if [ "$1" = "-I" ]; then exit 1; fi\necho "old python ran"\n')
        self.real("python3")
        done = self.launch(str(self.script))
        self.assertEqual(done.stdout.strip(), "ran 3")

    def test_a_noisy_stub_does_not_leak_into_the_output(self):
        self.stub("python", 'echo "Python was not found; run without arguments to install"\nexit 9009\n')
        self.real("python3")
        done = self.launch(str(self.script))
        self.assertEqual((done.stdout.strip(), done.stderr), ("ran 3", ""))

    def test_no_interpreter_in_hook_mode_exits_0_silently(self):
        done = self.launch("--hook", str(self.script))
        self.assertEqual((done.returncode, done.stdout, done.stderr), (0, "", ""))

    def test_no_interpreter_for_sb_exits_2_with_the_message(self):
        done = self.launch(str(self.script))
        self.assertEqual((done.returncode, done.stdout), (2, ""))
        self.assertEqual(done.stderr.strip(), MESSAGE)

    def test_hook_mode_still_runs_the_script(self):
        self.real("python3")
        done = self.launch("--hook", str(self.script))
        self.assertEqual((done.returncode, done.stdout.strip()), (0, "ran 3"))


class EntryPointTests(LauncherBase):
    def test_bin_sb_runs_through_the_launcher(self):
        done = subprocess.run([str(PLUGIN / "bin" / "sb"), "--help"], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("second-brain vault tooling", done.stdout)
        self.assertTrue(os.access(PLUGIN / "bin" / "sb", os.X_OK))
        self.assertTrue(os.access(LAUNCHER, os.X_OK))

    def test_bin_sb_works_with_only_python3_and_reports_a_missing_interpreter(self):
        self.real("python3")
        env = {"PATH": str(self.bin)}
        done = subprocess.run(["/bin/sh", str(PLUGIN / "bin" / "sb"), "--help"], capture_output=True,
                              text=True, env=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        (self.bin / "python3").unlink()
        done = subprocess.run(["/bin/sh", str(PLUGIN / "bin" / "sb"), "--help"], capture_output=True,
                              text=True, env=env)
        self.assertEqual((done.returncode, done.stderr.strip()), (2, MESSAGE))

    def test_hook_commands_go_through_the_launcher(self):
        spec = json.loads((PLUGIN / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        for event in spec.values():
            for hook in event[0]["hooks"]:
                command = hook["command"]
                self.assertTrue(command.startswith(
                    'sh "${CLAUDE_PLUGIN_ROOT}/bin/sb-python" --hook "${CLAUDE_PLUGIN_ROOT}/hooks/'), command)
                self.assertNotIn("python3", command)

    def test_hook_scripts_have_no_shebang(self):
        for path in (PLUGIN / "hooks").glob("*.py"):
            self.assertFalse(path.read_text(encoding="utf-8").startswith("#!"), str(path))

    def test_hook_latency_outside_a_vault(self):
        outside = tempfile.mkdtemp()
        self.addCleanup(os.rmdir, outside)
        event = json.dumps({"cwd": outside, "prompt": "o que sei sobre quokka wombat marsupiais?"})
        command = ["/bin/sh", str(LAUNCHER), "--hook", str(PLUGIN / "hooks" / "recall.py")]
        subprocess.run(command, input=event, capture_output=True, text=True, cwd=outside)   # warm up
        times = []
        for _ in range(20):
            started = time.perf_counter()
            done = subprocess.run(command, input=event, capture_output=True, text=True, cwd=outside)
            times.append((time.perf_counter() - started) * 1000)
            self.assertEqual((done.returncode, done.stdout), (0, ""))
        p95 = sorted(times)[18]
        self.assertLessEqual(p95, 80, "p95 %.1f ms, times %s" % (p95, [round(t) for t in sorted(times)]))


if __name__ == "__main__":
    unittest.main()
