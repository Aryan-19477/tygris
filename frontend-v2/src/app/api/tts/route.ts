import { NextRequest, NextResponse } from "next/server";
import type { Lang } from "@/lib/voiceDemoScript";

const VOICE_IDS: Record<Lang, string | undefined> = {
  en: process.env.ELEVENLABS_VOICE_ID_EN,
  hi: process.env.ELEVENLABS_VOICE_ID_HI,
  mr: process.env.ELEVENLABS_VOICE_ID_MR,
};

// Groq's Orpheus only speaks English. Requires accepting the model terms once at
// https://console.groq.com/playground?model=canopylabs%2Forpheus-v1-english
const GROQ_TTS_MODEL = "canopylabs/orpheus-v1-english";
const GROQ_TTS_VOICE = "hannah";

async function speakWithElevenLabs(text: string, lang: Lang, apiKey: string): Promise<Response> {
  const voiceId = VOICE_IDS[lang] ?? VOICE_IDS.en;
  if (!voiceId) throw new Error("no ElevenLabs voice configured");

  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: { "xi-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      text,
      model_id: "eleven_multilingual_v2",
      voice_settings: { stability: 0.5, similarity_boost: 0.75 },
    }),
  });
  if (!res.ok) throw new Error(`ElevenLabs TTS ${res.status}: ${await res.text()}`);

  return new NextResponse(await res.arrayBuffer(), {
    headers: { "Content-Type": "audio/mpeg", "X-TTS-Provider": "elevenlabs" },
  });
}

async function speakWithGroq(text: string, apiKey: string): Promise<Response> {
  const res = await fetch("https://api.groq.com/openai/v1/audio/speech", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: GROQ_TTS_MODEL, voice: GROQ_TTS_VOICE, input: text, response_format: "wav" }),
  });
  if (!res.ok) throw new Error(`Groq TTS ${res.status}: ${await res.text()}`);

  return new NextResponse(await res.arrayBuffer(), {
    headers: { "Content-Type": "audio/wav", "X-TTS-Provider": "groq" },
  });
}

export async function POST(req: NextRequest) {
  const { text, lang: rawLang } = await req.json();
  if (!text || typeof text !== "string") {
    return NextResponse.json({ error: "text is required" }, { status: 400 });
  }
  const lang: Lang = rawLang === "hi" || rawLang === "mr" ? rawLang : "en";

  const elevenKey = process.env.ELEVENLABS_API_KEY;
  const groqKey = process.env.GROQ_API_KEY;
  const errors: string[] = [];

  if (elevenKey) {
    try {
      return await speakWithElevenLabs(text, lang, elevenKey);
    } catch (err) {
      console.warn("[tts] ElevenLabs failed, falling back:", err);
      errors.push(String(err));
    }
  }

  if (groqKey && lang === "en") {
    try {
      return await speakWithGroq(text, groqKey);
    } catch (err) {
      console.warn("[tts] Groq failed, falling back to browser speech:", err);
      errors.push(String(err));
    }
  }

  // No server voice available — the client speaks the answer with the browser's built-in speech synthesis.
  return NextResponse.json({ error: errors.join(" | ") || "no TTS provider configured", fallback: "browser" }, { status: 503 });
}
