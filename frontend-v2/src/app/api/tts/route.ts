import { NextRequest, NextResponse } from "next/server";
import type { Lang } from "@/lib/voiceDemoScript";

const VOICE_IDS: Record<Lang, string | undefined> = {
  en: process.env.ELEVENLABS_VOICE_ID_EN,
  hi: process.env.ELEVENLABS_VOICE_ID_HI,
  mr: process.env.ELEVENLABS_VOICE_ID_MR,
};

export async function POST(req: NextRequest) {
  const { text, lang } = await req.json();
  if (!text || typeof text !== "string") {
    return NextResponse.json({ error: "text is required" }, { status: 400 });
  }

  const voiceId = VOICE_IDS[(lang as Lang) ?? "en"] ?? VOICE_IDS.en;
  if (!voiceId) {
    return NextResponse.json({ error: "no voice configured" }, { status: 500 });
  }

  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: {
      "xi-api-key": process.env.ELEVENLABS_API_KEY!,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text,
      model_id: "eleven_multilingual_v2",
      voice_settings: { stability: 0.5, similarity_boost: 0.75 },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    return NextResponse.json({ error: errText }, { status: 500 });
  }

  const audioBuffer = await res.arrayBuffer();
  return new NextResponse(audioBuffer, {
    headers: { "Content-Type": "audio/mpeg" },
  });
}
