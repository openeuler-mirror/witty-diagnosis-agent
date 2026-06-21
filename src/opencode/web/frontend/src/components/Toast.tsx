import { useEffect } from "react";
import { useStore } from "../store";
import { IconBolt } from "../icons";

export default function Toast() {
  const msg = useStore((s) => s.toastMsg);
  const clear = useStore((s) => s.clearToast);
  useEffect(() => {
    if (!msg) return;
    const t = setTimeout(clear, 2200);
    return () => clearTimeout(t);
  }, [msg, clear]);
  return (
    <div className={`toast${msg ? " show" : ""}`}>
      <IconBolt />
      {msg}
    </div>
  );
}
