"""
TYGRIS One-Click Unified Development Launcher
Launches both the FastAPI Backend (Port 8420) and the Next.js Frontend (Port 3000) concurrently.
"""

import os
import sys
import subprocess
import time

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")
FRONTEND_DIR = os.path.join(PROJECT_ROOT, "frontend-v2")

# Running the backend under any interpreter without torch silently falls
# back to a hash-based fake matcher (TigerReIDEngine._embed_query_stub)
# instead of the real trained model - /api/identify still returns
# "confident matches", but they're not based on the uploaded image's
# actual visual content.
#
# D:/tygris_venv has the CUDA-enabled torch build (the checkpoint was
# trained there, on the RTX 4050) and is preferred - inference still works
# fine on it without a GPU present, it's just used for the speed. Falls
# back to backend/.venv312 (CPU-only torch, same real model, just slower
# per identify call) if the GPU venv isn't present on this machine.
_GPU_VENV_PYTHON = "D:/tygris_venv/Scripts/python.exe"
_CPU_VENV_PYTHON = os.path.join(BACKEND_DIR, ".venv312", "Scripts", "python.exe")
BACKEND_PYTHON = _GPU_VENV_PYTHON if os.path.exists(_GPU_VENV_PYTHON) else _CPU_VENV_PYTHON


def main():
    print("=" * 70)
    print("🐅 TYGRIS Wildlife Intelligence Platform: Development Server")
    print("=" * 70)
    print(f"Backend Directory:  {BACKEND_DIR}")
    print(f"Frontend Directory: {FRONTEND_DIR}")
    print("-" * 70)

    if not os.path.exists(BACKEND_PYTHON):
        print(f"[TYGRIS] ERROR: no backend venv found (checked {_GPU_VENV_PYTHON} and {_CPU_VENV_PYTHON})")
        print("[TYGRIS] The trained re-ID model requires torch, which is only installed there.")
        print("[TYGRIS] Set it up with: cd backend && python -m venv .venv312 && "
              ".venv312\\Scripts\\pip install -r requirements.txt")
        sys.exit(1)
    print(f"[TYGRIS] Using backend interpreter: {BACKEND_PYTHON}")

    # 1. Start FastAPI Backend
    print("[1/2] Launching FastAPI Backend on http://localhost:8420 ...")
    backend_cmd = [BACKEND_PYTHON, "-m", "uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8420", "--reload"]
    backend_proc = subprocess.Popen(backend_cmd, cwd=PROJECT_ROOT)

    # 2. Start Next.js Frontend (v2)
    print("[2/2] Launching Next.js 16 Frontend (v2) on http://localhost:3001 ...")
    frontend_cmd = "npm run dev"
    frontend_proc = subprocess.Popen(frontend_cmd, cwd=FRONTEND_DIR, shell=True)

    print("\n✅ Both servers are running:")
    print("   • Web Dashboard:  http://localhost:3001")
    print("   • API Docs:       http://localhost:8420/docs")
    print("   • API Health:     http://localhost:8420/")
    print("\nPress Ctrl+C to stop both servers.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[TYGRIS] Stopping servers...")
        backend_proc.terminate()
        frontend_proc.terminate()
        print("[TYGRIS] Shutdown complete.")


if __name__ == "__main__":
    main()
