import { NextRequest, NextResponse } from "next/server";

export async function POST(req: NextRequest) {
  const incomingForm = await req.formData();
  const audio = incomingForm.get("audio");
  if (!audio || !(audio instanceof Blob)) {
    return NextResponse.json({ error: "audio file is required" }, { status: 400 });
  }

  const form = new FormData();
  form.append("model_id", "scribe_v1");
  form.append("file", audio, "recording.webm");

  const res = await fetch("https://api.elevenlabs.io/v1/speech-to-text", {
    method: "POST",
    headers: { "xi-api-key": process.env.ELEVENLABS_API_KEY! },
    body: form,
  });

  if (!res.ok) {
    const errText = await res.text();
    return NextResponse.json({ error: errText }, { status: 500 });
  }

  const data = await res.json();
  return NextResponse.json({
    text: data.text ?? "",
    languageCode: data.language_code ?? null,
  });
}
