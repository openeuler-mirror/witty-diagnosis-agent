import { create } from "zustand";
import type { SessionUser } from "./types";

type View =
  | { name: "list" }
  | { name: "wizard" }
  | { name: "detail"; taskId: string }
  | { name: "qa"; sessionId?: string };

interface AppState {
  user: SessionUser | null;
  authChecked: boolean;
  /** 后端能力探测：QA 模块是否启用（FR-011）。null=未探测。 */
  qaEnabled: boolean | null;
  view: View;
  toastMsg: string | null;

  setUser: (u: SessionUser | null) => void;
  setAuthChecked: (v: boolean) => void;
  setQaEnabled: (v: boolean) => void;
  goList: () => void;
  goWizard: () => void;
  goDetail: (taskId: string) => void;
  goQA: (sessionId?: string) => void;
  toast: (msg: string) => void;
  clearToast: () => void;
}

export const useStore = create<AppState>((set) => ({
  user: null,
  authChecked: false,
  qaEnabled: null,
  view: { name: "list" },
  toastMsg: null,

  setUser: (u) => set({ user: u }),
  setAuthChecked: (v) => set({ authChecked: v }),
  setQaEnabled: (v) => set({ qaEnabled: v }),
  goList: () => set({ view: { name: "list" } }),
  goWizard: () => set({ view: { name: "wizard" } }),
  goDetail: (taskId) => set({ view: { name: "detail", taskId } }),
  goQA: (sessionId) => set({ view: { name: "qa", sessionId } }),
  toast: (msg) => set({ toastMsg: msg }),
  clearToast: () => set({ toastMsg: null }),
}));
