import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        paper: {
          50: "#fdfcfa",
          100: "#fbfaf7",
          200: "#f4f1ea",
          300: "#e9e4d8",
          400: "#d6cebe",
          500: "#b8ac96",
          900: "#1c1917",
        },
        ink: {
          DEFAULT: "#18181b",
          light: "#52525b",
          muted: "#a1a1aa",
        },
        shield: {
          amber: "#92400e",
          green: "#166534",
          red: "#991b1b",
        },
      },
      fontFamily: {
        serif: ["Newsreader", "Georgia", "serif"],
        mono: ["JetBrains Mono", "SFMono-Regular", "Menlo", "monospace"],
        sans: ["Inter", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};
export default config;
