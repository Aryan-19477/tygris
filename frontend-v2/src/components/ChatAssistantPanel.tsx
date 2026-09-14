"use client";

import { useRef, useState, useEffect } from "react";
import { ChatCircleDots, X, PaperPlaneRight } from "@phosphor-icons/react";
import type { AssistantMessage } from "@/app/api/assistant/route";

export default function ChatAssistantPanel() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<AssistantMessage[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, busy]);

  const send = async () => {
    const text = input.trim();
    if (!text || busy) return;

    const nextHistory = [...messages, { role: "user", text } as AssistantMessage];
    setMessages(nextHistory);
    setInput("");
    setBusy(true);
    setError("");

    try {
      const res = await fetch("/api/assistant", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // Cap history sent — an unbounded transcript plus a tool-heavy answer
        // can blow past Groq's free-tier tokens-per-minute limit mid-session.
        body: JSON.stringify({ message: text, lang: "en", history: messages.slice(-6) }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Assistant request failed");
      setMessages([...nextHistory, { role: "assistant", text: data.answer }]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Assistant couldn't answer that.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed bottom-5 right-5 z-50 flex flex-col items-end gap-3">
      {open && (
        <div className="flex h-[28rem] w-80 flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-xl sm:w-96">
          <div className="flex items-center justify-between border-b border-border px-4 py-3">
            <div>
              <div className="text-sm font-semibold text-foreground">Field Assistant</div>
              <div className="text-[11px] text-muted">Ask about tigers, alerts, or stations</div>
            </div>
            <button
              onClick={() => setOpen(false)}
              className="flex h-7 w-7 items-center justify-center rounded-full text-muted hover:bg-surface-sunken hover:text-foreground"
              aria-label="Close chat"
            >
              <X size={15} />
            </button>
          </div>

          <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto px-4 py-3">
            {messages.length === 0 && (
              <p className="text-xs text-muted">
                Try: &ldquo;How many tigers are we tracking?&rdquo; or &ldquo;Any priority alerts right now?&rdquo;
              </p>
            )}
            {messages.map((m, i) => (
              <div
                key={i}
                className={`max-w-[85%] rounded-xl px-3 py-2 text-[13px] leading-relaxed ${
                  m.role === "user"
                    ? "ml-auto bg-accent text-accent-foreground"
                    : "bg-surface-sunken text-foreground"
                }`}
              >
                {m.text}
              </div>
            ))}
            {busy && (
              <div className="max-w-[85%] rounded-xl bg-surface-sunken px-3 py-2 text-[13px] text-muted">
                Thinking…
              </div>
            )}
            {error && (
              <div className="max-w-[85%] rounded-xl bg-danger-soft px-3 py-2 text-[13px] text-danger">
                {error}
              </div>
            )}
          </div>

          <div className="flex items-center gap-2 border-t border-border p-3">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  send();
                }
              }}
              placeholder="Ask a question…"
              disabled={busy}
              className="flex-1 rounded-full border border-border bg-background px-3 py-2 text-[13px] text-foreground outline-none focus:border-accent"
            />
            <button
              onClick={send}
              disabled={busy || !input.trim()}
              aria-label="Send"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent text-accent-foreground disabled:opacity-50"
            >
              <PaperPlaneRight size={14} weight="fill" />
            </button>
          </div>
        </div>
      )}

      <button
        onClick={() => setOpen((v) => !v)}
        aria-label={open ? "Close field assistant chat" : "Open field assistant chat"}
        className="flex h-12 w-12 items-center justify-center rounded-full bg-accent text-accent-foreground shadow-lg transition-transform hover:scale-105"
      >
        {open ? <X size={20} /> : <ChatCircleDots size={20} weight="fill" />}
      </button>
    </div>
  );
}
