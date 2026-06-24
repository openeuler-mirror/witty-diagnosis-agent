// 内联 SVG 图标（沿用原型描边风格）。
type P = { size?: number };
const base = (size: number) => ({
  width: size,
  height: size,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
});

export const IconSearch = ({ size = 16 }: P) => (
  <svg {...base(size)}>
    <circle cx="11" cy="11" r="7" />
    <path d="M21 21l-4-4" />
  </svg>
);
export const IconPlus = ({ size = 15 }: P) => (
  <svg {...base(size)} strokeWidth={2.2}>
    <path d="M12 5v14M5 12h14" />
  </svg>
);
export const IconFile = ({ size = 16 }: P) => (
  <svg {...base(size)}>
    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
    <path d="M14 2v6h6" />
  </svg>
);
export const IconBolt = ({ size = 15 }: P) => (
  <svg {...base(size)}>
    <path d="M13 2L3 14h9l-1 8 10-12h-9z" />
  </svg>
);
export const IconGrid = ({ size = 18 }: P) => (
  <svg {...base(size)}>
    <path d="M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z" />
  </svg>
);
export const IconLogout = ({ size = 18 }: P) => (
  <svg {...base(size)}>
    <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
  </svg>
);
export const IconChat = ({ size = 18 }: P) => (
  <svg {...base(size)}>
    <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8z" />
  </svg>
);
