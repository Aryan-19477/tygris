"use client";

import { X } from "@phosphor-icons/react";
import type { GISStation } from "@/lib/api";
import { IdentifyCapture } from "./IdentifyCapture";

/**
 * Station upload slide-over — a ranger uploads a fresh capture from the
 * exact station she's looking at on the map and stays oriented on the map
 * she was just viewing. For uploading without first finding a station on
 * the map, see the standalone Identify tab.
 */
export function StationUploadPanel({
  station,
  onClose,
}: {
  station: GISStation;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-2000 flex justify-end slideover-backdrop" onClick={onClose}>
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex h-full w-full max-w-md flex-col overflow-y-auto border-l border-border bg-background shadow-2xl"
      >
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div>
            <div className="font-mono text-xs text-muted">{station.camera_id}</div>
            <div className="text-base font-medium text-foreground">Upload a capture</div>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-full text-muted hover:bg-surface hover:text-foreground"
          >
            <X size={16} />
          </button>
        </div>

        <div className="flex flex-col gap-2 border-b border-border px-5 py-3 font-mono text-xs text-muted">
          <div className="flex items-center justify-between">
            <span>Zone</span>
            <span className="text-foreground">{station.zone}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Sub-region</span>
            <span className="text-foreground">{station.sub_region || "—"}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Status</span>
            <span className={station.operational_status === "OPERATIONAL" ? "text-positive" : "text-danger"}>
              {station.operational_status}
            </span>
          </div>
        </div>

        <div className="flex-1 p-5">
          <IdentifyCapture stationId={station.camera_id} />
        </div>
      </div>
    </div>
  );
}
