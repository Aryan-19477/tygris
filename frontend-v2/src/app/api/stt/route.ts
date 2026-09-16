import { NextRequest, NextResponse } from "next/server";

interface Transcript {
  text: string;
  languageCode: string | null;
}

// Groq's Whisper returns full language names ("English"); the client expects codes.
const WHISPER_LANG_CODES: Record<string, string> = {
  english: "en",
  hindi: "hi",
  marathi: "mr",
};

function fileNameFor(audio: Blob) {
  const type = audio.type;
  if (type.includes("ogg")) return "recording.ogg";
  if (type.includes("mp4")) return "recording.mp4";
  if (type.includes("mpeg")) return "recording.mp3";
  if (type.includes("wav")) return "recording.wav";
  return "recording.webm";
}

async function transcribeWithElevenLabs(audio: Blob, apiKey: string): Promise<Transcript> {
  const form = new FormData();
  form.append("model_id", "scribe_v1");
  form.append("file", audio, fileNameFor(audio));

  const res = await fetch("https://api.elevenlabs.io/v1/speech-to-text", {
    method: "POST",
    headers: { "xi-api-key": apiKey },
    body: form,
  });
  if (!res.ok) throw new Error(`ElevenLabs STT ${res.status}: ${await res.text()}`);

  const data = await res.json();
  return { text: data.text ?? "", languageCode: data.language_code ?? null };
}

async function transcribeWithGroq(audio: Blob, apiKey: string): Promise<Transcript> {
  const form = new FormData();
  form.append("model", "whisper-large-v3-turbo");
  form.append("response_format", "verbose_json");
  form.append("file", audio, fileNameFor(audio));

  const res = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  if (!res.ok) throw new Error(`Groq STT ${res.status}: ${await res.text()}`);

  const data = await res.json();
  const language = typeof data.language === "string" ? data.language.toLowerCase() : null;
  return {
    text: (data.text ?? "").trim(),
    languageCode: language ? (WHISPER_LANG_CODES[language] ?? language) : null,
  };
}

export async function POST(req: NextRequest) {
  const incomingForm = await req.formData();
  const audio = incomingForm.get("audio");
  if (!audio || !(audio instanceof Blob)) {
    return NextResponse.json({ error: "audio file is required" }, { status: 400 });
  }

  const elevenKey = process.env.ELEVENLABS_API_KEY;
  const groqKey = process.env.GROQ_API_KEY;

  // ElevenLabs Scribe first; if it's missing, out of quota, or erroring, fall back to Groq Whisper.
  if (elevenKey) {
    try {
      return NextResponse.json({ ...(await transcribeWithElevenLabs(audio, elevenKey)), provider: "elevenlabs" });
    } catch (err) {
      console.warn("[stt] ElevenLabs failed, falling back to Groq:", err);
    }
  }

  if (!groqKey) {
    return NextResponse.json({ error: "No working speech-to-text provider configured." }, { status: 500 });
  }

  try {
    return NextResponse.json({ ...(await transcribeWithGroq(audio, groqKey)), provider: "groq" });
  } catch (err) {
    console.error("[stt] Groq failed:", err);
    return NextResponse.json({ error: err instanceof Error ? err.message : "Transcription failed." }, { status: 500 });
  }
}
