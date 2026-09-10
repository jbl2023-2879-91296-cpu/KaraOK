/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.php',
    './public/**/*.php'
  ],
  theme: {
    extend: {
      colors: {
        ink: '#f8fafc',
        panel: '#ffffff',
        line: '#e2e8f0',
        accent: '#475569'
      }
    }
  },
  plugins: []
};

