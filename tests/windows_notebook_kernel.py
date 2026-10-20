#!/usr/bin/env python3
"""Execute 42 in the relocated bundle's configured local Jupyter kernel.

Run with its packaged Python after WindowsInit created the profile kernelspec.
This opens only Jupyter's local loopback channels. No GUI, downloads, user
documents, existing kernels or global environment settings are involved.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from jupyter_client import KernelManager
from jupyter_client.kernelspec import KernelSpecManager


def check(kernelspec, expected_python, timeout):
    kernelspec = kernelspec.resolve(strict=True)
    expected_python = expected_python.resolve(strict=True)
    if not Path(sys.executable).samefile(expected_python):
        raise RuntimeError("Run this check with the configured packaged Python")
    document = json.loads(kernelspec.read_text(encoding="utf-8"))
    argv = document.get("argv", [])
    if not argv or not Path(argv[0]).is_absolute() or not Path(argv[0]).samefile(expected_python):
        raise RuntimeError("The installed kernelspec retained a different Python executable")
    if "ipykernel_launcher" not in argv or "{connection_file}" not in argv:
        raise RuntimeError("The installed kernelspec is not the expected Python Jupyter kernel")
    provisioner = document.get("metadata", {}).get("kernel_provisioner", {}).get("provisioner_name", "local-provisioner")
    if provisioner != "local-provisioner":
        raise RuntimeError("This check accepts only the local kernel provisioner")

    deadline = time.monotonic() + timeout

    def remaining():
        duration = deadline - time.monotonic()
        if duration <= 0:
            raise TimeoutError("The packaged Notebook kernel exceeded its bounded check time")
        return duration

    with tempfile.TemporaryDirectory(prefix="glow-packaged-kernel-") as temporary:
        work = Path(temporary)
        spec_manager = KernelSpecManager(kernel_dirs=[str(kernelspec.parent.parent)], ensure_native_kernel=False)
        selected = spec_manager.get_kernel_spec(kernelspec.parent.name)
        if not Path(selected.resource_dir).samefile(kernelspec.parent):
            raise RuntimeError("Jupyter selected a kernelspec outside the configured profile")
        manager = KernelManager(kernel_name=kernelspec.parent.name, kernel_spec_manager=spec_manager,
                                connection_file=str(work / "connection.json"), ip="127.0.0.1", transport="tcp")
        client, process = None, None
        environment = dict(os.environ)
        for name in ("PYTHONHOME", "PYTHONPATH", "PYTHONSTARTUP"):
            environment.pop(name, None)
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONUTF8"] = "1"
        for name, directory in (("IPYTHONDIR", "ipython"), ("JUPYTER_CONFIG_DIR", "config"),
                                ("JUPYTER_DATA_DIR", "data"), ("JUPYTER_RUNTIME_DIR", "runtime"),
                                ("MPLCONFIGDIR", "matplotlib")):
            path = work / directory
            path.mkdir()
            environment[name] = str(path)
        with (work / "kernel.log").open("wb") as output:
            try:
                options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
                manager.start_kernel(cwd=str(work), env=environment, stdout=output, stderr=subprocess.STDOUT, **options)
                process = getattr(manager.provisioner, "process", None)
                client = manager.blocking_client()
                client.start_channels()
                client.wait_for_ready(timeout=remaining())
                request = client.execute("40 + 2", store_history=False, allow_stdin=False, stop_on_error=True)
                result = None
                while True:
                    message = client.get_iopub_msg(timeout=remaining())
                    if message.get("parent_header", {}).get("msg_id") != request:
                        continue
                    kind, content = message["header"]["msg_type"], message["content"]
                    if kind == "error":
                        raise RuntimeError("Kernel expression failed: " + content.get("ename", "error") + ": " + content.get("evalue", ""))
                    if kind == "execute_result":
                        result = content.get("data", {}).get("text/plain")
                    if kind == "status" and content.get("execution_state") == "idle":
                        break
                while True:
                    reply = client.get_shell_msg(timeout=remaining())
                    if reply.get("parent_header", {}).get("msg_id") == request:
                        break
                if result != "42" or reply.get("content", {}).get("status") != "ok":
                    raise RuntimeError("The packaged kernel did not execute 40 + 2 successfully")
            finally:
                # Retain a handle even when startup raised after creating the
                # process. Only this check's own kernel may be terminated.
                process = process or getattr(manager.provisioner, "process", None)
                try:
                    if client is not None:
                        client.stop_channels()
                finally:
                    try:
                        manager.shutdown_kernel(now=True)
                    finally:
                        if process is not None and process.poll() is None:
                            process.kill()
                            process.wait(timeout=10)
                if manager.has_kernel or (process is not None and process.poll() is None):
                    raise RuntimeError("The check's Notebook kernel did not shut down")
    print("Relocated bundled Notebook kernel executed 40 + 2 = 42; kernel process stopped and temporary files removed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernelspec", type=Path, required=True)
    parser.add_argument("--expected-python", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 120:
        parser.error("--timeout must be between 1 and 120 seconds")
    try:
        check(args.kernelspec, args.expected_python, args.timeout)
    except Exception as error:
        parser.exit(1, "Packaged Notebook kernel check failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
