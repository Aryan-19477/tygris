"use client";

import { useState } from "react";
import { Microphone } from "@phosphor-icons/react";
import { detectLangFromTranscript, normalizeScribeLang, type Lang } from "@/lib/voiceDemoScript";
import { useLanguage } from "@/lib/i18n/LanguageContext";

async function askAssistant(message: string, lang: Lang): Promise<string> {
  const res = await fetch("/api/assistant", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, lang }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error ?? "Assistant request failed");
  return data.answer as string;
}

type Status = "idle" | "listening" | "thinking" | "speaking" | "error";

const SPEECH_LOCALES: Record<Lang, string> = { en: "en-IN", hi: "hi-IN", mr: "mr-IN" };

function speakInBrowser(text: string, lang: Lang, setStatus: (s: Status) => void, onFail: () => void) {
  if (typeof window === "undefined" || !window.speechSynthesis) return onFail();

  const utterance = new SpeechSynthesisUtterance(text);
  const locale = SPEECH_LOCALES[lang];
  utterance.lang = locale;
  const voice = window.speechSynthesis.getVoices().find((v) => v.lang === locale || v.lang.startsWith(lang));
  if (voice) utterance.voice = voice;
  utterance.onend = () => setStatus("idle");
  utterance.onerror = onFail;

  window.speechSynthesis.cancel();
  setStatus("speaking");
  window.speechSynthesis.speak(utterance);
}

const RECORD_MS = 5000;

function pickMimeType(): string {
  const candidates = ["audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus", "audio/mp4"];
  for (const type of candidates) {
    if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(type)) return type;
  }
  return "";
}

async function recordAudio(ms: number): Promise<Blob> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const mimeType = pickMimeType();
  const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
  const chunks: BlobPart[] = [];

  const stopped = new Promise<Blob>((resolve) => {
    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunks.push(e.data);
    };
    recorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop());
      resolve(new Blob(chunks, { type: mimeType || "audio/webm" }));
    };
  });

  recorder.start();
  await new Promise((r) => setTimeout(r, ms));
  recorder.stop();

  return stopped;
}

export default function VoiceAgentButton() {
  const { t } = useLanguage();
  const [status, setStatus] = useState<Status>("idle");
  const [heard, setHeard] = useState("");
  const [errorMsg, setErrorMsg] = useState("");

  const handleClick = async () => {
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
      setStatus("error");
      setErrorMsg(t("voice.micNotSupported"));
      return;
    }

    setStatus("listening");
    setHeard("");
    setErrorMsg("");

    let audioBlob: Blob;
    try {
      audioBlob = await recordAudio(RECORD_MS);
    } catch (err) {
      console.error("[voice] mic recording failed:", err);
      setStatus("error");
      setErrorMsg(t("voice.micAccessFailed"));
      return;
    }

    setStatus("thinking");

    let transcript = "";
    let scribeLang: string | null = null;
    try {
      const form = new FormData();
      form.append("audio", audioBlob, "recording.webm");
      const sttRes = await fetch("/api/stt", { method: "POST", body: form });
      if (!sttRes.ok) throw new Error(await sttRes.text());
      const data = await sttRes.json();
      transcript = data.text ?? "";
      scribeLang = data.languageCode ?? null;
      console.log("[voice] transcript:", transcript, "scribe lang:", scribeLang);
    } catch (err) {
      console.error("[voice] STT request failed:", err);
      setStatus("error");
      setErrorMsg(t("voice.transcribeFailed"));
      return;
    }

    if (!transcript.trim()) {
      setStatus("error");
      setErrorMsg(t("voice.noSpeechDetected"));
      return;
    }

    const preferred = normalizeScribeLang(scribeLang);
    const lang = detectLangFromTranscript(transcript, ["en", "hi", "mr"], preferred) ?? preferred ?? "en";

    setHeard(`[${lang}] ${transcript}`);
    setStatus("thinking");

    let answer: string;
    try {
      answer = await askAssistant(transcript, lang);
    } catch (err) {
      console.error("[voice] assistant request failed:", err);
      setStatus("error");
      setErrorMsg(err instanceof Error ? err.message : "Assistant couldn't answer that.");
      return;
    }

    setHeard(answer);

    try {
      const res = await fetch("/api/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: answer, lang }),
      });
      if (!res.ok) throw new Error("TTS request failed");

      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      setStatus("speaking");
      audio.onended = () => {
        URL.revokeObjectURL(url);
        setStatus("idle");
      };
      await audio.play();
    } catch (err) {
      // ElevenLabs and Groq voices both unavailable — speak with the browser instead.
      console.warn("[voice] server TTS failed, using browser speech:", err);
      speakInBrowser(answer, lang, setStatus, () => {
        setStatus("error");
        setErrorMsg(t("voice.replyFailed"));
      });
    }
  };

  const label =
    status === "listening"
      ? t("voice.listening")
      : status === "thinking"
        ? t("voice.thinking")
        : status === "speaking"
          ? t("voice.speaking")
          : status === "error"
            ? t("voice.tryAgain")
            : t("voice.askAssistant");

  const busy = status === "listening" || status === "thinking" || status === "speaking";

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        onClick={handleClick}
        disabled={busy}
        aria-label={label}
        className={`group relative flex h-10 items-center gap-2 rounded-full px-4 text-[13px] font-semibold tracking-tight shadow-sm transition-all duration-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent active:translate-y-px active:scale-[0.98] ${
          status === "error"
            ? "bg-danger text-white hover:bg-danger/90"
            : "bg-accent text-accent-foreground hover:bg-accent-strong hover:shadow-md"
        } disabled:cursor-default disabled:opacity-95`}
      >
        {busy && (
          <span
            aria-hidden
            className="absolute inset-0 animate-ping rounded-full bg-accent opacity-20"
          />
        )}
        <Microphone
          size={17}
          weight={status === "listening" ? "fill" : "bold"}
          className={status === "listening" ? "animate-pulse" : ""}
        />
        {label}
      </button>
      {errorMsg ? (
        <span className="max-w-55 truncate font-mono text-[10px] text-priority-high">{errorMsg}</span>
      ) : (
        heard && <span className="max-w-55 truncate font-mono text-[10px] text-muted">{heard}</span>
      )}
    </div>
  );
}
