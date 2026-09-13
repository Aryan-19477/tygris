# Voice AI Demo — ElevenLabs Integration Plan (Rawcoded / No-LLM Tier, Multilingual)

Goal: a button in the Vikasit dashboard that lets you speak a question — in
**English, Hindi, or Marathi** — and hear a spoken answer in that same
language. Fully hardcoded — no agent reasoning, no tool-calling, no LLM in the
loop. You speak, we auto-detect which of the 3 languages you used, keyword-match
the transcript against known questions in that language, and play back a fixed
pre-written answer as audio via ElevenLabs Text-to-Speech in a matching voice.

---

## 0. Security note (do this first)

`frontend/.env.local` currently has:
```
ElevenaLABS=sk_d3a387ccb2bd59525eaf3ecb48cb22113e1a77b9a124ab38
```
Rename to `ELEVENLABS_API_KEY`, keep it **server-only** (never
`NEXT_PUBLIC_`), confirm `.env.local` is gitignored, and rotate the key if
there's any chance it's been committed or shared elsewhere.

---

## 1. Voices needed

You've already saved two voices under ElevenLabs → My Voices:
- **Raunak M** — Hindi, Narration → used for **Hindi and Marathi** answers
  (Marathi-specific stock voices are rare; this voice reading Marathi text via
  `eleven_multilingual_v2` is the practical choice).
- Anvi — not used in this plan, kept saved for future use if wanted.

English voice: **Shreya G** (`KawjuInLhxYsnVJlqveG`).

`frontend/.env.local` (already set):
```
NEXT_PUBLIC_API_BASE=http://127.0.0.1:8420
ELEVENLABS_API_KEY=sk_...
ELEVENLABS_VOICE_ID_EN=KawjuInLhxYsnVJlqveG
ELEVENLABS_VOICE_ID_HI=QD3mM8iI4N1qizZxCXmc
ELEVENLABS_VOICE_ID_MR=QD3mM8iI4N1qizZxCXmc
```

Keeping 3 separate env keys (even though HI/MR point to the same voice) means
swapping in a dedicated Marathi voice later is a one-line env change, not a
code change.

---

## 2. Architecture

```
[User clicks "Ask" button, speaks]
        │
        ▼
Run browser SpeechRecognition THREE TIMES against the same
utterance — once each with lang = "en-IN", "hi-IN", "mr-IN"
(see Section 3 for how this is actually sequenced)
        │
        ▼
Keep the result with the highest confidence score
→ gives us both the transcript AND the detected language
        │
        ▼
Keyword-match the transcript against that language's Q&A table
        │
        ▼
Matched question → fixed answer STRING in the detected language
        │
        ▼
Frontend calls /api/tts with { text, lang }
        │
        ▼
Route picks ELEVENLABS_VOICE_ID_<LANG> and calls ElevenLabs
POST /v1/text-to-speech/{voice_id} with model_id eleven_multilingual_v2
        │
        ▼
Browser plays the returned audio
```

### Why "try all 3, keep best" instead of one recognizer call

Web Speech API's `SpeechRecognition.lang` must be set before `.start()` — it
cannot auto-detect across languages mid-utterance. Running it three times
against re-recorded audio isn't possible (you'd need the user to repeat
themselves), so instead: **one mic capture, three parallel `SpeechRecognition`
instances** listening to the live mic stream simultaneously, each primed for a
different language. Each returns a transcript + a `confidence` score; we keep
the highest-confidence result. This works because Chrome allows multiple
concurrent recognition sessions, and genuinely different-language speech
scores much lower confidence when force-decoded against the wrong language
model — so the correct language reliably wins.

Practical fallback: if confidence scores come back too close to call (rare,
but possible for short utterances), default to whichever result's transcript
matched a known keyword set first, then fall back to English.

---

## 3. Multilingual Q&A tables

`frontend/src/lib/voiceDemoScript.ts`:
```ts
export type Lang = "en" | "hi" | "mr";

export interface DemoQA {
  id: string;
  matchKeywords: string[]; // all must appear (case-insensitive) in transcript
  answer: string;
}

export const DEMO_QA: Record<Lang, DemoQA[]> = {
  en: [
    {
      id: "sightings_today",
      matchKeywords: ["tiger", "today"],
      answer:
        "There have been 118 confirmed tiger sightings today across all active camera stations.",
    },
    {
      id: "priority_alerts",
      matchKeywords: ["priority", "alert"],
      answer:
        "Target T-052 has not been sighted in the last three days. Earlier sightings placed it approaching a village boundary — that's the top priority right now.",
    },
  ],
  hi: [
    {
      id: "sightings_today",
      matchKeywords: ["बाघ", "आज"], // "tiger", "today"
      answer:
        "आज सभी सक्रिय कैमरा स्टेशनों पर 118 बाघों की पुष्टि हुई है।",
    },
    {
      id: "priority_alerts",
      matchKeywords: ["प्राथमिकता", "अलर्ट"], // "priority", "alert"
      answer:
        "टारगेट टी-052 पिछले तीन दिनों से दिखाई नहीं दिया है। पहले की तस्वीरों में यह एक गांव की सीमा की ओर बढ़ता दिखा था — यह अभी सबसे बड़ी प्राथमिकता है।",
    },
  ],
  mr: [
    {
      id: "sightings_today",
      matchKeywords: ["वाघ", "आज"], // "tiger", "today"
      answer:
        "आज सर्व सक्रिय कॅमेरा स्टेशन्सवर 118 वाघांची नोंद झाली आहे.",
    },
    {
      id: "priority_alerts",
      matchKeywords: ["प्राधान्य", "अलर्ट"], // "priority", "alert"
      answer:
        "टार्गेट टी-052 गेल्या तीन दिवसांपासून दिसलेला नाही. आधीच्या नोंदींमध्ये तो गावाच्या सीमेकडे जाताना दिसला होता — सध्या हीच सर्वात मोठी प्राधान्याची बाब आहे.",
    },
  ],
};

export const FALLBACK_ANSWER: Record<Lang, string> = {
  en: "I don't have an answer for that in this demo yet — try asking about today's tiger sightings or priority alerts.",
  hi: "इस डेमो में इसका उत्तर अभी उपलब्ध नहीं है — कृपया आज के बाघ दिखने या प्राथमिकता अलर्ट के बारे में पूछें।",
  mr: "या डेमोमध्ये याचे उत्तर अजून उपलब्ध नाही — कृपया आजच्या वाघांच्या नोंदी किंवा प्राधान्य अलर्टबद्दल विचारा.",
};

export function matchDemoAnswer(transcript: string, lang: Lang): string {
  const lower = transcript.toLowerCase();
  const table = DEMO_QA[lang];
  const hit = table.find((qa) =>
    qa.matchKeywords.every((kw) => lower.includes(kw.toLowerCase()))
  );
  return hit ? hit.answer : FALLBACK_ANSWER[lang];
}
```

Note: Hindi and Marathi share some vocabulary in Devanagari script (e.g. "आज"
means "today" in both). That's fine here because matching is scoped **within**
the already-detected language's table — we only compare against the Hindi
table if Hindi was the detected language, so there's no cross-language
collision.

---

## 4. Server route — language-aware TTS

`frontend/src/app/api/tts/route.ts`:
```ts
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

  const res = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
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
    }
  );

  if (!res.ok) {
    const errText = await res.text();
    return NextResponse.json({ error: errText }, { status: 500 });
  }

  const audioBuffer = await res.arrayBuffer();
  return new NextResponse(audioBuffer, {
    headers: { "Content-Type": "audio/mpeg" },
  });
}
```

`eleven_multilingual_v2` is required here (not `eleven_turbo_v2_5`) — it's
ElevenLabs' model with real Hindi/Marathi pronunciation support. Slightly
higher latency than turbo, still fine for a demo.

---

## 5. Speech recognition — multi-language race

`frontend/src/components/VoiceAgentButton.tsx`:
```tsx
"use client";

import { useState } from "react";
import { Microphone } from "@phosphor-icons/react";
import { matchDemoAnswer, type Lang } from "@/lib/voiceDemoScript";

type Status = "idle" | "listening" | "thinking" | "speaking" | "error";

const LANG_CODES: { lang: Lang; code: string }[] = [
  { lang: "en", code: "en-IN" },
  { lang: "hi", code: "hi-IN" },
  { lang: "mr", code: "mr-IN" },
];

interface RecognitionResult {
  lang: Lang;
  transcript: string;
  confidence: number;
}

function listenOnce(code: string, lang: Lang): Promise<RecognitionResult | null> {
  return new Promise((resolve) => {
    const SpeechRecognition =
      (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRecognition) return resolve(null);

    const recognition = new SpeechRecognition();
    recognition.lang = code;
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;

    recognition.onresult = (event: any) => {
      const result = event.results[0][0];
      resolve({ lang, transcript: result.transcript, confidence: result.confidence ?? 0 });
    };
    recognition.onerror = () => resolve(null);
    recognition.onend = () => resolve(null); // resolves null if onresult never fired

    recognition.start();
  });
}

export default function VoiceAgentButton() {
  const [status, setStatus] = useState<Status>("idle");
  const [heard, setHeard] = useState("");

  const handleClick = async () => {
    const hasSpeech =
      (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!hasSpeech) {
      setStatus("error");
      alert("Speech recognition isn't supported in this browser. Try Chrome or Edge.");
      return;
    }

    setStatus("listening");

    // Race all 3 languages against the same mic capture, keep best confidence.
    const results = await Promise.all(
      LANG_CODES.map(({ lang, code }) => listenOnce(code, lang))
    );
    const best = results
      .filter((r): r is RecognitionResult => r !== null && r.transcript.length > 0)
      .sort((a, b) => b.confidence - a.confidence)[0];

    if (!best) {
      setStatus("error");
      return;
    }

    setHeard(`[${best.lang}] ${best.transcript}`);
    setStatus("thinking");

    const answer = matchDemoAnswer(best.transcript, best.lang);

    try {
      const res = await fetch("/api/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: answer, lang: best.lang }),
      });
      if (!res.ok) throw new Error("TTS request failed");

      const blob = await res.blob();
      const audio = new Audio(URL.createObjectURL(blob));
      setStatus("speaking");
      audio.onended = () => setStatus("idle");
      audio.play();
    } catch (err) {
      console.error(err);
      setStatus("error");
    }
  };

  const label =
    status === "listening"
      ? "Listening…"
      : status === "thinking"
      ? "Thinking…"
      : status === "speaking"
      ? "Speaking…"
      : "Ask the field assistant";

  return (
    <div className="flex flex-col items-start gap-1">
      <button
        onClick={handleClick}
        disabled={status === "listening" || status === "thinking" || status === "speaking"}
        className="flex items-center gap-2 rounded-full px-4 py-2 bg-neutral-900 text-white hover:bg-neutral-700 disabled:opacity-60"
      >
        <Microphone size={18} weight={status === "listening" ? "fill" : "regular"} />
        {label}
      </button>
      {heard && <span className="text-xs text-neutral-500">Heard: {heard}</span>}
    </div>
  );
}
```

**Caveat to test for**: running 3 concurrent `SpeechRecognition` instances
against one mic works in Chrome but browser behavior here isn't formally
standardized — if concurrent sessions turn out to conflict in practice (e.g.
only one gets mic access), fall back to a sequential race with a shared
`AbortController`-style short-circuit (stop the other two once one instance
returns a high-confidence result), or fall back further to the language-toggle
UI approach. Flag this during Step 7 testing below.

---

## 6. Wire into UI

Drop `<VoiceAgentButton />` into `frontend/src/components/TopBar.tsx` (or
`AppShell.tsx`) so it's visible from every view.

## 7. Test

```bash
cd frontend
npm run dev
```
In Chrome:
- Say **"how many tigers were spotted today"** → English answer, 118.
- Say **"आज कितने बाघ दिखे"** → Hindi answer.
- Say **"आज किती वाघ दिसले"** → Marathi answer.
- Say something unmatched → language-appropriate fallback line.

Watch the "Heard: [lang] ..." debug line under the button to confirm the
correct language was detected each time — if it's consistently picking the
wrong one, the fix is almost always in `LANG_CODES` region codes (try `hi-IN`
vs plain `hi`, etc.) rather than the matching logic.

---

## 8. What this plan deliberately skips

- No real STT/NLU training, no LLM, no ElevenLabs Agent/dashboard config.
- No live backend wiring — answers are hardcoded per language in
  `voiceDemoScript.ts`.
- No handling of code-mixed speech (e.g. Hinglish mid-sentence) — each
  utterance is treated as one language.
- No persistence of conversation history.

## 9. Later upgrade path (not part of this pass)

- Swap hardcoded answer strings for real data pulled from
  `frontend/src/lib/api.ts`, formatted into each language's phrasing.
- Add a dedicated Marathi voice once available (just change
  `ELEVENLABS_VOICE_ID_MR`).
- If the 3x-concurrent-recognition approach proves flaky across browsers,
  move to a hosted multilingual STT (e.g. ElevenLabs' own Scribe STT endpoint,
  which does support language auto-detection server-side) instead of the
  browser's Web Speech API.
- If keyword matching starts feeling too rigid, that's the point where the
  ElevenLabs Conversational AI Agent (LLM-driven multilingual intent
  matching) becomes worth the extra setup.
