'use client';

// Keeps the footer's copyright year current without depending on a
// rebuild - the rest of the page stays statically generated, only this
// small piece is computed client-side on each render.
export function CopyrightYear() {
  return new Date().getFullYear();
}
