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


def main():
    print("=" * 70)
    print("🐅 TYGRIS Wildlife Intelligence Platform: Development Server")
    print("=" * 70)
    print(f"Backend Directory:  {BACKEND_DIR}")
    print(f"Frontend Directory: {FRONTEND_DIR}")
    print("-" * 70)

    # 1. Start FastAPI Backend
    print("[1/2] Launching FastAPI Backend on http://localhost:8420 ...")
    backend_cmd = [sys.executable, "-m", "uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8420", "--reload"]
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
