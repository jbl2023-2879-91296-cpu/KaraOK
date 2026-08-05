/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.php',
    './public/**/*.php'
  ],
  theme: {
    extend: {
      colors: {
        ink: '#0b1020',
        panel: '#121a2b',
        line: '#25324a',
        accent: '#4a90d9'
      }
    }
  },
  plugins: []
};

